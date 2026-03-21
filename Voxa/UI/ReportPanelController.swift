//
//  ReportPanelController.swift
//  Voxa
//
//  Floating panel controller for daily records view.
//  Similar to PanelController but for the records/memory view.
//

import SwiftUI
import AppKit

// Notifications for report panel
extension Notification.Name {
    static let closeReportPanel = Notification.Name("closeReportPanel")
    static let refreshReportData = Notification.Name("refreshReportData")
}

@MainActor
class ReportPanelController {
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<DailyReportView>?

    init() {}

    /// Show the records panel centered on screen
    func show() {
        if panel == nil {
            createPanel()
        }

        guard let panel = panel else { return }

        // Center on screen with larger size for records view
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let panelWidth: CGFloat = 600
            let panelHeight: CGFloat = 500
            let x = screenRect.midX - panelWidth / 2
            let y = screenRect.midY - panelHeight / 2

            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
        }

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        // 发送刷新通知
        NotificationCenter.default.post(name: .refreshReportData, object: nil)
    }

    /// Hide the records panel
    func hide() {
        panel?.orderOut(nil)
    }

    /// Toggle visibility
    func toggle() {
        if let panel = panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Check if panel is visible
    var isVisible: Bool {
        return panel?.isVisible ?? false
    }

    private func createPanel() {
        let contentView = DailyReportView()

        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: 600, height: 500)
        hosting.autoresizingMask = [.width, .height]

        // 设置 hosting 视图的背景和圆角
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1).cgColor
        hosting.layer?.cornerRadius = 12

        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500))

        // 创建一个带圆角的容器视图
        let containerView = NSView(frame: hosting.frame)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1).cgColor
        containerView.layer?.cornerRadius = 12

        // 将 hosting 视图添加到容器中
        hosting.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: containerView.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        panel.contentView = containerView

        // 设置面板背景透明，让 containerView 的背景和圆角生效
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.alphaValue = 1.0

        // 面板大小限制
        panel.contentMinSize = NSSize(width: 500, height: 400)

        // 监听关闭通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseNotification),
            name: .closeReportPanel,
            object: nil
        )

        self.hostingView = hosting
        self.panel = panel
    }

    @objc private func handleCloseNotification() {
        hide()
    }
}
