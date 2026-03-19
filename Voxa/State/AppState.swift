//
//  AppState.swift
//  Voxa
//
//  Central application state managed by MainActor.
//

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    // MARK: - UI State
    
    /// The current text displayed in the input bar
    @Published var text: String = ""
    
    /// Whether currently recording
    @Published var isRecording: Bool = false
    
    /// Whether polishing is enabled
    @Published var polishEnabled: Bool = true
    
    /// Current cursor position in the text
    @Published var cursorPosition: Int = 0
    
    /// Whether user is currently editing (acts as a lock)
    @Published var isEditing: Bool = false
    
    /// Pending ASR updates while editing
    private var pendingPartial: String? = nil
    private var pendingFinals: [String] = []
    
    // MARK: - Internal State
    
    /// The target application to inject text into
    var targetApp: NSRunningApplication?
    
    /// Confirmed text that won't be overwritten by partial results
    var confirmedText: String = ""
    
    /// Last partial ASR result (unconfirmed)
    var lastPartial: String = ""
    
    /// Track where partial was inserted for replacement
    private var partialInsertPosition: Int = 0
    
    // MARK: - Methods
    
    /// Append final ASR result at cursor position
    func appendFinal(_ text: String) {
        // 如果用户正在编辑，暂存 final 更新
        if isEditing {
            pendingFinals.append(text)
            return
        }
        
        // 如果 final 文本为空，不处理
        guard !text.isEmpty else { return }
        
        applyFinal(text)
    }
    
    /// Apply a final ASR result
    private func applyFinal(_ text: String) {
        let cleaned = Cleaner.clean(text)
        
        // 在光标位置插入最终文本
        let insertPos = min(cursorPosition, self.text.count)
        
        // 使用 NSString 处理多行文本的索引
        let nsText = self.text as NSString
        let prefix = nsText.substring(to: insertPos)
        let suffix = nsText.substring(from: insertPos)
        
        self.text = prefix + cleaned + suffix
        
        // 更新 confirmedText 为整个文本
        confirmedText = self.text
        lastPartial = ""
        partialInsertPosition = 0
        
        // 更新光标位置到新插入文本之后
        cursorPosition = insertPos + cleaned.count
    }
    
    /// Update partial ASR result at cursor position
    func updatePartial(_ text: String) {
        // 如果用户正在编辑，暂存更新，不立即应用
        if isEditing {
            pendingPartial = text
            return
        }
        
        // 如果 partial 文本为空，不处理
        guard !text.isEmpty else { return }
        
        // 如果有上一次的 partial，先删除它
        if !lastPartial.isEmpty {
            removeLastPartial()
        }
        
        // 在光标位置插入新的 partial
        let insertPos = min(cursorPosition, self.text.count)
        
        // 使用 NSString 处理多行文本的索引
        let nsText = self.text as NSString
        let prefix = nsText.substring(to: insertPos)
        let suffix = nsText.substring(from: insertPos)
        
        self.text = prefix + text + suffix
        
        // 记录插入位置和长度，用于下次替换
        partialInsertPosition = insertPos
        lastPartial = text
        
        // 不移动光标位置，保持在原处
    }
    
    /// Remove the last partial text that was inserted
    private func removeLastPartial() {
        guard !lastPartial.isEmpty else { return }
        
        // 检查位置是否有效
        guard partialInsertPosition + lastPartial.count <= text.count else {
            // 文本已被用户修改，无法删除，直接重置
            lastPartial = ""
            return
        }
        
        // 使用 NSString 处理多行文本
        let nsText = text as NSString
        let prefix = nsText.substring(to: partialInsertPosition)
        let suffix = nsText.substring(from: partialInsertPosition + lastPartial.count)
        text = prefix + suffix
        
        // 如果光标在删除区域之后，调整光标位置
        if cursorPosition > partialInsertPosition + lastPartial.count {
            cursorPosition -= lastPartial.count
        } else if cursorPosition > partialInsertPosition {
            cursorPosition = partialInsertPosition
        }
    }
    
    /// Reset state for new recording session
    func reset() {
        text = ""
        confirmedText = ""
        lastPartial = ""
        partialInsertPosition = 0
        cursorPosition = 0
        pendingPartial = nil
        pendingFinals = []
        isEditing = false
    }
    
    /// Called when user starts editing (acquire lock)
    func beginEditing() {
        isEditing = true
        // 只在有 ASR 内容暂存时才记录日志
        if pendingPartial != nil || !pendingFinals.isEmpty {
            NSLog("[Voxa] 开始编辑，暂停 ASR 更新")
        }
    }
    
    /// Called when user ends editing (release lock and apply pending updates)
    func endEditing() {
        isEditing = false
        
        // 应用暂存的 partial
        if let pending = pendingPartial {
            NSLog("[Voxa] 结束编辑，应用暂存的 ASR 更新")
            updatePartial(pending)
            pendingPartial = nil
        }
        
        // 应用暂存的 finals
        for final in pendingFinals {
            applyFinal(final)
        }
        if !pendingFinals.isEmpty {
            NSLog("[Voxa] 应用了 \(pendingFinals.count) 条暂存的 final 更新")
            pendingFinals = []
        }
    }
    
    /// Get final text for injection
    func getFinalText() -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
