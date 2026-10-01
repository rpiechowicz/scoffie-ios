import SwiftUI

/// „Wychodzisz z gotowania?” (XW0–2, D22): trwające timery jako pigułki,
/// dwa kafle — **Wstrzymaj** (wyróżniony; sesja i timery zostają) i
/// **Zakończ** (timery się wyłączają) — i „Gotuj dalej”. Bez krzyżyka i bez
/// drugiego potwierdzenia.
struct CookExitSheet: View {
    let session: CookSession
    let onPause: () -> Void
    let onEnd: () -> Void
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let running = session.dockTimers(now: context.date).filter { item in
                switch item.status {
                case .running, .overdue: true
                default: false
                }
            }
            VStack(spacing: 0) {
                Text("Wychodzisz z gotowania?")
                    .cookText(SCCook.Typography.exitTitle)
                    .foregroundStyle(Color.scLabel(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 26)
                Text("Krok \(session.stepIndex + 1) z \(session.stepCount) · \(CookRecipeFacts.shortTitle(session.recipeTitle))")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.scMuted(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                if !running.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(running.prefix(2)) { item in
                            CookTimerPill(item: item)
                        }
                    }
                    .padding(.top, 14)
                }

                HStack(spacing: 12) {
                    tile(
                        title: "Wstrzymaj",
                        caption: running.isEmpty ? "Wrócisz do tego kroku" : "Timery lecą dalej",
                        icon: "pause.fill",
                        tint: SCPalette.sage,
                        highlighted: true,
                        action: onPause
                    )
                    tile(
                        title: "Zakończ",
                        caption: running.isEmpty ? "Wyjdziesz z przepisu" : "Timery się wyłączą",
                        icon: "stop.fill",
                        tint: SCPalette.terracotta,
                        highlighted: false,
                        action: onEnd
                    )
                }
                .padding(.top, 18)

                Spacer(minLength: 16)

                Button(action: onContinue) {
                    Text("Gotuj dalej")
                        .cookText(SCCook.Typography.buttonQuiet)
                        .foregroundStyle(Color.scLabel(scheme))
                        .frame(maxWidth: .infinity, minHeight: SCCook.Height.button)
                        .background(Capsule().fill(Color.scChipBg(scheme)))
                        .overlay(Capsule().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.bottom, 8)
        }
    }

    private func tile(
        title: String,
        caption: String,
        icon: String,
        tint: Color,
        highlighted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous)
        return Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: SCCook.Size.exitTileIcon, height: SCCook.Size.exitTileIcon)
                    .background(Circle().fill(tint.opacity(0.16)))
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.scLabel(scheme))
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.scMuted(scheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: SCCook.Height.exitTile)
            .background(shape.fill(highlighted ? tint.opacity(SCCook.Opacity.pauseTileFill) : Color.scTileBg(scheme)))
            .overlay(shape.strokeBorder(highlighted ? tint.opacity(SCCook.Opacity.pauseTileStroke) : Color.scTileStroke(scheme), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

extension CookRecipeFacts {
    /// Nazwa dania do „Krok 8 z 12 · Kotlet de volaille” — bez dopisku po „ z ”.
    static func shortTitle(_ title: String) -> String {
        if let range = title.range(of: " z ") ?? title.range(of: " ze ") {
            return String(title[..<range.lowerBound])
        }
        return title
    }
}
