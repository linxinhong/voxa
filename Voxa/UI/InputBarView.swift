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
            // Recording indicator
            Circle()
                .fill(appState.isRecording ? Color.red : Color.gray)
                .frame(width: 8, height: 8)
                .padding(.top, 8)
                .opacity(appState.isRecording ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.3), value: appState.isRecording)
            
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：Partial 文本（灰色，实时）
                if !appState.currentPartial.isEmpty {
                    PartialTextView(
                        text: appState.currentPartial,
                        minHeight: 20,
                        maxHeight: 60
                    )
                    .frame(minWidth: 300, maxWidth: 500)
                }
                
                // 第二行：Confirmed 文本（黑色，固定）
                ConfirmedTextView(
                    text: $appState.text,
                    confirmedText: appState.confirmedText,
                    cursorPosition: $appState.cursorPosition,
                    minHeight: 24,
                    maxHeight: 120
                )
                .frame(minWidth: 300, maxWidth: 500)
            }
            
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
    }
}

// MARK: - Partial Text View (灰色，实时)

struct PartialTextView: NSViewRepresentable {
    let text: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.secondaryLabelColor  // 灰色
        textView.backgroundColor = .clear
        textView.isRichText = false
        
        // 单行显示
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.textContainer?.maximumNumberOfLines = 1
        textView.textContainer?.lineBreakMode = .byTruncatingTail
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}

// MARK: - Confirmed Text View (黑色，固定)

struct ConfirmedTextView: NSViewRepresentable {
    @Binding var text: String
    let confirmedText: String
    @Binding var cursorPosition: Int
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.labelColor  // 黑色
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        
        // 设置初始 frame
        textView.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        
        // 垂直方向可扩展
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
        
        // 设置默认文本
        textView.string = confirmedText
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autoresizingMask = [.width, .height]
        scrollView.contentView.autoresizingMask = [.width, .height]
        scrollView.contentView.autoresizesSubviews = true
        
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
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // 只显示 confirmedText（不包含 partial）
        if textView.string != confirmedText {
            context.coordinator.syncConfirmedText(confirmedText)
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
            
            let newPosition = textView.selectedRange.location
            Task { @MainActor in
                self.parent.cursorPosition = newPosition
            }
        }
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  notification.object as? NSTextView === textView,
                  !isSyncing else { return }
            
            updateHeight()
            
            let newPosition = textView.selectedRange.location
            Task { @MainActor in
                self.parent.text = textView.string
                self.parent.cursorPosition = newPosition
            }
        }
        
        func syncConfirmedText(_ text: String) {
            guard let textView = textView else { return }
            guard !isSyncing else { return }
            
            isSyncing = true
            
            // 保存当前光标位置
            let currentPosition = textView.selectedRange.location
            
            // 更新文本
            textView.string = text
            
            // 恢复光标位置（如果可能）
            let newLength = text.count
            let restorePosition = min(currentPosition, newLength)
            textView.setSelectedRange(NSRange(location: restorePosition, length: 0))
            
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
            
            let newHeight = max(parent.minHeight, min(textHeight, parent.maxHeight))
            
            if abs(newHeight - lastHeight) > 2 {
                lastHeight = newHeight
                
                // 调整窗口大小
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
            
            let needsScroller = textHeight > parent.maxHeight
            if scrollView.hasVerticalScroller != needsScroller {
                scrollView.hasVerticalScroller = needsScroller
            }
            
            textView.scrollRangeToVisible(textView.selectedRange)
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
