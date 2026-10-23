<!-- autopilot:start -->
# Транскрибатор встреч

Локальная программа для macOS: записывает созвоны (Zoom, Google Meet, Телемост, Контур.Толк и др.), транскрибирует с разбивкой по спикерам и делает краткое summary.

## Команды

| Команда | Что делает |
|---------|------------|
| `make setup` | `uv sync`: Python 3.12 + `.venv` |
| `make check` | pytest (48) + Swift `selftest` (86 проверок) — единственная проверка проекта |
| `uv run pytest tests/test_merge.py` | один файл тестов |
| `cd app && swift run selftest` | только Swift-проверки |
| `make app` | собрать `build/MeetingTranscriber.app` (release + Info.plist + ad-hoc подпись) |
| `build/MeetingTranscriber.app/Contents/MacOS/MeetingTranscriber --probe` | снимок: кто держит микрофон, какие окна видны (`--watch` — раз в 2 с, с событиями детектора) |
| `.venv/bin/python -m transcriber process "<папка встречи>"` | обработать запись → `meeting.md`; на готовой папке ничего не делает |
| `.venv/bin/python -m transcriber resummarize "<папка встречи>"` | заново summary из `transcript.json` (не запускалась при описании) |
| `make install` / `make uninstall` | LaunchAgent + копия в `~/Applications` + `config.json` / снятие. НЕ проверены, трогают систему; сухой прогон: `MT_HOME=<dir> MT_SKIP_LAUNCHCTL=1` |

## Где что

- `transcriber/` — Python-пайплайн; вход `__main__.py` → `pipeline.py` (`process`, `resummarize`; зависимости asr/diarize/summarize передаются параметром — так тесты подставляют фейки).
- `transcriber/merge.py` — чистая логика склейки спикеров и удаления эха, главный шов тестов; `vad.py` режет речь на участки ≤ 28 с перед `asr.py`.
- `transcriber/models_cache.py` — загрузка HF-моделей; `diarize.py` — pyannote `speaker-diarization-community-1`.
- `transcriber/config.py` и `app/Sources/DetectorCore/AppConfig.swift` — две реализации одного `~/.config/meeting-transcriber/config.json`; ключ меняешь — правь обе.
- `app/Package.swift` — три таргета: `DetectorCore` (только Foundation: детектор, `MeetingStore`, `ProcessingQueue`, `TrackAligner`), `MeetingTranscriber` (AppKit/CoreAudio/ScreenCaptureKit: `Recorder`, `SystemProbe`, `StatusMenu`, `Notifier`), `selftest` (замена XCTest, его нет).
- `app/Sources/selftest/` — Swift-проверки; новый набор `XxxTests.all()` добавь вызовом в конец `selftest/main.swift`.
- `scripts/build_app.sh` (сборка .app), `scripts/install.sh`, `scripts/uninstall.sh`.
- Контракт Swift ↔ Python — папка встречи `<outputDir>/<ГГГГ-ММ-ДД ЧЧ-ММ> <Приложение>/` (`meta.json`, `mic.caf`/`system.caf`, `transcript.json`, `meeting.md`, `error.txt`); файлы пишут `app/Sources/DetectorCore/MeetingStore.swift` и `transcriber/pipeline.py`; пользовательское описание — `README.md`.
- Логи приложения: `~/Library/Logs/MeetingTranscriber/` (`processing.log`, `app.log` из LaunchAgent).

## Подводные камни

- Подпись ad-hoc: после каждой пересборки macOS может заново спросить микрофон и запись экрана/системного аудио или молча считать доступ выключенным — выдай заново и перезапусти приложение.
- Приложение из LaunchAgent не видит PATH из nvm: пути к `claude` и `.venv/bin/python` берутся из `~/.config/meeting-transcriber/config.json` (`claudePath`, `pythonPath`); `ProcessingQueue` добавляет к PATH дочернего процесса только `/opt/homebrew/bin`, `/usr/local/bin` и папку `claude`.
- Модели HF берутся сначала из локального кеша (`local_files_only=True`), сеть — только если кеша нет: онлайн-проверка обновлений висела минутами. Токен — `~/.cache/huggingface/token`, библиотека читает сама.
- `torch==2.8.0`, `torchaudio==2.8.0`, `torchcodec==0.7.0` закреплены в `pyproject.toml` вместе — не обновляй по одному.
- Код выхода `process`: 0 — ок, 1 — сбой, 2 — расшифровка готова, сбой только summary (`ProcessingQueue.exitSummaryFailed`; не путать с ошибкой). Починка — `resummarize`.
- Summary — `claude -p`: нужен живой вход в Claude Code CLI (подписка), иначе summary падает, а транскрипт остаётся.
- Весь текст для пользователя — по-русски, имена в коде — по-английски. Тяжёлые модели в тестах не грузить.

## Окружение

- macOS 15+, Apple Silicon; только Command Line Tools (Xcode нет), SwiftPM; Python 3.12 строго (`>=3.12,<3.13`) через `uv`; системный `python3` не использовать.
- `ffmpeg` и `uv` из Homebrew; `claude` в PATH (его абсолютный путь пишет `install.sh`).
- Настройки: `~/.config/meeting-transcriber/config.json` (`outputDir` по умолчанию `~/transcripts`, `language`, `claudePath`, `pythonPath`, `summaryTimeoutSec`, `extraBundleIDs`, `extraTitlePatterns`); `autoRecord` — в `UserDefaults` приложения.
- Сети нет, кроме `claude -p` и первой загрузки моделей HF.

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
