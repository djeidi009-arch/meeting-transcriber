#!/bin/bash
# Собирает build/MeetingTranscriber.app: SwiftPM (release) + Info.plist + ad-hoc подпись.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MeetingTranscriber.app"

cd "$ROOT/app"
swift build -c release --product MeetingTranscriber
BIN="$(swift build -c release --show-bin-path)/MeetingTranscriber"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeetingTranscriber"
cp "$ROOT/app/Resources/Info.plist" "$APP/Contents/Info.plist"
# Иконка нарисована кодом (asset-каталогов без Xcode нет); файл лежит в репозитории, пересоздаётся при пропаже.
ICON="$ROOT/app/Resources/AppIcon.icns"
[ -f "$ICON" ] || swift "$ROOT/scripts/make_icon.swift" "$ICON"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
# Папка проекта — рабочий каталог для `python -m transcriber`.
/usr/libexec/PlistBuddy -c "Set :MTProjectDir $ROOT" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Требование по идентификатору, а не по cdhash: иначе после каждой пересборки macOS забывает выданные разрешения.
codesign --force --sign - --identifier ru.local.meeting-transcriber -r='designated => identifier "ru.local.meeting-transcriber"' "$APP"
codesign --verify --strict "$APP"
echo "Собрано: $APP"
