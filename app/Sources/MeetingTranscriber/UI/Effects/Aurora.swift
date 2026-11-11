import SwiftUI

/// Мягкий неподвижный фон: сетка 3×3. Движение на экране ведёт волна, фон с ней не спорит и не тратит процессор.
/// Только лайм и холодный нейтральный тон: акцент остаётся один, в тёмной теме нет грязных смесей.
struct Aurora: View {
    var body: some View {
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.42, 0], [1, 0],
            [0, 0.58], [0.56, 0.44], [1, 0.38],
            [0, 1], [0.62, 1], [1, 1],
        ], colors: [
            Theme.glow.opacity(0.30), Theme.cool.opacity(0.10), Theme.cool.opacity(0.30),
            Theme.cool.opacity(0.16), .clear, Theme.glow.opacity(0.14),
            Theme.cool.opacity(0.26), Theme.glow.opacity(0.20), Theme.cool.opacity(0.12),
        ])
        .accessibilityHidden(true)
    }
}
