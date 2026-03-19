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
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 🔴 录音指示器
            Circle()
                .fill(appState.isRecording ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
                .padding(.top, 8)
                .opacity(appState.isRecording ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.3), value: appState.isRecording)
            
            VStack(alignment: .leading, spacing: 4) {
                // 第1行：Partial 区域（灰色，只读）+ ⬇ 按钮
                HStack(spacing: 8) {
                    // Partial 文本（整句覆盖显示）
                    PartialTextView(
                        text: appState.partialText,
                        minHeight: 20
                    )
                    .frame(maxWidth: .infinity, minHeight: 20)
                    
                    // 绿色闪烁图标（当有 pending 时闪烁）
                    if appState.hasPending {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.green)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.15).repeatCount(3, autoreverses: true), value: appState.hasPending)
                    }
                }
                .frame(minWidth: 300, maxWidth: 500, minHeight: 20)
                // 空时隐藏但保持空间
                .opacity(appState.partialText.isEmpty && !appState.hasPending ? 0 : 1)
                
                // 第2行：Confirmed 区域（黑色，可编辑）
                ConfirmedTextView(
                    text: $appState.confirmedText,
                    cursorOffset: $appState.cursorOffset,
                    minHeight: 24,
                    maxHeight: 120
                )
                .frame(minWidth: 300, maxWidth: 500)
            }
            
            // ✨ 润色开关
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
            Color.white
                .cornerRadius(12)
                .shadow(radius: 4)
        )
        .frame(minWidth: 400, maxWidth: 600)
    }
}

// MARK: - 第1行：Partial 文本视图（灰色，只读，整句覆盖）

struct PartialTextView: NSViewRepresentable {
    let text: String
    let minHeight: CGFloat
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.textColor = NSColor.darkGray
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}

// MARK: - 第2行：Confirmed 文本视图（黑色，可编辑）

struct ConfirmedTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorOffset: Int
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.black
        textView.backgroundColor = .white
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        
        // 初始 frame
        textView.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        
        // 垂直可扩展
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.autoresizingMask = [.width]
        
        // 初始文本
        textView.string = text
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.documentView = textView
        scrollView.autoresizingMask = [.width, .height]
        scrollView.contentView.autoresizingMask = [.width, .height]
        scrollView.contentView.autoresizesSubviews = true
        
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        
        // 监听选择变化（光标位置）
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
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // 同步 confirmedText
        if textView.string != text {
            context.coordinator.syncText(text)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ConfirmedTextView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var isSyncing = false
        private var lastHeight: CGFloat = 0
        
        init(_ parent: ConfirmedTextView) {
            self.parent = parent
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func selectionDidChange(_ notification: Notification) {
            guard let textView = textView,
                  notification.object as? NSTextView === textView else { return }
            
            // 更新光标位置
            let newOffset = textView.selectedRange.location
            Task { @MainActor in
                if newOffset != self.parent.cursorOffset {
                    self.parent.cursorOffset = newOffset
                }
            }
        }
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  notification.object as? NSTextView === textView,
                  !isSyncing else { return }
            
            // 用户正在编辑，通知 AppState
            Task { @MainActor in
                // 触发编辑锁
                // Note: 需要在 AppState 中处理编辑锁
            }
            
            // 同步文本到 parent
            let newText = textView.string
            Task { @MainActor in
                self.parent.text = newText
            }
            
            // 更新高度
            updateHeight()
        }
        
        /// 从外部同步文本
        func syncText(_ text: String) {
            guard let textView = textView else { return }
            guard !isSyncing else { return }
            
            isSyncing = true
            
            // 保存当前选择范围
            let selectedRange = textView.selectedRange
            
            // 更新文本
            textView.string = text
            
            // 恢复选择范围
            let newLength = text.count
            if selectedRange.location <= newLength {
                textView.setSelectedRange(selectedRange)
            }
            
            // 强制刷新
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.needsDisplay = true
            
            // 更新高度
            updateHeight()
            
            isSyncing = false
        }
        
        func updateHeight() {
            guard let textView = textView,
                  let scrollView = scrollView else { return }
            
            let textContainer = textView.textContainer!
            let layoutManager = textView.layoutManager!
            
            layoutManager.ensureLayout(for: textContainer)
            
            let usedRect = layoutManager.usedRect(for: textContainer)
            let textHeight = usedRect.height + textView.textContainerInset.height * 2 + 4
            
            let newHeight = max(24, min(textHeight, 120))
            
            if abs(newHeight - lastHeight) > 2 {
                lastHeight = newHeight
                
                guard let window = scrollView.window else { return }
                var frame = window.frame
                let heightDiff = newHeight - scrollView.frame.height
                frame.origin.y -= heightDiff
                frame.size.height += heightDiff
                if frame.size.height < 60 {
                    frame.size.height = 60
                }
                window.setFrame(frame, display: true, animate: false)
            }
            
            let needsScroller = textHeight > 120
            if scrollView.hasVerticalScroller != needsScroller {
                scrollView.hasVerticalScroller = needsScroller
            }
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
