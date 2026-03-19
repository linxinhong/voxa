//
//  AppDelegate.swift
//  Voxa
//
//  Application delegate handling initialization and menu bar.
//

import SwiftUI
import AppKit
import HotKey

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController!
    private var hotkeyManager: HotkeyManager!
    private var audioCapture: AudioCapture!
    private var asrClient: AsrClient!
    private var appState: AppState!
    
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        VoxaLog("[Voxa] 应用启动中...")
        
        // Initialize app state
        appState = AppState()
        VoxaLog("[Voxa] AppState 初始化完成")
        
        // Initialize panel controller
        panelController = PanelController(appState: appState)
        VoxaLog("[Voxa] PanelController 初始化完成")
        
        // Initialize audio capture
        audioCapture = AudioCapture()
        VoxaLog("[Voxa] AudioCapture 初始化完成")
        
        // Initialize ASR client
        asrClient = AsrClient(appState: appState)
        VoxaLog("[Voxa] AsrClient 初始化完成")
        
        // Initialize hotkey manager
        hotkeyManager = HotkeyManager(
            appState: appState,
            panelController: panelController,
            audioCapture: audioCapture,
            asrClient: asrClient
        )
        VoxaLog("[Voxa] HotkeyManager 初始化完成")
        
        // Setup menu bar
        setupMenuBar()
        VoxaLog("[Voxa] 菜单栏设置完成")
        
        // Setup main menu
        setupMainMenu()
        
        // Check permissions
        checkPermissions()
        
        VoxaLog("[Voxa] 应用启动完成！按 Option+Space 开始录音")
        VoxaLog("[Voxa] 也可以在菜单栏点击 Voxa 图标开始")
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 点击 Dock 图标时显示浮动窗口
        if !appState.isRecording {
            hotkeyManager.toggle()
        }
        return true
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 Voxa", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // Control menu
        let controlMenuItem = NSMenuItem()
        controlMenuItem.title = "控制"
        mainMenu.addItem(controlMenuItem)
        let controlMenu = NSMenu()
        controlMenuItem.submenu = controlMenu
        
        let toggleItem = NSMenuItem(title: "开始/停止录音", action: #selector(toggleRecording), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.option]
        controlMenu.addItem(toggleItem)
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voxa")
        }
        
        // Set log file path for user reference
        let fileManager = FileManager.default
        let possibleLogPaths = [
            fileManager.currentDirectoryPath + "/logs/voxa.log",
            fileManager.homeDirectoryForCurrentUser.path + "/.voxa/logs/voxa.log",
            "/tmp/voxa-logs/voxa.log"
        ]
        for path in possibleLogPaths {
            if fileManager.fileExists(atPath: path) {
                VoxaLog("[Voxa] 日志文件: \(path)")
                break
            }
        }
        
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: "开始录音 (Option+Space)",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        
        // 点击状态栏图标直接开始录音（而不是显示菜单）
        if let button = statusItem?.button {
            button.target = self
            button.action = #selector(toggleRecording)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc func toggleRecording() {
        hotkeyManager.toggle()
    }
    
    @objc private func openSettings() {
        let alert = NSAlert()
        alert.messageText = "设置"
        alert.informativeText = "API Key 设置:\n\n1. 环境变量: export DASHSCOPE_API_KEY=xxx\n2. 或使用 Keychain (待实现)"
        alert.runModal()
    }
    
    private func checkPermissions() {
        // Check microphone permission (macOS will prompt automatically)
        AudioCapture.checkPermission { granted in
            Task { @MainActor in
                if !granted {
                    self.showPermissionAlert(for: "麦克风")
                }
            }
        }
        
        // Check accessibility permission
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            VoxaLog("[Voxa] 辅助功能权限未授予")
        }
    }
    
    private func showPermissionAlert(for permission: String) {
        let alert = NSAlert()
        alert.messageText = "需要\(permission)权限"
        alert.informativeText = "Voxa 需要\(permission)权限才能正常工作。请在系统设置中开启。"
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "稍后")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
