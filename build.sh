#!/bin/bash
set -e

# Get version from the first argument, default to 1.0 if not provided
VERSION="${1:-1.0}"

APP_NAME="Stream Bucket"
APP_ID="com.developername.streambucket" 
DEVELOPER_NAME="Reuben Davern"
DEVELOPER_WEBSITE="https://www.reubendavern.com"
COPYRIGHT_YEAR=$(date +%Y)

# Path to your custom DMG background image (Recommended size: 600x400 px)
DMG_BACKGROUND_SOURCE="icon/dmg_background.png"

BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building $APP_NAME v$VERSION..."

# Ensure build directory exists and clean only the current app bundle
mkdir -p "$BUILD_DIR"
rm -rf "$APP_DIR"

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
cp icon/AppIcon.icns "$RESOURCES_DIR/"

# Create Info.plist with dynamic version injection
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
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    
    <!-- Developer Details -->
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © $COPYRIGHT_YEAR $DEVELOPER_NAME - $DEVELOPER_WEBSITE, All rights reserved.</string>
    <key>CFBundleGetInfoString</key>
    <string>$VERSION, $DEVELOPER_NAME, $DEVELOPER_WEBSITE</string>
    
    <!-- Custom Developer Website Key -->
    <key>WHDeveloperURL</key>
    <string>$DEVELOPER_WEBSITE</string>
</dict>
</plist>
EOF

# Ensure background image exists before proceeding
if [ ! -f "$DMG_BACKGROUND_SOURCE" ]; then
    echo "Error: DMG background image not found at '$DMG_BACKGROUND_SOURCE'."
    echo "Please place a 600x400 image there or update the DMG_BACKGROUND_SOURCE variable."
    exit 1
fi

# Format DMG filename
DMG_NAME="${APP_NAME// /_}_v${VERSION}.dmg"
TMP_DMG="$BUILD_DIR/pack.temp.dmg"

echo "Creating temporary writeable DMG..."
# Calculate approximate size needed for the DMG (App size + 20MB padding)
APP_SIZE=$(du -sm "$APP_DIR" | cut -f1)
DMG_SIZE=$((APP_SIZE + 20))

hdiutil create -size "${DMG_SIZE}m" -fs HFS+ -volname "$APP_NAME" -o "$TMP_DMG" -quiet

echo "Mounting temporary DMG..."
# Mount and capture the mount point path
MOUNT_DIR=$(hdiutil attach -nobrowse -noverify -noautoopen "$TMP_DMG" | grep -o '/Volumes/.*' | head -n 1)

echo "Copying assets into DMG..."
# Copy the app bundle
cp -R "$APP_DIR" "$MOUNT_DIR/"

# Create the Applications folder symlink
ln -s /Applications "$MOUNT_DIR/Applications"

# Copy background image into a hidden folder inside the DMG
mkdir "$MOUNT_DIR/.background"
cp "$DMG_BACKGROUND_SOURCE" "$MOUNT_DIR/.background/background.png"

echo "Applying visual layout adjustments via Finder..."
# Use AppleScript to set window bounds, background, and icon positions
osascript <<EOF
tell application "Finder"
    set theDisk to disk "$APP_NAME"
    open theDisk
    delay 1
    
    set containerWindow to container window of theDisk
    set current view of containerWindow to icon view
    set toolbar visible of containerWindow to false
    set statusbar visible of containerWindow to false
    
    # Position window (left, top, right, bottom) -> 600x400 window size
    set the bounds of containerWindow to {400, 100, 1000, 500}
    
    set viewOptions to the icon view options of containerWindow
    set icon size of viewOptions to 120
    set arrangement of viewOptions to not arranged
    
    # Use relative HFS path targeted cleanly directly to the disk object
    set background picture of viewOptions to file ".background:background.png" of theDisk
    
    # Set item positions directly on the disk object
    set position of item "$APP_NAME.app" of theDisk to {150, 180}
    set position of item "Applications" of theDisk to {450, 180}
    
    # Force Finder to refresh and save its internal cache structure
    update theDisk
    delay 5
    
    # Closing the window commits the layout modifications into the physical .DS_Store file
    close containerWindow
    delay 5
end tell
EOF

# Flush file system buffers to ensure the written .DS_Store file is solid
sync

echo "Unmounting temporary DMG..."
hdiutil detach "$MOUNT_DIR" -quiet
sleep 5

echo "Compressing and finalizing DMG..."
# Convert the writeable DMG to a compressed, read-only production DMG
rm -f "$BUILD_DIR/$DMG_NAME"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$BUILD_DIR/$DMG_NAME" -quiet

# Clean up temporary files
rm -f "$TMP_DMG"

echo "Done! The finished DMG is located at: $BUILD_DIR/$DMG_NAME"