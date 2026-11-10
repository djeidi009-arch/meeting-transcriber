import DetectorCore
import Foundation
import Observation

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
    /// Таймкод найденного фрагмента: экран встречи ставит на него плеер и сбрасывает в nil.
    var seekRequest: Double?
    var isRecording = false
    var recordingStartedAt: Date?

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
            demoStatus[item.id].map {
                MeetingItem(id: item.id, dir: item.dir, title: item.title, app: item.app, startedAt: item.startedAt,
                            duration: item.duration, status: $0, sourceFile: item.sourceFile, summaryFailed: item.summaryFailed)
            } ?? item
        }
        if fresh != items {
            items = fresh
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
    func importFiles(_ urls: [URL]) -> [String] {
        var errors: [String] = []
        for file in urls {
            do {
                let dir = try store.createImport(file: file)
                if isDemo { simulateProcessing(dir) } else { queue?.enqueue(dir) }
                selection = dir.lastPathComponent
            } catch {
                errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
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
