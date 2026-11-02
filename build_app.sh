#!/bin/zsh
set -euo pipefail

PROJECT_DIR="/Users/paulcooper/.gemini/antigravity/scratch/cf15t-command-center"
APP_NAME="CF15T Command Center"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>CF15T Command Center</string>
    <key>CFBundleExecutable</key>
    <string>CF15TCommandCenter</string>
    <key>CFBundleIdentifier</key>
    <string>com.paulcooper.cf15t-command-center</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CF15T Command Center</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>CF15T Command Center controls microphone mute and input levels for Grok Bot and Dot.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>CF15T Command Center uses system events for audio volume and window management.</string>
</dict>
</plist>
EOF

echo "Compiling CF15T Command Center..."
swiftc \
    -O \
    -target arm64-apple-macosx15.0 \
    -framework Cocoa \
    -framework SwiftUI \
    -framework ApplicationServices \
    -framework CoreAudio \
    -framework AudioToolbox \
    -framework IOKit \
    "$PROJECT_DIR/Sources/Models.swift" \
    "$PROJECT_DIR/Sources/CoreAudioMicManager.swift" \
    "$PROJECT_DIR/Sources/WindowTilingEngine.swift" \
    "$PROJECT_DIR/Sources/AgentAndTaskMonitor.swift" \
    "$PROJECT_DIR/Sources/CursorSnapbackEngine.swift" \
    "$PROJECT_DIR/Sources/SiSTouchHardwareDriver.swift" \
    "$PROJECT_DIR/Sources/CommandCenterViewModel.swift" \
    "$PROJECT_DIR/Sources/VoiceSlotEditorSheet.swift" \
    "$PROJECT_DIR/Sources/CommandCenterViews.swift" \
    "$PROJECT_DIR/Sources/CF15TCommandCenterApp.swift" \
    -o "$MACOS_DIR/CF15TCommandCenter"

codesign --force --deep --sign - "$APP_BUNDLE"
echo "Build complete: $APP_BUNDLE"
