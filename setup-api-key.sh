#!/bin/bash

# setup-api-key.sh - 设置 Voxa API Key

CONFIG_DIR="$HOME/.config/voxa"
CONFIG_FILE="$CONFIG_DIR/config.json"

# 创建配置目录
mkdir -p "$CONFIG_DIR"

echo "🔑 Voxa API Key 设置"
echo ""
echo "配置文件位置: $CONFIG_FILE"
echo ""

# 检查是否已有配置文件
if [ -f "$CONFIG_FILE" ]; then
    echo "⚠️  配置文件已存在"
    read -p "是否覆盖? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 0
    fi
fi

# 提示输入 API Key
read -p "请输入 DashScope API Key: " api_key

if [ -z "$api_key" ]; then
    echo "❌ API Key 不能为空"
    exit 1
fi

# 创建配置文件
cat > "$CONFIG_FILE" << EOF
{
  "api_key": "$api_key",
  "templates": {
    "alt+1": {
      "name": "轻度润色",
      "prompt": "你是一个语音转文字的轻度润色助手。用户输入是语音识别的原始结果，你只能做以下修改：修正明显的错别字、同音字错误、补全缺失标点、去除重复词。禁止改变用户的表达方式、句式结构、语气和风格。禁止添加任何原文中没有的内容。只输出润色后的文字，不要任何解释。"
    },
    "alt+2": {
      "name": "正式书面",
      "prompt": "转为正式书面语，使用规范的语法和词汇，适合商务邮件和正式文档。保持原意不变。"
    },
    "alt+3": {
      "name": "自然口语",
      "prompt": "转为自然流畅的口语表达，适合日常聊天和即时通讯。保持轻松自然的语气。"
    },
    "alt+4": {
      "name": "精简文本",
      "prompt": "精简文本，去除冗余词汇和重复内容，保留核心信息。保持原意不变。"
    }
  }
}
EOF

echo ""
echo "✅ API Key 已保存到: $CONFIG_FILE"
echo ""
echo "你也可以手动编辑该文件来:"
echo "  - 修改 API Key"
echo "  - 自定义润色模板"
echo ""
echo "🚀 重启 Voxa 后生效"
