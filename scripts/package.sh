#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="${APP_NAME:-Codex 任务宠物}"
VERSION="${VERSION:-1.1.3}"
BUILD_NUMBER="${BUILD_NUMBER:-6}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"

swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$BIN_DIR/AgentPet" "$APP_PATH/Contents/MacOS/AgentPet"
cp "$ROOT_DIR/Support/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ROOT_DIR/Sources/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AgentPet.icns"
for resource_bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$resource_bundle" "$APP_PATH/Contents/Resources/"
done

plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PATH/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

codesign --force --deep --sign - "$APP_PATH"
printf '应用包已生成：%s\n' "$APP_PATH"
