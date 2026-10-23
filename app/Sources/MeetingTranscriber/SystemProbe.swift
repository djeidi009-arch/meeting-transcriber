import AppKit
import CoreAudio
import CoreGraphics
import DetectorCore
import ScreenCaptureKit

/// Процесс, у которого CoreAudio видит активный ввод с микрофона.
struct MicProcess {
    let pid: pid_t
    let bundleID: String
    let name: String
}

/// Снимок системы для детектора: процессы с активным вводом (CoreAudio) + заголовки окон (ScreenCaptureKit).
final class SystemProbe {
    private let ownPID = getpid()

    func snapshot() async -> Snapshot {
        let mic = micProcesses().map(\.bundleID).filter { !$0.isEmpty }
        let windows = await windowTitles()
        return Snapshot(micBundleIDs: mic, windows: windows, time: ProcessInfo.processInfo.systemUptime)
    }

    /// Все процессы с активным вводом, кроме собственного.
    func micProcesses() -> [MicProcess] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        var result: [MicProcess] = []
        for id in ids {
            guard let running: UInt32 = readScalar(id, kAudioProcessPropertyIsRunningInput), running != 0 else { continue }
            let pid: pid_t = readScalar(id, kAudioProcessPropertyPID) ?? -1
            if pid == ownPID { continue }
            var bundle = readString(id, kAudioProcessPropertyBundleID) ?? ""
            let app = pid > 0 ? NSRunningApplication(processIdentifier: pid) : nil
            if bundle.isEmpty { bundle = app?.bundleIdentifier ?? "" }
            let name = app?.localizedName ?? processName(pid)
            result.append(MicProcess(pid: pid, bundleID: bundle, name: name))
        }
        return result
    }

    /// Заголовки окон. Без разрешения на запись экрана — пусто (и без системного запроса каждые 2 с).
    func windowTitles() async -> [(bundleID: String, title: String)] {
        guard CGPreflightScreenCaptureAccess() else { return [] }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            return content.windows.compactMap { w in
                guard let title = w.title, !title.isEmpty, let bundle = w.owningApplication?.bundleIdentifier else { return nil }
                return (bundle, title)
            }
        } catch {
            return []
        }
    }

    private func readScalar<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr) == noErr else { return nil }
        return ptr.pointee
    }

    private func readString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func processName(_ pid: pid_t) -> String {
        guard pid > 0 else { return "?" }
        var buf = [CChar](repeating: 0, count: 1024)
        return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "pid \(pid)"
    }
}
