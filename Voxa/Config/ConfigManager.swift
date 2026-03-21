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

    // 个人背景说明（用于日报分析）
    private(set) var aboutMe: String = """
我是 starred，一名独立开发者，正在构建语音输入工具 Voxa。
技术栈：Swift、SwiftUI、macOS 开发。
工作风格：专注、高效，喜欢快速迭代和验证想法。
当前目标：将 Voxa 打造成一个实用的语音辅助工具。
"""

    // 日报提示词模板（包含 {about-me} 占位符）
    private let dailyReportPromptTemplate = """
# Role：个人效能分析师与执行力教练

## 目标
你现在是我的私人效能分析师。我每天会通过语音输入记录大量的信息，涵盖工作记录、灵感想法、待办事项和日常闲聊。我将提供每天的结构化语音记录数据，请你结合我的【个人背景上下文】，帮我进行深度的总结与梳理，并重点从"提质增效"和"发现问题"的视角生成一份高质量的个人日报。

## 👤 关于我 (Context & About Me)
请在后续的所有分析中，时刻牢记以下关于我的背景信息：
{about-me}

## 输入数据格式说明
我提供的数据格式如下：
- [序号]：记录的顺序编号
- [完整时间]：语音输入的时间戳（YYYY-MM-DD HH:mm:ss）
- [时长]：录音时长
- [分类标签]：工作 / 想法 / TODO / 闲聊
- [输入应用]：发生语音输入的应用 bundle identifier（这是判断输入语境的核心依据）
- <语音开始>...<语音结束>：语音转文字的原始内容

## 日报输出结构与要求
请严格按照以下模块输出我的专属日报：

### 📊 1. 核心数据与概览 (Daily Overview)
- **数据统计**：总记录数、总语音时长、各分类标签占比。
- **应用生态分布**：统计在不同 [输入应用] 中的记录数量与时长，揭示我今天的信息输入偏好。
- **状态一言**：结合【关于我】的设定，用精炼的一句话概括我今天是否走在正确的轨道上。

### 📝 2. 事项梳理与结网 (Information Summary)
*(注意：请结合[输入应用]还原上下文，并在梳理时标注信息来源)*
- **✅ 待办追踪 (TODO)**：提取明确的行动项。请特别标出哪些 TODO 与我【当前的核心目标】高度相关，哪些是偏离核心的杂事。
- **💼 工作纪要 (Work)**：结构化总结核心工作推进。摒弃口语化表述，转化为符合我【职业角色】的专业输出。
- **💡 灵感与想法 (Idea)**：提炼有价值的创意，并结合我的背景给出下一步探索建议。

### 🚀 3. 提质增效分析 (Efficiency Optimization)
*(重点关注：如何帮我优化输入流，提高产出价值)*
- **工具-场景匹配度复盘**：结合[输入应用]和[时长]，分析信息分类和工具使用是否存在错位（如在聊天软件里录入过长的复杂想法）。
- **目标对齐度检测**：核对今天的工作和想法记录，有多大比例投入到了我【当前的核心目标】中？是否存在"捡了芝麻丢了西瓜"的情况？

### 🔍 4. 发现问题与诊断 (Problem Discovery)
*(重点关注：结合我的痛点，做我的"监督者"，直击要害)*
- **情绪与痛点雷达**：结合我的【工作痛点/性格弱点】，敏锐捕捉我今天的语音（尤其是闲聊或抱怨）中是否出现了这些旧毛病复发的迹象。
- **隐藏漏洞预警**：指出工作安排上的冲突、逻辑自相矛盾，或只停留在"想法"层面却迟迟未转化为"TODO"的假性勤奋。
- **时间与场景盲点**：结合[完整时间]和[输入应用]，分析时间错位（如深夜在工作软件中频繁录音，或核心工作时间在社交软件中大量发散想法）。

### 🎯 5. 明日行动策略 (Actionable Steps)
- 结合今天的分析与我的【个人背景】，为我明天的第一步行动提供 3 条最关键、最具有杠杆效应的建议。要求极其具体、可落地。

## 语气要求
- 你的语气应保持专业、客观、敏锐，像一位严格但极具洞察力的教练。
- 不要只是简单复述我的话，**必须要有你的洞察，且深度绑定我的【关于我】设定**。
- 输出排版需清晰美观，适当使用 Emoji，重点内容请使用加粗标记。
"""

    // 日报提示词（计算属性，替换占位符）
    var dailyReportPrompt: String {
        return dailyReportPromptTemplate.replacingOccurrences(of: "{about-me}", with: aboutMe)
    }

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

                // 读取角色说明
                if let role = json["about_me"] as? String {
                    aboutMe = role
                    VoxaLog("[Config] 从配置文件加载角色说明")
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

            // 保存角色说明
            dict["about_me"] = aboutMe
            
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

    /// 更新个人背景说明
    func updateAboutMe(_ description: String) {
        aboutMe = description
        saveConfig()
        VoxaLog("[Config] 个人背景说明已更新")
    }

    /// 获取所有可用的快捷键
    func availableShortcuts() -> [String] {
        return Array(templates.keys).sorted()
    }
}
