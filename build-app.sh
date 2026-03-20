#!/bin/bash

# build-app.sh - 构建 Voxa.app 应用包

set -e

APP_NAME="Voxa"
BUNDLE_ID="com.voxa.app"
VERSION="1.0"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_BUNDLE="${APP_NAME}.app"

echo "🔨 构建 Release 版本..."
swift build -c release

echo "📦 创建 App Bundle..."

# 清理旧的 app bundle
rm -rf "${APP_BUNDLE}"

# 创建目录结构
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 复制可执行文件
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# 创建 Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>Voxa</string>
    <key>CFBundleIdentifier</key>
    <string>com.voxa.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Voxa</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voxa 需要访问麦克风来进行语音识别</string>
</dict>
</plist>
EOF

# 复制 entitlement
cp "Voxa/Voxa.entitlements" "${APP_BUNDLE}/Contents/Resources/" 2>/dev/null || true

# 签名
echo "🔏 签名 App..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ 构建完成: ${APP_BUNDLE}"
echo ""
echo "📍 位置: $(pwd)/${APP_BUNDLE}"
echo "🚀 运行: open ${APP_BUNDLE}"
