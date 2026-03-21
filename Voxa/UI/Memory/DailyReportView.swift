//
//  DailyReportView.swift
//  Voxa
//
//  Daily report view with tabs for records and AI summary.
//  Tabs in top-right. Auto-generates summary if missing.
//

import SwiftUI

enum ReportTab {
    case records   // 输入记录
    case summary   // 日报总结
}

struct DailyReportView: View {
    @State private var selectedDate = Date()
    @State private var selectedTab: ReportTab = .summary
    @State private var dailyRecords: DailyRecords?
    @State private var summary: DailySummary?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var availableDates: [Date] = []
    @State private var showDatepicker = false
    @State private var selectedCategory: VoiceRecord.Category?

    // ESC监听器引用，用于移除
    @State private var escapeMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏（关闭按钮 + 日期 + Tab）
            header

            Divider()

            // 内容区域（直接显示，不包裹 ScrollView）
            switch selectedTab {
            case .records:
                recordsView
            case .summary:
                summaryView
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(red: 0.9, green: 0.9, blue: 0.9))
        .onAppear {
            Task {
                await loadData()
            }
            setupEscapeMonitor()
        }
        .onDisappear {
            removeEscapeMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshReportData)) { _ in
            Task {
                await loadData()
            }
        }
    }

    // MARK: - Escape Monitor

    private func setupEscapeMonitor() {
        // 移除旧监听器
        removeEscapeMonitor()

        // 使用本地监听器
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // ESC key
                NotificationCenter.default.post(name: .closeReportPanel, object: nil)
                return nil  // 消费事件，不再传递
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // MARK: - Close Action

    private func closePanel() {
        NotificationCenter.default.post(name: .closeReportPanel, object: nil)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // 左侧：关闭按钮
            Button(action: closePanel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            // 日期选择
            Button(action: {
                showDatepicker = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(Color(red: 0, green: 0, blue: 0))
                    Text(formatDate(selectedDate))
                        .foregroundColor(Color(red: 0, green: 0, blue: 0))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0, green: 0, blue: 0))
                }
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showDatepicker) {
                VStack {
                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    HStack {
                        Spacer()
                        Button("确定") {
                            showDatepicker = false
                            Task { await loadData() }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding()
            }

            Spacer()

            // 右侧：Tab 切换
            HStack(spacing: 0) {
                TabButton(
                    title: "输入记录",
                    isSelected: selectedTab == .records,
                    action: { selectedTab = .records }
                )
                TabButton(
                    title: "日报总结",
                    isSelected: selectedTab == .summary,
                    action: { selectedTab = .summary }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.9, green: 0.9, blue: 0.9))
    }

    // MARK: - Records View

    private var recordsView: some View {
        VStack(spacing: 0) {
            // 分类筛选器 - 固定在顶部
            categoryFilterBar

            Divider()

            // 记录列表内容 - 可滚动
            ScrollView {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let records = dailyRecords, !records.sortedRecords.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredRecords) { record in
                            RecordWithSendButton(record: record)
                        }
                    }
                    .padding()
                } else {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Summary View

    private var summaryView: some View {
        VStack(spacing: 0) {
            // 固定顶部区域（不滚动）
            if let summary = summary {
                // 统计卡片行和生成日报按钮
                HStack(spacing: 12) {
                    // 统计卡片（左对齐）
                    HStack(spacing: 16) {
                        // 记录数量
                        HStack(spacing: 4) {
                            Text("\(summary.recordCount)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("条")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        // 总时长
                        HStack(spacing: 4) {
                            Text(formatDuration(summary.totalDuration))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("时长")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        // 分类分布
                        ForEach(summary.categoryCounts.sorted(by: { $0.count > $1.count }), id: \.category) { item in
                            HStack(spacing: 2) {
                                Text(item.category.displayName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("×\(item.count)")
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)  // 原来6 + 8 = 14
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)

                    Spacer()

                    // 生成日报按钮（右对齐）
                    Button(action: {
                        Task {
                            await generateSummary()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text("⭐")
                            Text("生成日报")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.green, lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
                .padding()

                Divider()

                // 可滚动的总结内容
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // 总结内容卡片
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.summary)
                                .font(.body)
                                .foregroundColor(.primary)
                                .lineSpacing(1.4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 0)
                }
            } else if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                // 没有总结时的空状态
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // 空统计卡片
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Text("0")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("条")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)

                        Spacer()

                        // 生成日报按钮
                        Button(action: {
                            Task {
                                await generateSummary()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                Text("生成日报")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Color(.controlBackgroundColor))
                            .foregroundColor(.green)
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.green, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                    .padding()

                    Divider()

                    // 空状态提示
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("点击「生成日报」查看今日总结")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Regenerate Summary

    private func regenerateSummary() async {
        await generateSummary()
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton(nil, "全部", filteredRecords.count)

                ForEach([VoiceRecord.Category.work, .idea, .todo, .chat], id: \.self) { category in
                    let count = dailyRecords?.records.filter { $0.category == category }.count ?? 0
                    filterButton(category, category.displayName, count)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .padding(.vertical, 6)
    }

    private func filterButton(_ category: VoiceRecord.Category?, _ name: String, _ count: Int) -> some View {
        let isSelected = selectedCategory == category

        return Button(action: {
            withAnimation {
                selectedCategory = isSelected ? nil : category
            }
        }) {
            Text(name)
                .font(.caption2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.green : Color(.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : Color.primary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats Card

    private func statsCard(_ summary: DailySummary) -> some View {
        HStack(spacing: 24) {
            // 记录数量
            VStack(alignment: .leading, spacing: 4) {
                Text("\(summary.recordCount)")
                    .font(.system(size: 24, weight: .bold))
                Text("条记录")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 总时长
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDuration(summary.totalDuration))
                    .font(.system(size: 24, weight: .bold))
                Text("总时长")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 分类分布
            VStack(alignment: .leading, spacing: 4) {
                ForEach(summary.categoryCounts.sorted(by: { $0.count > $1.count }), id: \.category) { item in
                    HStack(spacing: 4) {
                        Text(item.category.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("×\(item.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("加载中...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text(error)
                .font(.body)
                .foregroundColor(.secondary)

            if selectedTab == .summary {
                Button("重试") {
                    Task { await generateSummary() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("今天还没有语音记录")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Properties

    private var filteredRecords: [VoiceRecord] {
        guard let records = dailyRecords else { return [] }

        let sourceRecords = records.sortedRecords
        if let filter = selectedCategory {
            return sourceRecords.filter { $0.category == filter }
        } else {
            return sourceRecords
        }
    }

    // MARK: - Actions

    private func loadData() async {
        isLoading = false
        errorMessage = nil
        summary = nil

        // 加载可用日期列表
        availableDates = await VoiceMemoryStore.shared.availableDates()

        // 加载选定日期的记录和总结
        do {
            dailyRecords = try await VoiceMemoryStore.shared.loadDailyRecords(for: selectedDate)

            // 从单独的总结文件加载
            if let savedSummary = try await VoiceMemoryStore.shared.loadSummary(for: selectedDate) {
                summary = savedSummary
            }
            // 不再自动生成日报，需要用户点击按钮
        } catch {
            errorMessage = "加载记录失败: \(error.localizedDescription)"
        }
    }

    private func generateSummary() async {
        isLoading = true
        errorMessage = nil

        guard let records = dailyRecords else {
            errorMessage = "没有记录可以总结"
            isLoading = false
            return
        }

        do {
            let newSummary = try await DailySummaryService.shared.generateSummary(for: records)
            summary = newSummary

            // 保存总结到文件
            try await VoiceMemoryStore.shared.saveSummary(newSummary, for: selectedDate)
            VoxaLog("[DailyReportView] 日报总结已保存")
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes > 0 {
            return "\(minutes)分钟"
        } else {
            return "\(Int(duration))秒"
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .foregroundColor(isSelected ? .white : .black)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isSelected ? Color.green : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Record with Send Button

struct RecordWithSendButton: View {
    let record: VoiceRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 记录内容
            VStack(alignment: .leading, spacing: 6) {
                // 时间和分类
                HStack {
                    Text(formatTime(record.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let category = record.category {
                        Text("·")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(category.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(categoryColor(for: category).opacity(0.2))
                            .foregroundColor(categoryColor(for: category))
                            .cornerRadius(6)
                    }

                    Spacer()

                    Text(formatDuration(record.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // 内容
                Text(record.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(1.2)
            }

            // 发送按钮
            Button(action: {
                Task { await sendToTargetApp() }
            }) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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

    private func categoryColor(for category: VoiceRecord.Category) -> Color {
        switch category {
        case .work: return .blue
        case .idea: return .purple
        case .todo: return .orange
        case .chat: return .green
        }
    }

    private func sendToTargetApp() async {
        // 获取当前最前面的应用
        guard let targetApp = NSWorkspace.shared.frontmostApplication else {
            VoxaLog("[RecordWithSendButton] 无法获取目标应用")
            return
        }

        VoxaLog("[RecordWithSendButton] 发送到: \(targetApp.bundleIdentifier ?? "未知应用")")
        await Injector.inject(text: record.text, to: targetApp)
    }
}

// MARK: - Preview

struct DailyReportView_Previews: PreviewProvider {
    static var previews: some View {
        DailyReportView()
    }
}
