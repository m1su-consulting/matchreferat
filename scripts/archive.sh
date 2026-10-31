#!/bin/bash
# Usage: scripts/archive.sh            -> builds a Release archive and opens Xcode Organizer
#        scripts/archive.sh --upload   -> builds and uploads straight to App Store Connect
# Requires: Sources/GoogleService-Info.plist and the Apple account for team VNDXQRN7C3 in Xcode.
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

UPLOAD=false
[ "$1" = "--upload" ] && UPLOAD=true

TEAM_ID="VNDXQRN7C3"
ARCHIVE_PATH="$PROJECT_DIR/build/Archive/Matchreferat.xcarchive"

if [ ! -f Sources/GoogleService-Info.plist ]; then
  echo "⚠️  Sources/GoogleService-Info.plist saknas – livelänken fungerar inte utan den."
  exit 1
fi

rm -rf Matchreferat.xcodeproj && xcodegen generate
VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"(.*)".*/\1/')
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed -E 's/.*"(.*)".*/\1/')
echo "🏷  Matchreferat $VERSION (bygge $BUILD)"

rm -rf "$ARCHIVE_PATH"
xcodebuild \
  -project Matchreferat.xcodeproj \
  -scheme Matchreferat \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive
echo "✅ Arkiv: $ARCHIVE_PATH"

if [ "$UPLOAD" = true ]; then
  EXPORT_OPTIONS="$PROJECT_DIR/build/Archive/ExportOptions.plist"
  cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$PROJECT_DIR/build/Archive/export" -allowProvisioningUpdates
  echo "✨ Uppladdat! Bygget syns i App Store Connect om 10–30 minuter."
  echo "   Höj CURRENT_PROJECT_VERSION i project.yml innan nästa uppladdning (nu $BUILD)."
else
  open -a Xcode "$ARCHIVE_PATH"
  echo "✨ Klicka 'Distribute App' -> 'App Store Connect' i Xcode Organizer."
fi
