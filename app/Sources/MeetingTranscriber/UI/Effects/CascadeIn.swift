import SwiftUI

/// Каскадное появление: элементы всплывают по очереди. При «Уменьшении движения» — простое проявление.
private struct CascadeIn: ViewModifier {
    let order: Int
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(order: Int, active: Bool) {
        self.order = order
        _shown = State(initialValue: !active)
    }

    func body(content: Content) -> some View {
        let still = shown || reduceMotion
        // дальние реплики не ждут дольше полутора секунд
        let animation = reduceMotion ? Animation.easeOut(duration: 0.3)
            : .spring(duration: 0.6, bounce: 0.25).delay(0.25 + Double(min(order, 18)) * 0.07)
        content
            .opacity(shown ? 1 : 0)
            .offset(y: still ? 0 : 22)
            .blur(radius: still ? 0 : 8)
            // своя анимация ближе к элементу, чем анимации экрана, — иначе те её перебивают
            .animation(animation, value: shown)
            .onAppear { shown = true }
    }
}

extension View {
    /// `active` читается один раз, при создании: обычное открытие встречи идёт без задержки.
    func cascadeIn(order: Int, active: Bool) -> some View {
        modifier(CascadeIn(order: order, active: active))
    }
}
