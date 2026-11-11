import DetectorCore
import SwiftUI

/// Плеер встречи: волна штрихами на мягком градиенте, под ней — управление; текущее время показано один раз, слева.
struct PlayerBar: View {
    @Environment(AppModel.self) private var model
    let player: PlayerModel
    /// Финал обработки: пока карточка обработки сжимается сюда, плеер скрыт — глаз видит одну поверхность; управление проявляется следом.
    var collapsing = false
    @State private var rateHovered = false

    var body: some View {
        VStack(spacing: 8) {
            if let path = player.missingVideo {
                Label("Видео не найдено: \(path)", systemImage: "video.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(path)
            }
            if player.hasMedia || !player.isLoaded {
                // место волны занято с первого кадра, ещё до загрузки звука: сюда приезжает волна обработки
                Waveform(player: player, collapsing: collapsing)
                    .frame(height: 56)
                    .allowsHitTesting(player.hasMedia)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.playerSlot = $0 }
                controls
                    .opacity(player.hasMedia && !collapsing ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: collapsing)
                    .disabled(!player.hasMedia)
            } else {
                Label("Запись не сохранилась", systemImage: "waveform.slash")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        // подпись о пропавшем видео раздвигает карточку плавно, а не рывком
        .animation(.easeOut(duration: 0.25), value: player.missingVideo)
        .background {
            ZStack {
                Theme.card
                if player.hasMedia || !player.isLoaded { SoftGradient() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.playerCardSlot = $0 }
        .opacity(collapsing ? 0 : 1)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Text(MeetingDocument.shortTimecode(player.currentTime))
                .frame(minWidth: 52, alignment: .leading)
            Spacer(minLength: 0)
            control("gobackward.15", "Назад на 15 секунд") { player.seek(to: player.currentTime - 15) }
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 42, height: 42)
                    .background(Theme.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(SpringyButtonStyle())
            .help(player.isPlaying ? "Пауза (пробел)" : "Слушать (пробел)")
            .accessibilityLabel(player.isPlaying ? "Пауза" : "Слушать")
            control("goforward.15", "Вперёд на 15 секунд") { player.seek(to: player.currentTime + 15) }
            Spacer(minLength: 0)
            Button {
                let rates = PlayerModel.rates
                player.rate = rates[((rates.firstIndex(of: player.rate) ?? 0) + 1) % rates.count]
            } label: {
                Text(rateText)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.primary.opacity(rateHovered ? 0.14 : 0.08), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { rateHovered = $0 }
            .animation(.easeOut(duration: 0.15), value: rateHovered)
            .help("Скорость воспроизведения")
            .accessibilityLabel("Скорость \(rateText)")
            Text(MeetingDocument.shortTimecode(player.duration))
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .font(.callout.weight(.medium).monospacedDigit())
    }

    private var rateText: String {
        (player.rate == 1.5 ? "1,5" : String(Int(player.rate))) + "×"
    }

    private func control(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(IconButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Волна тонкими штрихами: сыгранная часть — акцентом; клик и протяжка перематывают.
private struct Waveform: View {
    let player: PlayerModel
    var collapsing = false
    /// Пока тянут — курсор идёт за мышью, а не за плеером.
    @State private var dragged: Double?
    /// Доля ширины под курсором мыши — для подсказки времени.
    @State private var hover: Double?

    var body: some View {
        GeometryReader { geo in
            let growing = !player.levels.isEmpty && !collapsing
            let progress = dragged ?? (player.duration > 0 ? player.currentTime / player.duration : 0)
            // пока формы звука нет (и пока в финале сюда сжимается карточка обработки) — линия; потом штрихи вырастают из неё
            WaveBars(levels: player.levels, real: growing ? 1 : 0, played: progress, head: player.hasMedia)
                .animation(.spring(duration: 0.7, bounce: 0.2), value: growing)
            .overlay {
                // время под курсором (или под пальцем, пока тянут): метка всплывает над волной, в поле карточки
                if let at = dragged ?? hover {
                    let atX = geo.size.width * at
                    Rectangle().fill(.primary.opacity(0.25))
                        .frame(width: 1, height: geo.size.height)
                        .position(x: atX, y: geo.size.height / 2)
                        .opacity(dragged == nil ? 1 : 0)
                    Text(MeetingDocument.shortTimecode(at * player.duration))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accent, in: Capsule())
                        .fixedSize()
                        .position(x: min(max(atX, 22), geo.size.width - 22), y: -7)
                }
            }
            .animation(.easeOut(duration: 0.12), value: (dragged ?? hover) == nil)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let point) = phase { hover = min(max(point.x / geo.size.width, 0), 1) } else { hover = nil }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { dragged = min(max($0.location.x / geo.size.width, 0), 1) }
                .onEnded { _ in
                    if let dragged { player.seek(to: dragged * player.duration) }
                    dragged = nil
                })
        }
        .accessibilityElement()
        .accessibilityLabel("Позиция в записи")
        .accessibilityValue(MeetingDocument.shortTimecode(player.currentTime))
        .accessibilityAdjustableAction { direction in
            player.seek(to: player.currentTime + (direction == .increment ? 15 : -15))
        }
    }
}

/// Мягкий размытый градиент за волной — как на ориентире.
struct SoftGradient: View {
    var body: some View {
        MeshGradient(width: 3, height: 2, points: [
            [0, 0], [0.45, 0], [1, 0],
            [0, 1], [0.6, 1], [1, 1],
        ], colors: [
            Theme.glow.opacity(0.24), Theme.cool.opacity(0.08), Theme.cool.opacity(0.28),
            Theme.cool.opacity(0.12), .clear, Theme.glow.opacity(0.12),
        ])
    }
}
