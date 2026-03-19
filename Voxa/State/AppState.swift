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
    
    /// Confirmed text (excluding current partial)
    private(set) var confirmedText: String = ""
    
    /// Current partial text (unconfirmed, will be replaced)
    private(set) var currentPartial: String = ""
    
    /// Pending final text waiting for user to insert
    @Published var pendingFinalText: String = ""
    
    // MARK: - Methods
    
    /// Reset state for new recording session
    func reset() {
        text = ""
        confirmedText = ""
        currentPartial = ""
        pendingFinalText = ""
        cursorPosition = 0
        pendingPartial = nil
        pendingFinals = []
        isEditing = false
    }
    
    /// Update partial ASR result - 显示 partial 但不保存到 confirmedText
    func updatePartial(_ partialText: String) {
        // 如果用户正在编辑，暂存更新
        if isEditing {
            pendingPartial = partialText
            return
        }
        
        // 更新 currentPartial
        currentPartial = partialText
        
        // 显示：已确认 + partial（partial 会变化）
        let newText = confirmedText + currentPartial
        
        // 只有当文本真正变化时才更新
        if newText != text {
            text = newText
            VoxaLog("[AppState] updatePartial: confirmed=\(confirmedText.count)字, partial=\(currentPartial.count)字")
        }
    }
    
    /// Append final ASR result - confirms the partial and adds new text
    func appendFinal(_ finalText: String) {
        // 如果用户正在编辑，暂存 final 更新
        if isEditing {
            pendingFinals.append(finalText)
            return
        }
        
        // 如果 final 文本为空，不处理
        guard !finalText.isEmpty else { return }
        
        applyFinal(finalText)
    }
    
    /// 接收 final 但不自动插入，保存到 pendingFinalText 等待用户点击
    private func applyFinal(_ finalText: String) {
        // 清洗 final 文本
        let cleaned = Cleaner.clean(finalText)
        
        // 保存到 pendingFinalText，不清空 partial（保持第1行显示）
        pendingFinalText = cleaned
        
        VoxaLog("[AppState] applyFinal: saved to pendingFinalText=\"\(cleaned)\"")
    }
    
    /// 用户点击插入按钮，将 pendingFinalText 插入到光标位置
    func insertPendingFinal() {
        guard !pendingFinalText.isEmpty else { return }
        
        // 在光标位置插入文本
        let insertPos = min(cursorPosition, text.count)
        let nsText = text as NSString
        let prefix = nsText.substring(to: insertPos)
        let suffix = nsText.substring(from: insertPos)
        
        let newText = prefix + pendingFinalText + suffix
        text = newText
        confirmedText = newText
        
        // 更新光标位置到插入文本之后
        cursorPosition = insertPos + pendingFinalText.count
        
        VoxaLog("[AppState] insertPendingFinal: inserted=\"\(pendingFinalText)\" at position \(insertPos)")
        
        // 清空 pending 和 partial
        pendingFinalText = ""
        currentPartial = ""
    }
    
    /// Called when user starts editing (acquire lock)
    func beginEditing() {
        isEditing = true
        if pendingPartial != nil || !pendingFinals.isEmpty {
            VoxaLog("[Voxa] 开始编辑，暂停 ASR 更新")
        }
    }
    
    /// Called when user ends editing (release lock and apply pending updates)
    func endEditing() {
        isEditing = false
        
        // 应用暂存的 partial
        if let pending = pendingPartial {
            VoxaLog("[Voxa] 结束编辑，应用暂存的 ASR 更新")
            updatePartial(pending)
            pendingPartial = nil
        }
        
        // 应用暂存的 finals（直接插入，因为用户已结束编辑）
        for final in pendingFinals {
            let cleaned = Cleaner.clean(final)
            confirmedText += cleaned
        }
        if !pendingFinals.isEmpty {
            text = confirmedText
            pendingFinals = []
        }
        if !pendingFinals.isEmpty {
            VoxaLog("[Voxa] 应用了 \(pendingFinals.count) 条暂存的 final 更新")
            pendingFinals = []
        }
    }
    
    /// Get final text for injection
    func getFinalText() -> String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
