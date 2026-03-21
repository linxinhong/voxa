//
//  DailySummaryService.swift
//  Voxa
//
//  AI-powered daily summary generation service.
//

import Foundation

actor DailySummaryService {
    static let shared = DailySummaryService()

    private let endpoint = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    private var apiKey: String {
        if let envKey = ProcessInfo.processInfo.environment["DASHSCOPE_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return ConfigManager.shared.apiKey
    }

    private init() {}

    /// 生成指定日期的日报总结
    func generateSummary(for dailyRecords: DailyRecords) async throws -> DailySummary {
        guard !dailyRecords.records.isEmpty else {
            throw SummaryError.noRecords
        }

        guard !apiKey.isEmpty else {
            throw SummaryError.apiKeyMissing
        }

        VoxaLog("[DailySummaryService] 开始生成日报，记录数: \(dailyRecords.records.count)")

        // 从配置读取提示词
        let systemPrompt = ConfigManager.shared.dailyReportPrompt

        // 构建用户消息（包含所有记录和目标应用信息）
        let userMessage = buildUserMessage(from: dailyRecords)

        // 构建请求
        let requestBody: [String: Any] = [
            "model": "qwen-turbo",
            "input": [
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userMessage]
                ]
            ],
            "parameters": [
                "result_format": "message",
                "max_tokens": 2000
            ]
        ]

        guard let url = URL(string: endpoint) else {
            throw SummaryError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30  // 日报生成需要更长时间

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                VoxaLog("[DailySummaryService] API 返回错误: \(response)")
                throw SummaryError.apiError
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let output = json["output"] as? [String: Any],
                  let choices = output["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                VoxaLog("[DailySummaryService] API 响应解析失败")
                throw SummaryError.invalidResponse
            }

            let summaryText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            VoxaLog("[DailySummaryService] 日报生成成功，长度: \(summaryText.count) 字符")

            // 保存提示词用于调试
            let systemPrompt = ConfigManager.shared.dailyReportPrompt

            let summary = DailySummary(
                date: dailyRecords.date,
                recordCount: dailyRecords.records.count,
                totalDuration: dailyRecords.totalDuration,
                categoryCounts: buildCategoryCounts(from: dailyRecords),
                summary: summaryText,
                topicDistribution: nil,
                insights: nil,
                systemPrompt: systemPrompt
            )

            return summary

        } catch {
            VoxaLog("[DailySummaryService] 请求失败: \(error)")
            throw SummaryError.networkError
        }
    }

    // MARK: - 构建用户消息

    private func buildUserMessage(from dailyRecords: DailyRecords) -> String {
        var message = "语音记录日报\n\n"

        // 统计目标应用分布
        let appCounts = Dictionary(grouping: dailyRecords.records, by: { $0.targetApp })
            .mapValues { $0.count }
            .sorted(by: { $0.value > $1.value })

        if !appCounts.isEmpty {
            message += "【输入来源】\n"
            for (appBundle, count) in appCounts {
                let appName = appBundle ?? "未知应用"
                message += "- \(appName): \(count)条\n"
            }
            message += "\n"
        }

        // 格式化记录列表（精简版，节约 token）
        for (index, record) in dailyRecords.records.enumerated() {
            let timeStr = formatTime(record.timestamp)
            // duration 保留2位小数，去掉秒数部分显示
            let durationMin = String(format: "%.2f", record.duration / 60.0)
            var categoryTag = ""
            if let category = record.category {
                categoryTag = "[\(category.displayName)]"
            }
            let appTag = record.targetApp != nil ? "[\(record.targetApp!)]" : ""
            message += "\(index + 1). \(timeStr) \(durationMin)min \(categoryTag) \(appTag) \(record.text)\n"
        }

        // 添加生成要求
        message += "\n生成日报：概要(记录数/总时长/分类统计)、主要主题、关键要点"

        return message
    }

    // MARK: - 辅助方法

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }

    private func buildCategoryCounts(from dailyRecords: DailyRecords) -> [DailySummary.CategoryCount] {
        let counts = dailyRecords.categoryCounts
        return counts.map { category, count in
            DailySummary.CategoryCount(category: category, count: count)
        }
    }
}

// MARK: - Extensions

extension VoiceRecord.Category {
    var displayName: String {
        switch self {
        case .work: return "工作"
        case .idea: return "想法"
        case .todo: return "TODO"
        case .chat: return "闲聊"
        }
    }
}

// MARK: - Errors

enum SummaryError: Error {
    case noRecords
    case apiKeyMissing
    case apiError
    case networkError
    case invalidResponse

    var localizedDescription: String {
        switch self {
        case .noRecords:
            return "没有记录可以总结"
        case .apiKeyMissing:
            return "API Key 未配置，请先配置通义千问 API Key"
        case .apiError:
            return "API 调用失败"
        case .networkError:
            return "网络请求失败"
        case .invalidResponse:
            return "API 响应格式错误"
        }
    }
}
