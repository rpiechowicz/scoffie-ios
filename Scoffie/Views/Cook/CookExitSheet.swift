import SwiftUI
import UIKit

/// „Wychodzisz z gotowania?” (XW0–2, D22): trwające timery jako pigułki,
/// dwa kafle — **Wstrzymaj** (wyróżniony; sesja i timery zostają) i
/// **Zakończ** (timery się wyłączają) — i „Gotuj dalej”. Bez krzyżyka i bez
/// drugiego potwierdzenia.
///
/// Pigułki są WSZYSTKIE (runda 5: „widzę tylko 2 timery”) — zawijane
/// w wiersze na środku, a arkusz ma wysokość treści (pomiar jak w arkuszu
/// Timery), więc trzeci i czwarty timer nie wypychają przycisków za dół.
///
/// Runda 10 („niech się otwiera jak wszystkie inne”): wysokość jest
/// POLICZONA przed pokazaniem (`estimatedHeight` — te same kroje, kafle
/// i zawijanie pigułek co układ), więc arkusz wjeżdża od razu na swoją
/// wysokość. Dawny szacunek 400 pt kurczył się do treści dopiero w trakcie
/// wjazdu, a treść wchodziła jeszcze własną kaskadą — wyglądało to jak
/// drugie otwarcie. Pomiar zostaje, ale poprawia już tylko ułamki.
struct CookExitSheet: View {
    let session: CookSession
    let onPause: () -> Void
    let onEnd: () -> Void
    let onContinue: () -> Void

    @State private var contentHeight: CGFloat
    @State private var bottomInset: CGFloat = 0
    @Environment(\.colorScheme) private var scheme

    init(
        session: CookSession,
        onPause: @escaping () -> Void,
        onEnd: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) {
        self.session = session
        self.onPause = onPause
        self.onEnd = onEnd
        self.onContinue = onContinue
        _contentHeight = State(initialValue: Self.estimatedHeight(session: session, running: Self.running(in: session, at: Date())))
    }

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(running: Self.running(in: session, at: context.date))
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
    }

    /// Trwające i po czasie — lecą dalej po „Wstrzymaj”, gasną po „Zakończ”.
    private static func running(in session: CookSession, at now: Date) -> [CookDockTimer] {
        session.timerLineup(now: now).filter { item in
            switch item.status {
            case .running, .overdue: true
            default: false
            }
        }
    }

    // MARK: - Wysokość przed pokazaniem

    /// Treść arkusza policzona z TYCH SAMYCH liczb co `content`, odstęp po
    /// odstępie z góry na dół: wiersze tekstu z krojów UIKit (z zawijaniem
    /// na szerokości), kafle z ikoną i podpisem do dwóch linii, pigułki
    /// zawijane jak `AllergenChipFlow`. Pomyłka to najwyżej punkt — tyle
    /// poprawi pomiar, a arkusz nie przeskakuje w trakcie wjazdu.
    private static func estimatedHeight(session: CookSession, running: [CookDockTimer]) -> CGFloat {
        let width = screenWidth - 2 * SCCook.Spacing.page
        // Nagłówek `EditorialSheetHeader(compact:)`: kafelek 36 obok eyebrow
        // (10,5 bold) i tytułu (19 bold, jedna linia), pod spodem podtytuł 13
        // po 10 pt odstępu.
        let titleBlock = UIFont.systemFont(ofSize: 10.5, weight: .bold).lineHeight + 2
            + UIFont.systemFont(ofSize: 19, weight: .bold).lineHeight
        var height: CGFloat = headerTop + max(36, titleBlock)
        height += 10 + textHeight(subtitle(session), font: .systemFont(ofSize: 13), width: width)
        if !running.isEmpty {
            height += 14 + pillsHeight(running, width: width)
        }
        let tileWidth = (width - 12) / 2
        let captions = running.isEmpty
            ? ["Wrócisz do tego kroku", "Wyjdziesz z przepisu"]
            : ["Timery lecą dalej", "Timery się wyłączą"]
        let captionLine = UIFont.systemFont(ofSize: 13).lineHeight
        let tileTitle = UIFont.systemFont(ofSize: 17, weight: .bold).lineHeight
        var tile: CGFloat = 0
        for caption in captions {
            let wrapped = textHeight(caption, font: .systemFont(ofSize: 13), width: tileWidth - 24)
            let inner: CGFloat = 16 + SCCook.Size.exitTileIcon + 10 + tileTitle + 2
            tile = max(tile, inner + min(wrapped, 2 * captionLine) + 16)
        }
        height += 18 + max(SCCook.Height.exitTile, tile)
        height += 22 + SCCook.Height.button + 8
        return ceil(height)
    }

    /// Odstęp nad nagłówkiem — jak w innych kompaktowych arkuszach.
    private static let headerTop: CGFloat = 20

    private static func subtitle(_ session: CookSession) -> String {
        "Krok \(session.stepIndex + 1) z \(session.stepCount) · \(CookRecipeFacts.shortTitle(session.recipeTitle))"
    }

    /// Pigułka `CookTimerPill`: 8 + pierścień + 8 + nazwa + 8 + czas + 14,
    /// wysokość 40; wiersze po 8 pt odstępu, jak w `AllergenChipFlow`.
    private static func pillsHeight(_ items: [CookDockTimer], width: CGFloat) -> CGFloat {
        let label = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let clock = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .heavy)
        var rows = 1
        var rowWidth: CGFloat = 0
        for item in items {
            let name = textWidth(item.timer.label, font: label)
            let time = textWidth(CookDockLabels.time(item.status), font: clock)
            let pill: CGFloat = 8 + SCCook.Size.pillRing + 8 + name + 8 + time + 14
            let appended: CGFloat = rowWidth == 0 ? pill : rowWidth + 8 + pill
            if appended > width, rowWidth > 0 {
                rows += 1
                rowWidth = pill
            } else {
                rowWidth = appended
            }
        }
        return CGFloat(rows) * 40 + CGFloat(rows - 1) * 8
    }

    /// Arkusz ma szerokość ekranu.
    private static var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first ?? 393
    }

    private static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func textHeight(_ text: String, font: UIFont, kern: CGFloat = 0, width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .kern: kern],
            context: nil
        )
        return ceil(rect.height)
    }

    private func content(running: [CookDockTimer]) -> some View {
        VStack(spacing: 0) {
            // Wspólny nagłówek arkuszy, kompaktowy (Rafał 4.10.2026: „1:1
            // wszędzie tak samo”). Krzyżyk = „Gotuj dalej”. Dawniej wyśrodkowany
            // tytuł bez krzyżyka — jedyny arkusz bez nagłówka.
            EditorialSheetHeader(
                eyebrow: "Gotowanie",
                title: "Wychodzisz z gotowania?",
                icon: "pause.fill",
                accent: SCPalette.sage,
                subtitle: Self.subtitle(session),
                compact: true,
                onClose: onContinue
            )
            .padding(.top, Self.headerTop)

            if !running.isEmpty {
                AllergenChipFlow(spacing: 8, alignment: .center) {
                    ForEach(running) { item in
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

            Button(action: onContinue) {
                Text("Gotuj dalej")
                    .cookText(SCCook.Typography.buttonQuiet)
                    .foregroundStyle(Color.scLabel(scheme))
                    .frame(maxWidth: .infinity, minHeight: SCCook.Height.button)
                    // Neutralne szkło — przycisk wtórny jak `AssistantGhostButton`.
                    .scChromeGlass(in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
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
                    .font(.sc(size: 20, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: SCCook.Size.exitTileIcon, height: SCCook.Size.exitTileIcon)
                    .background(Circle().fill(tint.opacity(0.16)))
                VStack(spacing: 2) {
                    Text(title)
                        .font(.sc(size: 17, weight: .bold))
                        .foregroundStyle(Color.scLabel(scheme))
                    Text(caption)
                        .font(.sc(size: 13))
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
