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
    
    /// Callback for voice activity detection (true = 有声音, false = 静音)
    private var voiceActivityHandler: ((Bool) -> Void)?
    
    /// 静音阈值 (RMS 振幅)
    private let silenceThreshold: Float = 0.01
    
    /// 最后检测到声音的时间
    private var lastVoiceTime: Date = Date()
    
    /// 获取最后检测到声音的时间
    var lastVoiceActivityTime: Date { lastVoiceTime }
    
    /// Target format: 16kHz, mono, Int16
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!
    
    // MARK: - Permission
    
    static func checkPermission() -> PermissionStatus {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
    }
    
    static func requestPermission(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            completion(granted)
        }
    }
    
    enum PermissionStatus {
        case granted
        case denied
        case undetermined
    }
    
    // MARK: - Control
    
    func start(
        audioHandler: @escaping (Data) -> Void,
        voiceActivityHandler: ((Bool) -> Void)? = nil
    ) throws {
        guard !isRunning else { return }
        
        // 检查麦克风权限
        let permission = AudioCapture.checkPermission()
        switch permission {
        case .denied:
            throw AudioError.permissionDenied
        case .undetermined:
            // 请求权限，但这里不等待，让系统提示
            break
        case .granted:
            break
        }
        
        self.audioHandler = audioHandler
        self.voiceActivityHandler = voiceActivityHandler
        self.lastVoiceTime = Date()
        
        do {
            try setupAudioEngine()
            try engine?.start()
            isRunning = true
        } catch {
            VoxaLog("Failed to start audio engine: \(error)")
            throw AudioError.engineStartFailed(error)
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
        
        // 检测音量（RMS）
        let hasVoice = detectVoiceActivity(in: buffer)
        if hasVoice {
            lastVoiceTime = Date()
        }
        voiceActivityHandler?(hasVoice)
        
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
    
    /// 检测音频缓冲区中是否有语音活动
    private func detectVoiceActivity(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else { return false }
        
        let frameLength = Int(buffer.frameLength)
        let samples = channelData[0]
        
        // 计算 RMS (Root Mean Square) 振幅
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += samples[i] * samples[i]
        }
        let rms = sqrt(sum / Float(frameLength))
        
        return rms > silenceThreshold
    }
    
    enum AudioError: Error {
        case converterCreationFailed
        case permissionDenied
        case engineStartFailed(Error)
        
        var localizedDescription: String {
            switch self {
            case .converterCreationFailed:
                return "音频格式转换器创建失败"
            case .permissionDenied:
                return "麦克风权限被拒绝"
            case .engineStartFailed(let error):
                return "音频引擎启动失败: \(error.localizedDescription)"
            }
        }
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
