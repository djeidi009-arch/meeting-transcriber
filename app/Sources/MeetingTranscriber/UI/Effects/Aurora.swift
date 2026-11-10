import SwiftUI

/// Плавно переливающийся мягкий фон: сетка 3×3, внутренние точки медленно дрейфуют.
struct Aurora: View {
    var colors: [Color] = [
        .pink.opacity(0.30), .purple.opacity(0.12), .blue.opacity(0.30),
        Theme.accent.opacity(0.30), .clear, .cyan.opacity(0.20),
        .blue.opacity(0.22), Theme.accent.opacity(0.22), .pink.opacity(0.24),
    ]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [Float(0.5 + 0.2 * sin(t * 0.7 + 0)), 0], [1, 0],
                [0, Float(0.5 + 0.2 * sin(t * 0.5 + 1))], [Float(0.5 + 0.2 * sin(t * 0.9 + 2)), Float(0.5 + 0.2 * sin(t * 0.6 + 3))], [1, Float(0.5 + 0.2 * sin(t * 0.8 + 4))],
                [0, 1], [Float(0.5 + 0.2 * sin(t * 0.6 + 5)), 1], [1, 1],
            ], colors: colors)
        }
        .opacity(scheme == .dark ? 0.75 : 1)
        .accessibilityHidden(true)
    }
}
