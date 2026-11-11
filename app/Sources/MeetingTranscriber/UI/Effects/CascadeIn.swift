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
        // каскад ждёт своей очереди в финале обработки; шаг 0,04 с, не больше 12 шагов — вся цепочка короче 0,8 с
        let animation = reduceMotion ? Animation.easeOut(duration: 0.3)
            : .timingCurve(0.16, 1, 0.3, 1, duration: 0.3).delay(Finale.cascadeDelay + Double(min(order, 12)) * 0.04)
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 24)
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

/// Финал обработки, по очереди: отметка последнего шага → уходит текст → карточка сжимается в плеер → поднимается содержимое → всплеск.
enum Finale {
    static let check = 0.45  // последний шаг отмечен, волна застыла: вдох перед сжатием
    static let clear = 0.2   // содержимое карточки обработки гаснет, остаётся одна волна
    static let collapse = 0.55 // карточка обработки сжимается в карточку плеера, форма сплющивается в линию записи
    static let settle = 0.7    // из линии вырастают штрихи волны плеера, проявляется управление
    static let cascadeDelay = 0.3 // содержимое поднимается на освободившееся место, когда карточка уже почти сжалась
}
