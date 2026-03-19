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
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    /// Show the floating panel centered on screen
    func show() {
        if panel == nil {
            createPanel()
        }
        
        guard let panel = panel else { return }
        
        // Position panel at center of main screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let panelWidth: CGFloat = 500
            let minPanelHeight: CGFloat = 60  // 最小高度（1行）
            let x = screenRect.midX - panelWidth / 2
            let y = screenRect.midY + 100  // Slightly above center
            
            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: minPanelHeight), display: false)
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
    }
    
    /// Check if panel is visible
    var isVisible: Bool {
        return panel?.isVisible ?? false
    }
    
    private func createPanel() {
        let contentView = InputBarView(appState: appState)
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 100)
        
        // 启用 layer 并设置圆角遮罩
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 100))
        panel.contentView = hostingView
        
        // 让面板支持自动调整大小（基于内容）
        panel.contentMinSize = NSSize(width: 440, height: 60)
        panel.contentMaxSize = NSSize(width: 440, height: 400)
        
        // 监听文本高度变化通知
        setupHeightObserver()
        
        self.panel = panel
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
        guard let panel = panel,
              let textHeight = notification.userInfo?["height"] as? CGFloat else { return }
        
        // 计算总高度：外部padding(10) + 第一行(约32) + spacing(6) + 第二行padding(12) + 输入框高度 + 外部padding(10)
        let totalHeight = 10 + 32 + 6 + 12 + textHeight + 10
        let newHeight = min(max(totalHeight, 70), 400)
        
        var frame = panel.frame
        // 只有变化超过5px才调整
        guard abs(frame.height - newHeight) > 5 else { return }
        
        // 保持顶部位置不变，调整高度
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight
        panel.setFrame(frame, display: true, animate: false)
        
        VoxaLog("[Panel] 调整窗口高度: \(Int(newHeight))px (文本高度: \(Int(textHeight))px)")
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
