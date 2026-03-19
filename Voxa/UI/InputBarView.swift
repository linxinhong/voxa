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
        VStack(alignment: .leading, spacing: 4) {
            // 第1行：Partial（浅灰背景 + 右侧麦克风）
            PartialRowView(
                partialText: appState.partialText,
                hasPending: appState.hasPending,
                isRecording: appState.isRecording
            )
            .frame(maxWidth: .infinity)
            
            // 第2行：Confirmed（白色背景）+ 星星按钮
            ConfirmedRowView(
                appState: appState,
                onPolish: polishPartial
            )
            .frame(maxWidth: .infinity)
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
    
    /// 润色 partial 文本并全量更新 confirmedText（带锁定）
    func polishPartial() async {
        let textToPolish = appState.partialText
        guard !textToPolish.isEmpty else { return }
        
        // 1. 开始润色：锁定文本框
        appState.startPolishing()
        
        // 2. 执行润色
        let polished = await Polisher.polish(textToPolish)
        
        // 3. 完成润色：替换文本，光标定位到最后，解锁
        appState.finishPolishing(polished)
    }
}

// MARK: - 第1行：Partial（浅灰背景）

struct PartialRowView: View {
    let partialText: String
    let hasPending: Bool
    let isRecording: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Partial 文本（黑色，背景是灰色）
            Text(partialText.isEmpty ? " " : partialText)
                .font(.system(size: 14))
                .foregroundColor(.black)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 右侧：麦克风图标（常驻）
            if hasPending {
                // Final 到达：绿色闪烁
                Image(systemName: "mic.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15).repeatCount(3, autoreverses: true), value: hasPending)
            } else {
                // 常驻灰色麦克风，有 partial 时闪烁
                MicBlinkingView(hasContent: !partialText.isEmpty)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(6)
        .frame(minHeight: 28)
    }
}

// 麦克风闪烁视图（灰色-绿色-灰色-绿色）
struct MicBlinkingView: View {
    let hasContent: Bool
    @State private var isGreen = false
    
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 14))
            .foregroundColor(isGreen ? .green : .gray)
            .onChange(of: hasContent) { newValue in
                if newValue {
                    // 有内容时开始闪烁
                    withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                        isGreen = true
                    }
                } else {
                    // 无内容时停止闪烁，恢复灰色
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isGreen = false
                    }
                }
            }
    }
}

// MARK: - 第2行：Confirmed（白色背景 + 星星按钮）

struct ConfirmedRowView: View {
    @ObservedObject var appState: AppState
    let onPolish: () async -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Confirmed 文本编辑区（润色时锁定）
            ConfirmedTextView(
                text: $appState.confirmedText,
                cursorOffset: $appState.cursorOffset,
                isEditable: !appState.isPolishing
            )
            .frame(maxWidth: .infinity)
            
            // 星星润色按钮（常驻橙色，点击润色并全量更新）
            Button(action: {
                Task { await onPolish() }
            }) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
            }
            .buttonStyle(PlainButtonStyle())
            .help("润色当前文本并替换全部内容")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white)
        .cornerRadius(6)
        .frame(minHeight: 28)
    }
}

// MARK: - Confirmed 文本编辑视图

struct ConfirmedTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorOffset: Int
    let isEditable: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.black
        textView.backgroundColor = .white
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        
        // 启用标准编辑行为（Cmd+A/C/V/X 等）
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        
        // 注意：macOS NSTextView 原生支持 Emacs 快捷键（Ctrl+A/E/F/B 等）
        
        textView.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
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
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionDidChange),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        
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
        
        // 更新可编辑状态
        textView.isEditable = isEditable
        
        // 同步文本
        if textView.string != text {
            context.coordinator.syncText(text, cursorPosition: cursorOffset)
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
            
            // 润色中时不更新
            guard self.parent.isEditable else { return }
            
            let newText = textView.string
            Task { @MainActor in
                self.parent.text = newText
            }
            
            updateHeight()
        }
        
        func syncText(_ text: String, cursorPosition: Int) {
            guard let textView = textView else { return }
            guard !isSyncing else { return }
            
            isSyncing = true
            
            textView.string = text
            
            let validPosition = min(cursorPosition, text.count)
            textView.setSelectedRange(NSRange(location: validPosition, length: 0))
            
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            textView.needsDisplay = true
            
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
