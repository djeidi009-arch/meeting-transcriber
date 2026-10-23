#!/bin/bash
# Снимает автозапуск и удаляет приложение из ~/Applications.
# Настройки (~/.config/meeting-transcriber) и встречи (~/transcripts) не трогает.
# Проверка без изменений системы: MT_HOME=/tmp/x MT_SKIP_LAUNCHCTL=1 scripts/uninstall.sh
set -euo pipefail

TARGET_HOME="${MT_HOME:-$HOME}"
LABEL="ru.local.meeting-transcriber"
AGENT="$TARGET_HOME/Library/LaunchAgents/$LABEL.plist"
APP="$TARGET_HOME/Applications/MeetingTranscriber.app"

if [ -z "${MT_SKIP_LAUNCHCTL:-}" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  pkill -x MeetingTranscriber 2>/dev/null || true
fi
rm -f "$AGENT"
rm -rf "$APP"
echo "Удалено: $APP и $AGENT"
echo "Настройки и встречи оставлены: $TARGET_HOME/.config/meeting-transcriber, папка из outputDir"
