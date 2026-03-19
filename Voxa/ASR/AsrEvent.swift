//
//  AsrEvent.swift
//  Voxa
//
//  ASR event definitions.
//

import Foundation

enum AsrEvent {
    /// Partial recognition result
    case partial(String)
    
    /// Final recognition result
    case final(String)
    
    /// Error occurred
    case error(Error)
    
    /// Connection status changed
    case connected
    case disconnected
}

// MARK: - WebSocket Message Types

struct RunTaskMessage: Codable {
    let header: MessageHeader
    let payload: RunTaskPayload
    
    init(apiKey: String) {
        self.header = MessageHeader(
            action: "run-task",
            task_id: UUID().uuidString,
            streaming: "duplex"
        )
        self.payload = RunTaskPayload(
            model: "paraformer-realtime-v2",
            task_group: "audio",
            task: "asr",
            function: "recognition",
            parameters: AsrParameters(
                format: "pcm",
                sample_rate: 16000,
                enable_intermediate_result: true,
                enable_punctuation_prediction: true,
                enable_inverse_text_normalization: true
            ),
            input: AsrInput()
        )
    }
}

struct FinishTaskMessage: Codable {
    let header: MessageHeader
    
    init(taskId: String) {
        self.header = MessageHeader(
            action: "finish-task",
            task_id: taskId,
            streaming: "duplex"
        )
    }
}

struct MessageHeader: Codable {
    let action: String
    let task_id: String
    let streaming: String
}

struct RunTaskPayload: Codable {
    let model: String
    let task_group: String
    let task: String
    let function: String
    let parameters: AsrParameters
    let input: AsrInput
}

struct AsrParameters: Codable {
    let format: String
    let sample_rate: Int
    let enable_intermediate_result: Bool
    let enable_punctuation_prediction: Bool
    let enable_inverse_text_normalization: Bool
}

struct AsrInput: Codable {
    // Empty for streaming ASR
}

// MARK: - Response Types

struct AsrResponse: Codable {
    let header: ResponseHeader
    let payload: ResponsePayload?
}

struct ResponseHeader: Codable {
    let event: String
    let task_id: String?
    let error_code: String?
    let error_message: String?
}

struct ResponsePayload: Codable {
    let output: AsrOutput?
}

struct AsrOutput: Codable {
    let sentence: AsrSentence?
}

struct AsrSentence: Codable {
    let text: String
    let sentence_end: Bool?
}
