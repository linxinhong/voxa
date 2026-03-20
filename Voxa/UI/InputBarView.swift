//
//  InputBarView.swift
//  Voxa
//

import SwiftUI
import AppKit

struct InputBarView: View {
    @ObservedObject var appState: AppState
    @StateObject private var statsManager = StatsManager.shared
    @StateObject private var statsWindowController = StatsWindowController.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第1行：10px【麦克风】10px【partial文本（左对齐）】10px【时长】10px【风格标签】10px
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // 麦克风按钮：点击暂停/恢复录音
                Button(action: {
                    NotificationCenter.default.post(name: .togglePauseRecording, object: nil)
                }) {
                    Image(systemName: appState.isPaused ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(appState.isPaused ? .red : (appState.isRecording ? .green : .gray))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(appState.isPaused ? "恢复录音" : "暂停录音")
                .accessibilityHint(appState.isPaused ? "点击继续录音" : "点击暂停录音")

                Text(appState.partialText.isEmpty ? " " : appState.partialText)
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 时长显示（可点击 toggle）
                Button(action: {
                    statsWindowController.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .medium))
                        Text("[\(statsManager.formatDuration(statsManager.currentSessionSeconds))]")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(statsWindowController.isVisible ? .orange : .gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(statsWindowController.isVisible ? Color.orange.opacity(0.15) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .frame(minHeight: 44)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("使用统计")
                .accessibilityHint("点击查看使用时长和费用统计")
                
                // 风格标签（固定宽度约4个字）
                Text(appState.currentPolishName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
                    .frame(width: 50, alignment: .center)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.15))
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 0)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
            )
            
            // 第2行：10px【输入框（自动换行）】10px
            TextEditorRepresentable(
                text: $appState.confirmedText,
                cursorOffset: $appState.cursorOffset,
                isEditable: !appState.isPolishing,
                onHeightChange: { height in
                    appState.editorHeight = max(24, height)
                }
            )
            .frame(minHeight: 24, maxHeight: 400)  // 默认1行（24px），最大400px
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white)
            .cornerRadius(8)
            .padding(.bottom, 10)  // 第二行下方额外 10px，加上 VStack 的 10px = 20px
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(radius: 4)
        )
        .frame(width: 440)
        .onAppear {
            setupEscapeMonitor()
        }
    }

    private func setupEscapeMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // keyCode 36 = Return/Enter, 53 = ESC
            if event.keyCode == 53 {
                NotificationCenter.default.post(name: .hidePanel, object: nil)
                return nil
            }
            // 调试：记录回车键
            if event.keyCode == 36 {
                VoxaLog("[InputBar] 检测到回车键")
            }
            return event
        }
    }
}

extension Notification.Name {
    static let hidePanel = Notification.Name("hidePanel")
    static let textHeightDidChange = Notification.Name("textHeightDidChange")
    static let toggleRecording = Notification.Name("toggleRecording")
    static let togglePauseRecording = Notification.Name("togglePauseRecording")
}

struct TextEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorOffset: Int
    let isEditable: Bool
    let onHeightChange: (CGFloat) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.autoresizingMask = [.width, .height]

        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isFieldEditor = false  // 不作为 fieldEditor，允许独立编辑
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = .black
        textView.backgroundColor = .white
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        
        // 设置初始 frame，否则可能看不到
        textView.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        textView.minSize = NSSize(width: 0, height: 24)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.string = text
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autoresizingMask = [.width, .height]

        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 24)
        ])
        
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.parent = self
        
        // 设置 delegate 来处理文本变化（比 NotificationCenter 更可靠）
        textView.delegate = context.coordinator
        
        // 成为 first responder
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let scrollView = nsView.subviews.first as? NSScrollView,
              let textView = scrollView.documentView as? NSTextView else { return }

        textView.isEditable = isEditable

        // 防止循环更新
        guard !Coordinator.isUpdatingFromBinding else { return }

        // 只在文本真正不同时才更新
        if textView.string != text {
            // 检查是否有 marked text（输入法正在使用）
            let hasMarkedText = textView.hasMarkedText()

            // 如果输入法正在使用，跳过更新（不打断用户输入）
            if hasMarkedText {
                return
            }

            Coordinator.isUpdatingFromBinding = true
            textView.string = text
            textView.textColor = .black
            Coordinator.isUpdatingFromBinding = false

            // 同步光标位置
            if cursorOffset <= text.count {
                textView.setSelectedRange(NSRange(location: cursorOffset, length: 0))
            }
        }
        
        // 确保文本容器宽度正确
        let containerWidth = scrollView.frame.width
        if textView.textContainer?.containerSize.width != containerWidth {
            textView.textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        
        // 自动调整容器高度（只在高度真正变化时才更新和发送通知）
        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = max(24, usedRect.height + 16)

        if abs(textView.frame.height - newHeight) > 1 {
            textView.frame.size.height = newHeight
            scrollView.frame.size.height = newHeight

            // 只在高度真正变化时发送通知
            NotificationCenter.default.post(
                name: .textHeightDidChange,
                object: nil,
                userInfo: ["height": newHeight]
            )
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorRepresentable!
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        // 静态标志防止循环更新
        static var isUpdatingFromBinding = false
        
        init(_ parent: TextEditorRepresentable) {
            self.parent = parent
        }

        // NSTextViewDelegate 方法：文本变化时调用
        func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  let scrollView = scrollView else { return }

            // 防止循环更新
            guard !Coordinator.isUpdatingFromBinding else { return }

            // 更新 binding
            if parent.text != textView.string {
                Coordinator.isUpdatingFromBinding = true
                parent.text = textView.string
                Coordinator.isUpdatingFromBinding = false
            }

            // 计算文本高度（只在真正变化时才通知）
            let layoutManager = textView.layoutManager!
            let textContainer = textView.textContainer!
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = max(24, usedRect.height + 16)

            // 只在高度变化超过阈值时才发送通知
            if abs(textView.frame.height - newHeight) > 1 {
                parent.onHeightChange(newHeight)

                NotificationCenter.default.post(
                    name: .textHeightDidChange,
                    object: nil,
                    userInfo: ["height": newHeight]
                )
            }
        }
        
        // 保持旧方法兼容
        @objc func textChanged() {
            guard let textView = textView,
                  let scrollView = scrollView else { 
                VoxaLog("[TextEditor] textChanged: textView 或 scrollView 为 nil")
                return 
            }
            
            VoxaLog("[TextEditor] textChanged 被调用")
            
            parent.text = textView.string
            
            // 确保文本容器宽度与视图宽度一致
            let containerWidth = scrollView.frame.width
            if let textContainer = textView.textContainer {
                if textContainer.containerSize.width != containerWidth {
                    textContainer.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
                }
                
                // 调整高度并发送通知
                let layoutManager = textView.layoutManager!
                layoutManager.ensureLayout(for: textContainer)
                let usedRect = layoutManager.usedRect(for: textContainer)
                let newHeight = max(24, usedRect.height + 16)
                
                if abs(textView.frame.height - newHeight) > 1 {
                    textView.frame.size.height = newHeight
                    scrollView.frame.size.height = newHeight
                }
                
                VoxaLog("[TextEditor] 高度变化: \(Int(newHeight))px, 文本长度: \(textView.string.count)")
                
                // 每次都发送通知（确保窗口高度更新）
                NotificationCenter.default.post(
                    name: .textHeightDidChange,
                    object: nil,
                    userInfo: ["height": newHeight]
                )
            }
        }
        
        // NSTextViewDelegate 方法：光标位置变化
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }
            let newOffset = textView.selectedRange.location
            if newOffset >= 0 && newOffset != parent.cursorOffset {
                parent.cursorOffset = newOffset
                VoxaLog("[TextEditor] 光标位置: \(newOffset)")
            }
        }
        
        // 保持旧方法兼容
        @objc func selectionChanged() {
            guard let textView = textView else { return }
            let newOffset = textView.selectedRange.location
            if newOffset >= 0 && newOffset != parent.cursorOffset {
                parent.cursorOffset = newOffset
            }
        }
    }
}
