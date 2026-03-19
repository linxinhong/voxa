//
//  FloatingPanel.swift
//  Voxa
//
//  Borderless, non-activating floating panel that stays on top.
//

import SwiftUI
import AppKit

class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .borderless,
                .nonactivatingPanel,     // Don't steal focus from target app
                .resizable               // Allow resizing for multi-line
            ],
            backing: .buffered,
            defer: false
        )
        
        // Always on top
        self.level = .floating
        
        // Show on all spaces and above fullscreen apps
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]
        
        // Transparent background
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        
        // Allow moving by dragging
        self.isMovableByWindowBackground = true
        
        // Allow becoming key window for text editing
        self.becomesKeyOnlyIfNeeded = false
        
        // 支持自动调整大小
        self.isReleasedWhenClosed = false
    }
    
    /// Allow panel to become key window for text editing
    override var canBecomeKey: Bool {
        return true
    }
    
    /// Prevent panel from becoming main window
    override var canBecomeMain: Bool {
        return false
    }
    
    /// 支持动态调整大小
    override func setContentSize(_ size: NSSize) {
        super.setContentSize(size)
    }
}
