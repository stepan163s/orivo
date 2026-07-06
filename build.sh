#!/bin/bash
set -e

echo "=== Building Orivo in Release mode ==="
swift build -c release

echo "=== Packaging Orivo.app ==="
APP_DIR="Orivo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# Copy binary
cp ".build/release/Orivo" "$MACOS_DIR/Orivo"

MPV_DYLIB="${MPV_DYLIB:-}"
if [ -z "$MPV_DYLIB" ]; then
    for candidate in \
        "/opt/homebrew/opt/mpv/lib/libmpv.2.dylib" \
        "/usr/local/opt/mpv/lib/libmpv.2.dylib" \
        "/Applications/IINA.app/Contents/Frameworks/libmpv.2.dylib"; do
        if [ -f "$candidate" ]; then
            MPV_DYLIB="$candidate"
            break
        fi
    done
fi

if [ -z "$MPV_DYLIB" ]; then
    echo "Error: libmpv.2.dylib was not found. Install mpv with Homebrew or set MPV_DYLIB=/path/to/libmpv.2.dylib"
    exit 1
fi

# Copy libmpv and its Homebrew dylib dependencies into the bundle
cp "$MPV_DYLIB" "$FRAMEWORKS_DIR/libmpv.2.dylib"
chmod u+w "$FRAMEWORKS_DIR/libmpv.2.dylib"

copy_homebrew_dependency() {
    local dependency="$1"
    case "$dependency" in
        /opt/homebrew/*|/usr/local/*)
            ;;
        *)
            return
            ;;
    esac

    if [ ! -f "$dependency" ]; then
        return
    fi

    local destination="$FRAMEWORKS_DIR/$(basename "$dependency")"
    if [ ! -f "$destination" ]; then
        echo "Bundling $(basename "$dependency")"
        cp "$dependency" "$destination"
        chmod u+w "$destination"
        dylib_queue+=("$destination")
    fi
}

dylib_queue=("$FRAMEWORKS_DIR/libmpv.2.dylib")
processed_dylibs=""
queue_index=0

while [ "$queue_index" -lt "${#dylib_queue[@]}" ]; do
    dylib="${dylib_queue[$queue_index]}"
    queue_index=$((queue_index + 1))

    case "$processed_dylibs" in
        *"|$dylib|"*) continue ;;
    esac
    processed_dylibs="$processed_dylibs|$dylib|"

    while IFS= read -r dependency; do
        copy_homebrew_dependency "$dependency"
    done < <(otool -L "$dylib" | awk 'NR > 1 { print $1 }')
done

rewrite_homebrew_dependencies() {
    local target="$1"
    while IFS= read -r dependency; do
        case "$dependency" in
            /opt/homebrew/*|/usr/local/*)
                local bundled_dependency="$FRAMEWORKS_DIR/$(basename "$dependency")"
                if [ -f "$bundled_dependency" ]; then
                    install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$target" || true
                fi
                ;;
        esac
    done < <(otool -L "$target" | awk 'NR > 1 { print $1 }')
}

# Ensure the executable can locate bundled libraries inside the Frameworks folder.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/Orivo" || true

for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    install_name_tool -id "@rpath/$(basename "$dylib")" "$dylib" || true
    rewrite_homebrew_dependencies "$dylib"
done
rewrite_homebrew_dependencies "$MACOS_DIR/Orivo"

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
    <string>1.0.6</string>
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
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/stepan163s/orivo/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>+/G7vB1+22/eXb7UuPfVb3tJe8t90lrcQzXj9cRcpW8=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
EOF

echo "=== Code-signing Orivo.app ==="
codesign --force --deep --sign - Orivo.app

echo "=== Orivo.app created successfully! ==="
