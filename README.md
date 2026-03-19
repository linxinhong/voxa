# Voxa

一款基于 Swift 构建的 macOS 浮动语音输入工具。

## 功能特性

- 🎙️ **实时语音识别**：基于阿里云百炼 Paraformer ASR
- ⌨️ **全局快捷键**：Option + Space 快速切换
- 💬 **浮动输入条**：不抢夺目标应用焦点
- ✨ **智能润色**：本地清洗 + LLM 轻度润色
- 📋 **无缝注入**：剪贴板 + Cmd+V 自动注入文字

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Swift 5.10+
- Xcode 15+ (可选)

## 安装

### 方式一：从源码构建

```bash
# 克隆仓库
git clone <repository-url>
cd Voxa

# 设置 API Key (开发用)
export DASHSCOPE_API_KEY="your-api-key"

# 构建
swift build

# 运行
swift run
```

### 方式二：Xcode 打开

```bash
open Package.swift
```

## 配置

### API Key

在运行前需要设置阿里云百炼 API Key：

```bash
export DASHSCOPE_API_KEY="sk-xxxxxxxx"
```

或使用 Keychain 存储（待实现）。

### 权限

首次运行需要授权：

1. **麦克风权限**：用于语音识别
2. **辅助功能权限**：用于模拟 Cmd+V 注入文字

## 使用

1. 在任何输入框中，按下 **Option + Space**
2. 开始说话，文字会实时显示在浮动条中
3. 再次按下 **Option + Space** 或手动编辑后按 Enter
4. 文字会自动注入到之前的输入框

## 快捷键

- `Option + Space`：开始/停止录音
- `Esc`：取消录音

## 项目结构

```
Voxa/
├── VoxaApp.swift              # 应用入口
├── AppDelegate.swift          # 应用生命周期和菜单栏
├── UI/
│   ├── FloatingPanel.swift    # 浮动窗口
│   ├── InputBarView.swift     # 输入条视图
│   └── PanelController.swift  # 面板控制
├── State/
│   └── AppState.swift         # 应用状态
├── Hotkey/
│   └── HotkeyManager.swift    # 热键管理
├── Audio/
│   └── AudioCapture.swift     # 音频采集
├── ASR/
│   ├── AsrClient.swift        # ASR WebSocket 客户端
│   └── AsrEvent.swift         # ASR 事件定义
├── Cleaner.swift              # 本地文本清洗
├── Polisher.swift             # LLM 润色
└── Injector.swift             # 文字注入
```

## 技术栈

- **语言**：Swift 5.10+
- **GUI**：SwiftUI + AppKit
- **音频**：AVAudioEngine
- **ASR**：阿里云百炼 Paraformer 实时语音识别 v2
- **WebSocket**：URLSessionWebSocketTask
- **热键**：soffes/HotKey
- **权限**：Keychain, Accessibility

## License

MIT License
