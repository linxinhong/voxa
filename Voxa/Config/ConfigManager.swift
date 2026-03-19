//
//  ConfigManager.swift
//  Voxa
//
//  Configuration management for custom polish templates.
//

import Foundation

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/voxa")
    private let configFile = "config.json"
    
    var templates: [String: String] = [:]
    var currentShortcut: String = "alt+1"
    
    // 默认配置
    private let defaultTemplates: [String: String] = [
        "alt+1": "你是一个语音转文字的轻度润色助手。用户输入是语音识别的原始结果，你只能做以下修改：修正明显的错别字、同音字错误、补全缺失标点、去除重复词。禁止改变用户的表达方式、句式结构、语气和风格。禁止添加任何原文中没有的内容。只输出润色后的文字，不要任何解释。",
        "alt+2": "转为正式书面语，使用规范的语法和词汇，适合商务邮件和正式文档。保持原意不变。",
        "alt+3": "转为自然流畅的口语表达，适合日常聊天和即时通讯。保持轻松自然的语气。",
        "alt+4": "精简文本，去除冗余词汇和重复内容，保留核心信息。保持原意不变。"
    ]
    
    init() {
        VoxaLog("[Config] ConfigManager 初始化开始")
        loadConfig()
        VoxaLog("[Config] ConfigManager 初始化完成，当前模板: \(currentShortcut)")
    }
    
    /// 加载配置文件
    func loadConfig() {
        let filePath = configDir.appendingPathComponent(configFile)
        
        // 检查配置文件是否存在
        if !FileManager.default.fileExists(atPath: filePath.path) {
            // 创建默认配置
            createDefaultConfig()
        }
        
        // 读取配置
        do {
            let data = try Data(contentsOf: filePath)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                templates = json
                VoxaLog("[Config] 加载了 \(templates.count) 个润色模板")
            }
        } catch {
            VoxaLog("[Config] 读取配置失败: \(error)，使用默认配置")
            templates = defaultTemplates
        }
    }
    
    /// 创建默认配置文件
    private func createDefaultConfig() {
        do {
            // 创建目录
            try FileManager.default.createDirectory(
                at: configDir,
                withIntermediateDirectories: true
            )
            
            // 写入默认配置
            let filePath = configDir.appendingPathComponent(configFile)
            let data = try JSONSerialization.data(
                withJSONObject: defaultTemplates,
                options: [.prettyPrinted]
            )
            try data.write(to: filePath)
            
            templates = defaultTemplates
            VoxaLog("[Config] 创建默认配置: \(filePath.path)")
        } catch {
            VoxaLog("[Config] 创建默认配置失败: \(error)")
            templates = defaultTemplates
        }
    }
    
    /// 获取指定快捷键的提示词
    func getPrompt(for shortcut: String) -> String? {
        return templates[shortcut]
    }
    
    /// 获取当前提示词
    func currentPrompt() -> String {
        return templates[currentShortcut] ?? defaultTemplates["alt+1"]!
    }
    
    /// 切换到指定模板
    func switchTo(shortcut: String) -> Bool {
        if templates[shortcut] != nil {
            currentShortcut = shortcut
            VoxaLog("[Config] 切换到模板: \(shortcut)")
            return true
        }
        return false
    }
    
    /// 获取所有可用的快捷键
    func availableShortcuts() -> [String] {
        return Array(templates.keys).sorted()
    }
}
