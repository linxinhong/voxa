//
//  AsrClient.swift
//  Voxa
//
//  WebSocket client for Alibaba Cloud DashScope Paraformer ASR.
//

import Foundation

actor AsrClient: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private var taskId: String?
    private var isConnected = false
    
    private let appState: AppState
    private let apiKey: String
    
    init(appState: AppState) {
        self.appState = appState
        
        // Get API key from environment or keychain
        if let envKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"] {
            self.apiKey = envKey
        } else {
            // TODO: Get from keychain
            self.apiKey = ""
        }
        
        super.init()
    }
    
    // MARK: - Connection
    
    func connect() async {
        guard !isConnected else { return }
        
        guard !apiKey.isEmpty else {
            VoxaLog("Error: DASHSCOPE_API_KEY not set")
            return
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
            VoxaLog("WebSocket error: \(error)")
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
            VoxaLog("[ASR] 原始数据: \(text)")
        }
    }
    
    private func handleBinary(_ data: Data) {
        // Handle binary responses if needed
        NSLog("Received binary data: \(data.count) bytes")
    }
    
    private func handleSentence(_ sentence: AsrSentence) {
        let text = sentence.text
        let isFinal = sentence.sentence_end ?? false
        
        VoxaLog("[ASR] 收到识别结果: \"\(text)\", isFinal: \(isFinal)")
        
        Task { @MainActor in
            if isFinal {
                // Final 结果：在光标位置插入并清洗
                appState.appendFinal(text)
                VoxaLog("[ASR] 已追加 final 文本: \"\(text)\"")
            } else {
                // Partial 结果：在光标位置插入
                appState.updatePartial(text)
                VoxaLog("[ASR] 已更新 partial 文本: \"\(text)\"")
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
