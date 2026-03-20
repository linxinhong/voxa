//
//  StatsManager.swift
//  Voxa
//
//  语音转文字时长统计管理
//

import Foundation
import Combine

@MainActor
class StatsManager: ObservableObject {
    static let shared = StatsManager()
    
    // 价格常量：0.00024元/秒
    let pricePerSecond: Double = 0.00024
    
    // 当前会话时长（秒）
    @Published var currentSessionSeconds: Int = 0
    
    private var sessionStartTime: Date?
    private var timer: Timer?
    private var accumulatedSeconds: Int = 0
    
    // 配置文件路径
    private var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/voxa", isDirectory: true)
    }
    
    private var statsFile: URL {
        configDir.appendingPathComponent("stats.json")
    }
    
    // 内存中的统计数据
    private var dailyStats: [String: Int] = [:]  // ["2026-03-19": 3600]
    
    private init() {
        loadStats()
    }
    
    // MARK: - 会话控制
    
    // ASR 活跃状态
    private var isAsrActive: Bool = false
    private var asrActiveStartTime: Date?
    private var asrActiveAccumulatedSeconds: Int = 0
    
    /// ASR 开始处理语音（麦克风绿色）
    func markAsrActive() {
        guard !isAsrActive else { return }
        isAsrActive = true
        asrActiveStartTime = Date()
        
        // 启动定时器
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateAsrActiveDuration()
            }
        }
        
        VoxaLog("[Stats] ASR 活跃，开始计费")
    }
    
    /// ASR 静音（麦克风灰色）
    func markAsrInactive() {
        guard isAsrActive else { return }
        isAsrActive = false
        
        // 累加本次活跃时长
        if let startTime = asrActiveStartTime {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            asrActiveAccumulatedSeconds += elapsed
            asrActiveStartTime = nil
        }
        
        timer?.invalidate()
        timer = nil
        
        VoxaLog("[Stats] ASR 静音，暂停计费，当前累计: \(asrActiveAccumulatedSeconds)s")
    }
    
    /// 停止本次会话，保存时长
    func stopSession() {
        // 如果还在活跃状态，先结算
        if isAsrActive {
            markAsrInactive()
        }
        
        // 保存本次时长到当日
        let totalSessionSeconds = asrActiveAccumulatedSeconds
        addToToday(seconds: totalSessionSeconds)
        
        // 清理
        timer?.invalidate()
        timer = nil
        asrActiveAccumulatedSeconds = 0
        currentSessionSeconds = 0
        
        VoxaLog("[Stats] 会话结束，保存时长: \(totalSessionSeconds)s")
    }
    
    private func updateAsrActiveDuration() {
        guard isAsrActive, let startTime = asrActiveStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime))
        currentSessionSeconds = asrActiveAccumulatedSeconds + elapsed
    }
    
    private func updateCurrentSession() {
        guard let startTime = sessionStartTime else { return }
        let elapsed = Int(Date().timeIntervalSince(startTime))
        currentSessionSeconds = accumulatedSeconds + elapsed
    }
    
    // MARK: - 统计数据
    
    /// 今日时长（秒）
    func todayDuration() -> Int {
        let todayKey = formatDate(Date())
        return dailyStats[todayKey] ?? 0
    }
    
    /// 平均每日时长（秒）
    func averageDailyDuration() -> Int {
        guard !dailyStats.isEmpty else { return 0 }
        let total = dailyStats.values.reduce(0, +)
        return total / dailyStats.count
    }
    
    /// 本月时长（秒）
    func monthDuration() -> Int {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        
        var total = 0
        for (dateKey, seconds) in dailyStats {
            if let date = parseDate(dateKey) {
                let month = calendar.component(.month, from: date)
                let year = calendar.component(.year, from: date)
                if month == currentMonth && year == currentYear {
                    total += seconds
                }
            }
        }
        return total
    }
    
    /// 总时长（秒）- 历史累计
    func totalDuration() -> Int {
        return dailyStats.values.reduce(0, +)
    }
    
    /// 计算费用
    func calculateCost(seconds: Int) -> Double {
        return Double(seconds) * pricePerSecond
    }
    
    // MARK: - 数据持久化
    
    private func addToToday(seconds: Int) {
        let todayKey = formatDate(Date())
        dailyStats[todayKey, default: 0] += seconds
        saveStats()
    }
    
    private func loadStats() {
        guard FileManager.default.fileExists(atPath: statsFile.path) else { return }
        
        do {
            let data = try Data(contentsOf: statsFile)
            let decoder = JSONDecoder()
            dailyStats = try decoder.decode([String: Int].self, from: data)
        } catch {
            VoxaLog("[StatsManager] 加载统计失败: \(error)")
        }
    }
    
    private func saveStats() {
        do {
            // 确保目录存在
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(dailyStats)
            try data.write(to: statsFile)
        } catch {
            VoxaLog("[StatsManager] 保存统计失败: \(error)")
        }
    }
    
    // MARK: - 格式化
    
    /// 格式化为 MM:SS
    func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
    
    /// 格式化为 X小时X分X秒
    func formatDurationLong(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        if hours > 0 {
            return "\(hours)小时\(minutes)分\(secs)秒"
        } else if minutes > 0 {
            return "\(minutes)分\(secs)秒"
        } else {
            return "\(secs)秒"
        }
    }
    
    // MARK: - 辅助方法
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
