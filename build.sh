#!/bin/bash
set -e

echo "=== Building Orivo in Release mode ==="
swift build -c release

echo "=== Packaging Orivo.app ==="
APP_DIR="Orivo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp ".build/release/Orivo" "$MACOS_DIR/Orivo"

# Copy libmpv framework into the bundle
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
cp "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib" "$FRAMEWORKS_DIR/libmpv.2.dylib"

# Ensure the executable can locate the library inside the Frameworks folder and system Homebrew
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/Orivo" || true
install_name_tool -add_rpath "/opt/homebrew/lib" "$MACOS_DIR/Orivo" || true

# Generate AppIcon.icns if icon.jpg exists
if [ -f "icon.jpg" ]; then
    echo "=== Generating AppIcon.icns ==="
    mkdir -p AppIcon.iconset
    sips -s format png -z 16 16     icon.jpg --out AppIcon.iconset/icon_16x16.png > /dev/null 2>&1
    sips -s format png -z 32 32     icon.jpg --out AppIcon.iconset/icon_16x16@2x.png > /dev/null 2>&1
    sips -s format png -z 32 32     icon.jpg --out AppIcon.iconset/icon_32x32.png > /dev/null 2>&1
    sips -s format png -z 64 64     icon.jpg --out AppIcon.iconset/icon_32x32@2x.png > /dev/null 2>&1
    sips -s format png -z 128 128   icon.jpg --out AppIcon.iconset/icon_128x128.png > /dev/null 2>&1
    sips -s format png -z 256 256   icon.jpg --out AppIcon.iconset/icon_128x128@2x.png > /dev/null 2>&1
    sips -s format png -z 256 256   icon.jpg --out AppIcon.iconset/icon_256x256.png > /dev/null 2>&1
    sips -s format png -z 512 512   icon.jpg --out AppIcon.iconset/icon_256x256@2x.png > /dev/null 2>&1
    sips -s format png -z 512 512   icon.jpg --out AppIcon.iconset/icon_512x512.png > /dev/null 2>&1
    sips -s format png -z 1024 1024 icon.jpg --out AppIcon.iconset/icon_512x512@2x.png > /dev/null 2>&1
    
    iconutil -c icns AppIcon.iconset
    mv AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
    rm -rf AppIcon.iconset
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Orivo</string>
    <key>CFBundleIdentifier</key>
    <string>com.orivo.manager</string>
    <key>CFBundleName</key>
    <string>Orivo</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "=== Code-signing Orivo.app ==="
codesign --force --deep --sign - Orivo.app

echo "=== Orivo.app created successfully! ==="
