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
            NSLog("[Voxa] 设置剪贴板失败")
            return
        }
        
        // 先让当前应用（Voxa）放弃 Key Window 状态
        NSApp.hide(nil)
        
        // 等待 Voxa 隐藏
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        
        // Activate target app
        targetApp.activate(options: .activateIgnoringOtherApps)
        
        // Wait for focus transition
        try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms
        
        // Simulate Cmd+V
        simulatePaste()
        
        // Wait for paste to complete
        try? await Task.sleep(nanoseconds: 80_000_000)  // 80ms
        
        // Restore clipboard
        pasteboard.clearContents()
        
        if let savedItems = savedItems, !savedItems.isEmpty {
            let success = pasteboard.writeObjects(savedItems)
            if !success {
                NSLog("[Voxa] 恢复剪贴板失败，尝试恢复字符串")
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
        
        // Key down events
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        
        // Key up events
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        // Set flags
        cmdDown?.flags = .maskCommand
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        cmdUp?.flags = .maskCommand
        
        // Post events: Cmd down, V down, V up, Cmd up
        cmdDown?.post(tap: .cgSessionEventTap)
        vDown?.post(tap: .cgSessionEventTap)
        vUp?.post(tap: .cgSessionEventTap)
        cmdUp?.post(tap: .cgSessionEventTap)
    }
}
