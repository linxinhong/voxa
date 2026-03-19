//
//  Logger.swift
//  Voxa
//
//  Simple file logger for debugging.
//

import Foundation

enum Logger {
    private static let logFile: FileHandle? = {
        let fileManager = FileManager.default
        
        // 尝试多个可能的路径
        let possiblePaths = [
            fileManager.currentDirectoryPath + "/logs",
            fileManager.homeDirectoryForCurrentUser.path + "/.voxa/logs",
            "/tmp/voxa-logs"
        ]
        
        var logsDir: String?
        for path in possiblePaths {
            if !fileManager.fileExists(atPath: path) {
                try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
            if fileManager.fileExists(atPath: path) {
                logsDir = path
                break
            }
        }
        
        guard let dir = logsDir else { return nil }
        
        let logPath = dir + "/voxa.log"
        
        // Create log file if needed
        if !fileManager.fileExists(atPath: logPath) {
            fileManager.createFile(atPath: logPath, contents: nil)
        }
        
        return FileHandle(forWritingAtPath: logPath)
    }()
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
    
    private static let lock = NSLock()
    
    static func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let logLine = "[\(timestamp)] \(message)\n"
        
        // Print to console
        print(logLine, terminator: "")
        
        // Write to file
        lock.lock()
        defer { lock.unlock() }
        
        if let data = logLine.data(using: .utf8) {
            logFile?.seekToEndOfFile()
            logFile?.write(data)
            logFile?.synchronizeFile()
        }
    }
}

// Convenience function
func VoxaLog(_ message: String) {
    Logger.log(message)
}
