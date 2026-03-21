//
//  VoiceMemoryStore.swift
//  Voxa
//
//  Local storage manager for voice records using JSONL format.
//  Records are stored as JSONL (one JSON object per line).
//  Summaries are stored in separate files with "summary-" prefix.
//

import Foundation

actor VoiceMemoryStore {
    static let shared = VoiceMemoryStore()

    /// 存储目录：~/.config/voxa/records/
    private let recordsDirectory: URL

    /// 数据保留策略
    enum RetentionPeriod: Int, Codable, CaseIterable {
        case thirtyDays = 30
        case ninetyDays = 90
        case oneEightyDays = 180
        case forever = 0  // 0 表示永久保留

        var displayName: String {
            switch self {
            case .thirtyDays: return "30天"
            case .ninetyDays: return "90天"
            case .oneEightyDays: return "180天"
            case .forever: return "永久"
            }
        }
    }

    /// 当前保留策略（从 UserDefaults 读取）
    var retentionPeriod: RetentionPeriod {
        get {
            let raw = UserDefaults.standard.integer(forKey: "voiceMemoryRetention")
            return RetentionPeriod(rawValue: raw) ?? .ninetyDays
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "voiceMemoryRetention")
            // 异步清理过期数据
            Task {
                await deleteOldRecords()
            }
        }
    }

    private init() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let recordsDir = homeDir.appendingPathComponent(".config/voxa/records", isDirectory: true)

        // 创建目录
        if !fileManager.fileExists(atPath: recordsDir.path) {
            try? fileManager.createDirectory(at: recordsDir, withIntermediateDirectories: true)
        }

        self.recordsDirectory = recordsDir
        VoxaLog("[VoiceMemoryStore] 存储目录: \(recordsDir.path)")
    }

    // MARK: - 保存记录

    /// 保存一条语音记录（追加到当天的 JSONL 文件）
    func saveRecord(_ record: VoiceRecord) async throws {
        let fileName = recordsFileName(for: record.timestamp)
        let fileURL = recordsDirectory.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(record)
        // 验证数据有效
        guard String(data: data, encoding: .utf8) != nil else {
            throw VoiceMemoryError.encodingFailed
        }

        // 追加到文件末尾
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let fileHandle = try FileHandle(forWritingTo: fileURL)
            defer { try? fileHandle.close() }

            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: "\n".data(using: .utf8)!)
            try fileHandle.write(contentsOf: data)
        } else {
            // 新文件，直接写入
            try data.write(to: fileURL)
        }

        VoxaLog("[VoiceMemoryStore] 已保存记录到: \(fileName)")
    }

    // MARK: - 读取记录

    /// 读取指定日期的所有记录
    func loadDailyRecords(for date: Date) async throws -> DailyRecords {
        let fileName = self.recordsFileName(for: date)
        let fileURL = recordsDirectory.appendingPathComponent(fileName)

        VoxaLog("[VoiceMemoryStore] 加载日期: \(fileName)")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // 文件不存在，返回空记录
            VoxaLog("[VoiceMemoryStore] 文件不存在")
            return DailyRecords(date: date)
        }

        VoxaLog("[VoiceMemoryStore] 文件存在，开始解析")

        // 读取 JSONL 文件，每行一个 JSON 对象
        let fileContents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = fileContents.components(separatedBy: .newlines).filter { !$0.isEmpty }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var result = DailyRecords(date: date)
        for line in lines {
            if let data = line.data(using: .utf8),
               let record = try? decoder.decode(VoiceRecord.self, from: data) {
                result.addRecord(record)
            }
        }

        VoxaLog("[VoiceMemoryStore] 解析成功，记录数: \(result.records.count)")
        return result
    }

    /// 加载最近 N 天的记录
    func loadRecentRecords(days: Int) async throws -> [DailyRecords] {
        var results: [DailyRecords] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for i in 0..<days {
            if let date = calendar.date(byAdding: .day, value: -i, to: today) {
                do {
                    let records = try await loadDailyRecords(for: date)
                    if !records.records.isEmpty {
                        results.append(records)
                    }
                } catch {
                    VoxaLog("[VoiceMemoryStore] 无法加载 \(date): \(error)")
                }
            }
        }

        return results
    }

    /// 获取所有可用的日期列表
    func availableDates() async -> [Date] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: recordsDirectory.path) else {
            return []
        }

        var dates: Set<Date> = []
        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent

            // 只支持 JSONL 格式
            if filename.hasPrefix("records-") && filename.hasSuffix(".jsonl") {
                // 从文件名解析日期：records-2026-03-21.jsonl
                let dateString = filename
                    .replacingOccurrences(of: "records-", with: "")
                    .replacingOccurrences(of: ".jsonl", with: "")

                // 使用 DateFormatter 解析 YYYY-MM-DD 格式
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                if let date = formatter.date(from: dateString) {
                    dates.insert(date)
                    VoxaLog("[VoiceMemoryStore] 找到日期文件: \(filename) -> \(date)")
                }
            }
        }

        VoxaLog("[VoiceMemoryStore] 可用日期数量: \(dates.count)")
        return dates.sorted(by: >)
    }

    // MARK: - 读取/保存总结

    /// 读取指定日期的总结
    func loadSummary(for date: Date) async throws -> DailySummary? {
        let fileName = summaryFileName(for: date)
        let fileURL = recordsDirectory.appendingPathComponent(fileName)

        VoxaLog("[VoiceMemoryStore] 加载总结: \(fileName)")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            VoxaLog("[VoiceMemoryStore] 总结文件不存在: \(fileURL.path)")
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let summary = try decoder.decode(DailySummary.self, from: data)
        VoxaLog("[VoiceMemoryStore] 总结加载成功")
        return summary
    }

    /// 保存日报总结到单独的文件
    func saveSummary(_ summary: DailySummary, for date: Date) async throws {
        let fileName = summaryFileName(for: date)
        let fileURL = recordsDirectory.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(summary)
        try data.write(to: fileURL)

        VoxaLog("[VoiceMemoryStore] 已保存日报总结到: \(fileName)")
    }

    // MARK: - 清理过期数据

    /// 删除超过保留期限的记录
    private func deleteOldRecords() async {
        let cutoffDate: Date
        switch retentionPeriod {
        case .forever:
            return // 永久保留，不删除
        case .thirtyDays, .ninetyDays, .oneEightyDays:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionPeriod.rawValue, to: Date()) ?? Date()
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: recordsDirectory.path) else {
            return
        }

        var deletedCount = 0
        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent

            // 删除过期的记录文件（JSONL 格式）
            if filename.hasPrefix("records-") && filename.hasSuffix(".jsonl") {
                let dateString = filename
                    .replacingOccurrences(of: "records-", with: "")
                    .replacingOccurrences(of: ".jsonl", with: "")
                if let fileDate = parseDateFromFileName(dateString) {
                    if fileDate < cutoffDate {
                        do {
                            try fileManager.removeItem(at: fileURL)
                            deletedCount += 1
                            VoxaLog("[VoiceMemoryStore] 已删除过期记录: \(filename)")
                        } catch {
                            VoxaLog("[VoiceMemoryStore] 删除失败: \(filename) - \(error)")
                        }
                    }
                }
            }

            // 删除过期的总结文件
            if filename.hasPrefix("summary-") && filename.hasSuffix(".json") {
                let dateString = filename
                    .replacingOccurrences(of: "summary-", with: "")
                    .replacingOccurrences(of: ".json", with: "")
                if let fileDate = parseDateFromFileName(dateString) {
                    if fileDate < cutoffDate {
                        do {
                            try fileManager.removeItem(at: fileURL)
                            deletedCount += 1
                            VoxaLog("[VoiceMemoryStore] 已删除过期总结: \(filename)")
                        } catch {
                            VoxaLog("[VoiceMemoryStore] 删除失败: \(filename) - \(error)")
                        }
                    }
                }
            }
        }

        if deletedCount > 0 {
            VoxaLog("[VoiceMemoryStore] 共删除 \(deletedCount) 个过期文件")
        }
    }

    /// 删除指定日期的所有记录和总结
    func deleteRecords(for date: Date) async throws {
        let recordsFileName = recordsFileName(for: date)
        let summaryFileName = summaryFileName(for: date)

        let recordsFileURL = recordsDirectory.appendingPathComponent(recordsFileName)
        let summaryFileURL = recordsDirectory.appendingPathComponent(summaryFileName)

        if FileManager.default.fileExists(atPath: recordsFileURL.path) {
            try FileManager.default.removeItem(at: recordsFileURL)
            VoxaLog("[VoiceMemoryStore] 已删除记录: \(recordsFileName)")
        }

        if FileManager.default.fileExists(atPath: summaryFileURL.path) {
            try FileManager.default.removeItem(at: summaryFileURL)
            VoxaLog("[VoiceMemoryStore] 已删除总结: \(summaryFileName)")
        }
    }

    /// 清除所有记录（慎用）
    func clearAllRecords() async throws {
        let fileManager = FileManager.default
        try fileManager.removeItem(atPath: recordsDirectory.path)
        try fileManager.createDirectory(at: recordsDirectory, withIntermediateDirectories: true)
        VoxaLog("[VoiceMemoryStore] 已清除所有记录")
    }

    // MARK: - 辅助方法

    /// 记录文件名：records-YYYY-MM-DD.jsonl
    private func recordsFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: date)
        return "records-\(dateString).jsonl"
    }

    /// 总结文件名：summary-YYYY-MM-DD.json
    private func summaryFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: date)
        return "summary-\(dateString).json"
    }

    /// 从文件名解析日期
    private func parseDateFromFileName(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }
}

// MARK: - Errors

enum VoiceMemoryError: Error {
    case encodingFailed
    case decodingFailed
    case fileNotFound
}
