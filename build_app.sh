#!/bin/bash
set -e

echo "🔨 Building RunwayLeft in Release mode..."
swift build -c release

APP_NAME="RunwayLeft.app"
EXECUTABLE="RunwayLeft"
BUNDLE_DIR="build/$APP_NAME"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MacOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📁 Creating app bundle structure at $BUNDLE_DIR..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MacOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "🚚 Copying compiled binary, app icon, and brand assets..."
cp ".build/release/$EXECUTABLE" "$MacOS_DIR/$EXECUTABLE"
cp assets/*.png "$RESOURCES_DIR/" 2>/dev/null || true
cp assets/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"

echo "📄 Creating Info.plist..."
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>RunwayLeft</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.runwayleft.app</string>
    <key>CFBundleName</key>
    <string>RunwayLeft</string>
    <key>CFBundleDisplayName</key>
    <string>RunwayLeft</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.13.0</string>
    <key>CFBundleVersion</key>
    <string>16</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <!-- A self-hosted LiteLLM proxy is typically plain http://localhost:4000 or
         an internal host; the user types the URL, so arbitrary loads are allowed. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "📄 Creating Entitlements.plist..."
cat << 'EOF' > "Entitlements.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF

chmod +x "$MacOS_DIR/$EXECUTABLE"

echo "🔏 Code-signing app bundle with entitlements..."
# Use Apple's xattr explicitly: pyenv/pip can shadow it with a Python xattr that lacks -r
/usr/bin/xattr -cr "$BUNDLE_DIR"
codesign --force --deep --options runtime --entitlements Entitlements.plist --sign - "$BUNDLE_DIR"

echo "✅ App bundle created and signed successfully at build/$APP_NAME"
echo "🚀 To run the app, execute: open 'build/$APP_NAME'"
