//
//  AsrClient.swift
//  Voxa
//
//  WebSocket client for Alibaba Cloud DashScope Paraformer ASR.
//

import Foundation

// MARK: - ASR Errors

enum AsrError: Error {
    case apiKeyMissing
    case connectionFailed(Error)
    case sendFailed(Error)
    
    var localizedDescription: String {
        switch self {
        case .apiKeyMissing:
            return "未配置 API Key"
        case .connectionFailed(let error):
            return "连接失败: \(error.localizedDescription)"
        case .sendFailed(let error):
            return "发送失败: \(error.localizedDescription)"
        }
    }
}

actor AsrClient: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var taskId: String?
    private var isConnected = false
    
    private let appState: AppState
    private let apiKey: String
    
    init(appState: AppState) {
        self.appState = appState
        
        // 获取 API Key（优先级：环境变量 > 配置文件）
        var key = ""
        // 1. 环境变量
        if let envKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"], !envKey.isEmpty {
            key = envKey
        } else {
            // 2. 配置文件
            let configKey = ConfigManager.shared.apiKey
            if !configKey.isEmpty {
                key = configKey
            }
        }
        self.apiKey = key
        
        super.init()
    }
    
    /// 检查 API Key 是否已配置
    var hasApiKey: Bool {
        return !apiKey.isEmpty
    }
    
    // MARK: - Connection
    
    func connect() async throws {
        guard !isConnected else { return }
        
        guard !apiKey.isEmpty else {
            VoxaLog("Error: DASHSCOPE_API_KEY not set")
            throw AsrError.apiKeyMissing
        }
        
        let url = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference/")!
        var request = URLRequest(url: url)
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: request)
        
        webSocketTask?.resume()
        
        // Send run-task message
        let runTask = RunTaskMessage(apiKey: apiKey)
        taskId = runTask.header.task_id
        
        do {
            let data = try JSONEncoder().encode(runTask)
            if let json = String(data: data, encoding: .utf8) {
                try await webSocketTask?.send(.string(json))
                VoxaLog("[ASR] 发送 run-task: \(json)")
            }
        } catch {
            VoxaLog("Failed to send run-task: \(error)")
        }
        
        // Start receiving
        receiveMessage()
    }
    
    func disconnect() async {
        guard isConnected, let taskId = taskId else { return }
        
        // Send finish-task message
        let finishTask = FinishTaskMessage(taskId: taskId)
        do {
            let data = try JSONEncoder().encode(finishTask)
            if let json = String(data: data, encoding: .utf8) {
                try await webSocketTask?.send(.string(json))
                VoxaLog("[ASR] 发送 finish-task")
            }
        } catch {
            VoxaLog("Failed to send finish-task: \(error)")
        }
        
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }
    
    // MARK: - Audio Streaming
    
    func sendAudio(_ data: Data) async {
        guard isConnected else { return }
        
        do {
            try await webSocketTask?.send(.data(data))
        } catch {
            VoxaLog("Failed to send audio: \(error)")
        }
    }
    
    // MARK: - Message Handling
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { [weak self] in
                await self?.handleResult(result)
            }
        }
    }
    
    private func handleResult(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                handleJSON(text)
            case .data(let data):
                handleBinary(data)
            @unknown default:
                break
            }
            
            // Continue receiving
            receiveMessage()
            
        case .failure(let error):
            // 忽略 socket 已断开的错误（正常关闭时的竞态条件）
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
                // Socket is not connected - 正常关闭，忽略
            } else {
                VoxaLog("WebSocket error: \(error)")
            }
            isConnected = false
        }
    }
    
    private func handleJSON(_ text: String) {
        NSLog("[ASR] 收到 JSON: \(text.prefix(200))...")
        
        guard let data = text.data(using: .utf8) else { return }
        
        do {
            let response = try JSONDecoder().decode(AsrResponse.self, from: data)
            
            VoxaLog("[ASR] event: \(response.header.event)")
            
            switch response.header.event {
            case "task-started":
                isConnected = true
                VoxaLog("ASR task started")
                
            case "task-finished":
                isConnected = false
                VoxaLog("ASR task finished")
                
            case "result-generated":
                VoxaLog("[ASR] result-generated, payload: \(response.payload != nil ? "有" : "无")")
                if let output = response.payload?.output {
                    if let sentence = output.sentence {
                        VoxaLog("[ASR] output.sentence: \(sentence)")
                        handleSentence(sentence)
                    } else {
                        VoxaLog("[ASR] sentence 为空")
                    }
                } else {
                    VoxaLog("[ASR] payload 或 output 为空")
                }
                
            case "error":
                if let errorCode = response.header.error_code {
                    VoxaLog("ASR error: \(errorCode) - \(response.header.error_message ?? "")")
                }
                
            default:
                VoxaLog("[ASR] 未知事件: \(response.header.event)")
            }
        } catch {
            VoxaLog("Failed to decode response: \(error)")
        }
    }
    
    private func handleBinary(_ data: Data) {
        // Handle binary responses if needed
        NSLog("Received binary data: \(data.count) bytes")
    }
    
    private func handleSentence(_ sentence: AsrSentence) {
        let text = sentence.text
        let isFinal = sentence.sentence_end ?? false
        
        Task { @MainActor in
            // 有语音输入，标记 ASR 活跃（麦克风绿色，开始计费）
            if !text.isEmpty {
                appState.isAsrActive = true
                StatsManager.shared.markAsrActive()
            }
            
            if isFinal {
                // Final：保留第1行，显示 ⬇ 按钮等待用户确认
                appState.receiveFinal(text)
            } else {
                // Partial：整句覆盖第1行
                appState.updatePartial(text)
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension AsrClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task {
            await self.handleConnected()
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task {
            await self.handleDisconnected()
        }
    }
    
    private func handleConnected() {
        VoxaLog("WebSocket connected")
    }
    
    private func handleDisconnected() {
        VoxaLog("WebSocket disconnected")
        isConnected = false
    }
}
