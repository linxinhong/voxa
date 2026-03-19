//
//  AudioCapture.swift
//  Voxa
//
//  AVAudioEngine microphone capture with resampling to 16kHz.
//

import Foundation
import AVFoundation

actor AudioCapture {
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var isRunning = false
    
    /// Callback for audio data
    private var audioHandler: ((Data) -> Void)?
    
    /// Target format: 16kHz, mono, Int16
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!
    
    // MARK: - Permission
    
    static func checkPermission(completion: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                completion(granted)
            }
        @unknown default:
            completion(false)
        }
    }
    
    // MARK: - Control
    
    func start(audioHandler: @escaping (Data) -> Void) {
        guard !isRunning else { return }
        
        self.audioHandler = audioHandler
        
        do {
            try setupAudioEngine()
            try engine?.start()
            isRunning = true
        } catch {
            VoxaLog("Failed to start audio engine: \(error)")
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        converter = nil
        isRunning = false
        audioHandler = nil
    }
    
    // MARK: - Setup
    
    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        
        // Get input format (typically 48kHz)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create converter to target format
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterCreationFailed
        }
        
        self.converter = converter
        
        // Buffer size for ~200ms of audio at 16kHz
        let bufferSize = UInt32(16000 * 0.2)  // 3200 samples
        let inputBufferSize = AVAudioFrameCount(Double(bufferSize) * inputFormat.sampleRate / 16000.0)
        
        inputNode.installTap(onBus: 0, bufferSize: inputBufferSize, format: inputFormat) { [weak self] buffer, _ in
            Task { [weak self] in
                await self?.processBuffer(buffer)
            }
        }
        
        self.engine = engine
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter else { return }
        
        // Create output buffer
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(16000 * 0.2)
        )!
        
        // Convert using input block
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            VoxaLog("Conversion error: \(error)")
            return
        }
        
        // Extract Int16 data
        guard let channelData = outputBuffer.int16ChannelData else { return }
        
        let frameLength = Int(outputBuffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * 2)
        
        // Send data
        audioHandler?(data)
    }
    
    enum AudioError: Error {
        case converterCreationFailed
    }
}

// MARK: - AVAudioSession for macOS

#if os(macOS)
class AVAudioSession {
    static func sharedInstance() -> AVAudioSession {
        return AVAudioSession()
    }
    
    var recordPermission: RecordPermission {
        // macOS doesn't use AVAudioSession for permissions
        // Return granted assuming Info.plist has NSMicrophoneUsageDescription
        return .granted
    }
    
    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        // macOS will prompt automatically when first accessing microphone
        response(true)
    }
    
    enum RecordPermission {
        case granted
        case denied
        case undetermined
    }
}
#endif
