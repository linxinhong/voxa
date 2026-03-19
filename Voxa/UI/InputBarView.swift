//
//  InputBarView.swift
//  Voxa
//

import SwiftUI
import AppKit

struct InputBarView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第1行：10px【麦克风】10px【partial文本（左对齐）】10px【风格标签】10px
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 12))
                    .foregroundColor(appState.hasPending ? .green : (appState.partialText.isEmpty ? .gray : .green))
                    .frame(width: 16, height: 16)
                
                Text(appState.partialText.isEmpty ? " " : appState.partialText)
                    .font(.system(size: 14))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 风格标签（固定宽度约4个字）
                Text(appState.currentPolishName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .frame(width: 48, alignment: .center)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(6)
            
            // 第2行：10px【输入框（自动换行）】10px
            TextEditorRepresentable(
                text: $appState.confirmedText,
                cursorOffset: $appState.cursorOffset,
                isEditable: !appState.isPolishing,
                onHeightChange: { height in
                    appState.editorHeight = height
                }
            )
            .frame(height: max(24, appState.editorHeight))  // 根据内容调整高度
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white)
            .cornerRadius(8)
        }
        .padding(10)
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
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = .black
        textView.backgroundColor = .white
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        textView.allowsUndo = true
        
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
        
        // 同步文本
        if textView.string != text {
            textView.string = text
        }
        
        // 同步光标位置（如果不同）
        let currentRange = textView.selectedRange
        if currentRange.location != cursorOffset && cursorOffset <= text.count {
            textView.setSelectedRange(NSRange(location: cursorOffset, length: 0))
        }
        
        // 确保文本容器宽度正确
        let containerWidth = scrollView.frame.width
        if textView.textContainer?.containerSize.width != containerWidth {
            textView.textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        
        // 自动调整容器高度
        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = max(24, usedRect.height + 16)
        
        if abs(textView.frame.height - newHeight) > 1 {
            textView.frame.size.height = newHeight
            scrollView.frame.size.height = newHeight
        }
        
        // 发送高度通知
        NotificationCenter.default.post(
            name: .textHeightDidChange,
            object: nil,
            userInfo: ["height": newHeight]
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorRepresentable!
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        
        init(_ parent: TextEditorRepresentable) {
            self.parent = parent
        }
        
        // NSTextViewDelegate 方法：文本变化时调用
        func textDidChange(_ notification: Notification) {
            guard let textView = textView,
                  let scrollView = scrollView else { return }
            
            parent.text = textView.string
            
            // 计算文本高度
            let text = textView.string as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: textView.font ?? NSFont.systemFont(ofSize: 15)]
            let containerWidth = scrollView.frame.width - 20
            let size = text.boundingRect(
                with: NSSize(width: max(containerWidth, 100), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).size
            
            let newHeight = max(24, size.height + 16)
            
            // 回调给 SwiftUI
            parent.onHeightChange(newHeight)
            
            // 发送通知给 PanelController
            NotificationCenter.default.post(
                name: .textHeightDidChange,
                object: nil,
                userInfo: ["height": newHeight]
            )
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
        
        @objc func selectionChanged() {
            guard let textView = textView else { return }
            // 同步光标位置到 AppState
            let newOffset = textView.selectedRange.location
            if newOffset >= 0 && newOffset != parent.cursorOffset {
                parent.cursorOffset = newOffset
            }
        }
    }
}
