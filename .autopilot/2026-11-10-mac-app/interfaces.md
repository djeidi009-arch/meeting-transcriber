# Интерфейсы и правила проекта

Читается первым. Как устроен существующий код — `notes.md` рядом (точные имена и сигнатуры). На что должно быть похоже — `reference.md` и `reference-huddly.png`.

## Правила проекта

### Договорились с пользователем — не пересматривать (из прошлой сборки, дословно)

- Локальная программа в строке меню, а не бот-участник созвона — пользователь согласился
- Автостарт записи при обнаружении встречи, с индикатором и отключаемой галочкой
- Результаты в `~/transcripts`: папка на встречу, Markdown + аудио
- Summary — только `claude -p` по подписке Max: «Можно совсем обойтись без ollama»
- Запись по умолчанию ручная: «Предлагаю сделать запуск не автоматическим, а чтобы я сам запускал его» (2026-10-23)
- Голосовые и диктовка не должны запускать запись: «я записываю голосовые, а также использую программу для надиктовки» — браузерам и мессенджерам нужен ещё и заголовок окна созвона

### Окружение и запреты

- macOS 27.0, Apple Silicon, SDK 26.5, Swift 6.3.2. **Xcode нет** — только Command Line Tools: сборка `swift build`, нет `actool`, нет компилятора `metal`, нет XCTest. Свои `.metal`-шейдеры, asset-каталоги и `resources:` в таргетах **запрещены** — не соберутся или упадут при запуске.
- Весь текст, который видит пользователь, — по-русски. Имена в коде — по-английски. Комментарии — по-русски, коротко, про «почему».
- Сеть: только `claude -p` и первая загрузка моделей HF. Никаких облаков, ботов, аналитики.
- Одна проверка проекта: `make check` (pytest + `swift run selftest`). Она обязана проходить после каждого таска. Тяжёлые модели и `claude` в тестах не вызывать.
- **Личные данные.** В `~/transcripts` — реальные разговоры пользователя. Читать структуру можно; содержание реплик не цитировать в отчётах, коммитах, тестах, скриншотах. Для проверок и скриншотов — только демо-режим (`--demo`, ниже).
- **Установленная копия.** На машине работает `~/Applications/MeetingTranscriber.app` из LaunchAgent `ru.local.meeting-transcriber`. Её не останавливать, не заменять, `make install`/`uninstall` и `launchctl` не запускать — это решение пользователя. Собранное приложение для проверки запускать **только** с `--demo` (не трогает микрофон, очередь и реальные встречи) и с `-ApplePersistenceIgnoreState YES` (иначе после падения висит диалог восстановления окон); после проверки завершать свой процесс по PID, не `pkill -x MeetingTranscriber`.
- В рабочем дереве есть незакоммиченная работа пользователя (пункт меню «Загрузить аудио или видео…», `createImport`, `sourceFile`). Она — основа: не откатывать, не `git stash`, не `git checkout --`. Коммиты делает только оркестратор.
- Стиль кода — навык `ponytail` (уровень full): наименьшее изменение, которое полностью решает таск.

### Команды

| Команда | Что делает |
|---|---|
| `make check` | единственная проверка: `uv run pytest` + `cd app && swift run selftest`. На старте сборки: 50 pytest, 93 проверки Swift — все зелёные |
| `uv run pytest tests/test_pipeline.py` | один файл Python-тестов |
| `cd app && swift run selftest` | только Swift-проверки |
| `cd app && swift build` | быстрая сборка без бандла |
| `make app` | `build/MeetingTranscriber.app` (release + Info.plist + ad-hoc подпись) |
| `build/MeetingTranscriber.app/Contents/MacOS/MeetingTranscriber --demo -ApplePersistenceIgnoreState YES` | запуск для проверки (после таска 02); завершать по своему PID |

Python — только `uv run …` / `.venv/bin/python`, системный `python3` не использовать. Новые зависимости, кроме названных в §5, не добавлять — вернуть `BLOCKED`.

## Раскладка репозитория (после сборки)

```
transcriber/progress.py            новое: запись progress.json
transcriber/userdata.py            новое: чтение user.json
transcriber/pipeline.py, render.py правка: этапы и имена
app/Package.swift                  платформа macOS 26, зависимости DSWaveformImage и Pow
app/Sources/DetectorCore/          + MeetingLibrary.swift, MeetingDocument.swift, DemoLibrary.swift; правка ProcessingQueue.swift
app/Sources/MeetingTranscriber/    main.swift, StatusMenu.swift (правка), AppModel.swift, MainWindow.swift
app/Sources/MeetingTranscriber/UI/ Theme, RootView, MeetingListView, MeetingDetailView, PlayerModel, PlayerBar,
                                   TranscriptView, ImportFlow, ProcessingView, Export, Effects/*
app/Sources/selftest/              + LibraryTests.swift, DocumentTests.swift; правка QueueTests.swift
app/Resources/Info.plist           без LSUIElement, имя «Транскрибатор», иконка
app/Resources/AppIcon.icns         иконка (генерируется scripts/make_icon.swift)
scripts/build_app.sh               копирует иконку в Contents/Resources
docs/screenshots/                  light-*.png, dark-*.png
```

## Границы, решённые в спецификации

### 1. Папка встречи — контракт Swift ↔ Python (расширение, старое не меняется)

Существующие файлы (`meta.json`, `mic.m4a`/`system.m4a` (до обработки `.caf`), `transcript.json`, `meeting.md`, `error.txt`, `.recording`) и их формат **не меняются**. Старые папки без новых файлов обязаны открываться. Добавляются два файла:

**`user.json`** — правки пользователя. Пишет только Swift (атомарно), Python только читает. Отсутствует, пока ничего не переименовано.

```json
{ "title": "Планёрка по релизу", "speakers": { "Спикер 1": "Аня", "Я": "Никита" } }
```

- `title` — название встречи; нет ключа или пустая строка → берётся `meta.app`.
- `speakers` — метка из `transcript.json` → имя. Метки в `transcript.json` **никогда не переписываются**; имя накладывается при показе, экспорте и в `meeting.md`.
- Папка при переименовании не переименовывается.

**`progress.json`** — этап обработки. Пишет только Python (атомарно), Swift только читает. Существует только пока идёт `process`/`resummarize`; удаляется и при успехе, и при ошибке (`finally`).

```json
{ "stage": "asr", "fraction": 0.5, "updatedAt": "2026-11-10T19:30:00+07:00" }
```

- `stage` ∈ `extract` → `asr` → `diarize` → `summary`, строго в этом порядке, назад не идёт. `resummarize` пишет только `summary`.
- `extract` — с начала обработки до первого вызова `asr` (извлечение звука из файла и приведение дорожек); `asr` — распознавание всех дорожек; `diarize` — диаризация и склейка; `summary` — от вызова `_summarize` до записи `meeting.md`.
- `fraction` — доля внутри этапа `0…1` или `null`, если неизвестна. Обязателен только ключ `stage`.
- Подписи этапов в интерфейсе (одни и те же везде): «Извлечение звука», «Распознавание речи», «Спикеры», «Summary».

### 2. Python — `transcriber/`

- `transcriber/progress.py`: `write(meeting_dir: Path, stage: str, fraction: float | None = None) -> None` (атомарно), `clear(meeting_dir: Path) -> None`. Константы `EXTRACT, ASR, DIARIZE, SUMMARY`.
- `transcriber/userdata.py`: `load(meeting_dir: Path) -> UserData` (`title: str | None`, `speakers: dict[str, str]`; нет файла или битый JSON → пустой, без исключения); `UserData.name(label: str) -> str`.
- `pipeline._process` и `resummarize` вызывают `progress.write` на границах этапов; сигнатуры `asr`/`diarize`/`summarize` и тестовые фейки **не меняются**.
- `render.render_markdown` и текст, уходящий в summary, применяют `user.json`: заголовок — `title`, метки спикеров — имена. `transcript.json` остаётся с исходными метками.
- Коды выхода прежние (0 / 1 / 2). Заодно: `resummarize` при сбое summary выходит с кодом **2**, а не 1 (как `process`) — иначе окно не отличит «нет summary» от «ошибка».

### 3. Swift — `DetectorCore` (только Foundation; всё, что тестирует selftest, живёт здесь)

`ProcessingQueue` — добавить, ничего не ломая:

```swift
public struct Snapshot: Equatable { public let running: Job?; public let pending: [Job] }
public func snapshot() -> Snapshot
// новый параметр init, последним перед onFinish, со значением по умолчанию:
onChange: @escaping () -> Void = {}   // вызывается с фоновой очереди при любом изменении running/pending
```

`MeetingStore` — сделать `public`: `readMeta(_:)`, `parseISO`, `iso`, и новый `public func allMeetings() -> [URL]` (то, что сейчас `private meetingDirs()`).

`MeetingLibrary.swift` — чтение встреч для окна:

```swift
public enum ProcessingStage: String, CaseIterable, Sendable { case extract, asr, diarize, summary
    public var title: String }                      // «Извлечение звука» …
public struct ProgressInfo: Equatable, Sendable { public let stage: ProcessingStage; public let fraction: Double? }
public enum MeetingStatus: Equatable, Sendable {
    case recording, queued, processing(ProgressInfo?), ready, failed(String)
    public var title: String }                      // «Идёт запись» · «В очереди» · «Расшифровывается» · «Готово» · «Ошибка»
public struct MeetingItem: Identifiable, Equatable, Sendable {
    public let id: String            // имя папки
    public let dir: URL
    public let title: String         // user.json.title ?? meta.app
    public let app: String
    public let startedAt: Date?
    public let duration: TimeInterval?   // transcript.duration ?? (endedAt - startedAt)
    public let status: MeetingStatus
    public let sourceFile: URL?      // meta.sourceFile
    public let summaryFailed: Bool   // meeting.md есть, но summary «не удалось сделать»
}
public struct Utterance: Equatable, Sendable { public let start, end: Double; public let speaker: String; public let text: String }
public struct Transcript: Equatable, Sendable { public let utterances: [Utterance]; public let duration: Double }
public struct UserData: Codable, Equatable, Sendable { public var title: String?; public var speakers: [String: String]
    public func name(for label: String) -> String }
public struct DaySection: Identifiable, Equatable { public let id: String; public let title: String; public let items: [MeetingItem] }

public final class MeetingLibrary {
    public init(store: MeetingStore)
    public func items(queue: ProcessingQueue.Snapshot) -> [MeetingItem]      // новые первыми
    public func transcript(_ dir: URL) -> Transcript?
    public func summaryMarkdown(_ dir: URL) -> String?    // между «## Summary» и «## Транскрипт» в meeting.md
    public func userData(_ dir: URL) -> UserData
    public func setTitle(_ title: String, for dir: URL) throws
    public func setSpeakerName(_ name: String, label: String, for dir: URL) throws   // пустое имя → вернуть метку
    public func progress(_ dir: URL) -> ProgressInfo?
    public static func sections(_ items: [MeetingItem], now: Date, calendar: Calendar) -> [DaySection]  // «Сегодня», «Вчера», «5 ноября», «5 ноября 2025»
    public func search(_ query: String, in items: [MeetingItem]) -> [SearchHit]
}
public struct SearchHit: Equatable { public let item: MeetingItem; public let inTitle: Bool
    public let snippets: [Snippet] }                     // до 3 фрагментов текста с таймкодом
public struct Snippet: Equatable { public let start: Double; public let text: String }
```

Правило статуса (в этом порядке): есть `.recording` → `recording`; папка в `snapshot.running` → `processing(progress(dir))`; в `snapshot.pending` → `queued`; есть `meeting.md` → `ready`; есть `error.txt` → `failed(первая строка)`; иначе → `queued`.

Поиск: без учёта регистра и «ё/е», по `title` и по тексту реплик из `transcript.json`; пустой запрос → все встречи без фрагментов.

`MeetingDocument.swift` — одна модель для экрана и экспорта:

```swift
public struct MeetingDocument: Equatable {
    public let title: String; public let startedAt: Date?; public let duration: TimeInterval?
    public let summaryMarkdown: String?
    public let lines: [Line]                       // имя спикера уже подставлено
    public struct Line: Equatable { public let start: Double; public let speakerLabel: String; public let speakerName: String; public let text: String }
    public init(item: MeetingItem, transcript: Transcript?, summaryMarkdown: String?, user: UserData)
    public func markdown() -> String               // тот же формат, что meeting.md
    public func plainText() -> String              // для «Копировать текст»
    public static func timecode(_ seconds: Double) -> String   // «чч:мм:сс»
    public func speakerShares() -> [(label: String, name: String, share: Double)]
}
```

`DemoLibrary.swift`: `public enum DemoLibrary { public static func create(at dir: URL) throws }` — пишет в пустую папку 6–8 выдуманных встреч в настоящем формате (разные дни, приложения, длительности; готовые, одна с ошибкой, одна без summary) с выдуманным русским текстом о вымышленном продукте. Аудио в DetectorCore не создаётся — его делает приложение.

Швы тестов (selftest): `MeetingLibrary` на временной папке (статусы, секции по дням, поиск, `user.json`, `progress.json`), `MeetingDocument` (markdown, имена, доли), `ProcessingQueue.snapshot/onChange`, `DemoLibrary` (создаётся и читается). Python: `progress`, `userdata`, применение имён в `render` — pytest с существующими фейками.

### 4. Swift — приложение `MeetingTranscriber`

- **Запуск.** Остаётся `main.swift` + `NSApplication` + делегат `StatusMenu` (не `@main App`). Политика активации всегда `.regular`; `LSUIElement` из Info.plist убрать. Закрытие окна не завершает программу; клик по значку в Dock (`applicationShouldHandleReopen`) и пункт меню «Открыть Транскрибатор» открывают окно. При запуске окно открывается, если нет аргумента `--background` (его добавит LaunchAgent в `install.sh`).
- **Имя.** `CFBundleDisplayName` и `CFBundleName` — «Транскрибатор». Идентификатор `ru.local.meeting-transcriber`, исполняемый файл `MeetingTranscriber`, имя бандла `MeetingTranscriber.app`, пути логов — **не менять** (на них завязаны разрешения, LaunchAgent и скрипты).
- **`AppModel`** (`@MainActor @Observable final class`, `AppModel.swift`) — единственный источник состояния для окна и меню:

```swift
init(store: MeetingStore, queue: ProcessingQueue?, library: MeetingLibrary, isDemo: Bool)
var items: [MeetingItem]              // обновляет refresh()
var query: String
var selection: MeetingItem.ID?
var isRecording: Bool; var recordingStartedAt: Date?
var toggleRecording: () -> Void       // ставит StatusMenu
func refresh()                        // перечитать папки + snapshot очереди
func importFiles(_ urls: [URL]) -> [String]   // createImport + enqueue; возвращает тексты ошибок
func retry(_ item: MeetingItem)       // enqueue(.process)
func resummarize(_ item: MeetingItem) // enqueue(.resummarize)
func show(_ dir: URL)                 // выбрать встречу и открыть окно (уведомления, меню)
```

  `StatusMenu` создаёт `AppModel` в `applicationDidFinishLaunching`, зовёт `model.refresh()` при старте/остановке записи и из `onChange`/`onFinish` очереди (перенеся на main). Пока окно видно и есть `recording`/`queued`/`processing` — `refresh()` раз в секунду; иначе раз в 5 с. Импорт из меню и из окна идёт через один `importFiles`.
- **Окно.** `MainWindow.swift`: `NSWindow` + `NSHostingView(rootView: RootView().environment(model))`, минимальный размер 980×640, запоминает положение (`setFrameAutosaveName`).
- **Плеер.** `PlayerModel` (`@MainActor @Observable`): `load(item:)`, `play()/pause()/toggle()`, `seek(to:)`, `currentTime`, `duration`, `isPlaying`, `hasVideo`, `player: AVPlayer`. Источник: если `sourceFile` существует и в нём есть видеодорожка — он (с `VideoPlayer`); иначе `mic.m4a` + `system.m4a` одной `AVMutableComposition` (слышны обе стороны), при одной дорожке — она одна. Колбэк времени: `queue: .main` + `MainActor.assumeIsolated`.
- **Громкость записи.** `Recorder` получает `var onLevel: ((Float) -> Void)?` — уровень микрофона 0…1, не чаще 20 раз в секунду, с любой очереди; `StatusMenu` переносит на main в `AppModel.recordingLevels: [Float]` (последние ~120 значений) для живой волны. В демо уровень синтезируется.
- **Демо-режим** `--demo`: `outputDir` — временная папка с `DemoLibrary.create`, `queue == nil`, рекордер, детектор, запрос разрешений и `recoverPending` не запускаются, реальные встречи не читаются. Аудио для демо-встреч приложение синтезирует (тон/шум в WAV → `afconvert` в `system.m4a`). `importFiles` в демо не зовёт Python: проигрывает этапы по ~3 с каждый и завершает встречу готовым выдуманным транскриптом. Одна демо-встреча всегда «расшифровывается» по кругу — чтобы экран обработки можно было показать и снять.
- **Скриншоты** `--demo --screenshots <папка>`: открывает окно, по очереди в светлой и тёмной теме снимает экраны «список + встреча», «обработка», «перетаскивание» в `light-*.png` / `dark-*.png` и выходит с кодом 0.

### 5. Сборка и зависимости (проверено пробной сборкой)

- `app/Package.swift`: `swift-tools-version:6.0` остаётся; `platforms: [.macOS("26.0")]` (строкой — `.v26` требует tools 6.2); `swiftLanguageModes: [.v5]` остаётся. `LSMinimumSystemVersion` → 26.0. Проверки `#available` для Liquid Glass не нужны.
- Таргету `MeetingTranscriber` добавить `linkerSettings: .linkedFramework("AVKit")` и `"SwiftUI"` — **без AVKit `VideoPlayer` падает при первом показе**.
- Зависимости (только эти две):
  - `https://github.com/dmrschmidt/DSWaveformImage` from `14.5.0` — продукты `DSWaveformImage`, `DSWaveformImageViews`: `WaveformAnalyzer().samples(fromAudioAt:count:)` для волны.
  - `https://github.com/EmergeTools/Pow` from `1.0.6` — `.changeEffect(.shine/.jump/.spray)`, `.conditionalEffect(.pushDown)`, `.transition(.movingParts.pop/.blur/...)`. **Нельзя**: `.movingParts.poof`, `.anvil`, `SmokeEffect` — им нужны картинки из asset-каталога, без `actool` это падение.
- Не подключать: Vortex (не собирается без Xcode), Inferno (нет шейдеров), Lottie/Rive (нет иллюстраций). Частицы и фоны — свои: `Canvas` + `TimelineView(.animation)`, `MeshGradient`, `PhaseAnimator`, `KeyframeAnimator`, `symbolEffect`.
- Ресурсные бандлы SwiftPM в `.app` не копировать и `Bundle.module` не использовать. Свои файлы (иконка) кладёт `build_app.sh` в `Contents/Resources`, читать через `Bundle.main`.
- Liquid Glass: `.glassEffect(...)`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`, `.backgroundExtensionEffect()` — компилируются. Стекло — для панелей управления (плеер, тулбар, плавающие кнопки), не для содержимого.
- Экспорт: DOCX — `NSAttributedString.data(from:documentAttributes: [.documentType: .officeOpenXML])`; PDF — постранично через CoreText (`CTFramesetter`, A4 595×842, поля 56). `dataWithPDF` не использовать (одна длинная страница).

### 6. Облик (общие токены — `UI/Theme.swift`, владелец — таск оболочки)

- Один акцент — лайм (`#D4F25A` светлая тема, тот же на тёмной), текст на акценте — графит. Остальное — системные цвета, чтобы обе темы работали сами.
- Карточки: скругление 18, фон `.background.secondary`-подобный, без рамок; пилюли-капсулы для статусов и метаданных; шрифт системный, крупные заголовки.
- Цвет спикера: стабильный по метке, из палитры 6 цветов; «Я» — всегда акцентный графит/лайм.
- Все анимации уважают «Уменьшение движения» (`accessibilityReduceMotion`) — заменяются на проявление.

## Что построили законченные таски

<!-- дописывается по мере сборки -->

### T01 — данные для окна (сделано)

- Python: `progress.write(meeting_dir, stage, fraction=None)`, `progress.clear(meeting_dir)`, константы `EXTRACT/ASR/DIARIZE/SUMMARY`; `userdata.load(dir) -> UserData(title, speakers)`, `UserData.name(label)`; `render_markdown(..., user=UserData())`, `transcript_text(utterances, user=UserData())`; `pipeline.resummarize(...) -> str | None` — возвращает причину сбоя summary (CLI → код 2), исключение не бросает.
- `progress.json`: в этапе `asr` `fraction` = номер дорожки / число дорожек (0, 0.5), в остальных `null`. Если Python убит сигналом, файл остаётся — читать его только у идущего задания.
- Swift `DetectorCore`: всё из §3 с теми же сигнатурами. Сверх того: публичные `init` у `ProcessingQueue.Job(dir:kind:)`, `Snapshot(running:pending:)`, `MeetingItem`, `ProgressInfo`, `Utterance`, `Transcript`, `UserData(title:speakers:)`, `MeetingDocument.Line`; `Utterance`/`Transcript` — `Codable`; `MeetingDocument.durationText(_:) -> String` («1 ч 5 мин»); секция встреч без даты называется «Без даты».
- **Потоки.** `ProcessingQueue.onChange` при постановке вызывается с потока, вызвавшего `enqueue`, при старте и завершении — с фоновой очереди: переносить на main в обоих случаях. `MeetingLibrary.search` синхронный и читает транскрипты — **с главного потока не звать** (выносить в `Task.detached`, результат на main). Первый `items()` разбирает все `transcript.json` (дальше кеш по времени изменения) — первый вызов тоже не на главном потоке.
- `summaryMarkdown(dir)` возвращает `nil` и при сбое summary, и когда summary нет; сбой отличать по `item.summaryFailed`.
- Проверки после таска: 62 pytest, 192 проверки Swift.
- Ремонт по ревью: в `transcript.json` ключ `duration` необязателен (старый формат) — без него длительность равна концу последней реплики. `ProcessingQueue` удаляет старый `progress.json` в папке задания до того, как оно становится `running` (до `onChange` о старте) — этап из прошлого запуска не показывается. Проверок Swift: 199.

### T02 — приложение с окном (сделано)

- Файлы: `AppModel.swift`, `Demo.swift`, `MainWindow.swift`, `UI/Theme.swift`, `UI/RootView.swift`, `UI/MeetingListView.swift`, `UI/MeetingDetailView.swift` (сейчас — простая карточка-заглушка: её заменяет таск 03); `scripts/make_icon.swift` → `app/Resources/AppIcon.icns`.
- `AppModel` как в §4, сверх того: `isLoaded: Bool`, `hits: [SearchHit]?` (nil — запрос пуст), `isSearching: Bool`, `seekRequest: Double?` (таймкод найденного фрагмента: экран встречи ставит плеер и сбрасывает в nil), `chooseFiles: () -> Void` (панель выбора файлов), `openWindow: () -> Void`, `tick(windowVisible:)`.
- Демо: `AppModel.demoDir() throws -> URL`, `startDemo()`, `simulateProcessing(_ dir:, stages:, loop:)`; статусы демо подменяются через `demoStatus[id]`, `progress.json` в демо не пишется. Звука у демо-встреч пока нет.
- `MainWindow(model:)`, `.window`, `.show()`; `MainMenu.build(target:)`; `StatusMenu.showWindow()`, `StatusMenu.importClicked()`.
- `Notifier.onOpen: ((URL) -> Void)?`; параметр `open:` у `notify` — папка встречи, а не `meeting.md`.
- `Theme`: `accent`, `onAccent`, `page`, `card`, `cardRadius`, `speakerColor(_:)`; `View.card(padding:)`, `Pill(text:systemImage:tone:)`, `StatusPill(item:)`, `AccentButtonStyle`; расширения `MeetingItem.timeText/dateText/durationText/stage/errorText`, `MeetingStatus.isFailed`.
- Перетаскивания файлов, `Recorder.onLevel`, `--screenshots` ещё нет (таск 04). Pow подключён и используется (блик на пилюле), DSWaveformImage только подключён.
- Как исполнитель проверял облик: запуск `.app --demo`, снимок своего окна по его номеру из CGWindowList (скрипты-образцы: scratchpad `t02/shot.sh`, `t02/winlist.swift`). Демо делит UserDefaults с установленной копией (тот же bundle id) — новые ключи заводить с префиксом `window.`.

### T03 — экран встречи (сделано)

- Файлы: `UI/MeetingDetailView.swift`, `UI/PlayerModel.swift`, `UI/PlayerBar.swift`, `UI/TranscriptView.swift`, `UI/Export.swift`.
- `DetectorCore`: `MeetingDocument.shortTimecode(_:) -> String` («мм:сс», от часа «ч:мм:сс»), `lineIndex(at:) -> Int?`, `enum SummaryBlock { heading, bullet, paragraph }`, `summaryBlocks() -> [SummaryBlock]`.
- Приложение: `PlayerModel` (`load(item:) async`, `stop/play/pause/toggle`, `seek(to:)`, `currentTime`, `duration`, `isPlaying`, `hasVideo`, `hasMedia`, `isLoaded`, `missingVideo`, `rate`, `levels`, `currentLine`, `document`, `player`); `PlayerBar(player:)`; `MeetingHeader(item:document:)`; `EditableText`, `SpeakerAvatar`, `SpeakersCard`, `SummaryCard`, `TranscriptCard` (+ `lineID(_:)`); `Export.Format`, `Export.data(_:as:)`, `save`, `copy`, `alert`, `attributed`, `pdf`; `Theme.accentInk`; `AppModel.demoAudioReady: Set<MeetingItem.ID>` (звук демо-встреч синтезируется).
- Экран встречи сейчас показывает готовую встречу; для статусов «идёт запись», «в очереди», «расшифровывается», «ошибка» — простая карточка. Экран обработки, живая волна записи, каскадное появление реплик и частицы — таск 04.
- Проверок Swift: 206. Снимки-образцы экрана: scratchpad `t03/*.png`.

### T04 — загрузка, обработка, анимации, скриншоты (сделано)

- Файлы: `Screenshots.swift`, `UI/ImportFlow.swift`, `UI/ProcessingView.swift`, `UI/Effects/{Aurora,PulseWave,ParticleBurst,CascadeIn}.swift`; `docs/screenshots/{light,dark}-{meeting,processing,recording,drop}.png`.
- `AppModel`: `recordingLevels: [Float]` (до 540 значений), `pushLevel(_:)`, `dropTargeted`, `importFlight: (id: UUID, name: String)?`, `notice: String?`, `lastStage: [ID: ProcessingStage]`, `demoQueueTail`. `importFiles` сам отсеивает не-медиа, выбирает первую принятую встречу, ставит `importFlight` и `notice`.
- `Recorder.onLevel: ((Float) -> Void)?`; `Screenshots.run(model:window:into:) async -> Int32`; `MeetingStateView(item:)`; `View.importFlow()`, `View.cascadeIn(order:active:)`; `Aurora`, `PulseWave(energy:tint:)`, `ParticleBurst`; `ProcessingStage.symbol/explanation`; `TranscriptCard(cascade:)`.
- Демо пишет `progress.json` в формате Python и ведёт встречи по одной, как очередь.
- `--screenshots` снимает окно системным `screencapture` — нужен доступ «Запись экрана» у программы, из которой запускают; без него выходит с кодом 1.
- Упавший шаг обработки помнится только в памяти программы: после перезапуска ошибка показывается без отмеченного шага.

### F1 — правки по код-ревью (сделано)

- `MeetingItem.isTranscribed: Bool` (есть `meeting.md`); экран встречи выбирается по нему, а не по `status == .ready` — при повторе summary транскрипт остаётся.
- `ProcessingQueue` при `.failure` сама пишет `error.txt` с текстом из `Outcome`, если Python свежего не написал (при `cancelAll` — нет).
- `SummaryCard(document:failed:status:retry:)`. Видео — панелью над прокруткой, на ширину основной колонки.
- Проверок Swift: 216.
