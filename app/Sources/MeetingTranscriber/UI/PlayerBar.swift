import DetectorCore
import SwiftUI

/// Плеер встречи: волна штрихами на мягком градиенте и стеклянная панель управления.
struct PlayerBar: View {
    let player: PlayerModel

    var body: some View {
        VStack(spacing: 14) {
            if let path = player.missingVideo {
                Label("Видео не найдено: \(path)", systemImage: "video.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(path)
            }
            if player.hasMedia {
                Waveform(player: player)
                    .frame(height: 76)
                controls
            } else if player.isLoaded {
                Label("Запись не сохранилась", systemImage: "waveform.slash")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                Color.clear.frame(height: 134)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Theme.card
                if player.hasMedia { SoftGradient() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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
            }
            .buttonStyle(.plain)
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
                    .background(.primary.opacity(0.08), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Скорость воспроизведения")
            .accessibilityLabel("Скорость \(rateText)")
            Text(MeetingDocument.shortTimecode(player.duration))
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .font(.callout.weight(.medium).monospacedDigit())
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    private var rateText: String {
        (player.rate == 1.5 ? "1,5" : String(Int(player.rate))) + "×"
    }

    private func control(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Волна тонкими штрихами: сыгранная часть — акцентом; клик и протяжка перематывают.
private struct Waveform: View {
    let player: PlayerModel
    /// Пока тянут — курсор идёт за мышью, а не за плеером.
    @State private var dragged: Double?

    var body: some View {
        GeometryReader { geo in
            let progress = dragged ?? (player.duration > 0 ? player.currentTime / player.duration : 0)
            let x = geo.size.width * progress
            Canvas { context, size in
                    let step: CGFloat = 4
                    let count = max(1, Int(size.width / step))
                    let top: CGFloat = 20, height = size.height - top
                    for bar in 0..<count {
                        let level = player.levels.isEmpty ? 0 : CGFloat(player.levels[bar * player.levels.count / count])
                        let length = max(3, level * height)
                        let barX = CGFloat(bar) * step + 1
                        let rect = CGRect(x: barX, y: top + (height - length) / 2, width: 2, height: length)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1),
                                     with: barX < x ? .color(Theme.accentInk) : .style(.primary.opacity(0.28)))
                    }
                    context.fill(Path(CGRect(x: x - 0.5, y: top - 4, width: 1, height: height + 4)), with: .style(.primary.opacity(0.55)))
            }
            .overlay {
                Text(MeetingDocument.shortTimecode(progress * player.duration))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(Theme.onAccent)
                    .background(Theme.accent, in: Capsule())
                    .fixedSize()
                    .position(x: min(max(x, 22), geo.size.width - 22), y: 8)
            }
            .contentShape(Rectangle())
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
private struct SoftGradient: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MeshGradient(width: 3, height: 2, points: [
            [0, 0], [0.45, 0], [1, 0],
            [0, 1], [0.6, 1], [1, 1],
        ], colors: [
            .pink.opacity(0.26), .purple.opacity(0.10), .blue.opacity(0.28),
            .purple.opacity(0.12), .clear, .cyan.opacity(0.18),
        ])
        .opacity(scheme == .dark ? 0.75 : 1)
    }
}
