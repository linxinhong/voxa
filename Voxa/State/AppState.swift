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
    
    // MARK: - Methods
    
    /// Reset state for new recording session
    func reset() {
        text = ""
        confirmedText = ""
        currentPartial = ""
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
    
    /// Apply a final ASR result
    private func applyFinal(_ finalText: String) {
        // 清洗 final 文本
        let cleaned = Cleaner.clean(finalText)
        
        // 将清洗后的文本追加到已确认文本
        confirmedText += cleaned
        
        // 清空当前 partial（因为已经确认）
        currentPartial = ""
        
        // 更新显示文本
        text = confirmedText
        
        // 更新光标位置到文本末尾
        cursorPosition = text.count
        
        VoxaLog("[AppState] applyFinal: added=\"\(cleaned)\", confirmed=\"\(confirmedText)\"")
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
        
        // 应用暂存的 finals
        for final in pendingFinals {
            applyFinal(final)
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
