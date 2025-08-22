#!/bin/bash

APP_NAME="MovieCutTool"
BUNDLE_ID="com.dsgarage.moviecuttool"
VERSION="1.0"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"

# 既存のappバンドルを削除
rm -rf "$APP_DIR"

# appバンドル構造を作成
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 実行ファイルをコピー
cp "$BUILD_DIR/MovieCutToolApp" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Info.plistを作成
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja_JP</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# PkgInfoを作成
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "✅ $APP_NAME.app バンドルが作成されました"
echo "実行するには: open $APP_DIR"