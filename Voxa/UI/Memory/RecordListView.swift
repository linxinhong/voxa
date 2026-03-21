//
//  RecordListView.swift
//  Voxa
//
//  List view for voice records on a specific day.
//

import SwiftUI

struct RecordListView: View {
    let dailyRecords: DailyRecords
    @State private var expandedRecordIds: Set<UUID> = []
    @State private var filterCategory: VoiceRecord.Category?

    var body: some View {
        VStack(spacing: 0) {
            // 分类筛选器
            categoryFilter

            Divider()

            // 记录列表
            if filteredRecords.isEmpty {
                emptyView
            } else {
                list
            }
        }
        .frame(minWidth: 400)
    }

    // MARK: - Category Filter

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                filterButton(nil, "全部", filteredRecords.count)

                ForEach([VoiceRecord.Category.work, .idea, .todo, .chat], id: \.self) { category in
                    let count = dailyRecords.records.filter { $0.category == category }.count
                    filterButton(category, category.displayName, count)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private func filterButton(_ category: VoiceRecord.Category?, _ name: String, _ count: Int) -> some View {
        let isSelected = filterCategory == category

        return Button(action: {
            withAnimation {
                filterCategory = isSelected ? nil : category
            }
        }) {
            Text(name)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : Color.primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(filteredRecords) { record in
                    RecordRow(
                        record: record,
                        isExpanded: expandedRecordIds.contains(record.id)
                    ) {
                        withAnimation {
                            if expandedRecordIds.contains(record.id) {
                                expandedRecordIds.remove(record.id)
                            } else {
                                expandedRecordIds.insert(record.id)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("没有记录")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Properties

    private var filteredRecords: [VoiceRecord] {
        if let filter = filterCategory {
            return dailyRecords.records.filter { $0.category == filter }
        } else {
            return dailyRecords.records
        }
    }
}

// MARK: - Record Row

struct RecordRow: View {
    let record: VoiceRecord
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 简略行
            HStack(alignment: .top, spacing: 12) {
                // 分类图标
                if let category = record.category {
                    categoryIcon(category)
                } else {
                    Color.clear.frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // 时间
                    Text(formatTime(record.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 时长
                    Text(formatDuration(record.duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // 标题（如果有）
                    if let title = record.title {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    // 内容预览
                    Text(record.text.prefix(isExpanded ? 200 : 50))
                        .font(isExpanded ? .body : .subheadline)
                        .foregroundColor(isExpanded ? .primary : .secondary)
                        .lineLimit(isExpanded ? nil : 1)
                }

                Spacer()

                // 展开按钮
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // 展开后的完整内容
            if isExpanded {
                Text(record.text)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.leading, 40)

                // 标签
                if let tags = record.tags, !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.leading, 40)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private func categoryIcon(_ category: VoiceRecord.Category) -> some View {
        let imageName: String
        let color: Color

        switch category {
        case .work:
            imageName = "briefcase"
            color = .blue
        case .idea:
            imageName = "lightbulb"
            color = .yellow
        case .todo:
            imageName = "checkmark.circle"
            color = .green
        case .chat:
            imageName = "bubble.right"
            color = .orange
        }

        return Image(systemName: imageName)
            .foregroundColor(color)
            .frame(width: 24, height: 24)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }
}

// MARK: - Preview

struct RecordListView_Previews: PreviewProvider {
    static var previews: some View {
        let mockRecords = DailyRecords(date: Date())
        RecordListView(dailyRecords: mockRecords)
    }
}
