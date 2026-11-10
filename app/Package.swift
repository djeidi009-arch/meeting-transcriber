// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeetingTranscriber",
    platforms: [.macOS("26.0")], // строкой: `.v26` требует tools 6.2
    products: [
        .library(name: "DetectorCore", targets: ["DetectorCore"]),
        .executable(name: "MeetingTranscriber", targets: ["MeetingTranscriber"]),
        .executable(name: "selftest", targets: ["selftest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dmrschmidt/DSWaveformImage", from: "14.5.0"),
        .package(url: "https://github.com/EmergeTools/Pow", from: "1.0.6"),
    ],
    targets: [
        // Чистая логика без AppKit/CoreAudio: детектор, папка встречи, настройки, очередь.
        .target(name: "DetectorCore"),
        .executableTarget(
            name: "MeetingTranscriber",
            dependencies: [
                "DetectorCore",
                .product(name: "DSWaveformImage", package: "DSWaveformImage"),
                .product(name: "DSWaveformImageViews", package: "DSWaveformImage"),
                .product(name: "Pow", package: "Pow"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVKit"), // без него VideoPlayer падает при первом показе
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
