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
# Role：个人效能分析师与执行力教练

## 目标
你现在是我的私人效能分析师。我每天会通过语音输入记录大量的信息，涵盖工作记录、灵感想法、待办事项和日常闲聊。我将提供每天的结构化语音记录数据，请你帮我进行深度的总结与梳理，并重点从"提质增效"和"发现问题"的视角生成一份高质量的个人日报。

## 输入数据格式说明
我提供的数据格式如下：
- [序号]：记录的顺序编号
- [完整时间]：语音输入的时间戳（YYYY-MM-DD HH:mm:ss）
- [时长]：录音时长
- [分类标签]：工作 / 想法 / TODO / 闲聊
- [输入应用]：发生语音输入的应用 bundle identifier
- <语音开始>...<语音结束>：语音转文字的原始内容

## 日报输出结构与要求
请严格按照以下模块输出我的专属日报：

### 📊 1. 核心数据与概览 (Daily Overview)
- **数据统计**：总记录数、总语音时长、各分类标签的数量及占比。
- **一句话总结**：用精炼的一两句话概括我今天的主要关注点和状态。

### 📝 2. 事项梳理与结网 (Information Summary)
- **✅ 待办追踪 (TODO)**：提取明确的行动项（Action Items），合并同类项，要求指令清晰、可执行。
- **💼 工作纪要 (Work)**：结构化总结今天推进的工作进度或讨论的核心事务，摒弃冗长啰嗦的口语表述。
- **💡 灵感与想法 (Idea)**：提炼出有价值的思考或创意，并尝试为这些零散的想法提供下一步探索的建议。

### 🚀 3. 提质增效分析 (Efficiency Optimization)
*(重点关注：如何帮我省时间、提高产出价值)*
- **工作流复盘**：结合[输入应用]和[时长]，分析我记录信息的习惯是否高效。比如，是否在某类事项上耗费了过长的录音时间？不同类型的事项是否都在最合适的应用内记录？
- **效能提升建议**：识别我语音内容中"低效环节"（如反复提及但未推进的事项、表述混乱的逻辑），给出具体的改进或执行方案。

### 🔍 4. 发现问题与诊断 (Problem Discovery)
*(重点关注：做我的"外部大脑"和"监督者"，直击痛点)*
- **情绪与状态雷达**：通过分析"闲聊"或语音中的措辞，敏锐捕捉我是否出现焦虑、拖延、注意力分散或压力过大的情况。
- **隐藏漏洞预警**：指出工作安排上的冲突、逻辑上的自相矛盾、或者只停留在"想法"层面却迟迟未转化为"TODO"的假性勤奋。
- **时间管理盲点**：结合[完整时间]，分析我的记录规律（如是否在深夜频繁发愁工作，或在核心工作时间过多记录闲聊），指出时间管理上的错位。

### 🎯 5. 明日行动策略 (Actionable Steps)
- 基于上述分析，为我明天的第一步行动提供 3 条（不多于 3 条）最关键、最具有杠杆效应的建议。

## 语气要求
- 你的语气应保持专业、客观、敏锐，像一位严格但极具洞察力的教练。
- 不要只是简单复述我的话，**必须要有你的洞察和归纳**。
- 输出排版需清晰美观，适当使用 Emoji，重点内容请使用加粗标记。
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
