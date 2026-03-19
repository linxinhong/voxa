//
//  InputBarView.swift
//  Voxa
//
//  SwiftUI view for the floating input bar.
//

import SwiftUI
import AppKit
import Combine

struct InputBarView: View {
    @ObservedObject var appState: AppState
    @State private var textViewHeight: CGFloat = 24  // 初始1行高度
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Recording indicator
            Circle()
                .fill(appState.isRecording ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
                .padding(.top, 8)
                .opacity(appState.isRecording ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.3), value: appState.isRecording)
            
            // Multi-line text input with auto-expansion
            CursorTrackingTextView(
                text: $appState.text,
                cursorPosition: $appState.cursorPosition,
                minHeight: 24,    // 1行高度
                maxHeight: 120    // 最大5行左右
            )
            .frame(minWidth: 300, maxWidth: 500)
            
            // Polish toggle button
            Button(action: {
                appState.polishEnabled.toggle()
            }) {
                Image(systemName: appState.polishEnabled ? "sparkles" : "sparkles.slash")
                    .foregroundColor(appState.polishEnabled ? .yellow : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .help(appState.polishEnabled ? "润色已开启" : "润色已关闭")
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(12)
        )
        .frame(minWidth: 400, maxWidth: 600)
        .animation(.easeInOut(duration: 0.2), value: textViewHeight)
    }
}

// MARK: - Cursor Tracking Text View (Auto-expanding)

struct CursorTrackingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorPosition: Int
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    func makeNSView(context: Context) -> NSScrollView {
        // 创建 NSTextView
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        
        // 垂直方向可扩展，水平方向固定
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 0, height: 2)
        
        // 设置默认文本
        textView.string = self.text
        
        // 创建 NSScrollView
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false  // 默认不显示滚动条
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.contentView.autoresizingMask = [.width, .height]
        
        // 设置 coordinator 引用
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        
        // 监听选择变化
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        
        // 监听文本变化
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        
        // 初始计算高度
        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // 只有当外部文本变化时才更新（忽略 isSyncingFromAppState 检查，避免竞态）
        if textView.string != self.text {
            context.coordinator.syncText(from: self.text)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CursorTrackingTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isSyncingFromAppState = false
        var editingTimer: Timer?
        private var lastHeight: CGFloat = 0
        
        init(_ parent: CursorTrackingTextView) {
            self.parent = parent
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func selectionDidChange(_ notification: Notification) {
            guard let textView = textView,
                  notification.object as? NSTextView === textView else { return }
            
            let newPosition = getCurrentCursorPosition()
            Task { @MainActor in
                // 只更新光标位置，不触发编辑锁
                if newPosition != self.parent.cursorPosition {
                    self.parent.cursorPosition = newPosition
                }
            }
        }
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  notification.object as? NSTextView === textView,
                  !isSyncingFromAppState else { return }
            
            // 更新高度
            updateHeight()
            
            let newPosition = getCurrentCursorPosition()
            Task { @MainActor in
                self.parent.text = textView.string
                self.parent.cursorPosition = newPosition
            }
        }
        
        /// 计算并更新高度
        func updateHeight() {
            guard let textView = textView,
                  let scrollView = scrollView else { return }
            
            // 计算文本所需高度
            let textContainer = textView.textContainer!
            let layoutManager = textView.layoutManager!
            
            layoutManager.ensureLayout(for: textContainer)
            
            // 获取文本使用的矩形区域
            let usedRect = layoutManager.usedRect(for: textContainer)
            let textHeight = usedRect.height + textView.textContainerInset.height * 2 + 4  // 额外边距
            
            // 限制在最小和最大高度之间
            let newHeight = max(parent.minHeight, min(textHeight, parent.maxHeight))
            
            // 只有当高度变化超过阈值时才更新（避免频繁调整）
            if abs(newHeight - lastHeight) > 2 {
                lastHeight = newHeight
                
                // 调整窗口大小
                adjustWindowSize(to: newHeight)
            }
            
            // 如果超过最大高度，显示滚动条
            let needsScroller = textHeight > parent.maxHeight
            if scrollView.hasVerticalScroller != needsScroller {
                scrollView.hasVerticalScroller = needsScroller
            }
            
            // 确保光标可见
            textView.scrollRangeToVisible(textView.selectedRange)
        }
        
        /// 调整窗口大小以适应新高度
        private func adjustWindowSize(to newHeight: CGFloat) {
            guard let scrollView = scrollView,
                  let window = scrollView.window else { return }
            
            var frame = window.frame
            let heightDiff = newHeight - scrollView.frame.height
            
            // 从底部向上扩展，保持顶部位置不变
            frame.origin.y -= heightDiff
            frame.size.height += heightDiff
            
            // 确保最小高度
            if frame.size.height < 60 {
                frame.size.height = 60
            }
            
            window.setFrame(frame, display: true, animate: false)
        }
        
        /// 获取当前光标位置
        func getCurrentCursorPosition() -> Int {
            guard let textView = textView else { return 0 }
            return textView.selectedRange.location
        }
        
        /// 从外部同步文本
        func syncText(from text: String) {
            guard let textView = textView else { return }
            
            // 避免递归更新
            guard !isSyncingFromAppState else { return }
            isSyncingFromAppState = true
            
            NSLog("[UI] 同步文本到 TextView: \"\(text.prefix(50))\(text.count > 50 ? "..." : "")\"")
            
            // 保存当前光标位置
            let currentPosition = textView.selectedRange.location
            
            // 更新文本
            textView.string = text
            
            // 恢复光标位置（如果可能）
            let newLength = text.count
            let restorePosition = min(currentPosition, newLength)
            textView.setSelectedRange(NSRange(location: restorePosition, length: 0))
            
            // 更新高度
            updateHeight()
            
            // 立即重置标志，避免遗漏后续更新
            isSyncingFromAppState = false
        }
        
    }
}

// MARK: - Visual Effect View

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Preview

#Preview {
    InputBarView(appState: AppState())
}
