<!-- autopilot:start -->
# Транскрибатор встреч

Локальная программа для macOS: окно «Транскрибатор» + значок в строке меню. Записывает созвоны (Zoom, Meet, Телемост, Контур.Толк и др.) или берёт загруженные аудио/видео, транскрибирует по спикерам, делает summary.
Устройство, контракт папки встречи, статусы, потоки — `docs/architecture.md`; почему так — `docs/adr/`; словарь — `CONTEXT.md`.

## Команды

| Команда | Что делает |
|---------|------------|
| `make setup` | `uv sync`: Python 3.12 + `.venv` |
| `make check` | pytest (62) + Swift `selftest` (251), ~40 с — единственная проверка проекта |
| `uv run pytest tests/test_merge.py` | один файл тестов |
| `cd app && swift run selftest` | только Swift-проверки |
| `make app` | `build/MeetingTranscriber.app` (release + Info.plist + иконка + ad-hoc подпись), ~50 с; одно предупреждение в `Recorder.swift` (non-Sendable capture) — норма |
| `build/MeetingTranscriber.app/Contents/MacOS/MeetingTranscriber --demo -ApplePersistenceIgnoreState YES` | окно с выдуманными встречами, без микрофона, очереди и реальных данных. Флаг `-ApplePersistence…` обязателен: после падения иначе висит диалог восстановления окон |
| то же с `--demo --screenshots <папка> -ApplePersistenceIgnoreState YES` | 8 PNG (`light-*`/`dark-*`), код 0; нужен доступ «Запись экрана» у запускающей программы |
| `.venv/bin/python -m transcriber process "<папка встречи>"` | обработать → `meeting.md`; на готовой папке ничего не делает |
| `.venv/bin/python -m transcriber resummarize "<папка встречи>"` | заново summary из `transcript.json` (не запускалась при описании) |
| `make install` / `make uninstall` | LaunchAgent (запуск с `--background`) + копия в `~/Applications` + `config.json` / снятие. НЕ проверены, трогают систему; сухой прогон: `MT_HOME=<dir> MT_SKIP_LAUNCHCTL=1` |

Запуск без `--demo` (рекордер, очередь, реальные встречи) в сборке с окном ни разу не проверяли. Установленную копию из LaunchAgent не трогать; свой процесс завершать по PID.

## Где что

- `transcriber/` — Python-пайплайн: `__main__.py` → `pipeline.py` (`process`, `resummarize`; asr/diarize/summarize передаются параметром — тесты подставляют фейки). `merge.py` — склейка спикеров и эхо, главный шов тестов; `vad.py` режет речь до 28 с; `models_cache.py` — модели HF; `diarize.py` — pyannote `speaker-diarization-community-1`; `progress.py` пишет `progress.json`; `userdata.py` читает `user.json`.
- `transcriber/config.py` и `app/Sources/DetectorCore/AppConfig.swift` — две реализации одного `config.json`; ключ меняешь — правь обе.
- `app/Package.swift` — таргеты: `DetectorCore` (только Foundation: всё, что тестирует `selftest`), `MeetingTranscriber` (AppKit/SwiftUI; вход `main.swift`, делегат `StatusMenu.swift`, состояние окна `AppModel.swift`, экраны `UI/`, токены `UI/Theme.swift`, `Demo.swift`, `Screenshots.swift`), `selftest` (замена XCTest, видит только `DetectorCore`; новый набор `XxxTests.all()` — в конец `selftest/main.swift`). Зависимости: DSWaveformImage, Pow.
- Папка встречи `<outputDir>/<ГГГГ-ММ-ДД ЧЧ-ММ> <Приложение>/`: файлы, кто пишет, статус — `docs/architecture.md`.
- `scripts/`: `build_app.sh`, `install.sh`, `uninstall.sh`, `make_icon.swift` (рисует `app/Resources/AppIcon.icns`). Логи: `~/Library/Logs/MeetingTranscriber/` (`processing.log`, `app.log`).

## Подводные камни

- Подпись ad-hoc: после пересборки macOS может заново спросить микрофон и запись экрана или молча считать доступ выключенным — выдай заново и перезапусти приложение.
- LaunchAgent не видит PATH из nvm: `claude` и `.venv/bin/python` берутся из `config.json` (`claudePath`, `pythonPath`); `ProcessingQueue` добавляет к PATH только `/opt/homebrew/bin`, `/usr/local/bin` и папку `claude`.
- Модели HF — сначала из локального кеша (`local_files_only=True`): онлайн-проверка висела минутами. Токен — `~/.cache/huggingface/token`.
- `torch==2.8.0`, `torchaudio==2.8.0`, `torchcodec==0.7.0` закреплены вместе — не обновляй по одному.
- Код выхода `process`/`resummarize`: 0 — ок, 1 — сбой, 2 — транскрипт готов, сбой только summary (`ProcessingQueue.exitSummaryFailed`). Summary — `claude -p`, нужен живой вход в CLI.
- Без Xcode нет `actool` и `metal`: `resources:`, asset-каталоги, `.metal`, `Bundle.module` нельзя; Vortex и Inferno не собираются; из Pow нельзя `.poof`, `.anvil`, `SmokeEffect`. Без `linkedFramework("AVKit")` `VideoPlayer` падает при показе; `platforms: [.macOS("26.0")]` — строкой, `.v26` требует tools 6.2.
- Bundle id `ru.local.meeting-transcriber`, исполняемый файл и имя бандла `MeetingTranscriber` не менять: на них разрешения и LaunchAgent. Демо делит `UserDefaults` с установленной копией — новые ключи с префиксом `window.`.
- `MeetingLibrary.search` и первый `items()` читают все транскрипты — не с главного потока.
- Весь текст пользователю — по-русски, имена в коде — по-английски. Тяжёлые модели и `claude` в тестах не грузить.

## Окружение

- macOS 26+, Apple Silicon; только Command Line Tools (Xcode нет); Python 3.12 строго через `uv`, системный `python3` не использовать; `ffmpeg` и `uv` из Homebrew; `claude` в PATH (абсолютный путь пишет `install.sh`).
- `~/.config/meeting-transcriber/config.json`: `outputDir` (по умолчанию `~/transcripts`), `language`, `claudePath`, `pythonPath`, `summaryTimeoutSec`, `extraBundleIDs`, `extraTitlePatterns`; `autoRecord` (выкл. по умолчанию) — в `UserDefaults`.
- Аргументы приложения: `--background` (без окна при старте; ставит LaunchAgent), `--demo`, `--screenshots <папка>` (только с `--demo`), `--probe` [`--watch`] — снимок, кто держит микрофон. Сети нет, кроме `claude -p` и первой загрузки моделей HF.

## Как здесь работает Autopilot

Сборка ведётся навыком `/autopilot`. Требования, спецификация и таски — в `.autopilot/`.
Прогресс — `.autopilot/dashboard.html`. Требование из `manifest.md` может снять
только пользователь. Прерванную сборку продолжает «продолжи автопилот».

### Правка без автопилота

Мелкий баг или доводка после сборки — обычная сессия, без прогона.

Сначала прочитай:
1. `.autopilot/PROGRESS.md` — что не доделано, известные баги, о чём договорились с пользователем.
2. Что правили после последней сборки — первая строка таблицы в «История git».
3. Только если правка их касается: почему сделано так — `docs/adr/`; что значат слова — `CONTEXT.md`;
   что именно просили — `manifest.md` в папке сборки (указана в начале `PROGRESS.md`).

После правки:
- коммит — по правилам из «История git»;
- строка в «Правки без автопилота» в `PROGRESS.md`: дата — что — почему;
- починенный пункт из «Не доделано» или «Известные баги» — удали;
- договорились с пользователем о том, что следующая сборка не должна пересматривать, —
  строка в «Договорились», его словами.

### История git

Целиком не читай — бери срез под вопрос:

| Вопрос | Команда |
|---|---|
| что правили после последней сборки | `git log --oneline "$(git log -1 --format=%h --grep='^Autopilot: сборка сдана')"..HEAD -- . ':(exclude).autopilot'` |
| всё, что делали ради требования | `git log --oneline --grep="R02"` |
| история файла | `git log --oneline -10 -- <файл>` |
| когда появился или исчез код | `git log --oneline -S "<фрагмент>"` |
| почему строка такая | `git blame -L <с>,<по> <файл>`, затем `git show <sha>` |
| что внутри коммита | `git show --stat <sha>` |

Срез длиннее ~30 коммитов — отдай его субагенту и возьми выжимку в десять строк.

Коммит: заголовок — что (`fix: даты в одном формате`), тело — почему, трейлер
`--trailer "Requirements: R02"`, если правка касается требования из `manifest.md`.
Заголовок `Autopilot: сборка сдана` пишет только автопилот — по нему находят последнюю сборку.
<!-- autopilot:end -->
