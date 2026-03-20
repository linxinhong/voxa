//
//  HotkeyManager.swift
//  Voxa
//
//  Global hotkey registration and toggle logic.
//

import Foundation
import AppKit
import HotKey

@MainActor
class HotkeyManager {
    private let appState: AppState
    private let panelController: PanelController
    private let audioCapture: AudioCapture
    private let asrClient: AsrClient
    
    private var hotKey: HotKey?
    private var currentConfig: ShortcutConfig
    private var templateHotKeys: [HotKey] = []  // 保存模板快捷键引用
    
    // MARK: - 静音超时自动停止
    
    /// 静音超时时间（秒）
    private let silenceTimeout: TimeInterval = 60
    
    /// 静音检测定时器
    private var silenceTimer: Timer?
    
    /// 最后检测到声音的时间
    private var lastVoiceTime: Date = Date()
    
    /// 是否正在录音中（用于定时器检查）
    private var isMonitoringSilence = false
    
    init(appState: AppState, panelController: PanelController, audioCapture: AudioCapture, asrClient: AsrClient) {
        self.appState = appState
        self.panelController = panelController
        self.audioCapture = audioCapture
        self.asrClient = asrClient
        
        // 从环境变量读取快捷键配置
        if let shortcutString = ProcessInfo.processInfo.environment["VOXA_SHORTCUT"],
           let config = ShortcutConfig(from: shortcutString) {
            self.currentConfig = config
            VoxaLog("[Voxa] 从环境变量读取快捷键配置: \(config.displayString)")
        } else {
            self.currentConfig = .default
            VoxaLog("[Voxa] 使用默认快捷键: \(ShortcutConfig.default.displayString)")
        }
        
        setupHotkey()
        setupEscHandler()
    }
    
    private func setupEscHandler() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEscPressed),
            name: .hidePanel,
            object: nil
        )
        
        // 监听麦克风按钮点击（暂停/恢复）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePauseToggle),
            name: .togglePauseRecording,
            object: nil
        )
    }
    
    @objc private func handlePauseToggle() {
        VoxaLog("[Hotkey] 麦克风按钮点击，暂停/恢复录音")
        if appState.isRecording {
            pauseRecording()
        } else if appState.isPaused {
            resumeRecording()
        }
    }
    
    @objc private func handleEscPressed() {
        cancelRecording()
    }
    
    /// 更新快捷键配置
    func updateShortcut(_ config: ShortcutConfig) -> Bool {
        // 检查是否包含 fn 键
        if config.modifiers.contains("function") {
            VoxaLog("[Voxa] 警告: fn 键在 macOS 上通常不能作为全局热键的修饰键")
            VoxaLog("[Voxa] 建议使用 ctrl+space, ctrl+option+space 或 ctrl+cmd+space 替代")
            // 仍然尝试注册，但可能不工作
        }
        
        // 注销旧的热键
        hotKey = nil
        
        // 设置新的热键
        guard let key = config.hotKey else {
            VoxaLog("[Voxa] 无效的快捷键 key: \(config.key)")
            return false
        }
        
        let modifiers = config.hotKeyModifiers
        
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            VoxaLog("[Voxa] 热键触发: \(config.displayString)")
            self?.toggle()
        }
        
        currentConfig = config
        VoxaLog("[Voxa] 热键已更新为: \(config.displayString)")
        return true
    }
    
    private func setupHotkey() {
        _ = updateShortcut(currentConfig)
        setupPolishTemplateHotkeys()
    }
    
    /// 设置润色模板快捷键 Alt+1, Alt+2, ...
    private func setupPolishTemplateHotkeys() {
        // 注册 Alt+1 到 Alt+9
        let numberKeys: [Key] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine]
        
        for (index, key) in numberKeys.enumerated() {
            let shortcut = "alt+\(index + 1)"
            let hotKey = HotKey(key: key, modifiers: [.option])
            hotKey.keyDownHandler = { [weak self] in
                VoxaLog("[Hotkey] 触发模板切换: \(shortcut)")
                self?.appState.switchPolishTemplate(to: shortcut)
            }
            // 保存引用防止被释放
            templateHotKeys.append(hotKey)
        }
        
        VoxaLog("[Hotkey] 已注册润色模板快捷键: Alt+1 到 Alt+9")
    }
    
    /// Toggle recording state（Option+Space：停止/开始，不是暂停）
    func toggle() {
        if appState.isRecording || appState.isPaused {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// 暂停录音（不隐藏面板，可恢复）
    private func pauseRecording() {
        Task {
            await audioCapture.stop()
            await asrClient.disconnect()
            
            await MainActor.run {
                appState.isPaused = true
                appState.isRecording = false
                appState.isAsrActive = false
            }
            
            VoxaLog("[Voxa] 录音已暂停")
        }
    }
    
    /// 恢复录音
    private func resumeRecording() {
        Task {
            do {
                // 恢复静音检测
                lastVoiceTime = Date()
                isMonitoringSilence = true
                startSilenceTimer()
                
                try await asrClient.connect()
                try await audioCapture.start(
                    audioHandler: { [weak self] pcmData in
                        Task { [weak self] in
                            await self?.asrClient.sendAudio(pcmData)
                        }
                    },
                    voiceActivityHandler: { [weak self] hasVoice in
                        Task { @MainActor [weak self] in
                            if hasVoice {
                                self?.lastVoiceTime = Date()
                            }
                        }
                    }
                )
                
                await MainActor.run {
                    appState.isPaused = false
                    appState.isRecording = true
                }
                
                VoxaLog("[Voxa] 录音已恢复")
            } catch {
                VoxaLog("[Voxa] 恢复录音失败: \(error)")
                appState.showError("恢复录音失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// ESC 取消录音：停止但不注入，重置状态
    func cancelRecording() {
        Task {
            // 停止静音检测
            stopSilenceTimer()
            
            // Stop audio capture
            await audioCapture.stop()
            
            // Close ASR connection
            await asrClient.disconnect()
            
            await MainActor.run {
                appState.isRecording = false
            }
            
            // 丢弃 pending，保留已确认的文本但不注入
            let _ = appState.finalizeOnStop()
            
            VoxaLog("[Voxa] ESC 取消录音")
            
            // Hide panel only
            await MainActor.run {
                panelController.hide()
            }
        }
    }
    
    private func startRecording() {
        Task {
            // 先检查 API Key
            let apiKeyConfigured = await asrClient.hasApiKey
            guard apiKeyConfigured else {
                // 显示面板并显示错误
                appState.reset()
                panelController.show()
                appState.showPermissionError(for: .apiKey)
                VoxaLog("[Hotkey] API Key 未配置")
                return
            }
            
            // Record the target app before showing our UI
            appState.targetApp = NSWorkspace.shared.frontmostApplication
            
            // Reset state
            appState.reset()
            
            // Show panel
            panelController.show()
            
            // Start ASR connection
            do {
                try await asrClient.connect()
            } catch {
                if let asrError = error as? AsrError {
                    appState.showError(asrError.localizedDescription)
                } else {
                    appState.showError("ASR 连接失败: \(error.localizedDescription)")
                }
                VoxaLog("[Hotkey] ASR 连接失败: \(error)")
                return
            }
            
            // 初始化静音检测
            lastVoiceTime = Date()
            isMonitoringSilence = true
            startSilenceTimer()
            
            // Start audio capture（实际开始发送音频数据）
            do {
                try await audioCapture.start(
                    audioHandler: { [weak self] pcmData in
                        Task { [weak self] in
                            await self?.asrClient.sendAudio(pcmData)
                        }
                    },
                    voiceActivityHandler: { [weak self] hasVoice in
                        Task { @MainActor [weak self] in
                            if hasVoice {
                                self?.lastVoiceTime = Date()
                            }
                        }
                    }
                )
            } catch let error as AudioCapture.AudioError {
                appState.showPermissionError(for: .microphone)
                VoxaLog("[Hotkey] 音频捕获失败: \(error)")
                return
            } catch {
                appState.showError("音频启动失败: \(error.localizedDescription)")
                VoxaLog("[Hotkey] 音频捕获失败: \(error)")
                return
            }
            
            // 注意：计费在收到 ASR 结果时开始（markAsrActive）
            
            await MainActor.run {
                appState.isRecording = true
            }
        }
    }
    
    // MARK: - 静音超时检测
    
    /// 启动静音检测定时器
    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkSilenceTimeout()
            }
        }
    }
    
    /// 停止静音检测定时器
    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        isMonitoringSilence = false
    }
    
    /// 检查是否超过静音超时时间
    private func checkSilenceTimeout() {
        guard isMonitoringSilence && appState.isRecording else { return }
        
        let silenceDuration = Date().timeIntervalSince(lastVoiceTime)
        
        if silenceDuration >= silenceTimeout {
            VoxaLog("[Hotkey] 静音超过 \(silenceTimeout) 秒，自动停止录音")
            stopRecordingDueToSilence()
        } else if silenceDuration >= silenceTimeout - 10 {
            // 提前 10 秒显示提示（可选）
            let remaining = Int(silenceTimeout - silenceDuration)
            VoxaLog("[Hotkey] 即将因静音自动停止（还剩 \(remaining) 秒）")
        }
    }
    
    /// 因静音超时而停止录音
    private func stopRecordingDueToSilence() {
        stopSilenceTimer()
        
        // 显示提示
        appState.confirmedText += "\n[已自动停止：超过 60 秒未检测到声音]"
        
        // 调用正常停止流程
        stopRecording()
    }
    
    private func stopRecording() {
        Task {
            // 停止静音检测定时器
            stopSilenceTimer()
            
            // 停止计时
            StatsManager.shared.stopSession()
            
            // Stop audio capture
            await audioCapture.stop()
            
            // Close ASR connection
            await asrClient.disconnect()
            
            await MainActor.run {
                appState.isRecording = false
                appState.isAsrActive = false
            }
            
            // 停止录音时的处理：如果有 pending 未确认，自动追加到末尾
            var finalText = appState.finalizeOnStop()
            
            // 发送前自动润色（不锁定界面，直接执行）
            if !finalText.isEmpty {
                let polishedText = await Polisher.polish(finalText)
                if polishedText != finalText {
                    finalText = polishedText
                }
                // 直接更新，不经过锁定过程
                await MainActor.run {
                    appState.confirmedText = finalText
                    appState.partialText = ""
                    appState.clearPending()
                }
            }
            
            // Hide panel
            panelController.hide()
            
            // Inject text if not empty
            if !finalText.isEmpty {
                VoxaLog("[Voxa] 准备注入文本到 \(appState.targetApp?.bundleIdentifier ?? "未知应用")")
                await injectText(finalText)
            } else {
                VoxaLog("[Voxa] 最终文本为空，跳过注入")
            }
        }
    }
    
    private func injectText(_ text: String) async {
        guard let targetApp = appState.targetApp else { return }
        await Injector.inject(text: text, to: targetApp)
    }
    
    /// 获取当前快捷键配置的显示字符串
    var currentShortcutDisplay: String {
        return currentConfig.displayString
    }
}
