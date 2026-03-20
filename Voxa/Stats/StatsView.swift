//
//  StatsView.swift
//  Voxa
//
//  统计窗口
//

import SwiftUI

struct StatsView: View {
    @StateObject private var statsManager = StatsManager.shared
    @StateObject private var controller = StatsWindowController.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题行，带关闭按钮
            HStack {
                Text("使用统计")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                
                Spacer()
                
                Button(action: {
                    controller.hide()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider()
            
            // 今日
            StatRow(
                title: "今日",
                duration: statsManager.todayDuration(),
                cost: statsManager.calculateCost(seconds: statsManager.todayDuration())
            )
            
            // 平均每日
            StatRow(
                title: "平均每日",
                duration: statsManager.averageDailyDuration(),
                cost: nil
            )
            
            // 本月
            StatRow(
                title: "本月",
                duration: statsManager.monthDuration(),
                cost: statsManager.calculateCost(seconds: statsManager.monthDuration())
            )
            
            // 总计（历史累计）
            StatRow(
                title: "总计",
                duration: statsManager.totalDuration(),
                cost: statsManager.calculateCost(seconds: statsManager.totalDuration())
            )
            
            Divider()
            
            // 价格说明
            HStack {
                Text("计价")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Spacer()
                Text("0.00024元/秒")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
            }
            
            // 今日费用
            HStack {
                Text("今日已使用")
                    .font(.system(size: 14))
                    .foregroundColor(.black)
                Spacer()
                Text(String(format: "%.4f 元", statsManager.calculateCost(seconds: statsManager.todayDuration())))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange)
            }
            
            Spacer()
        }
        .padding(20)
        .frame(width: 280, height: 320)
    }
}

struct StatRow: View {
    let title: String
    let duration: Int
    let cost: Double?
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.black)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(StatsManager.shared.formatDurationLong(duration))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                
                if let cost = cost {
                    Text(String(format: "%.4f元", cost))
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - 统计窗口控制器

@MainActor
class StatsWindowController: ObservableObject {
    static let shared = StatsWindowController()
    
    private var window: NSPanel?
    @Published var isVisible: Bool = false
    
    private init() {}
    
    /// toggle 显示/隐藏
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }
    
    func show() {
        if window == nil {
            createWindow()
        }
        
        window?.orderFrontRegardless()
        isVisible = true
    }
    
    func hide() {
        window?.orderOut(nil)
        isVisible = false
    }
    
    private func createWindow() {
        let contentView = StatsView()
        let hostingView = NSHostingView(rootView: contentView)
        
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.contentView = hostingView
        panel.level = .floating
        panel.backgroundColor = .white
        panel.hasShadow = true
        panel.isOpaque = false
        
        // 圆角
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true
        
        // 居中显示
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - 140
            let y = screenRect.midY - 160
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window = panel
    }
}
