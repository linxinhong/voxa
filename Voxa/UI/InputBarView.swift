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
        VStack(alignment: .leading, spacing: 6) {
            // 第1行：Partial（浅灰背景）
            HStack(spacing: 8) {
                Text(appState.partialText.isEmpty ? " " : appState.partialText)
                    .font(.system(size: 14))
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Spacer()
                
                // 麦克风图标
                if appState.hasPending {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                        .foregroundColor(appState.partialText.isEmpty ? .gray : .green)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(6)
            
            // 第2行：Confirmed（白色背景 + 星星）
            HStack(spacing: 8) {
                // NSTextView 包装
                TextEditorView(
                    text: $appState.confirmedText,
                    cursorOffset: $appState.cursorOffset,
                    isEditable: !appState.isPolishing
                )
                .frame(height: max(24, min(120, estimateHeight(appState.confirmedText))))
                
                // 星星按钮
                PolishButton(isPolishing: appState.isPolishing) {
                    await polishPartial()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white)
            .cornerRadius(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color.white
                .cornerRadius(12)
                .shadow(radius: 4)
        )
        .frame(width: 450)
    }
    
    func estimateHeight(_ text: String) -> CGFloat {
        let lineCount = text.split(separator: "\n").count
        return CGFloat(lineCount) * 20 + 8
    }
    
    func polishPartial() async {
        let textToPolish = appState.confirmedText
        guard !textToPolish.isEmpty else { return }
        
        appState.startPolishing()
        let polished = await Polisher.polish(textToPolish)
        appState.finishPolishing(polished)
    }
}

// MARK: - 星星按钮

struct PolishButton: View {
    let isPolishing: Bool
    let action: () async -> Void
    @State private var isBlinking = false
    
    var body: some View {
        Button(action: {
            Task { await action() }
        }) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(.orange)
                .opacity(isBlinking ? 0.3 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isPolishing)
        .onChange(of: isPolishing) { polishing in
            if polishing {
                withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                    isBlinking = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isBlinking = false
                }
            }
        }
    }
}

// MARK: - NSTextView 包装

struct TextEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var cursorOffset: Int
    let isEditable: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor.black
        textView.backgroundColor = .white
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesInspectorBar = false
        textView.allowsUndo = true
        
        // 自动换行
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autoresizingMask = [.width, .height]
        
        context.coordinator.textView = textView
        
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
        textView.isEditable = isEditable
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(cursorOffset, text.count), length: 0))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextEditorView
        weak var textView: NSTextView?
        
        init(_ parent: TextEditorView) {
            self.parent = parent
        }
        
        @objc func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            parent.text = textView.string
            parent.cursorOffset = textView.selectedRange.location
        }
    }
}
