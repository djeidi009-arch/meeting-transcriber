import DetectorCore
import Foundation
import Observation
import UniformTypeIdentifiers

/// Единственный источник состояния для окна и меню: список встреч, поиск, выбор, запись.
@MainActor @Observable
final class AppModel {
    let store: MeetingStore
    let queue: ProcessingQueue?   // nil в демо: Python не запускается
    let library: MeetingLibrary
    let isDemo: Bool

    var items: [MeetingItem] = []
    /// false до первого чтения папок — чтобы не мигнуть приглашением «встреч нет».
    var isLoaded = false
    var query = "" { didSet { if query != oldValue { search() } } }
    /// Результаты поиска; nil — запрос пуст или первый ответ ещё не пришёл.
    var hits: [SearchHit]?
    var selection: MeetingItem.ID?
    /// Только что загруженная встреча: выбирается, когда появится в списке, — иначе на миг мелькнёт «Выберите встречу».
    @ObservationIgnored private var pendingSelection: MeetingItem.ID?
    /// Таймкод найденного фрагмента: экран встречи ставит на него плеер и сбрасывает в nil.
    var seekRequest: Double?
    var isRecording = false
    var recordingStartedAt: Date?
    /// Громкость микрофона 0…1, последние ~27 с — живая волна на экране записи.
    var recordingLevels: [Float] = []
    /// Файл сейчас держат над окном (в режиме скриншотов ставится вручную).
    var dropTargeted = false
    /// Только что принятый файл: его карточка летит к волне обработки. `origin` — точка броска в координатах окна; nil — от кнопки «Загрузить».
    var importFlight: (id: UUID, name: String, origin: CGPoint?)?
    /// Где в окне стоит волна обработки и волна плеера: между этими местами волна переезжает.
    var waveSlot: CGRect?
    var playerSlot: CGRect?
    /// То же для самих карточек: в финале карточка обработки сжимается в карточку плеера.
    var cardSlot: CGRect?
    var playerCardSlot: CGRect?
    /// Когда встреча перешла на текущий этап — для строки «этот шаг идёт…».
    var stageSince: [MeetingItem.ID: Date] = [:]
    /// Форма звука встреч, уже посчитанная в этом запуске: волна обработки и волна плеера рисуют одно и то же.
    var waveLevels: [MeetingItem.ID: [Float]] = [:]
    /// false — окно не видно или программа неактивна: бесконечные анимации стоят.
    var motionActive = true
    /// Сообщение поверх окна: файл не подошёл.
    var notice: String?
    /// Последний виденный этап встречи: `progress.json` при сбое удаляется, а упавший шаг показать надо.
    var lastStage: [MeetingItem.ID: ProcessingStage] = [:]

    // Ставит StatusMenu (в демо запись подменяет сама модель).
    var toggleRecording: () -> Void = {}
    var chooseFiles: () -> Void = {}
    var openWindow: () -> Void = {}

    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var ticks = 0
    // демо: статусы «в очереди/расшифровывается» вместо настоящей очереди
    @ObservationIgnored var demoStatus: [MeetingItem.ID: MeetingStatus] = [:]
    @ObservationIgnored var demoRecordingDir: URL?
    @ObservationIgnored var demoQueueTail: Task<Void, Never>?
    /// демо: встречи, которым уже синтезирован звук, — экран встречи перезагружает плеер, когда он появился
    var demoAudioReady: Set<MeetingItem.ID> = []

    init(store: MeetingStore, queue: ProcessingQueue?, library: MeetingLibrary, isDemo: Bool) {
        self.store = store
        self.queue = queue
        self.library = library
        self.isDemo = isDemo
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Перечитать папки и снимок очереди. Чтение — не на главном потоке: первый проход разбирает все транскрипты.
    func refresh() {
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        let snapshot = queue?.snapshot() ?? ProcessingQueue.Snapshot(running: nil, pending: [])
        let library = library
        Task.detached {
            let fresh = library.items(queue: snapshot)
            await MainActor.run { self.apply(fresh) }
        }
    }

    private func apply(_ fresh: [MeetingItem]) {
        refreshing = false
        let fresh = fresh.map { item in
            demoStatus[item.id].map { status in
                // демо идёт тем же путём, что и настоящая обработка: этап читается из progress.json в папке
                let status = status == .processing(nil) ? .processing(library.progress(item.dir)) : status
                return MeetingItem(id: item.id, dir: item.dir, title: item.title, app: item.app, startedAt: item.startedAt,
                                   duration: item.duration, status: status, sourceFile: item.sourceFile,
                                   summaryFailed: item.summaryFailed, isTranscribed: item.isTranscribed)
            } ?? item
        }
        for item in fresh {
            guard let stage = item.stage else {
                if stageSince[item.id] != nil { stageSince[item.id] = nil }
                continue
            }
            if lastStage[item.id] != stage || stageSince[item.id] == nil {
                lastStage[item.id] = stage
                stageSince[item.id] = Date()
            }
        }
        if fresh != items {
            items = fresh
            if let pending = pendingSelection, items.contains(where: { $0.id == pending }) {
                selection = pending
                pendingSelection = nil
            }
            if isSearching { search() }
        }
        if !isLoaded {
            isLoaded = true
            if selection == nil { selection = items.first { $0.status == .ready }?.id ?? items.first?.id }
        }
        if refreshAgain { refreshAgain = false; refresh() }
    }

    /// Раз в секунду из StatusMenu: пока окно видно и что-то идёт — обновлять каждую секунду, иначе раз в 5 с.
    func tick(windowVisible: Bool) {
        ticks += 1
        let active = windowVisible && items.contains { $0.status != .ready && !$0.status.isFailed }
        if active || ticks % 5 == 0 { refresh() }
    }

    private func search() {
        searchGeneration += 1
        guard isSearching else { hits = nil; return }
        let generation = searchGeneration, query = query, items = items, library = library
        // поиск читает транскрипты — не на главном потоке; устаревший ответ отбрасывается
        Task.detached {
            let found = library.search(query, in: items)
            await MainActor.run { if generation == self.searchGeneration { self.hits = found } }
        }
    }

    /// Общий путь импорта для меню и окна. Возвращает тексты ошибок по файлам.
    func importFiles(_ urls: [URL], from origin: CGPoint? = nil) -> [String] {
        var errors: [String] = []
        var first: URL?
        for file in urls {
            // папка, документ, картинка: тип — по самому файлу, а если его не прочитать — по расширению
            let type = (try? file.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: file.pathExtension)
            guard let type, type.conforms(to: .audio) || type.conforms(to: .movie) else {
                errors.append("Этот файл не похож на аудио или видео: \(file.lastPathComponent)")
                continue
            }
            do {
                let dir = try store.createImport(file: file)
                if isDemo { simulateProcessing(dir) } else { queue?.enqueue(dir) }
                // открывается первая: она и обрабатывается, остальные ждут в очереди
                if first == nil {
                    first = file
                    pendingSelection = dir.lastPathComponent
                    query = ""
                }
            } catch {
                errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if let first { importFlight = (UUID(), first.lastPathComponent, origin) }
        notice = errors.isEmpty ? nil : errors.joined(separator: "\n")
        refresh()
        return errors
    }

    func retry(_ item: MeetingItem) {
        if isDemo { simulateProcessing(item.dir) } else { queue?.enqueue(item.dir) }
        refresh()
    }

    func resummarize(_ item: MeetingItem) {
        if isDemo { simulateProcessing(item.dir, stages: [.summary]) } else { queue?.enqueue(item.dir, kind: .resummarize) }
        refresh()
    }

    /// Новое значение громкости: от `Recorder.onLevel`, в демо — синтезированное.
    func pushLevel(_ level: Float) {
        recordingLevels.append(level)
        if recordingLevels.count > 540 { recordingLevels.removeFirst(recordingLevels.count - 540) }
    }

    /// Выбрать встречу и открыть окно (уведомления, «Последние встречи»).
    func show(_ dir: URL) {
        selection = dir.lastPathComponent
        query = ""
        refresh()
        openWindow()
    }
}

extension MeetingStatus {
    var isFailed: Bool { if case .failed = self { return true } else { return false } }
}
