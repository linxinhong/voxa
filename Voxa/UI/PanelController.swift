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
        
        let hosting = NSHostingView(rootView: contentView)
        hosting.sizingOptions = [.preferredContentSize]
        hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 100)
        
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
    
    /// 根据内容调整窗口大小
    private func fitPanelToContent(animated: Bool = false) {
        guard let panel = panel, let hosting = hostingView else { return }
        
        // 强制布局计算
        hosting.layoutSubtreeIfNeeded()
        
        // 获取内容的理想大小
        let fittingSize = hosting.fittingSize
        let newHeight = min(max(fittingSize.height, 60), 400)
        
        var frame = panel.frame
        guard abs(frame.height - newHeight) > 5 else { return }
        
        // 保持顶部位置不变，调整高度
        frame.origin.y += frame.height - newHeight
        frame.size.height = newHeight
        
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        
        VoxaLog("[Panel] 调整窗口高度: \(Int(newHeight))px")
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
        // 直接使用 fittingSize 计算高度
        fitPanelToContent(animated: true)
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
