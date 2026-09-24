import SwiftUI

// Powitanie pustej rozmowy — makieta Claude Design „Scoffie — Asystent ·
// Empty state v2”, wariant A („wiadomość przy polu”): znak, otwarcie,
// jedno zdanie pomocy, główna akcja i alternatywy w JEDNYM bloku tuż nad
// polem wiadomości, pod kciukiem. To „zerowa wiadomość” asystenta: stoi
// tam, gdzie zacznie się rozmowa, i nie trafia do historii.
//
// Treść liczy `AssistantBriefingResolver` (17 sytuacji: pora dnia, plan
// dziś / jutro / tygodnia, godziny posiłków, bilans, pula). Widok nie liczy
// nic sam. Odejścia od makiety: przyciski w wariancie „soft”, pigułki
// alternatyw to `AssistantChip` z rozmowy, a pod zdaniem pomocy stoi
// kontekst bez słów — talerzyki pór, najbliższe danie albo pasek bilansu.
//
// Ruch: otwarcie i zdanie PISZĄ SIĘ (`SCTypedText`, jak odpowiedź
// asystenta), potem kaskadą wchodzą kontekst i akcje, a liczby liczą się
// od zera. Całość gra od nowa przy każdym wejściu na zakładkę i przy nowej
// sytuacji; ta sama sytuacja ze zmienioną liczbą („Za 39 minut obiad”)
// tylko roluje cyfry. Pisanie („Mam inny pomysł”, fokus pola) zdejmuje
// akcje i kontekst — otwarcie zostaje nad polem jako temat rozmowy.
//
// Znak nad otwarciem jest ŻYWY (`SCLivingMark`): oddycha i co kilka oddechów
// coś robi, pochyla się ku polu, gdy ktoś pisze, skinie przy pierwszej
// literze, a przy wykorzystanej puli drzemie.
struct AssistantEmptyState: View {
    let briefing: AssistantBriefing
    /// Tryb pisania: akcje i kontekst zgaszone. Przełącza go ekran RAZEM
    /// z klawiaturą, w jej animacji (`AssistantView.greetingComposing`) —
    /// nie sam fokus, patrz tam.
    var composing: Bool = false
    /// Podbicie = pierwsza litera w polu (znak skinie).
    var nudge: Int = 0
    /// Liczby puli — kontekst powitania, gdy pula jest wykorzystana.
    var quota: AssistantQuotaFacts? = nil
    /// Asystent odpoczywa (wyczerpana pula miesięczna) — znak drzemie.
    var sleeping: Bool = false
    let onAction: (AssistantBriefing.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scTabIsActive) private var isActiveTab

    /// Każde wejście na zakładkę i każda nowa sytuacja = nowe odtworzenie.
    @State private var play = 0

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AssistantGreeting(
                briefing: briefing,
                composing: composing,
                nudge: nudge,
                quota: quota,
                sleeping: sleeping,
                playKey: play,
                onAction: onAction
            )
            .id(briefing.kind)
            .transition(.opacity)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3), value: briefing.kind)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isActiveTab, initial: true) { _, active in
            if active { play += 1 }
        }
        .onChange(of: briefing.kind) { _, _ in play += 1 }
    }
}

/// Sam blok powitania.
private struct AssistantGreeting: View {
    let briefing: AssistantBriefing
    let composing: Bool
    let nudge: Int
    let quota: AssistantQuotaFacts?
    let sleeping: Bool
    let playKey: Int
    let onAction: (AssistantBriefing.Action) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// Tempo pisania: otwarcie spokojnie, zdanie pomocy szybciej.
    private static let baseHeadlineRate: Double = 65
    private static let baseSupportRate: Double = 170
    /// Oba zdania razem piszą się najwyżej tyle — przy dłuższym tekście
    /// tempo rośnie w tej samej proporcji, krótki pisze się jak dotąd.
    private static let typingBudget: Double = 0.75

    private var rateScale: Double {
        let natural = Double(briefing.headline.count) / Self.baseHeadlineRate
            + Double(briefing.supporting.count) / Self.baseSupportRate
        return max(1, natural / Self.typingBudget)
    }

    private var headlineRate: Double { Self.baseHeadlineRate * rateScale }
    private var supportRate: Double { Self.baseSupportRate * rateScale }
    private static let lead: Double = 0.08

    private var supportDelay: Double {
        Self.lead + SCTypedText.duration(briefing.headline, rate: headlineRate) + 0.05
    }

    /// Kontekst i akcje wchodzą, gdy zdanie pomocy jest w dwóch trzecich.
    private var restDelay: Double {
        supportDelay + SCTypedText.duration(briefing.supporting, rate: supportRate) * 0.66
    }

    /// Pula wykorzystana: zamiast talerzyków — kreseczki puli (co poszło,
    /// kiedy wraca albo co daje plan).
    private var quotaContext: AssistantQuotaFacts? {
        briefing.kind == .trialExhausted ? quota : nil
    }

    private var hasVisual: Bool { briefing.visual != .plain || quotaContext != nil }

    /// Nastrój znaku: drzemie przy wykorzystanej puli, nasłuchuje przy
    /// pisaniu, poza tym spokojnie oddycha.
    private var markMood: SCLivingMark.Mood {
        if briefing.isQuiet || sleeping { return .sleeping }
        return composing ? .attentive : .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Znak większy niż w makiecie (Kes 20 → 14 pt): przy 28-punktowym
            // otwarciu ginął — decyzja Rafała. Wejście (sprężyna od 0,4)
            // stoi NAD żywym znakiem, więc oddech gra już w trakcie wejścia.
            SCLivingMark(
                mood: markMood,
                color: briefing.isQuiet ? AssistantLook.ink(scheme).opacity(0.3) : AssistantLook.terraFill(scheme),
                size: 26,
                nudge: nudge,
                glows: !briefing.isQuiet,
                lively: true
            )
                .scaleEffect(revealed || reduceMotion ? 1 : 0.4)
                .opacity(revealed ? 1 : 0)
                .animation(revealed ? motion(.spring(duration: 0.5, bounce: 0.35)) : nil, value: revealed)
                .accessibilityHidden(true)

            SCTypedText(briefing.headline, playKey: playKey, rate: headlineRate, delay: Self.lead)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .lineSpacing(2)
                .foregroundStyle(AssistantLook.ink(scheme))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)

            SCTypedText(briefing.supporting, playKey: playKey, rate: supportRate, delay: supportDelay)
                .font(.system(size: 17))
                .tracking(-0.3)
                .lineSpacing(3)
                .foregroundStyle(AssistantLook.muted(scheme))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340, alignment: .leading)
                .padding(.top, 8)

            // Akcje i kontekst NIE wypadają z układu przy pisaniu (24.09.2026,
            // Rafał: „przyciski się chowają, a tytuł przeskakuje”): wyjęcie
            // widoku zmieniało wysokość bloku w jednej klatce, a wstawienie
            // przy chowaniu klawiatury rysowało przyciski od razu na miejscu
            // docelowym — nad polem, które jeszcze zjeżdżało. Teraz blok
            // ZWIJA się do zera (i rozwija) w krzywej klawiatury, razem
            // z polem, a krycie gaśnie osobno, szybciej — otwarcie jedzie
            // jednym ciągłym ruchem.
            GreetingCollapse(collapsed: composing) {
                VStack(alignment: .leading, spacing: 0) {
                    if let quotaContext {
                        AssistantQuotaPanel(facts: quotaContext, revealed: revealed, delay: restDelay + 0.1)
                            .padding(.top, 18)
                            .modifier(GreetingStep(revealed: revealed, delay: restDelay, reduceMotion: reduceMotion))
                    } else if hasVisual {
                        GreetingVisual(visual: briefing.visual, revealed: revealed, delay: restDelay)
                            .padding(.top, 18)
                            .modifier(GreetingStep(revealed: revealed, delay: restDelay, reduceMotion: reduceMotion))
                    }

                    GreetingPrimary(title: briefing.primary.title) {
                        onAction(briefing.primary)
                    }
                    .padding(.top, 24)
                    .modifier(GreetingStep(revealed: revealed, delay: restDelay + (hasVisual ? 0.08 : 0), reduceMotion: reduceMotion))

                    if !briefing.alternatives.isEmpty {
                        AllergenChipFlow(spacing: 8) {
                            ForEach(Array(briefing.alternatives.enumerated()), id: \.element.id) { index, action in
                                AssistantChip(title: action.title, icon: icon(for: action)) {
                                    onAction(action)
                                }
                                .modifier(GreetingStep(
                                    revealed: revealed,
                                    delay: restDelay + (hasVisual ? 0.08 : 0) + 0.07 * Double(index + 1),
                                    reduceMotion: reduceMotion
                                ))
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // BEZ `.animation(value: composing)`: zwinięcie bloku jedzie
        // w transakcji, w której ekran przełącza `composing` — w krzywej
        // klawiatury. Własna animacja tutaj (była `.smooth(0.3)`) nadpisywała
        // ją w tym poddrzewie i blok zjeżdżał innym tempem niż pole.
        .task(id: playKey) {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { revealed = false }
            // Klatka oddechu: najpierw stan zerowy, potem kaskada.
            try? await Task.sleep(for: .milliseconds(30))
            if Task.isCancelled { return }
            revealed = true
        }
        .accessibilityElement(children: .contain)
    }

    private func motion(_ animation: Animation) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : animation
    }

    /// „Mam inny pomysł” mówi ołówkiem, że otwiera pisanie.
    private func icon(for action: AssistantBriefing.Action) -> String? {
        switch action.kind {
        case .compose: return "square.and.pencil"
        case .openHistory: return "clock"
        case .openPlan: return MenuConstans.Plan.icon
        case .openShopping: return "basket"
        case .ask, .openPlans: return nil
        }
    }
}

/// Zwijany dół powitania: wysokość mierzona i animowana do zera w tej
/// transakcji, która przełącza `collapsed` (krzywa klawiatury z ekranu),
/// krycie gaśnie szybciej i we własnej animacji (`animation(_:body:)`, żeby
/// nie nadpisać ruchu układu). Zwinięty nie łapie dotyku i znika z VoiceOver.
private struct GreetingCollapse<Content: View>: View {
    let collapsed: Bool
    @ViewBuilder let content: Content

    @State private var height: CGFloat = 0

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .frame(height: collapsed ? 0 : (height > 0 ? height : nil), alignment: .top)
            // Przycięcie tylko przy zwijaniu — rozwinięty blok ma zapas na
            // cień i wciśnięcie przycisków.
            .clipShape(Rectangle().inset(by: collapsed ? 0 : -24))
            .animation(.easeOut(duration: collapsed ? 0.14 : 0.32)) {
                $0.opacity(collapsed ? 0 : 1)
            }
            .allowsHitTesting(!collapsed)
            .accessibilityHidden(collapsed)
    }
}

/// Wejście elementu kaskady: krycie i 10 pt w górę, po swoim opóźnieniu.
/// Znika od razu — opóźnione znikanie wyglądałoby jak zacięcie.
private struct GreetingStep: ViewModifier {
    let revealed: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .geometryGroup()
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 10)
            .animation(
                revealed
                    ? (reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.5).delay(delay))
                    : nil,
                value: revealed
            )
    }
}

/// Główna akcja powitania: kapsuła „soft” 50 pt na szerokość treści,
/// ze strzałką — wysyła zwykłą wiadomość i niczego nie zapisuje.
private struct GreetingPrimary: View {
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.numericText())
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(AssistantLook.terra(scheme))
            .padding(.leading, 22)
            .padding(.trailing, 20)
            .frame(height: 50)
            .scSoftCapsule(AssistantLook.terra(scheme))
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
    }
}

// MARK: - Kontekst

/// Kontekst pod zdaniem pomocy — stan dnia bez słów.
private struct GreetingVisual: View {
    let visual: AssistantBriefing.Visual
    let revealed: Bool
    let delay: Double

    var body: some View {
        switch visual {
        case .plain:
            EmptyView()
        case let .plates(plates):
            GreetingPlates(plates: plates, revealed: revealed, delay: delay)
        case let .meal(meal):
            GreetingMeal(meal: meal, revealed: revealed)
        case let .balance(current, target, unit):
            GreetingBalance(current: current, target: target, unit: unit, revealed: revealed, delay: delay)
        }
    }
}

/// Talerzyki pór dnia jak na Kalendarzu: zdjęcie dania albo pusty,
/// kreskowany krążek. Pora, o której mowa, ma terakotowy pierścień.
/// Wchodzą po kolei z lekkim wyskokiem.
private struct GreetingPlates: View {
    let plates: [AssistantBriefing.Plate]
    let revealed: Bool
    let delay: Double

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size: CGFloat = 46

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(plates.enumerated()), id: \.element.id) { index, plate in
                VStack(spacing: 6) {
                    plateCircle(plate)
                        .scaleEffect(revealed || reduceMotion ? 1 : 0.6)
                        .opacity(revealed ? 1 : 0)
                        .animation(
                            revealed
                                ? (reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.3).delay(delay + 0.06 * Double(index)))
                                : nil,
                            value: revealed
                        )

                    Text(plate.title)
                        .font(.system(size: 11.5, weight: plate.isFocus ? .bold : .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(plate.isFocus ? AssistantLook.terra(scheme) : AssistantLook.faint(scheme))
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(plate.title): \(plate.filled ? "jest w planie" : "pusto")")
            }
        }
    }

    @ViewBuilder
    private func plateCircle(_ plate: AssistantBriefing.Plate) -> some View {
        ZStack {
            if plate.filled {
                CachedAsyncImage(url: plate.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            AssistantLook.terraTint(scheme)
                            Image(systemName: "fork.knife")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AssistantLook.terra(scheme).opacity(0.7))
                        }
                    }
                }
                .frame(width: Self.size, height: Self.size)
                .clipShape(Circle())
                .shadow(color: Color.black.opacity(0.12), radius: 1, y: 1)
            } else {
                Circle()
                    .fill(plate.isFocus ? AssistantLook.terraTint(scheme) : Color.clear)
                    .overlay(
                        Circle().strokeBorder(
                            plate.isFocus ? AssistantLook.terraFill(scheme).opacity(0.55) : AssistantLook.dash(scheme),
                            style: StrokeStyle(lineWidth: 1.5, dash: [3.5, 3.5])
                        )
                    )
                    .overlay {
                        if plate.isFocus {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AssistantLook.terra(scheme))
                        }
                    }
                    .frame(width: Self.size, height: Self.size)
            }
        }
        .overlay(
            Circle()
                .stroke(plate.isFocus && plate.filled ? AssistantLook.terraFill(scheme) : Color.clear, lineWidth: 2)
                .padding(-3)
        )
    }
}

/// Najbliższe danie z planu: zdjęcie, pora z godziną, nazwa i liczby, które
/// liczą się od zera (`SCCountingText`). Kafel jak każda karta w aplikacji.
private struct GreetingMeal: View {
    let meal: AssistantBriefing.MealPreview
    let revealed: Bool

    @Environment(\.colorScheme) private var scheme

    private var meta: String? {
        var parts: [String] = []
        if meal.minutes > 0 { parts.append("\(meal.minutes) min") }
        if meal.kcal > 0 { parts.append("\(meal.kcal) kcal") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            AssistantThumbnail(url: meal.imageURL, size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.eyebrow)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(AssistantLook.terra(scheme))
                    .lineLimit(1)
                Text(meal.title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta, revealed {
                    SCCountingText(meta)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AssistantLook.muted(scheme))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.scTileBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Średnia wobec celu: liczba liczy się od zera, pasek rośnie od lewej,
/// kreska celu stoi na końcu toru.
private struct GreetingBalance: View {
    let current: Int
    let target: Int
    let unit: String
    let revealed: Bool
    let delay: Double

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { min(1, Double(current) / Double(max(target, 1))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if revealed {
                        SCCountingText("\(current) \(unit)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AssistantLook.ink(scheme))
                    }
                    Text("średnio dziennie")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AssistantLook.faint(scheme))
                }
                Spacer(minLength: 8)
                Text("cel \(target) \(unit)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AssistantLook.faint(scheme))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(AssistantLook.ink(scheme).opacity(0.09))
                    Capsule()
                        .fill(AssistantLook.terraFill(scheme))
                        .frame(width: geometry.size.width * (revealed ? fraction : 0))
                        .animation(
                            revealed ? (reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.9).delay(delay + 0.1)) : nil,
                            value: revealed
                        )
                    HStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(AssistantLook.ink(scheme).opacity(0.35))
                            .frame(width: 2, height: 14)
                    }
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: 340)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(current) \(unit) średnio dziennie, cel \(target) \(unit)")
    }
}
