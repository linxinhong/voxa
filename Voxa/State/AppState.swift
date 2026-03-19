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
    
    /// 第1行：partial 实时内容（整句覆盖，非追加，可被润色修改）
    @Published var partialText: String = ""
    
    /// 第2行：已确认的全部内容
    @Published var confirmedText: String = ""
    
    /// 是否有待确认的 final（控制 ⬇ 按钮显示）
    @Published var hasPending: Bool = false
    
    /// 待插入的 final 文本（已经过 Cleaner）
    @Published var pendingText: String = ""
    
    /// 第2行当前光标位置（UTF-16 offset）
    @Published var cursorOffset: Int = 0
    
    /// 是否正在录音
    @Published var isRecording: Bool = false
    
    /// 是否开启自动润色（默认关闭，改为手动点击星星润色）
    @Published var polishEnabled: Bool = false
    
    /// 是否用户正在编辑（编辑锁）
    @Published var isEditing: Bool = false
    
    /// 是否正在润色中（锁定文本框）
    @Published var isPolishing: Bool = false
    
    // MARK: - Internal State
    
    /// 目标应用
    var targetApp: NSRunningApplication?
    
    /// 暂存的 partial（编辑锁期间）
    private var pendingPartial: String? = nil
    
    /// 暂存的 final（编辑锁期间）
    private var pendingFinals: [String] = []
    
    // MARK: - Methods
    
    /// 重置状态（开始新录音会话）
    func reset() {
        partialText = ""
        confirmedText = ""
        hasPending = false
        pendingText = ""
        cursorOffset = 0
        pendingPartial = nil
        pendingFinals = []
        isEditing = false
    }
    
    /// 接收 partial：整句覆盖第1行（Paraformer partial 是覆盖语义）
    func updatePartial(_ text: String) {
        // 如果用户正在编辑，暂存
        if isEditing {
            pendingPartial = text
            return
        }
        
        // 直接覆盖 partialText（不是追加）
        partialText = text
        
        VoxaLog("[AppState] updatePartial: \"\(text)\"")
    }
    
    /// 接收 final：保留第1行，触发绿色图标闪烁，然后自动插入
    func receiveFinal(_ text: String) {
        // 如果用户正在编辑，暂存
        if isEditing {
            pendingFinals.append(text)
            return
        }
        
        // 清洗 final 文本
        let cleaned = Cleaner.clean(text)
        
        // 保存到 pendingText，设置 hasPending（触发绿色图标闪烁）
        pendingText = cleaned
        hasPending = true
        
        VoxaLog("[AppState] receiveFinal: \"\(cleaned)\"")
        
        // 延迟执行插入，让用户看到绿色图标闪烁
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms 闪烁时间
            self.autoInsertPending()
        }
    }
    
    /// 自动插入 pendingText 到 cursorOffset 位置
    private func autoInsertPending() {
        guard hasPending && !pendingText.isEmpty else {
            hasPending = false
            return
        }
        
        // 在 cursorOffset 位置插入
        let insertPos = min(cursorOffset, confirmedText.count)
        let nsText = confirmedText as NSString
        let prefix = nsText.substring(to: insertPos)
        let suffix = nsText.substring(from: insertPos)
        
        confirmedText = prefix + pendingText + suffix
        
        // 光标跟随到插入末尾
        cursorOffset = insertPos + pendingText.count
        
        VoxaLog("[AppState] autoInsert: \"\(pendingText)\" at \(insertPos), cursor now \(cursorOffset)")
        
        // 清空 pending 和第1行
        pendingText = ""
        hasPending = false
        partialText = ""  // 第1行清空
    }
    
    /// 清空 pending 状态
    func clearPending() {
        pendingText = ""
        hasPending = false
        partialText = ""
    }
    
    /// 用户开始编辑（获取编辑锁）
    func beginEditing() {
        guard !isPolishing else { return }  // 润色中禁止编辑
        isEditing = true
        if pendingPartial != nil || !pendingFinals.isEmpty {
            VoxaLog("[AppState] 开始编辑，暂停 ASR 更新")
        }
    }
    
    /// 用户结束编辑（释放编辑锁，应用暂存更新）
    func endEditing() {
        isEditing = false
        
        // 应用暂存的 partial
        if let pending = pendingPartial {
            partialText = pending
            pendingPartial = nil
        }
        
        // 应用暂存的 finals（直接追加到末尾）
        for final in pendingFinals {
            let cleaned = Cleaner.clean(final)
            confirmedText += cleaned
        }
        if !pendingFinals.isEmpty {
            cursorOffset = confirmedText.count
            pendingFinals = []
        }
    }
    
    /// 开始润色：锁定文本框
    func startPolishing() {
        isPolishing = true
        VoxaLog("[AppState] 开始润色，锁定文本框")
    }
    
    /// 完成润色：替换文本，光标定位到最后，解锁
    func finishPolishing(_ polishedText: String) {
        confirmedText = polishedText
        cursorOffset = polishedText.count  // 光标定位到最后
        isPolishing = false
        VoxaLog("[AppState] 润色完成，光标定位到 \(cursorOffset)")
    }
    
    /// 停止录音时的处理：如果有 pending 未确认，自动追加到末尾
    func finalizeOnStop() -> String {
        if hasPending && !pendingText.isEmpty {
            // 用户未点击 ⬇，自动追加到末尾
            confirmedText += pendingText
            clearPending()
        }
        return confirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 获取最终文本（用于注入目标应用）
    func getFinalText() -> String {
        return confirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
