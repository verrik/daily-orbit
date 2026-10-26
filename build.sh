#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${ORBIT_OUTPUT_DIR:-$SOURCE_DIR/dist}"
BUILD_DIR="${ORBIT_BUILD_DIR:-$SOURCE_DIR/.build}"
APP="$OUTPUT_DIR/Daily Orbit.app"
SAVER="$BUILD_DIR/Daily Orbit.saver"
mkdir -p "$BUILD_DIR/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SAVER/Contents/MacOS"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache"
TARGET="$(uname -m)-apple-macos13.0"
swiftc -swift-version 5 -target "$TARGET" -O -parse-as-library -emit-library -module-name DailyOrbitSaver \
    "$SOURCE_DIR/Sources/APODCore.swift" "$SOURCE_DIR/Sources/OrbitScreenSaver.swift" \
    -framework AppKit -framework ScreenSaver -framework ImageIO -framework UniformTypeIdentifiers \
    -o "$SAVER/Contents/MacOS/DailyOrbitSaver"
cat > "$SAVER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.dailyorbit.screensaver</string>
<key>CFBundleName</key><string>Daily Orbit</string>
<key>CFBundleExecutable</key><string>DailyOrbitSaver</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>NSPrincipalClass</key><string>DailyOrbitScreenSaverView</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$SAVER"
ditto "$SAVER" "$APP/Contents/Resources/Daily Orbit.saver"
swiftc -swift-version 5 -target "$TARGET" -O -parse-as-library \
    "$SOURCE_DIR/Sources/APODCore.swift" "$SOURCE_DIR/Sources/Desktop.swift" "$SOURCE_DIR/Sources/DailyOrbitApp.swift" \
    -framework AppKit -framework SwiftUI -framework ServiceManagement -framework ImageIO -framework UniformTypeIdentifiers \
    -o "$APP/Contents/MacOS/DailyOrbit"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.dailyorbit.app</string>
<key>CFBundleName</key><string>Daily Orbit</string>
<key>CFBundleDisplayName</key><string>Daily Orbit</string>
<key>CFBundleExecutable</key><string>DailyOrbit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Personal local app. APOD imagery retains its original credits and rights.</string>
</dict></plist>
PLIST
swift "$SOURCE_DIR/Resources/MakeIcon.swift" "$BUILD_DIR/AppIcon.iconset" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
