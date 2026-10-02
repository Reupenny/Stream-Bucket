#!/bin/bash
set -e

# Get version from the first argument, default to 1.0 if not provided
VERSION="${1:-1.0}"

APP_NAME="Stream Bucket"
APP_ID="com.developername.streambucket" 
DEVELOPER_NAME="Reuben Davern"
DEVELOPER_WEBSITE="https://reubendavern.com"
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

# --- Cleanup any volume left mounted by a previous (possibly interrupted) build ---
# If a stale "Stream Bucket" volume is still attached, macOS mounts the new image
# as "Stream Bucket 1". Finder's `disk "Stream Bucket"` then targets the OLD
# volume, so the background/icon settings are written there and silently lost
# from the DMG we ship. Always start from a known-clean mount state.
STALE_MOUNT="/Volumes/$APP_NAME"
if mount | grep -qF " on $STALE_MOUNT "; then
    echo "Detaching stale volume from a previous build..."
    hdiutil detach "$STALE_MOUNT" -quiet || hdiutil detach -force "$STALE_MOUNT" -quiet || true
    sleep 2
fi
# Remove the temp image from any earlier run so hdiutil create starts fresh.
rm -f "$TMP_DMG"

# If this script is interrupted (Ctrl-C) or errors out mid-way, detach the
# volume so the next build doesn't collide with a stale "Stream Bucket" mount.
cleanup_build_volume() {
    if [ -n "${MOUNT_DIR:-}" ] && mount | grep -qF " on $MOUNT_DIR "; then
        hdiutil detach -force "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    fi
}
trap cleanup_build_volume EXIT INT TERM

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
# Use AppleScript to set window bounds, background, and icon positions.
# `try`/`on error` is essential: without it a failed `set` (e.g. Finder can't
# resolve the disk) only prints "execution error" and the build still reports
# success, producing a DMG with a plain white background.
osascript <<EOF
tell application "Finder"
    try
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
        return "ok"
    on error errMsg number errNum
        return "FINDER_ERROR " & errNum & ": " & errMsg
    end try
end tell
EOF

# Verify the background was actually committed to the volume's .DS_Store.
# NOTE: Finder's `background picture` property cannot be read back (it always
# raises -10000 on Finder 27, even when unset), so we verify the artefact we
# care about instead: the `bwsp` (background window settings) record plus the
# background.png reference inside .DS_Store.
if [ ! -f "$MOUNT_DIR/.DS_Store" ]; then
    echo "Error: no .DS_Store was written to the DMG volume."
    echo "Aborting so a DMG with a missing background is not published."
    exit 1
fi

if ! python3 - "$MOUNT_DIR/.DS_Store" <<'PYCHECK'
import sys
data = open(sys.argv[1], 'rb').read()
text = data.decode('utf-16-le', 'ignore')
ok = b'bwsp' in data and 'background' in text.lower()
sys.exit(0 if ok else 1)
PYCHECK
then
    echo "Error: .DS_Store is missing the 'bwsp' background record."
    echo "Aborting so a DMG with a missing background is not published."
    exit 1
fi

echo "Verified: background record (bwsp) present in .DS_Store"

# Flush file system buffers to ensure the written .DS_Store file is solid
sync

echo "Unmounting temporary DMG..."
# Retry with a forced unmount so a lingering Finder handle cannot leave the
# volume attached (which would break the *next* build via the name collision).
hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach -force "$MOUNT_DIR" -quiet
sleep 2

# Make sure the volume really is gone before we finish.
for _ in 1 2 3 4 5; do
    mount | grep -qF " on $MOUNT_DIR " || break
    sleep 1
done
if mount | grep -qF " on $MOUNT_DIR "; then
    echo "Warning: $MOUNT_DIR is still mounted; forcing detach."
    hdiutil detach -force "$MOUNT_DIR" -quiet || true
    sleep 2
fi

echo "Compressing and finalizing DMG..."
# Convert the writeable DMG to a compressed, read-only production DMG
rm -f "$BUILD_DIR/$DMG_NAME"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$BUILD_DIR/$DMG_NAME" -quiet

# Clean up temporary files
rm -f "$TMP_DMG"

echo "Done! The finished DMG is located at: $BUILD_DIR/$DMG_NAME"