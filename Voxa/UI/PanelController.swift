//
//  PanelController.swift
//  Voxa
//
//  Controls showing/hiding the floating panel and positioning.
//

import SwiftUI
import AppKit

@MainActor
class PanelController {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<InputBarView>?
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    /// Show the floating panel centered on screen
    func show() {
        let isFirstTime = panel == nil
        
        if panel == nil {
            createPanel()
        }
        
        guard let panel = panel else { return }
        
        // 每次显示都重置高度到默认值（80px）
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let panelWidth: CGFloat = 440
            let defaultHeight: CGFloat = 80
            let x = screenRect.midX - panelWidth / 2
            let y = screenRect.midY + 100
            
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: defaultHeight), display: false)
        }
        
        panel.orderFrontRegardless()
        
        // Ensure text view gets focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let contentView = panel.contentView {
                self.makeFirstResponder(in: contentView)
            }
        }
    }
    
    /// Hide the floating panel
    func hide() {
        panel?.orderOut(nil)
        // 同时隐藏计费窗口
        StatsWindowController.shared.hide()
    }
    
    /// Check if panel is visible
    var isVisible: Bool {
        return panel?.isVisible ?? false
    }
    
    private func createPanel() {
        let contentView = InputBarView(appState: appState)
        
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 100)
        hosting.autoresizingMask = [.width, .height]
        
        // 启用 layer 并设置圆角遮罩
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 12
        hosting.layer?.masksToBounds = true
        
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 100))
        panel.contentView = hosting
        
        // 让面板支持自动调整大小
        panel.contentMinSize = NSSize(width: 440, height: 60)
        panel.contentMaxSize = NSSize(width: 440, height: 400)
        
        self.hostingView = hosting
        self.panel = panel
        
        // 监听文本高度变化通知
        setupHeightObserver()
    }
    
    private func setupHeightObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHeightChange(_:)),
            name: .textHeightDidChange,
            object: nil
        )
    }
    
    @objc private func handleHeightChange(_ notification: Notification) {
        guard let panel = self.panel,
              let textHeight = notification.userInfo?["height"] as? CGFloat else { return }
        
        // 计算总高度
        let totalHeight = 10 + 32 + 6 + 12 + textHeight + 10
        let targetHeight = min(max(totalHeight, 70), 400)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let panel = self.panel else { return }
            
            let currentHeight = panel.frame.height
            guard abs(currentHeight - targetHeight) > 5 else { return }
            
            // 调整窗口高度
            var frame = panel.frame
            frame.origin.y += currentHeight - targetHeight
            frame.size.height = targetHeight
            panel.setFrame(frame, display: true, animate: false)
            
            VoxaLog("[Panel] 调整: \(Int(currentHeight))px → \(Int(targetHeight))px")
        }
    }
    
    private func makeFirstResponder(in view: NSView) {
        // Find and focus the text view (in scroll view)
        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView,
               let textView = scrollView.documentView as? NSTextView {
                textView.window?.makeFirstResponder(textView)
                return
            }
            makeFirstResponder(in: subview)
        }
    }
}
