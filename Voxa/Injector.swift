//
//  Injector.swift
//  Voxa
//
//  Text injection via clipboard and Cmd+V simulation.
//

import Foundation
import AppKit
import CoreGraphics

enum Injector {
    
    /// Inject text into target application using clipboard + Cmd+V
    static func inject(text: String, to targetApp: NSRunningApplication) async {
        VoxaLog("[Injector] 开始注入 \(text.count) 字到 \(targetApp.bundleIdentifier ?? "未知应用")")
        
        let pasteboard = NSPasteboard.general
        
        // Save current clipboard content
        let savedString = pasteboard.string(forType: .string)
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            // 复制剪贴板项
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem.types.isEmpty ? nil : newItem
        }
        
        // Clear and set new text
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            VoxaLog("[Injector] 设置剪贴板失败")
            return
        }
        VoxaLog("[Injector] 剪贴板已设置: \(text.prefix(30))...")
        
        // 先让当前应用（Voxa）放弃 Key Window 状态
        await MainActor.run {
            NSApp.hide(nil)
        }
        VoxaLog("[Injector] Voxa 已隐藏")
        
        // 等待 Voxa 隐藏
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        
        // Activate target app
        targetApp.activate(options: .activateIgnoringOtherApps)
        VoxaLog("[Injector] 目标应用已激活")
        
        // Wait for focus transition
        try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms
        
        // Simulate Cmd+V
        VoxaLog("[Injector] 模拟 Cmd+V")
        simulatePaste()
        
        // Wait for paste to complete
        try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms
        VoxaLog("[Injector] 注入完成")
        
        // Restore clipboard
        pasteboard.clearContents()
        VoxaLog("[Injector] 剪贴板已恢复")
        
        if let savedItems = savedItems, !savedItems.isEmpty {
            let success = pasteboard.writeObjects(savedItems)
            if !success {
                VoxaLog("[Voxa] 恢复剪贴板失败，尝试恢复字符串")
                if let savedString = savedString {
                    pasteboard.setString(savedString, forType: .string)
                }
            }
        } else if let savedString = savedString {
            pasteboard.setString(savedString, forType: .string)
        }
    }
    
    private static func simulatePaste() {
        // Get source state
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Cmd key code: 0x37 (kVK_Command)
        // V key code: 0x09 (kVK_ANSI_V)
        
        // 方法1: 发送 Cmd+V 组合（大多数应用适用）
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        // Set flags
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        cmdUp?.flags = .maskCommand
        
        // 发送按键序列（添加延迟确保终端应用能接收）
        cmdDown?.post(tap: .cgSessionEventTap)
        usleep(5000)  // 5ms 延迟，终端应用需要更多时间
        vDown?.post(tap: .cgSessionEventTap)
        usleep(5000)
        vUp?.post(tap: .cgSessionEventTap)
        usleep(5000)
        cmdUp?.post(tap: .cgSessionEventTap)
        
        VoxaLog("[Injector] 按键事件已发送")
    }
}
