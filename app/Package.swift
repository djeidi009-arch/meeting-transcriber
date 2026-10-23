// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeetingTranscriber",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DetectorCore", targets: ["DetectorCore"]),
        .executable(name: "MeetingTranscriber", targets: ["MeetingTranscriber"]),
        .executable(name: "selftest", targets: ["selftest"]),
    ],
    targets: [
        // Чистая логика без AppKit/CoreAudio: детектор, папка встречи, настройки, очередь.
        .target(name: "DetectorCore"),
        .executableTarget(
            name: "MeetingTranscriber",
            dependencies: ["DetectorCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(name: "selftest", dependencies: ["DetectorCore"]),
    ],
    swiftLanguageModes: [.v5]
)
