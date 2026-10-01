import SwiftUI

/// „Wychodzisz z gotowania?” (XW0–2, D22): trwające timery jako pigułki,
/// dwa kafle — **Wstrzymaj** (wyróżniony; sesja i timery zostają) i
/// **Zakończ** (timery się wyłączają) — i „Gotuj dalej”. Bez krzyżyka i bez
/// drugiego potwierdzenia.
///
/// Pigułki są WSZYSTKIE (runda 5: „widzę tylko 2 timery”) — zawijane
/// w wiersze na środku, a arkusz ma wysokość treści (pomiar jak w arkuszu
/// Timery), więc trzeci i czwarty timer nie wypychają przycisków za dół.
struct CookExitSheet: View {
    let session: CookSession
    let onPause: () -> Void
    let onEnd: () -> Void
    let onContinue: () -> Void

    @State private var hasAppeared = false
    /// Szacunek przed pierwszym pomiarem — dawna stała wysokość arkusza.
    @State private var contentHeight: CGFloat = 400
    @State private var bottomInset: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(running: running(at: context.date))
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                guard height > 0, abs(height - contentHeight) > 0.5 else { return }
                contentHeight = height
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Margines gestu odczytany na czytniku z `ignoresSafeArea()` (wzór
        // `PlanDayGoalSheet`).
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.safeAreaInsets.bottom, initial: true) { _, value in
                        bottomInset = value
                    }
            }
            .ignoresSafeArea()
        }
        .presentationDetents([.height(contentHeight + bottomInset)])
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
    }

    /// Trwające i po czasie — lecą dalej po „Wstrzymaj”, gasną po „Zakończ”.
    private func running(at now: Date) -> [CookDockTimer] {
        session.timerLineup(now: now).filter { item in
            switch item.status {
            case .running, .overdue: true
            default: false
            }
        }
    }

    private func content(running: [CookDockTimer]) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text("Wychodzisz z gotowania?")
                    .cookText(SCCook.Typography.exitTitle)
                    .foregroundStyle(Color.scLabel(scheme))
                    .multilineTextAlignment(.center)
                Text("Krok \(session.stepIndex + 1) z \(session.stepCount) · \(CookRecipeFacts.shortTitle(session.recipeTitle))")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.scMuted(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.top, 26)
            .cookReveal(hasAppeared, order: 0)

            if !running.isEmpty {
                AllergenChipFlow(spacing: 8, alignment: .center) {
                    ForEach(running) { item in
                        CookTimerPill(item: item)
                    }
                }
                .padding(.top, 14)
                .cookReveal(hasAppeared, order: 1)
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
            .cookReveal(hasAppeared, order: 2)

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
            .padding(.top, 22)
            .cookReveal(hasAppeared, order: 3)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .padding(.bottom, 8)
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
    /// Gdzie tytuł dzieli się na nazwę i dopisek: pierwsze „ z ” / „ ze ”.
    private static func splitRange(_ title: String) -> Range<String.Index>? {
        title.range(of: " z ") ?? title.range(of: " ze ")
    }

    /// Nazwa dania do „Krok 8 z 12 · Kotlet de volaille” — bez dopisku po „ z ”.
    static func shortTitle(_ title: String) -> String {
        guard let range = splitRange(title) else { return title }
        return String(title[..<range.lowerBound])
    }

    /// Dopisek po „ z ” — „z ziemniakami i mizerią”.
    static func subtitle(_ title: String) -> String? {
        guard let range = splitRange(title) else { return nil }
        return String(title[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
    }
}
