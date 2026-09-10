#!/bin/bash
set -e

APP_NAME="RunwayLeft.app"
EXECUTABLE="RunwayLeft"
BUNDLE_DIR="build/$APP_NAME"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MacOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# RUNWAYLEFT_UNIVERSAL=1 builds for Apple silicon and Intel in one binary; the
# release workflow sets it so one download serves every Mac. Local builds stay
# single-architecture because they take half the time.
if [ "${RUNWAYLEFT_UNIVERSAL:-0}" = "1" ]; then
    echo "🔨 Building RunwayLeft in Release mode (universal)..."
    swift build -c release --arch arm64 --arch x86_64
    BINARY=".build/apple/Products/Release/$EXECUTABLE"
else
    echo "🔨 Building RunwayLeft in Release mode..."
    swift build -c release
    BINARY=".build/release/$EXECUTABLE"
fi

echo "📁 Creating app bundle structure at $BUNDLE_DIR..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MacOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "🚚 Copying compiled binary, app icon, and brand assets..."
cp "$BINARY" "$MacOS_DIR/$EXECUTABLE"
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
    <string>1.13.1</string>
    <key>CFBundleVersion</key>
    <string>17</string>
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
