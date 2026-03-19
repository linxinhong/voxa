# Voxa

Voxa 是一款基于 Swift 构建的 macOS 浮动语音输入工具。
监听全局快捷键，弹出极简浮动输入条，
通过 WebSocket 将音频流式传输至阿里云百炼 Paraformer ASR，
最终通过剪贴板将识别文字注入到之前聚焦的应用。

## 核心用户流程

1. 用户按下快捷键（开关切换）→ 浮动输入条出现，麦克风激活
2. 用户说话 → ASR 实时识别，结果直接更新到文本框
3. 用户可在说话过程中随时用键盘编辑文本框内容
4. 用户再次按下快捷键 → 停止录音，将文本框内容注入
   到之前聚焦的应用（剪贴板 + Cmd+V），浮动输入条消失

## 文字模型

输入条维护一个单一文本框：

[ 文字内容（用户可编辑）]

- ASR partial 结果：直接覆盖末尾未确认部分（无颜色区分）
- ASR final 结果：清洗后追加至已确认文字，lastPartial 清空
- 用户可自由移动光标并编辑任意位置

## 技术栈

- 语言：Swift 5.10+（严格并发模式）
- GUI：SwiftUI + AppKit（NSPanel 无标题栏浮动窗口，始终置顶）
- 音频：AVAudioEngine（系统原生，自动处理采样率转换，无需 rubato）
- ASR：阿里云百炼 Paraformer 实时语音识别 v2（WebSocket 双工流式）
- 异步：Swift 结构化并发（async/await、Actor、AsyncStream）
- WebSocket：URLSessionWebSocketTask（系统原生，零第三方依赖）
- 全局快捷键：soffes/HotKey 包（封装 Carbon RegisterEventHotKey）
- 文字注入：NSPasteboard + CGEventPost（模拟 Cmd+V）
- 密钥存储：macOS Keychain（SecItemAdd / SecItemCopyMatching）
- 配置：环境变量 DASHSCOPE_API_KEY（开发用）/ Keychain（生产用）

## 项目结构

Voxa/
├── VoxaApp.swift              # @main 入口，NSApplicationDelegate，生命周期
├── AppDelegate.swift          # NSApplication 初始化，菜单栏图标（LSUIElement）
│
├── UI/
│   ├── FloatingPanel.swift    # NSPanel 子类：无边框、不抢焦点、透明背景、始终置顶
│   ├── InputBarView.swift     # SwiftUI 视图：单一文本框
│   └── PanelController.swift  # 显示/隐藏浮动窗口，居中定位
│
├── State/
│   └── AppState.swift         # @MainActor ObservableObject
│                              #   字段：text、isRecording、polishEnabled、
│                              #         targetApp、lastPartial、confirmedText
│
├── Hotkey/
│   └── HotkeyManager.swift    # 注册全局快捷键，触发开关逻辑，记录目标 App
│
├── Audio/
│   └── AudioCapture.swift     # AVAudioEngine 麦克风采集
│                              #   → PCM 16kHz 单声道 i16 LE（含自动重采样）
│
├── ASR/
│   ├── AsrClient.swift        # 百炼 WebSocket 协议实现
│   │                          #   URLSessionWebSocketTask，收发异步循环
│   └── AsrEvent.swift         # 事件定义：partial(String) / final(String)
│
├── Cleaner.swift              # 本地规则过滤（嗯 啊 呃 等填充词、重复词）
├── Polisher.swift             # Qwen API 轻度润色（URLSession 异步，超时 1.5s）
└── Injector.swift             # NSPasteboard + CGEventPost 注入 + 还原剪贴板

## ASR 协议（百炼 Paraformer WebSocket）

WebSocket 地址：wss://dashscope.aliyuncs.com/api-ws/v1/inference/
鉴权 Header：Authorization: bearer {DASHSCOPE_API_KEY}

消息流程：
  客户端 → run-task（JSON，模型：paraformer-realtime-v2）
  服务端 → task-started
  客户端 → 二进制 PCM 帧（16kHz，单声道，i16 LE，每帧 ~200ms = 6400 字节）
  服务端 → result-generated（JSON，含 sentence.text 和 sentence_end 标志）
  客户端 → finish-task（JSON）
  服务端 → task-finished

run-task 关键参数：
  - format: pcm
  - sample_rate: 16000
  - enable_intermediate_result: true      ← 开启 partial 实时结果
  - enable_punctuation_prediction: true
  - enable_inverse_text_normalization: true

result-generated 数据路径：/payload/output/sentence
  - sentence.text：识别文字
  - sentence.sentence_end：true = final，false = partial

### WebSocket 实现说明（Swift）

使用 URLSessionWebSocketTask，无任何第三方依赖：

  let session = URLSession(configuration: .default, delegate: self, ...)
  let task = session.webSocketTask(with: request)
  task.resume()

  // 发送二进制 PCM 帧
  task.send(.data(pcmData)) { error in ... }

  // 接收循环（递归调用）
  func receiveLoop() {
      task.receive { [weak self] result in
          switch result {
          case .success(.string(let text)): self?.handleJSON(text)
          case .success(.data(let data)):   self?.handleBinary(data)
          case .failure(let error):         self?.handleError(error)
          }
          self?.receiveLoop()
      }
  }

## 音频采集（AVAudioEngine）

AVAudioEngine 以设备原生采样率采集（通常 48kHz），
AVAudioConverter 自动重采样为 ASR 所需格式（16kHz 单声道 i16 LE）。
无需引入 rubato 或其他第三方重采样库。

关键步骤：
  1. engine.inputNode.installTap(onBus:bufferSize:format:)
  2. AVAudioConverter：设备原生格式 → pcmFormatInt16 / 16kHz / 单声道
  3. 从 int16ChannelData 中提取 Data
  4. 按 200ms 分帧（~6400 字节）通过 AsyncStream 推送给 AsrClient

麦克风权限：Info.plist 中添加 NSMicrophoneUsageDescription（必须）

## 浮动窗口（NSPanel）

NSPanel 子类，实现不抢焦点的无边框浮动窗口：

  class FloatingPanel: NSPanel {
      init() {
          super.init(
              contentRect: .zero,
              styleMask: [
                  .borderless,
                  .nonactivatingPanel     // ← 不抢夺目标 App 焦点
              ],
              backing: .buffered,
              defer: false
          )
          self.level = .floating          // 始终置顶
          self.collectionBehavior = [
              .canJoinAllSpaces,          // 在所有桌面空间可见
              .fullScreenAuxiliary        // 全屏 App 上方显示
          ]
          self.backgroundColor = .clear
          self.isOpaque = false
          self.hasShadow = true
          self.isMovableByWindowBackground = true
      }
  }

背景：NSVisualEffectView（.hudWindow 材质）实现毛玻璃效果。

## 文字注入（macOS）

热键首次按下时（浮动窗口出现之前），记录当前聚焦的应用：
  NSWorkspace.shared.frontmostApplication

热键第二次按下时：
  1. 保存当前剪贴板内容：NSPasteboard.general.string(forType: .string)
  2. 将最终文字写入剪贴板：NSPasteboard.general.setString(text, forType: .string)
  3. 激活目标 App：targetApp.activate(options: .activateIgnoringOtherApps)
  4. 等待约 80ms 焦点转移完成（Task.sleep）
  5. 通过 CGEventPost 模拟 Cmd+V：
       let src = CGEventSource(stateID: .hidSystemState)
       let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
       vDown?.flags = .maskCommand
       vDown?.post(tap: .cgSessionEventTap)
       // 同样发送 keyDown: false
  6. 等待约 80ms 后还原原始剪贴板内容

## 全局快捷键

通过 HotKey 包（soffes/HotKey）注册，Swift Package Manager 引入：
  .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")

  let hotKey = HotKey(key: .space, modifiers: [.option])
  hotKey.keyDownHandler = { [weak self] in
      self?.hotkeyManager.toggle()
  }

CGEventPost 需要辅助功能权限（AXIsProcessTrusted()）。
首次启动时若权限未授予，引导用户前往系统设置开启。

## 配置与密钥存储

API Key 查找顺序：
  1. macOS Keychain（推荐，通过设置界面一次性配置）
  2. 环境变量 DASHSCOPE_API_KEY（开发/调试用）
  3. ~/.config/voxa/config.plist（兜底方案）

Keychain 操作直接使用系统 API，无需第三方库：
  SecItemAdd / SecItemCopyMatching，kSecClassGenericPassword

## 自动轻度润色

ASR 每次输出 final 句子后，可选择经过轻度润色再追加至文本框。

### 允许修改的内容
- 纠正明显的 ASR 识别错误（如的地得误用、同音字错误）
- 补全明显缺失的标点符号
- 去除 ASR 抖动导致的重复词（如"我我想" → "我想"）
- 规范中英文/数字之间的空格

### 禁止修改的内容
- 禁止改写或重新表述句子
- 禁止改变句式结构
- 禁止添加原文中没有的内容
- 禁止改变用户的语气和风格
- 禁止合并或拆分句子

### 实现方式

每个 ASR final 事件触发一次润色（一句话 = 一次调用）。
以 Swift async Task 异步执行，不阻塞 UI 和 ASR 流。

两阶段处理：
  第一阶段（本地，始终开启）：Cleaner.swift 规则过滤
    - 填充词：嗯 啊 呃 哦 喔 哎 哟
    - 重复词：就是就是 / 那个那个 / 然后然后
    - 句尾犹豫词

  第二阶段（可选，LLM 润色）：调用百炼 Qwen API（URLSession 异步）
    - 模型：qwen-turbo（低延迟）
    - 系统提示词强制限定为轻度修改（见下方）
    - API 调用失败或超时（> 1.5s）时，降级使用第一阶段结果
    - 由 AppState.polishEnabled（Bool，默认 true）控制开关
    - 超时设置：URLRequest.timeoutInterval = 1.5

### Qwen 系统提示词（第二阶段使用）

  你是一个语音转文字的轻度润色助手。
  用户输入是语音识别的原始结果，你只能做以下修改：
  修正明显的错别字、同音字错误、补全缺失标点、去除重复词。
  禁止改变用户的表达方式、句式结构、语气和风格。
  禁止添加任何原文中没有的内容。
  只输出润色后的文字，不要任何解释。

### 模块位置

  Voxa/Polisher.swift

## macOS 所需权限

- 麦克风：Info.plist 添加 NSMicrophoneUsageDescription
- 辅助功能：AXIsProcessTrusted() → CGEventPost（Cmd+V 注入）必须
- 网络：Entitlements 中添加 com.apple.security.network.client
         （WebSocket 连接 + Qwen API 调用）

## 应用模式

Info.plist 中设置 LSUIElement = YES
  → 无 Dock 图标，仅菜单栏显示
  → 浮动窗口不抢夺其他应用的焦点

## 开发说明

- 最低部署目标：macOS 13.0（Ventura）
- Swift 并发：严格模式，所有 UI 更新通过 @MainActor 执行
- 构建：Xcode 15+ 或 `xcodebuild -scheme Voxa`
- 调试日志：Console.app 或
    `log stream --predicate 'subsystem == "com.voxa.app"'`
- 首次运行需授权麦克风权限
- 首次运行需授权辅助功能权限（用于 Cmd+V 注入）
- 依赖管理：Swift Package Manager（不使用 CocoaPods / Carthage）

## 第三方依赖（Swift Package Manager）

.package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
  → 全局快捷键（封装 Carbon API）

除此之外无任何第三方依赖：
- WebSocket + Qwen API → URLSession（系统原生）
- 麦克风采集 + 重采样 → AVAudioEngine（系统原生）
- 全部基于 Apple 系统框架，零 Electron / WebView
