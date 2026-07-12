#!/bin/bash
set -e

APP_NAME="Stream Bucket"
APP_ID="com.developername.streambucket" 
DEVELOPER_NAME="Reuben Davern"
DEVELOPER_WEBSITE="https://www.reubendavern.com"
COPYRIGHT_YEAR=$(date +%Y)

APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building $APP_NAME..."

# Create app bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile Swift files
swiftc -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -O \
    Sources/*.swift \
    -o "$MACOS_DIR/$APP_NAME"

# Copy Icon
cp AppIcon.icns "$RESOURCES_DIR/"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    
    <!-- Developer Details -->
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © $COPYRIGHT_YEAR $DEVELOPER_NAME ($DEVELOPER_WEBSITE). All rights reserved.</string>
    <key>CFBundleGetInfoString</key>
    <string>1.0, $DEVELOPER_NAME, $DEVELOPER_WEBSITE</string>
    
    <!-- Custom Developer Website Key -->
    <key>WHDeveloperURL</key>
    <string>$DEVELOPER_WEBSITE</string>
</dict>
</plist>
EOF

echo "Done! Run with: open $APP_DIR"