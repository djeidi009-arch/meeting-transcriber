#!/bin/bash
# Ставит собранное приложение в ~/Applications, пишет config.json и LaunchAgent (автозапуск при входе).
# Для проверки без изменений системы:
#   MT_HOME=/tmp/x MT_SKIP_LAUNCHCTL=1 scripts/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_HOME="${MT_HOME:-$HOME}"
LABEL="ru.local.meeting-transcriber"
SRC_APP="$ROOT/build/MeetingTranscriber.app"
APP_DIR="$TARGET_HOME/Applications"
APP="$APP_DIR/MeetingTranscriber.app"
AGENT_DIR="$TARGET_HOME/Library/LaunchAgents"
AGENT="$AGENT_DIR/$LABEL.plist"
CONFIG_DIR="$TARGET_HOME/.config/meeting-transcriber"
CONFIG="$CONFIG_DIR/config.json"
PYTHON="$ROOT/.venv/bin/python"

[ -d "$SRC_APP" ] || { echo "Нет $SRC_APP — сначала make app" >&2; exit 1; }
[ -x "$PYTHON" ] || echo "Внимание: нет $PYTHON — выполните make setup" >&2

# Абсолютный путь к claude: у приложения из строки меню нет PATH из nvm.
CLAUDE="${MT_CLAUDE_PATH:-$(command -v claude 2>/dev/null || true)}"
if [ -z "$CLAUDE" ]; then
  CLAUDE="$("${SHELL:-/bin/zsh}" -lic 'command -v claude' 2>/dev/null | tail -1 || true)"
fi
if [ -z "$CLAUDE" ] || [ ! -x "$CLAUDE" ]; then
  echo "Внимание: claude не найден в PATH — summary работать не будет. Впишите claudePath в $CONFIG" >&2
  CLAUDE="claude"
fi

# Остановить запущенную копию перед заменой.
if [ -z "${MT_SKIP_LAUNCHCTL:-}" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  pkill -x MeetingTranscriber 2>/dev/null || true
fi

mkdir -p "$APP_DIR" "$AGENT_DIR" "$CONFIG_DIR"
rm -rf "$APP"
cp -R "$SRC_APP" "$APP"

# config.json: пути обновляются, остальные настройки пользователя сохраняются.
json_ok() { plutil -convert xml1 -o /dev/null "$1" >/dev/null 2>&1; }
if [ -f "$CONFIG" ] && json_ok "$CONFIG"; then
  plutil -replace claudePath -string "$CLAUDE" "$CONFIG"
  plutil -replace pythonPath -string "$PYTHON" "$CONFIG"
  plutil -convert json -r "$CONFIG"
elif [ -f "$CONFIG" ]; then
  cp "$CONFIG" "$CONFIG.bak"
  echo "Внимание: $CONFIG не читается как JSON — сохранён в config.json.bak и создан заново" >&2
  write_default=1
else
  write_default=1
fi
if [ -n "${write_default:-}" ]; then
  cat > "$CONFIG" <<JSON
{
  "outputDir": "~/transcripts",
  "language": "ru",
  "claudePath": "$CLAUDE",
  "pythonPath": "$PYTHON",
  "summaryTimeoutSec": 300,
  "extraBundleIDs": [],
  "extraTitlePatterns": []
}
JSON
fi
json_ok "$CONFIG" || { echo "Ошибка: $CONFIG — не JSON" >&2; exit 1; }

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP/Contents/MacOS/MeetingTranscriber</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>StandardErrorPath</key>
	<string>$TARGET_HOME/Library/Logs/MeetingTranscriber/app.log</string>
</dict>
</plist>
PLIST
plutil -lint "$AGENT" >/dev/null
mkdir -p "$TARGET_HOME/Library/Logs/MeetingTranscriber"

if [ -z "${MT_SKIP_LAUNCHCTL:-}" ]; then
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
fi

echo "Установлено: $APP"
echo "Автозапуск: $AGENT"
echo "Настройки: $CONFIG (claude: $CLAUDE)"
