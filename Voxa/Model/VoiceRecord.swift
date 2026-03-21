//
//  VoiceRecord.swift
//  Voxa
//
//  Single voice record model for the memory system.
//

import Foundation

/// 单条语音记录
struct VoiceRecord: Identifiable, Codable {
    /// 唯一标识符
    let id: UUID

    /// 时间戳
    let timestamp: Date

    /// 语音转文字结果
    let text: String

    /// 录音时长（秒）
    let duration: TimeInterval

    /// 目标应用（如 com.mitchellh.ghostty）
    let targetApp: String?

    /// AI 分类（工作/想法/TODO/闲聊）
    var category: Category?

    /// AI 生成的标题
    var title: String?

    /// 标签
    var tags: [String]?

    enum Category: String, Codable {
        case work   // 工作
        case idea   // 想法
        case todo   // TODO
        case chat   // 闲聊
    }
}

/// 日期的语音记录集合
struct DailyRecords: Codable {
    /// 日期（只保留日期部分，时间为 00:00:00）
    let date: Date

    /// 当天的所有记录
    var records: [VoiceRecord]

    /// AI 生成的日报
    var summary: DailySummary?

    init(date: Date) {
        // 将日期归一化为 00:00:00
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.date = calendar.date(from: components) ?? date
        self.records = []
        self.summary = nil
    }

    /// 添加一条记录
    mutating func addRecord(_ record: VoiceRecord) {
        records.append(record)
    }

    /// 计算总录音时长（分钟）
    var totalDuration: TimeInterval {
        records.reduce(0) { $0 + $1.duration }
    }

    /// 按分类统计
    var categoryCounts: [VoiceRecord.Category: Int] {
        var counts: [VoiceRecord.Category: Int] = [:]
        for record in records {
            if let category = record.category {
                counts[category, default: 0] += 1
            }
        }
        return counts
    }

    /// 按时间降序排列的记录（最新 → 最久）
    var sortedRecords: [VoiceRecord] {
        return records.sorted(by: { $0.timestamp > $1.timestamp })
    }
}

/// 日报总结
struct DailySummary: Identifiable, Codable {
    let id: UUID
    let date: Date

    /// 记录数量
    let recordCount: Int

    /// 总时长（秒）
    let totalDuration: TimeInterval

    /// 分类统计
    let categoryCounts: [CategoryCount]

    /// AI 生成的总结文本
    let summary: String

    /// 主题分布（每个主题的占比）
    let topicDistribution: [String: Int]?

    /// 关键洞察
    let insights: [String]?

    struct CategoryCount: Codable {
        let category: VoiceRecord.Category
        let count: Int
    }

    init(id: UUID = UUID(), date: Date, recordCount: Int, totalDuration: TimeInterval, categoryCounts: [CategoryCount], summary: String, topicDistribution: [String: Int]? = nil, insights: [String]? = nil) {
        self.id = id
        self.date = date
        self.recordCount = recordCount
        self.totalDuration = totalDuration
        self.categoryCounts = categoryCounts
        self.summary = summary
        self.topicDistribution = topicDistribution
        self.insights = insights
    }
}
