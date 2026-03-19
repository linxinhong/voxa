//
//  Logger.swift
//  Voxa
//
//  Simple file logger for debugging.
//

import Foundation

enum Logger {
    // 设置为 false 关闭日志
    static var isEnabled: Bool = false
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
    
    static func log(_ message: String) {
        guard isEnabled else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
}

// 便捷函数
func VoxaLog(_ message: String) {
    Logger.log(message)
}
