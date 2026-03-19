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
    }
    
    /// Toggle recording state
    func toggle() {
        if appState.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        Task {
            // Record the target app before showing our UI
            appState.targetApp = NSWorkspace.shared.frontmostApplication
            
            // Reset state
            appState.reset()
            
            // Show panel
            panelController.show()
            
            // Start ASR connection
            await asrClient.connect()
            
            // Start audio capture
            await audioCapture.start { [weak self] pcmData in
                Task { [weak self] in
                    await self?.asrClient.sendAudio(pcmData)
                }
            }
            
            await MainActor.run {
                appState.isRecording = true
            }
        }
    }
    
    private func stopRecording() {
        Task {
            // Stop audio capture
            await audioCapture.stop()
            
            // Close ASR connection
            await asrClient.disconnect()
            
            await MainActor.run {
                appState.isRecording = false
            }
            
            // 停止录音时的处理：如果有 pending 未确认，自动追加到末尾
            var finalText = appState.finalizeOnStop()
            
            VoxaLog("[Voxa] 停止录音，最终文本 [\(finalText.count) 字]: \(finalText.prefix(50))...")
            
            // 如果开启润色，执行润色
            if appState.polishEnabled && !finalText.isEmpty {
                VoxaLog("[Voxa] 开始润色文本...")
                let polishedText = await Polisher.polish(finalText)
                if polishedText != finalText {
                    VoxaLog("[Voxa] 润色完成")
                    VoxaLog("[Voxa] 原文: \(finalText)")
                    VoxaLog("[Voxa] 润色: \(polishedText)")
                    finalText = polishedText
                    // 更新 confirmedText 为润色后的文本
                    appState.confirmedText = finalText
                } else {
                    VoxaLog("[Voxa] 润色后无变化")
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
