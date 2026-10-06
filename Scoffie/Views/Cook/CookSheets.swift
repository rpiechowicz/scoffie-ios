import SwiftUI

/// Nagłówek sekcji listy składników — dział sklepu („WARZYWA”): arkusz
/// Składniki (oba widoki) i szuflada powitania.
/// Dział ma ikonę i kolor alejki z Zakupów; to JEDYNE miejsce ikony —
/// wiersze składników są bez niej (runda 7: „ikonę daj tylko przy
/// kategorii, a nie przy składniku”).
struct CookSectionHeader: View {
    let title: String
    let color: Color
    var count: Int?
    var icon: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.sc(size: 12, weight: .bold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            Text(title)
                .cookText(SCCook.Typography.sectionLabel)
                .foregroundStyle(color)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)")
                    .font(.sc(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(SCCook.Palette.caption(scheme))
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Timery

/// Arkusz Timery (ST5, Y3T1–3) — z kapsuły i plakietki. JEDYNE miejsce pauzy,
/// wznowienia, „+1 min”, „Pomiń” i „Gotowe” (stuknięcie w timer w doku tylko
/// włącza timer do włączenia, inaczej otwiera ten arkusz). Arkusz systemu
/// (runda 3 testów: karta rozwijana z doku „trochę się bugowała”), a jego
/// wysokość idzie za treścią: tyle wierszy, ile timerów, bez pustego dołu.
///
/// JEDNA lista w kolejności kroków (`CookSession.timerLineup`), bez sekcji
/// „Trwa / W tym kroku / Wstrzymany” (runda 2): wiersz zostaje na swoim
/// miejscu przez cały czas swojego timera, a stan mówią glif i podpis —
/// w kolorze TEGO timera, jak w kapsule.
struct CookTimersSheet: View {
    let session: CookSession
    let onTimer: (CookTimerAction) -> Void
    let onClose: () -> Void

    @State private var contentHeight: CGFloat
    @State private var bottomInset: CGFloat = 0

    init(session: CookSession, onTimer: @escaping (CookTimerAction) -> Void, onClose: @escaping () -> Void) {
        self.session = session
        self.onTimer = onTimer
        self.onClose = onClose
        _contentHeight = State(initialValue: Self.estimatedHeight(rows: session.timerLineup(now: Date()).count))
    }

    /// Szacunek przed pierwszym pomiarem: nagłówek z odstępami i wiersze
    /// `height.cookTimerRow`. Pomiar poda liczbę prawdziwą.
    private static func estimatedHeight(rows: Int) -> CGFloat {
        84 + CGFloat(max(rows, 1)) * SCCook.Height.timerRow + 16
    }

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                list(session.timerLineup(now: context.date))
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                guard height > 0, abs(height - contentHeight) > 0.5 else { return }
                contentHeight = height
            }
        }
        // Lista, która mieści się w całości, nie ma się od czego odbijać.
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Margines gestu odczytany NA CZYTNIKU z `ignoresSafeArea()` — treść
        // arkusza ma go już odjętego (wzór `PlanDayGoalSheet`).
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

    private func list(_ items: [CookDockTimer]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetHeader(
                eyebrow: Self.summary(items),
                title: "Timery",
                icon: "timer",
                accent: SCPalette.terracotta,
                compact: true,
                onClose: onClose
            )
            .padding(.top, 20)
            .padding(.bottom, 8)

            ForEach(items) { item in
                CookTimerRow(item: item, onTimer: onTimer)
                    // Pominięty / zrobiony wiersz zjeżdża w bok, a reszta
                    // dosuwa się pod nim (runda 9) — samo przenikanie
                    // zostawiało dziurę, w którą wiersze wskakiwały.
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .padding(.bottom, 16)
        .animation(SCCook.Motion.dock, value: items.map(\.id))
        // Ostatni timer zrobiony („Gotowe”) — pusty arkusz się zamyka.
        .onChange(of: items.isEmpty) { _, isEmpty in
            if isEmpty { onClose() }
        }
    }

    /// „1 trwa · 1 do włączenia” — eyebrow nagłówka.
    private static func summary(_ items: [CookDockTimer]) -> String {
        var running = 0
        var pending = 0
        var paused = 0
        for item in items {
            switch item.status {
            case .running, .overdue: running += 1
            case .pending: pending += 1
            case .paused: paused += 1
            case .finished: break
            }
        }
        var parts: [String] = []
        if running > 0 {
            parts.append("\(running) \(PolishPlural.form(running, one: "trwa", few: "trwają", many: "trwa"))")
        }
        if pending > 0 {
            parts.append("\(pending) do włączenia")
        }
        if paused > 0 {
            parts.append("\(paused) \(PolishPlural.form(paused, one: "wstrzymany", few: "wstrzymane", many: "wstrzymanych"))")
        }
        return parts.isEmpty ? "Gotowanie" : parts.joined(separator: " · ")
    }
}

/// Wiersz arkusza Timery — ten sam układ w każdym stanie: pierścień-przycisk
/// (glif ruchu w środku), nazwa z podpisem i czas — a w jego miejscu
/// „Pomiń” (do włączenia) albo „+1 min” (po czasie). Zmienia się glif,
/// podpis i wypełnienie, nie miejsce; kolor jest kolorem timera
/// (wstrzymany — przygaszony).
private struct CookTimerRow: View {
    let item: CookDockTimer
    let onTimer: (CookTimerAction) -> Void

    @Environment(\.colorScheme) private var scheme

    private var isOverdue: Bool { if case .overdue = item.status { true } else { false } }
    private var isPending: Bool { if case .pending = item.status { true } else { false } }
    private var isPaused: Bool { if case .paused = item.status { true } else { false } }
    private var isRunning: Bool { if case .running = item.status { true } else { false } }

    private var color: Color { item.accent.color }

    /// Kolor stanu: kolor timera, a wstrzymany — przygaszony.
    private var tone: Color {
        isPaused ? Color.scMuted(scheme) : color
    }

    var body: some View {
        let time = CookDockLabels.time(item.status)
        let captionText = caption
        HStack(spacing: 12) {
            control

            VStack(alignment: .leading, spacing: 2) {
                Text(item.timer.label)
                    .font(.sc(size: 16, weight: .bold))
                    .foregroundStyle(isPaused ? Color.scMuted(scheme) : Color.scLabel(scheme))
                    .lineLimit(1)
                Text(captionText)
                    .font(.sc(size: 12))
                    .foregroundStyle(isOverdue ? color : SCCook.Palette.caption(scheme))
                    .lineLimit(1)
                    .cookRoll(captionText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPending {
                // Pominięty przy „Dalej” timer zostaje w doku (runda 4) —
                // stąd się go odprawia, gdy nie jest potrzebny.
                sideButton("Pomiń", ink: Color.scMuted(scheme), label: "Pomiń: \(item.timer.label)") {
                    onTimer(.skip(item.id))
                }
            } else if isOverdue {
                // Po czasie i wyciszony („Tylko wycisz” na ekranie końca
                // timera): stuknięcie w kapsułę prowadzi tutaj, więc obok
                // „Gotowe” w pierścieniu musi być i „jeszcze chwilę”. Licznik
                // po czasie przechodzi do podpisu.
                sideButton("+1 min", ink: Color.scLabel(scheme), label: "Dodaj minutę: \(item.timer.label)") {
                    onTimer(.extend(item.id, 60))
                }
            } else {
                Text(time)
                    .cookText(SCCook.Typography.sheetTime)
                    .monospacedDigit()
                    .foregroundStyle(tone)
                    .cookTicking(time, countsDown: !isOverdue)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: SCCook.Height.timerRow)
        .accessibilityElement(children: .contain)
        // Zmiana stanu z zegara (koniec odliczania) — kolory przechodzą
        // sprężyną doku, a nie w klatce.
        .animation(SCCook.Motion.dock, value: item.status.phase)
    }

    private var caption: String {
        switch item.status {
        case .pending: "Start: \(item.timer.startLabel.lowercasedFirst) · \(CookClock.duration(item.timer))"
        case .running: "krok \(item.stepIndex + 1) · z \(CookClock.duration(item.timer))"
        case .paused: "wstrzymany — nie zadzwoni"
        case let .overdue(over, _, _): "po czasie \(CookClock.overdueText(over)) · krok \(item.stepIndex + 1)"
        case .finished: ""
        }
    }

    /// Przycisk obok wiersza — „Pomiń” (do włączenia), „+1 min” (po czasie):
    /// neutralne szkło 34 pt, dotyk 44 pt.
    private func sideButton(_ title: String, ink: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.sc(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(height: 34)
                .scChromeGlass(in: Capsule())
                .contentShape(Capsule())
                .scTapHeight(44, drawn: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .transition(.opacity)
    }

    /// Pierścień-przycisk 46 pt: łuk pozostałego czasu (trwa, wstrzymany)
    /// albo pełny krążek w kolorze timera (czeka — ▶, po czasie — ✓).
    private var control: some View {
        let side = SCCook.Size.sheetTimerRing
        let filled = isPending || isOverdue
        return Button {
            if let action = item.primaryAction { onTimer(action) }
        } label: {
            ZStack {
                Circle().fill(filled ? color : .clear)
                CookTimerRing(fraction: item.status.remainingFraction, color: tone, lineWidth: SCCook.Stroke.sheetTimerRing)
                    .opacity(isRunning || isPaused ? 1 : 0)
                Image(systemName: item.primaryIcon)
                    .font(.sc(size: 14, weight: .heavy))
                    .foregroundStyle(filled ? Color.scPageBase(scheme) : (isPaused ? Color.scLabel(scheme) : tone))
                    .offset(x: item.primaryIcon == "play.fill" ? 1 : 0)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .cookInvitePulse(Circle(), color: color, isActive: isPending)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.primaryLabel)
    }
}

// MARK: - Składniki

/// Arkusz Składniki — z wyspy (KM1, KM2). Otwiera się na pół ekranu,
/// a przewijanie listy rozwija go na cały (runda 3). Bez odhaczania (D7).
///
/// Oba widoki stoją w działach sklepu (runda 4 i 9: „poukładaj składniki
/// względem kategorii”): „Ten krok” — składniki bieżącego kroku, „Cały
/// przepis” — wszystkie, a pod działem każdy wiersz mówi, w którym kroku
/// wchodzi; te z kroków już zrobionych są przygaszone z ptaszkiem.
struct CookIngredientsSheet: View {
    enum Scope: Hashable {
        case step
        case recipe
    }

    let session: CookSession
    let onClose: () -> Void

    @State private var scope: Scope = .step
    @Environment(\.colorScheme) private var scheme

    private var index: Int { session.stepIndex }

    private func lines(at stepIndex: Int) -> [CookIngredientLine] {
        guard session.steps.indices.contains(stepIndex) else { return [] }
        return session.package.lines(for: session.steps[stepIndex], portions: session.portions)
    }

    /// „Cały przepis N” = wiersze listy (składnik dzielony między kroki to
    /// kilka wierszy — sól ×3), tak jak liczą sekcje.
    private var recipeCount: Int {
        session.steps.indices.reduce(0) { $0 + lines(at: $1).count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Nagłówek i przełącznik stoją nad listą — nie przewijają się.
            VStack(alignment: .leading, spacing: 16) {
                EditorialSheetHeader(
                    eyebrow: "Krok \(index + 1) z \(session.stepCount)",
                    title: "Składniki",
                    icon: "basket",
                    accent: SCPalette.terracotta,
                    compact: true,
                    onClose: onClose
                )
                scopePicker
            }
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.top, 20)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch scope {
                    case .step:
                        stepList
                    case .recipe:
                        aisleRows(session.steps.indices.flatMap { lines(at: $0) })
                    }
                }
                .padding(.horizontal, SCCook.Spacing.page)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scScrollEdgeFade()
        }
    }

    /// „Ten krok”: składniki bieżącego kroku w działach sklepu z ikoną
    /// i kolorem alejki — jak w „Całym przepisie” (runda 9: „per krok też
    /// sortuj po kategoriach”; etykiety „Teraz” / „Za chwilę” i sekcja
    /// następnego kroku odpadły jako „totalnie niepotrzebne”). Krok bez
    /// składników nie zostawia pustego arkusza (runda 5) — od rundy 10
    /// cichy napis na środku (`CookStepNoIngredients`), bez karty, ptaszka
    /// i przycisku („minimalistycznie”); „Cały przepis” jest w przełączniku.
    @ViewBuilder
    private var stepList: some View {
        let now = lines(at: index)
        if now.isEmpty {
            CookStepNoIngredients(nextStep: nextStepWithIngredients)
                // Środek widocznej części arkusza (pół ekranu albo cały),
                // odrobinę nad połową — tam pada wzrok.
                .containerRelativeFrame(.vertical) { length, _ in length * 0.8 }
        } else {
            aisleRows(now)
        }
    }

    /// Numer (od 1) najbliższego dalszego kroku, który przynosi składniki.
    private var nextStepWithIngredients: Int? {
        session.steps.indices
            .first { $0 > index && !lines(at: $0).isEmpty }
            .map { $0 + 1 }
    }

    /// Działy sklepu z nagłówkiem (ikona i kolor alejki) i wierszami — ten
    /// sam strój w „Ten krok” i „Całym przepisie”.
    private func aisleRows(_ lines: [CookIngredientLine]) -> some View {
        ForEach(CookIngredientAisle.make(lines)) { aisle in
            CookSectionHeader(
                title: aisle.title,
                color: CookIngredientLook.color(aisle.department),
                count: aisle.lines.count,
                icon: CookIngredientLook.icon(aisle.department)
            )
            lineRows(aisle.lines)
        }
    }

    private func lineRows(_ lines: [CookIngredientLine]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.element.id) { offset, line in
            row(line)
            if offset < lines.count - 1 {
                Rectangle()
                    .fill(Color.scChipBg(scheme))
                    .frame(height: 1)
            }
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            // Jak plakietka na wyspie: składniki TEGO kroku (makieta: „Ten krok 4”).
            scopeSegment(.step, title: "Ten krok", count: lines(at: index).count)
            scopeSegment(.recipe, title: "Cały przepis", count: recipeCount)
        }
        .padding(4)
        .background(Capsule().fill(Color.scTileStroke(scheme)))
    }

    private func scopeSegment(_ value: Scope, title: String, count: Int) -> some View {
        let selected = scope == value
        return Button {
            withAnimation(.smooth(duration: 0.25)) { scope = value }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.sc(size: 14, weight: selected ? .bold : .semibold))
                Text("\(count)")
                    .font(.sc(size: 14, weight: selected ? .bold : .semibold))
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? Color.scLabel(scheme) : Color.scMuted(scheme))
            .frame(maxWidth: .infinity)
            .frame(height: SCCook.Height.segment)
            // Wybrany zakres = szklana soczewka na płaskim torze (Liquid
            // Glass runda 3), jak przełączniki iOS 26.
            .background {
                if selected {
                    Color.clear.scChromeGlass(in: Capsule())
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Wiersz: nazwa, podpis, ilość — bez ikony (dział mówi nagłówek
    /// sekcji). W „Ten krok” podpis to część składnika („połowa”), w „Całym
    /// przepisie” — krok, w którym wchodzi („teraz” w terakocie); składnik
    /// z kroku już za nami jest przygaszony, z ptaszkiem w podpisie.
    private func row(_ line: CookIngredientLine) -> some View {
        let dim = SCCook.Palette.caption(scheme)
        let stepIndex = session.steps.firstIndex { $0.id == line.stepId } ?? index
        let isDone = scope == .recipe && stepIndex < index
        let isNow = scope == .recipe && stepIndex == index
        let caption: String? = {
            guard scope == .recipe else { return line.partLabel }
            let when = isNow ? "teraz" : "krok \(stepIndex + 1)"
            return line.partLabel.map { "\(when) · \($0)" } ?? when
        }()
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.sc(size: 16, weight: .semibold))
                    .foregroundStyle(isDone ? dim : Color.scLabel(scheme))
                    .lineLimit(1)
                if let caption {
                    HStack(spacing: 4) {
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.sc(size: 10, weight: .heavy))
                                .accessibilityHidden(true)
                        }
                        Text(caption)
                    }
                    .font(.sc(size: 12, weight: isNow ? .semibold : .regular))
                    .foregroundStyle(isNow ? SCPalette.terracotta : dim)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(line.amountText)
                .font(.sc(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isDone ? dim : Color.scLabel(scheme))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: caption == nil ? SCCook.Height.ingredientRow : SCCook.Height.ingredientRow + 6)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? "już w daniu" : "")
    }
}

extension String {
    /// „Kotlety na patelni” → „kotlety na patelni” — do podpisu „Start: …”.
    var lowercasedFirst: String {
        guard let first else { return self }
        return String(first).lowercased(with: Locale(identifier: "pl_PL")) + dropFirst()
    }
}

/// Krok bez składników w arkuszu Składniki (runda 10: „minimalistycznie, bez
/// buttonów czy checków”): przygaszony koszyk, jedno zdanie i cichy dopisek,
/// kiedy wejdą następne. Nic do stuknięcia.
private struct CookStepNoIngredients: View {
    let nextStep: Int?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "basket")
                .font(.sc(size: 30, weight: .light))
                .foregroundStyle(Color.scFaint(scheme))
            Text("Ten krok bez składników")
                .font(.sc(size: 17, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .padding(.top, 14)
            Text(hint)
                .font(.sc(size: 14))
                .foregroundStyle(Color.scMuted(scheme))
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var hint: String {
        guard let nextStep else { return "Nowych składników już nie będzie" }
        return "Następne wchodzą w kroku \(nextStep)"
    }
}
