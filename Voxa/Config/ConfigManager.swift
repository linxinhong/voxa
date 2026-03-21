//
//  ConfigManager.swift
//  Voxa
//
//  Configuration management for custom polish templates.
//

import Foundation

/// 润色模板结构
struct PolishTemplate: Codable {
    let name: String    // 显示名称，如 "轻度润色"
    let prompt: String  // 提示词内容
}

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/voxa")
    private let configFile = "config.json"
    
    var templates: [String: PolishTemplate] = [:]
    var currentShortcut: String = "alt+1"
    
    // API Key
    private(set) var apiKey: String = ""

    // 日报提示词
    private(set) var dailyReportPrompt: String = """
    你是一个专业的日报助手。请根据用户提供的语音输入记录，生成一份简洁、有条理的日报。

    要求：
    1. 使用简洁自然的中文
    2. 按照指定格式输出
    3. 突出重点，不要流水账
    4. 提取关键信息和洞察
    """

    // 默认配置（带名称）
    private let defaultTemplates: [String: PolishTemplate] = [
        "alt+1": PolishTemplate(
            name: "轻度润色",
            prompt: "你是一个语音转文字的轻度润色助手。用户输入是语音识别的原始结果，你只能做以下修改：修正明显的错别字、同音字错误、补全缺失标点、去除重复词。禁止改变用户的表达方式、句式结构、语气和风格。禁止添加任何原文中没有的内容。只输出润色后的文字，不要任何解释。"
        ),
        "alt+2": PolishTemplate(
            name: "正式书面",
            prompt: "转为正式书面语，使用规范的语法和词汇，适合商务邮件和正式文档。保持原意不变。"
        ),
        "alt+3": PolishTemplate(
            name: "自然口语",
            prompt: "转为自然流畅的口语表达，适合日常聊天和即时通讯。保持轻松自然的语气。"
        ),
        "alt+4": PolishTemplate(
            name: "精简文本",
            prompt: "精简文本，去除冗余词汇和重复内容，保留核心信息。保持原意不变。"
        )
    ]
    
    init() {
        VoxaLog("[Config] ConfigManager 初始化开始")
        loadConfig()
        VoxaLog("[Config] ConfigManager 初始化完成，当前模板: \(currentShortcut) - \(currentTemplate().name)")
    }
    
    /// 加载配置文件
    func loadConfig() {
        let filePath = configDir.appendingPathComponent(configFile)
        
        // 检查配置文件是否存在
        if !FileManager.default.fileExists(atPath: filePath.path) {
            // 创建默认配置
            createDefaultConfig()
            return
        }
        
        // 读取配置
        do {
            let data = try Data(contentsOf: filePath)
            
            // 尝试解析完整格式（带 api_key 和 templates）
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // 读取 API Key
                if let key = json["api_key"] as? String {
                    apiKey = key
                    VoxaLog("[Config] 从配置文件加载 API Key")
                }

                // 读取日报提示词
                if let prompt = json["daily_report_prompt"] as? String {
                    dailyReportPrompt = prompt
                    VoxaLog("[Config] 从配置文件加载日报提示词")
                }
                
                // 读取模板配置
                if let templatesDict = json["templates"] as? [String: [String: String]] {
                    var newTemplates: [String: PolishTemplate] = [:]
                    for (key, value) in templatesDict {
                        if let name = value["name"], let prompt = value["prompt"] {
                            newTemplates[key] = PolishTemplate(name: name, prompt: prompt)
                        }
                    }
                    if !newTemplates.isEmpty {
                        templates = newTemplates
                        VoxaLog("[Config] 加载了 \(templates.count) 个润色模板（完整格式）")
                        return
                    }
                }
            }
            
            // 尝试解析旧格式（仅模板，无 api_key）
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]] {
                // 检查是否是模板格式（包含 name/prompt 键）
                var isTemplateFormat = false
                for (_, value) in json {
                    if value["name"] != nil && value["prompt"] != nil {
                        isTemplateFormat = true
                        break
                    }
                }
                
                if isTemplateFormat {
                    var newTemplates: [String: PolishTemplate] = [:]
                    for (key, value) in json {
                        if let name = value["name"], let prompt = value["prompt"] {
                            newTemplates[key] = PolishTemplate(name: name, prompt: prompt)
                        }
                    }
                    if !newTemplates.isEmpty {
                        templates = newTemplates
                        VoxaLog("[Config] 加载了 \(templates.count) 个润色模板（模板格式）")
                        // 迁移到新格式
                        saveConfig()
                        return
                    }
                }
            }
            
            // 尝试解析旧格式（仅 prompt 字符串）
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                // 旧格式: {"alt+1": "prompt..."}
                var migratedTemplates: [String: PolishTemplate] = [:]
                for (key, prompt) in json {
                    // 根据快捷键生成默认名称
                    let defaultName = defaultTemplates[key]?.name ?? "模板 \(key)"
                    migratedTemplates[key] = PolishTemplate(name: defaultName, prompt: prompt)
                }
                templates = migratedTemplates
                VoxaLog("[Config] 加载了 \(templates.count) 个润色模板（旧格式已迁移）")
                
                // 保存为新格式
                saveConfig()
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
            
            templates = defaultTemplates
            saveConfig()
            
            VoxaLog("[Config] 创建默认配置: \(configDir.appendingPathComponent(configFile).path)")
        } catch {
            VoxaLog("[Config] 创建默认配置失败: \(error)")
            templates = defaultTemplates
        }
    }
    
    /// 保存配置到文件
    private func saveConfig() {
        do {
            let filePath = configDir.appendingPathComponent(configFile)
            
            // 构建完整配置字典
            var templatesDict: [String: [String: String]] = [:]
            for (key, template) in templates {
                templatesDict[key] = ["name": template.name, "prompt": template.prompt]
            }
            
            var dict: [String: Any] = [
                "templates": templatesDict
            ]

            // 只有当 apiKey 不为空时才保存
            if !apiKey.isEmpty {
                dict["api_key"] = apiKey
            }

            // 保存日报提示词
            dict["daily_report_prompt"] = dailyReportPrompt
            
            let data = try JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: filePath)
        } catch {
            VoxaLog("[Config] 保存配置失败: \(error)")
        }
    }
    
    /// 获取指定快捷键的模板
    func getTemplate(for shortcut: String) -> PolishTemplate? {
        return templates[shortcut]
    }
    
    /// 获取当前模板
    func currentTemplate() -> PolishTemplate {
        return templates[currentShortcut] ?? defaultTemplates["alt+1"]!
    }
    
    /// 获取当前提示词
    func currentPrompt() -> String {
        return currentTemplate().prompt
    }
    
    /// 切换到指定模板
    func switchTo(shortcut: String) -> Bool {
        if templates[shortcut] != nil {
            currentShortcut = shortcut
            let template = currentTemplate()
            VoxaLog("[Config] 切换到模板: \(shortcut) - \(template.name)")
            return true
        }
        return false
    }
    
    /// 获取所有可用的快捷键
    func availableShortcuts() -> [String] {
        return Array(templates.keys).sorted()
    }
}
