# Интерфейсы и правила проекта

## Правила проекта

- macOS 15+ (у пользователя 27), Apple Silicon M4, 16 ГБ. Xcode нет — только Command Line Tools: Swift собирается через SwiftPM (`swift build`), XCTest может отсутствовать — тесты Swift идут исполняемым таргетом `selftest` с собственными проверками.
- Python — через `uv`, Python 3.12, `.venv` в корне проекта. Системный `python3` (3.9) не использовать.
- Весь текст, который видит пользователь (меню, уведомления, Markdown, README) — по-русски. Имена в коде — по-английски.
- Никаких сетевых сервисов, кроме `claude -p` и первой загрузки моделей с Hugging Face. Ключей и токенов в коде и настройках нет; токен HF уже лежит в `~/.cache/huggingface/token`, библиотека берёт его сама.
- `ollama` не используется ни в каком виде.
- Одна команда проверки: `make check` (pytest + swift selftest). Один файл тестов: `uv run pytest tests/test_merge.py`; только Swift: `cd app && swift run selftest`.
- Команды: `make setup` (uv sync), `make app` (собрать `.app` в `build/`), `make install` (setup + app + копия в `~/Applications/MeetingTranscriber.app` + LaunchAgent `ru.local.meeting-transcriber` + `config.json` с абсолютными путями к `claude` и `.venv/bin/python`), `make uninstall`.
- Таск 01 владеет `pyproject.toml`, `transcriber/`, `tests/`; таск 02 — `app/`, `scripts/`, `Makefile`, `README.md`. Чужую зону не трогать.
- Зависимости Python (ставит таск 01): `mlx-whisper`, `pyannote.audio==4.0.7`, `torch`, `pytest`. Тяжёлые модели в тестах не грузить — тесты используют фейки через параметры `pipeline.process`.

## Раскладка репозитория

```
Makefile                  setup · app · install · uninstall · check
pyproject.toml            пакет transcriber, зависимости
transcriber/              Python-обработка
tests/                    pytest
app/Package.swift         SwiftPM: DetectorCore (lib), MeetingTranscriber (exe), selftest (exe)
app/Sources/...
app/Resources/Info.plist  LSUIElement, NSMicrophoneUsageDescription, bundle id ru.local.meeting-transcriber
scripts/                  build_app.sh, install.sh (LaunchAgent, config)
README.md                 по-русски: установка, разрешения, как пользоваться
```

## Границы, решённые в спецификации

### Папка встречи — общий контракт Swift ↔ Python

`<outputDir>/<YYYY-MM-DD HH-MM> <AppName>/` (при совпадении имени — суффикс ` (2)`).

| Файл | Кто пишет | Когда |
|---|---|---|
| `meta.json` | Swift | при старте записи; `endedAt` дописывается при остановке |
| `.recording` | Swift | пустой маркер на время записи; удаляется при остановке |
| `mic.caf`, `system.caf` | Swift | во время записи (CAF — переживает падение) |
| `mic.m4a`, `system.m4a` | Python | конвертация из `.caf`; `.caf` удаляются только после успешного `meeting.md` |
| `transcript.json` | Python | реплики после склейки — для повторного summary без расшифровки |
| `meeting.md` | Python | итог; его наличие = встреча обработана |
| `error.txt` | Python | текст последней ошибки обработки (удаляется при успехе) |

`meta.json`: `{"app": "Zoom", "bundleId": "us.zoom.xos", "startedAt": "ISO-8601 с часовым поясом", "endedAt": "…|null", "manual": false}`.

Дорожка может отсутствовать или быть пустой/тишиной (нет доступа, никто не говорил) — обработка не падает, просто нет реплик этой дорожки.

### Настройки — `~/.config/meeting-transcriber/config.json`

Читают обе стороны; нет файла/ключа → значение по умолчанию.
`outputDir` (`~/transcripts`), `language` (`ru`), `claudePath` (`claude`), `pythonPath` (`<проект>/.venv/bin/python`), `summaryTimeoutSec` (300), `extraBundleIDs` ([]), `extraTitlePatterns` ([]). Пишет `scripts/install.sh` с абсолютными путями. Автостарт вкл/выкл — `UserDefaults` приложения, ключ `autoRecord` (по умолчанию true).

### Python — пакет `transcriber`

CLI (`python -m transcriber …`), код выхода 0 — успех, иначе 1 и одна строка ошибки по-русски в stderr:
- `process <meeting_dir>` — caf→m4a/wav, расшифровка, спикеры, склейка, summary, `meeting.md`. Повторный вызов на обработанной папке — ничего не делает, код 0.
- `resummarize <meeting_dir>` — читает `transcript.json`, заново делает summary, перезаписывает `meeting.md`.

Модули и их открытые функции:
- `config.load() -> Config` (dataclass с полями выше).
- `audio.to_wav16k(src: Path, dst: Path) -> bool` (False — дорожки нет или она пустая), `audio.to_m4a(src, dst)`; ffmpeg из `/opt/homebrew/bin` или PATH.
- `asr.transcribe(wav: Path, language: str) -> list[Segment]` — `Segment(start: float, end: float, text: str)`.
- `diarize.diarize(wav: Path) -> list[Turn]` — `Turn(start, end, speaker: str)` (сырые метки pyannote).
- `merge` — **чистые функции, главный шов тестов**:
  - `assign_speakers(segments, turns) -> list[Utterance]` — `Utterance(start, end, speaker, text)`; спикер с наибольшим перекрытием, без перекрытия — ближайший по времени; метки переименовываются в «Спикер 1..N» в порядке первого появления; нет turns → все «Спикер 1».
  - `mic_utterances(segments) -> list[Utterance]` — speaker «Я».
  - `drop_echo(mic, system, threshold=0.6) -> list[Utterance]` — убирает из mic реплики, пересекающиеся по времени (±1 с) с репликой system и похожие по тексту (difflib ratio ≥ threshold).
  - `combine(mic, system) -> list[Utterance]` — сортировка по start, склейка подряд идущих реплик одного спикера (пауза ≤ 30 с).
- `summary.summarize(transcript: str, claude_path: str, timeout: int) -> str` — markdown разделов «Кратко», «Решения», «Задачи», «Открытые вопросы»; бросает `SummaryError(reason)` на ненулевой код, таймаут, пустой вывод, отсутствие бинаря. Вызов: `[claude_path, "-p", "--output-format", "text", <без инструментов>]`, транскрипт в stdin, промпт по-русски.
- `render.render_markdown(meta: dict, summary: str | None, summary_error: str | None, utterances) -> str` — заголовок «<App> — <дата время>», длительность, `## Summary` (или текст ошибки с подсказкой «Меню → Повторить summary»), `## Транскрипт` строками `**[чч:мм:сс] Спикер:** текст`. Пустой транскрипт → «Речь не распознана».
- `pipeline.process(dir, cfg, asr=..., diarize=..., summarize=...)` — зависимости передаются параметрами, тесты подставляют фейки.

### Swift — пакет `app/`

- `DetectorCore` (библиотека, без AppKit/CoreAudio — **шов тестов**):
  - `struct Snapshot { micBundleIDs: [String]; windows: [(bundleID: String, title: String)]; time: TimeInterval }`
  - `struct DetectorConfig { appBundlePrefixes: [String: String] /* префикс bundle ID → имя для папки */; titlePatterns: [String]; startAfter = 5; stopAfter = 90 }` + `static let builtIn`, расширяемый `extraBundleIDs`/`extraTitlePatterns`.
  - `final class MeetingDetector { init(config:); func update(_ s: Snapshot, autoRecord: Bool, isRecording: Bool) -> DetectorEvent?; func noteManualStop() }`, `enum DetectorEvent { case start(appName: String, bundleID: String); case stop }`. Старт — мик держит приложение из списка ≥ startAfter; признак «встреча продолжается» — мик у приложения из списка **или** окно приложения из списка с заголовком по шаблону; stop — признаков нет ≥ stopAfter. Stop выдаётся и при ручной записи, если встреча была распознана; ручная запись без распознанной встречи останавливается только вручную. После `noteManualStop` старт не выдаётся, пока признаки не пропадут полностью.
- `SystemProbe` — снимок раз в 2 с: CoreAudio-процессы с активным вводом (bundle ID; собственный процесс исключён) + заголовки окон через `SCShareableContent`.
- `Recorder` — `start(dir: URL) throws`, `stop() async`; ScreenCaptureKit, звук системы (исключая своё приложение) → `system.caf`, микрофон → `mic.caf`. Нет разрешения → бросает понятную ошибку.
- `MeetingStore` — создание папки и `meta.json`, удаление записи < 15 с, поиск необработанных при запуске (снимает устаревшие `.recording`).
- `ProcessingQueue` — последовательно запускает `<pythonPath> -m transcriber process|resummarize <dir>` (cwd — проект), уведомление по результату.
- `StatusMenu` — значок 🎙 / 🔴 мм:сс / ⏳; пункты: Начать/Остановить запись, Записывать автоматически ✓, Последние встречи ▸, Повторить summary (последняя встреча), Открыть папку транскриптов, Нет доступа: открыть настройки (только когда нет разрешения), Выход. Выход во время записи — корректный stop, встреча в обработку при следующем запуске.
- Уведомления — `UNUserNotificationCenter`; если недоступно — `osascript display notification`.

## Что построили законченные таски
