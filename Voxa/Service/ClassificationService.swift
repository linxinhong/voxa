//
//  ClassificationService.swift
//  Voxa
//
//  AI-powered automatic classification for voice records.
//  Uses recent 10 records as context for better accuracy.
//  Categories: Work(工作), Idea(想法), TODO(待办), Chat(闲聊)
//

import Foundation

actor ClassificationService {
    static let shared = ClassificationService()

    private let endpoint = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    private var apiKey: String {
        if let envKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return ConfigManager.shared.apiKey
    }

    private init() {}

    /// 对语音记录进行分类
    func classify(_ record: VoiceRecord, recentRecords: [VoiceRecord] = []) async -> VoiceRecord.Category? {
        guard !apiKey.isEmpty else {
            VoxaLog("[ClassificationService] API Key 为空，跳过分类")
            return nil
        }

        VoxaLog("[ClassificationService] 开始分类，上下文记录数: \(recentRecords.count)")

        let userMessage = buildPrompt(from: record, recentRecords: recentRecords)
        let requestBody: [String: Any] = [
            "model": "qwen-turbo",
            "input": [
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userMessage]
                ]
            ],
            "parameters": [
                "result_format": "message",
                "max_tokens": 100
            ]
        ]

        guard let url = URL(string: endpoint) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 5.0  // 分类需要更多时间处理上下文

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                VoxaLog("[ClassificationService] API 返回错误: \(response)")
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [String: Any],
                  let choices = output["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                VoxaLog("[ClassificationService] API 响应解析失败")
                return nil
            }

            let category = parseCategory(from: content)
            if let category = category {
                VoxaLog("[ClassificationService] 分类结果: \(category.displayName)")
            }
            return category

        } catch {
            VoxaLog("[ClassificationService] 分类失败: \(error)")
            return nil
        }
    }

    // MARK: - Prompt

    private let systemPrompt = """
    你是一个语音内容分类助手。请将用户的语音输入归类到以下四个类别之一：

    1. 工作 - 与工作、会议、项目、任务相关的内容
    2. 想法 - 灵感、创意、思考、计划相关的内容
    3. TODO - 待办事项、提醒、任务相关的内容
    4. 闲聊 - 日常闲聊、打招呼、无关紧要的内容

    分析规则：
    - 结合上下文（最近的记录）来判断当前内容的意图
    - 如果内容提到"稍后处理"、"提醒"等，通常是 TODO
    - 如果内容是技术讨论、问题分析，通常是工作
    - 如果内容是自言自语或测试，可能是闲聊
    - 只返回类别名称（工作/想法/TODO/闲聊），不要其他文字
    """

    private func buildPrompt(from record: VoiceRecord, recentRecords: [VoiceRecord]) -> String {
        var message = "请将以下语音输入归类：\n\n"

        // 添加当前记录（包含窗口信息）
        let targetAppInfo = record.targetApp ?? "未知应用"
        message += "【当前】[\(targetAppInfo)] \(record.text)\n"

        // 添加最近 10 条记录作为上下文
        if !recentRecords.isEmpty {
            let contextRecords = Array(recentRecords.suffix(10))
            message += "\n【最近 \(contextRecords.count) 条记录】\n"
            for (index, contextRecord) in contextRecords.enumerated() {
                let timeStr = formatTime(contextRecord.timestamp)
                let appInfo = contextRecord.targetApp ?? "未知"
                message += "\(index + 1). [\(timeStr) | \(appInfo)] \(contextRecord.text.prefix(50))\n"
            }
        }

        message += "\n请将【当前】内容归类为：工作/想法/TODO/闲聊（只返回类别名称）"
        return message
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Parsing

    private func parseCategory(from text: String) -> VoiceRecord.Category? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // 直接匹配类别名称
        if cleaned.contains("工作") { return .work }
        if cleaned.contains("想法") { return .idea }
        if cleaned.contains("todo") || cleaned.contains("待办") { return .todo }
        if cleaned.contains("闲聊") { return .chat }

        // 模糊匹配
        if cleaned.hasPrefix("工作") { return .work }
        if cleaned.hasPrefix("想法") { return .idea }
        if cleaned.hasPrefix("todo") || cleaned.hasPrefix("待办") { return .todo }
        if cleaned.hasPrefix("闲聊") { return .chat }

        return nil
    }
}
