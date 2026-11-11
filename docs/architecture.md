# Архитектура

Почему так решено — `docs/adr/`. Что значат слова — `CONTEXT.md`.

## Поток данных

```
запись (Recorder) ─┐
                   ├─> папка встречи ─> ProcessingQueue ─> python -m transcriber ─> meeting.md
загрузка файла ────┘   (MeetingStore)   (по одной)           (pipeline.py)            transcript.json
(createImport)                                                     │
                                                                   └─> progress.json ─> MeetingLibrary ─> AppModel ─> окно
```

1. Запись: `StatusMenu` → `Recorder` пишет `mic.caf` и `system.caf`; `MeetingStore.createMeeting` ставит `.recording`, `finishMeeting` снимает (короче 15 с — папка удаляется).
2. Загрузка: `AppModel.importFiles` → `MeetingStore.createImport` (`meta.json` с `sourceFile`, без `.recording`); звук достаёт Python.
3. `ProcessingQueue.enqueue` — одно задание за раз; запускает `python -m transcriber process|resummarize <папка>` дочерним процессом, пишет `processing.log`.
4. Python: `extract` (ffmpeg → wav 16 кГц, `.caf` → `.m4a`) → `asr` (`vad.py` режет на участки ≤ 28 с) → `diarize` (только дорожка `system`) → склейка (`merge.py`) → `transcript.json` → summary (`claude -p`) → `meeting.md`.
5. `progress.json` пишется на границах этапов. `AppModel.refresh()` перечитывает папки и `queue.snapshot()` через `MeetingLibrary.items` и обновляет `items`; окно (SwiftUI) читает `AppModel`.
6. Частота `refresh()`: из `StatusMenu` раз в секунду по таймеру, `tick` обновляет каждую секунду пока окно видно и есть незавершённые встречи, иначе раз в 5 с; плюс при старте и остановке записи, из `onChange` и `onFinish` очереди.

## Границы модулей

| Модуль | Что внутри | Правило |
|---|---|---|
| `transcriber/` (Python) | `pipeline`, `merge`, `vad`, `asr`, `diarize`, `summary`, `render`, `audio`, `progress`, `userdata`, `config` | Читает `meta.json`, `user.json`; пишет `transcript.json`, `meeting.md`, `error.txt`, `progress.json`, `*.m4a`. Тесты — `tests/`, с фейками вместо `asr`/`diarize`/`summarize` |
| `DetectorCore` (Swift) | `MeetingDetector`, `MeetingStore`, `MeetingLibrary`, `MeetingDocument`, `DemoLibrary`, `ProcessingQueue`, `TrackAligner`, `AppConfig` | Только Foundation. Всё, что нужно проверить, живёт здесь |
| `MeetingTranscriber` (Swift) | `main.swift`, `StatusMenu` (делегат), `AppModel`, `MainWindow`, `Recorder`, `SystemProbe`, `Notifier`, `Demo`, `Screenshots`, `UI/*` | AppKit, SwiftUI, CoreAudio, ScreenCaptureKit, AVKit. Не тестируется `selftest`-ом |
| `selftest` | `XxxTests.all()`, вызовы в конце `selftest/main.swift` | Замена XCTest. Зависит только от `DetectorCore` |

- `AppModel` (`@MainActor @Observable`) — единственный источник состояния для окна и меню; создаётся в `StatusMenu.applicationDidFinishLaunching`.
- `transcriber/config.py` и `DetectorCore/AppConfig.swift` — две реализации одного `config.json`.
- Запуск: `main.swift` + `NSApplication` + делегат `StatusMenu` (не `@main App`); активация `.regular`; закрытие окна не завершает программу; без `--background` окно открывается при старте.
- Окно: `MainWindow` — `NSWindow` + `NSHostingView(RootView)`, минимум 980×640, положение запоминается (`MainWindow`).
- Плеер (`UI/PlayerModel`): `sourceFile`, если он существует и с видео; иначе `mic.m4a` + `system.m4a` одной композицией.

## Контракт папки встречи

`<outputDir>/<ГГГГ-ММ-ДД ЧЧ-ММ> <Приложение>[ (n)]/`. Новые файлы старые папки не ломают: старые открываются без них.

| Файл | Пишет | Читает | Заметки |
|---|---|---|---|
| `meta.json` | Swift (`MeetingStore`, атомарно) | Swift, Python | `app`, `bundleId`, `startedAt`, `endedAt` (null пока идёт), `manual`, `sourceFile` (только у загрузки) |
| `.recording` | Swift | Swift, Python | Маркер «запись идёт»; Python отказывается обрабатывать |
| `mic.caf`, `system.caf` | Swift (`Recorder`) | Python | После обработки удаляются, если есть `.m4a` или файл пуст (только заголовок) |
| `mic.m4a`, `system.m4a` | Python (`audio.to_m4a`) | Swift (плеер), Python | У загрузки — только `system.m4a` из `sourceFile` |
| `transcript.json` | Python | Swift, Python (`resummarize`) | `utterances[]` (`start`, `end`, `speaker`, `text`), `duration` (в старых нет). Метки спикеров не переписываются |
| `meeting.md` | Python | Swift | Summary между `## Summary` и `## Транскрипт`; есть файл — встреча обработана |
| `error.txt` | Python; `ProcessingQueue`, если Python не успел | Swift | Первая строка — текст ошибки; удаляется при новой попытке |
| `user.json` | только Swift (`MeetingLibrary`, атомарно) | Python, Swift | `{"title": ..., "speakers": {метка: имя}}`; нет файла, пока ничего не правили. Имя накладывается при показе, экспорте и в `meeting.md` |
| `progress.json` | только Python (`progress.py`, атомарно) | Swift | `{"stage", "fraction", "updatedAt"}`; живёт, пока идёт `process`/`resummarize`; `finally` удаляет |

`progress.json`:
- `stage`: `extract` → `asr` → `diarize` → `summary`, назад не идёт; `resummarize` пишет только `summary`. Подписи: «Извлечение звука», «Распознавание речи», «Спикеры», «Summary».
- `fraction`: `0…1` или `null`; в `asr` это номер дорожки / число дорожек.
- Если Python убит сигналом, файл остаётся: `ProcessingQueue` удаляет его до старта задания, читать его надо только у идущего задания.

Код выхода `python -m transcriber`: 0 — ок, 1 — сбой, 2 — транскрипт готов, сбой только summary (`ProcessingQueue.exitSummaryFailed`, оба варианта: `process` и `resummarize`).

## Статус встречи

`MeetingLibrary.items` вычисляет по порядку, первое совпавшее:

1. есть `.recording` → `recording`
2. папка в `snapshot.running` → `processing(progress.json)`
3. папка в `snapshot.pending` → `queued`
4. есть `meeting.md` → `ready`
5. есть `error.txt` → `failed(первая строка)`
6. иначе → `queued`

- `summaryFailed` — `meeting.md` есть, но summary «не удалось сделать»; `summaryMarkdown` тогда `nil`.
- Экран встречи выбирается по `item.isTranscribed` (есть `meeting.md`), а не по `status == .ready`: при повторе summary транскрипт остаётся.
- Название — `user.json.title`, иначе `meta.app`. Длительность — `transcript.duration`, иначе конец последней реплики, иначе `endedAt − startedAt`.

## Соглашения

- Тестируется:
  - `DetectorCore` — `selftest` на временных папках; сюда же класть новую логику.
  - Python — `pytest` с фейками, тяжёлые модели и `claude` не вызываются.
  - `MeetingTranscriber` (UI, `Recorder`, `StatusMenu`) — автотестов нет; проверка — `--demo` глазами или `--demo --screenshots`.
- Потоки:
  - `ProcessingQueue.onChange` при `enqueue` приходит с потока вызывающего, при старте и завершении — с фоновой очереди; на main переносить во всех случаях.
  - `MeetingLibrary.search` и первый `items()` читают все `transcript.json` — не с главного потока (`Task.detached`, результат на main).
  - `PlayerModel`: колбэк времени `queue: .main` + `MainActor.assumeIsolated`.
- Сборка без Xcode (только Command Line Tools):
  - Нет `actool`, `metal`, XCTest: `resources:`, asset-каталоги, `.metal`, `Bundle.module` запрещены; файлы в `.app` кладёт `scripts/build_app.sh`, читать через `Bundle.main`.
  - Из зависимостей — только DSWaveformImage и Pow; Vortex и Inferno не собираются; из Pow нельзя `.poof`, `.anvil`, `SmokeEffect`.
  - `platforms: [.macOS("26.0")]` строкой (`.v26` требует tools 6.2); `linkedFramework("AVKit")` обязателен, иначе `VideoPlayer` падает при показе.
  - Идентификатор `ru.local.meeting-transcriber`, исполняемый файл `MeetingTranscriber`, имя `MeetingTranscriber.app`, пути логов не менять: на них завязаны разрешения, LaunchAgent и скрипты. Показываемое имя — «Транскрибатор».
- Демо-режим `--demo`:
  - `outputDir` — `$TMPDIR/transcriber-demo-<pid>` с `DemoLibrary.create`; очереди (`queue == nil`), рекордера, детектора, запроса разрешений и `recoverPending` нет, реальные встречи не читаются.
  - Звук демо-встреч приложение синтезирует (WAV → `afconvert` → `system.m4a`). `importFiles` не зовёт Python: проигрывает этапы по ~3 с и пишет `progress.json` в формате Python. Одна встреча «расшифровывается» по кругу.
  - `--demo --screenshots <папка>`: 8 PNG (`light-*`, `dark-*`) и выход; снимает системный `screencapture`, нужен доступ «Запись экрана» у запускающей программы, без него код 1. `--screenshots` без `--demo` — отказ.
- UI: токены — `UI/Theme.swift` (один акцент лайм); анимации уважают «Уменьшение движения». На экране обработки — живая форма `UI/Effects/Orb.swift` (облик этапа — `OrbLook`); в финале карточка обработки сжимается в карточку плеера, форма сплющивается в линию, из которой вырастает волна плеера `UI/Effects/WaveBars.swift`. Места карточек и волны — `AppModel.cardSlot`/`playerCardSlot`/`waveSlot`/`playerSlot`, форма звука — `AppModel.waveLevels`. Чистая логика (`WaveSource`, `WaveFlight`) — в `DetectorCore/WaveMotion.swift`. Бесконечные циклы — не чаще 30 кадров/с и только при `AppModel.motionActive` (окно на виду, программа активна).
- Весь текст пользователю — по-русски; имена в коде — по-английски; комментарии — по-русски, коротко, про «почему».
