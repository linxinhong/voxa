//
//  Polisher.swift
//  Voxa
//
//  LLM-based light polishing for ASR results using Qwen API.
//

import Foundation

enum Polisher {
    
    /// 获取 API Key（优先级：环境变量 > 配置文件）
    private static var apiKey: String {
        // 1. 环境变量
        if let envKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        // 2. 配置文件
        let configKey = ConfigManager.shared.apiKey
        if !configKey.isEmpty {
            return configKey
        }
        return ""
    }
    
    private static let endpoint = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    
    private static let systemPrompt = """
    你是一个语音转文字的轻度润色助手。
    用户输入是语音识别的原始结果，你只能做以下修改：
    修正明显的错别字、同音字错误、补全缺失标点、去除重复词。
    禁止改变用户的表达方式、句式结构、语气和风格。
    禁止添加任何原文中没有的内容。
    只输出润色后的文字，不要任何解释。
    """
    
    /// Polish text using Qwen API with custom prompt
    /// Falls back to original text if API fails or times out (> 1.5s)
    static func polish(_ text: String, customPrompt: String? = nil) async -> String {
        guard !apiKey.isEmpty else {
            return text
        }
        
        // 使用自定义提示词或当前配置的提示词
        let prompt = customPrompt ?? ConfigManager.shared.currentPrompt()
        
        do {
            return try await withTimeout(seconds: 1.5) {
                try await performPolish(text, systemPrompt: prompt)
            }
        } catch {
            VoxaLog("Polish failed or timed out: \(error)")
            return text
        }
    }
    
    private static func performPolish(_ text: String, systemPrompt: String) async throws -> String {
        let requestBody: [String: Any] = [
            "model": "qwen-turbo",
            "input": [
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": text]
                ]
            ],
            "parameters": [
                "result_format": "message"
            ]
        ]
        
        guard let url = URL(string: endpoint) else {
            throw PolishError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 1.5
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PolishError.apiError
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let output = json["output"] as? [String: Any],
              let choices = output["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PolishError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PolishError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    enum PolishError: Error {
        case invalidURL
        case apiError
        case invalidResponse
        case timeout
    }
}
