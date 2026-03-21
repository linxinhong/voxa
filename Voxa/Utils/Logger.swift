//
//  Logger.swift
//  Voxa
//
//  Simple file logger for debugging with UTF-8 BOM support.
//

import Foundation

enum Logger {
    // 设置为 false 关闭日志
    static var isEnabled: Bool = true

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // UTF-8 BOM 标记，帮助编辑器正确识别中文
    private static let utf8BOM: Data = Data([0xEF, 0xBB, 0xBF])

    // 日志文件路径
    private static var logFile: URL {
        let fileManager = FileManager.default
        let logDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/voxa", isDirectory: true)
        try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        return logDir.appendingPathComponent("voxa.log")
    }

    static func log(_ message: String) {
        guard isEnabled else { return }

        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"

        // 输出到控制台
        print(logMessage, terminator: "")

        // 写入日志文件
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: logFile.path) {
            // 文件存在，追加写入
            if let handle = FileHandle(forWritingAtPath: logFile.path) {
                handle.seekToEndOfFile()
                if let data = logMessage.data(using: .utf8) {
                    handle.write(data)
                }
                handle.synchronizeFile()
            }
        } else {
            // 文件不存在，创建新文件并添加 UTF-8 BOM
            let fileData = NSMutableData()
            fileData.append(utf8BOM)
            if let data = logMessage.data(using: .utf8) {
                fileData.append(data)
            }
            fileData.write(to: logFile, atomically: true)
        }
    }
}

// 便捷函数
func VoxaLog(_ message: String) {
    Logger.log(message)
}
