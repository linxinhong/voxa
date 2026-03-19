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
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        // 设置 hugging 优先级让视图根据内容调整大小
        hostingView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        // 启用 layer 并设置圆角遮罩
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 80))
        panel.contentView = hostingView
        
        // 让面板支持自动调整大小（基于内容）
        panel.contentMinSize = NSSize(width: 440, height: 60)
        panel.contentMaxSize = NSSize(width: 440, height: 400)
        
        // 监听内容高度变化，同步调整窗口
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textHeightDidChange),
            name: .textHeightDidChange,
            object: nil
        )
        
        self.panel = panel
    }
    
    @objc private func textHeightDidChange() {
        guard let panel = panel else { return }
        
        // 使用 fittingSize 获取理想大小
        if let hostingView = panel.contentView as? NSHostingView<InputBarView> {
            let fittingSize = hostingView.fittingSize
            let newHeight = min(max(fittingSize.height, 60), 400)
            
            var frame = panel.frame
            if abs(frame.height - newHeight) > 5 {
                // 保持顶部位置不变，调整高度
                frame.origin.y += frame.height - newHeight
                frame.size.height = newHeight
                panel.setFrame(frame, display: true, animate: false)
            }
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
