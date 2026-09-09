#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONFIGURATION=${1:-Release}
case "$CONFIGURATION" in
  Debug) SWIFT_CONFIGURATION=debug ;;
  Release) SWIFT_CONFIGURATION=release ;;
  *) echo "Usage: $0 [Debug|Release]" >&2; exit 2 ;;
esac
APP="$ROOT/.build/$CONFIGURATION/Borders.app"
swift build --package-path "$ROOT" -c "$SWIFT_CONFIGURATION" -Xswiftc -warnings-as-errors
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/$SWIFT_CONFIGURATION/borders" "$APP/Contents/MacOS/borders"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>Borders</string>
<key>CFBundleExecutable</key><string>borders</string>
<key>CFBundleIdentifier</key><string>com.nickromney.borders</string>
<key>CFBundleName</key><string>Borders</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "Built $APP"
