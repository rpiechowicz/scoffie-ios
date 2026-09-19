import SwiftUI

/// Wiersz „myślę" nad odpowiedzią — JEDEN widok na całe życie tury.
///
/// Wzorzec: ThoughtLine z React Bits. Głowa wiersza to glif, etykieta,
/// licznik i chevron; pod nią ślad kroków. W trakcie tury glif oddycha,
/// etykieta ma połysk, licznik tyka co dziesiątą sekundy, a ślad rośnie:
/// każdy kolejny krok wjeżdża z góry, poprzedni dostaje ptaszek, bieżący
/// pulsuje kropką. Gdy tura się domyka, NIC nie znika i nie wskakuje:
/// „Myślę…" przechodzi w „Myślałem" rozmyciem w miejscu, licznik zjeżdża
/// za nową etykietę, glif gaśnie do znaku, ślad zwija się pod chevron.
/// To dlatego jest jeden widok z dwiema fazami, a nie dwa widoki
/// z przenikaniem — przenikanie było podmianą pikseli, a to jest ruch.
///
/// Czas i faza ruchu liczą się z JEDNEGO zegara (`TimelineView` względem
/// epoki tury): żaden element nie ma własnego `@State` z pętlą, więc
/// przebudowy przy kolejnych krokach niczego nie zatrzymują ani nie
/// rozjeżdżają w fazie.
///
/// W slocie ostatniej tury `AssistantView` trzyma go w JEDNYM miejscu
/// drzewa od pierwszej klatki tury do końca życia odpowiedzi w slocie —
/// po następnym pytaniu odpowiedź przechodzi do części przed slotem
/// i tam ten sam wiersz (faza `settled`) rysuje `MessageBubble`.
struct AssistantThoughtLine: View {
    enum Phase: Equatable {
        /// Tura biegnie. `startedAt` = epoka zegara (oddech, połysk, licznik).
        case working(startedAt: Date, isStopping: Bool)
        /// Tura domknięta. `nil` = czasu nie dało się policzyć.
        case settled(duration: TimeInterval?)
    }

    let phase: Phase
    /// Kroki tury: na żywo wszystkie (z przejściowymi — „Czytam pytanie",
    /// „Piszę odpowiedź"), po turze tylko narzędzia i zapis.
    let steps: [AgentProgressStepDTO]
    /// Rozwinięcie śladu PO turze — stan trzyma ekran po id wiadomości,
    /// bo wiersz zmienia miejsce w drzewie (slot → część przed slotem).
    @Binding var isExpanded: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Ślad W TRAKCIE tury: ZWINIĘTY — na żywo głowa mówi jeden bieżący
    /// status („Sprawdzam plan tygodnia”), a pod nią stoi linia aktywności
    /// i opis kontekstu. Cała lista kroków jest pod chevronem, bo kilkanaście
    /// wierszy narastających pod pytaniem czytało się jak log, nie jak
    /// rozmowa. Po domknięciu decyduje `isExpanded`.
    @State private var isOpenWhileWorking = false
    @State private var showsPatience = false
    /// Jednorazowe wejście: nowy slot powstaje w NIEANIMOWANEJ transakcji
    /// (`.id(slotKey)`), więc `.transition` nie ma czego animować — wiersz
    /// wchodzi sam.
    @State private var appeared = false

    /// Po tylu sekundach warto powiedzieć, że nie trzeba tu siedzieć.
    private static let patienceAfter: TimeInterval = 18
    /// Osiadanie: rozmycie etykiety, zjazd licznika, zwinięcie śladu.
    private static let settleDuration: TimeInterval = 0.35
    /// Oddech glifu i puls kropki — jeden okres, żeby nie migały w kontrze.
    private static let breathPeriod: TimeInterval = 1.6
    private static let shimmerPeriod: TimeInterval = 1.8
    private static let glyphSize: CGFloat = 14
    /// Wcięcie śladu i linijki „Możesz wyjść": glif 14 + odstęp 8.
    private static let indent: CGFloat = 22

    // MARK: Stan pochodny

    private var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    private var isStopping: Bool {
        if case let .working(_, stopping) = phase { return stopping }
        return false
    }

    private var startedAt: Date? {
        if case let .working(start, _) = phase { return start }
        return nil
    }

    private var settledDuration: TimeInterval? {
        if case let .settled(duration) = phase { return duration }
        return nil
    }

    private var hasTrace: Bool { !steps.isEmpty }

    private var isOpen: Bool {
        hasTrace && (isWorking ? isOpenWhileWorking : isExpanded)
    }

    /// Planowanie trwa OD kroku z `phase` do końca — liczenie z ostatniego
    /// kroku cofało ton po pierwszym narzędziu planisty.
    private var inPlanning: Bool { steps.contains { $0.isHandoff } }
    /// Zapis to fakt, który się nie cofa.
    private var hasWritten: Bool { steps.contains { $0.writes == true } }

    /// Terakota → indygo (planista) → szałwia (zapisano); tylko w jedną stronę.
    private var accent: Color {
        if hasWritten { return SCPalette.sage }
        if inPlanning { return SCPalette.indigo }
        return SCPalette.terracotta
    }

    /// Etykieta głowy. Przy otwartym śladzie bieżący krok widać niżej,
    /// więc głowa mówi po prostu „Myślę…"; przy zwiniętym śladzie głowa
    /// przejmuje bieżący krok — zwinięcie nie ma odbierać informacji.
    private var workingLabel: String {
        if isStopping { return "Zatrzymuję…" }
        if isOpen { return "Myślę…" }
        return steps.last?.label ?? "Myślę…"
    }

    /// Kontekst pod statusem: z czego asystent właśnie korzysta, słowami
    /// z aplikacji („Przepisy · cele domowników · plan”), nigdy nazwami
    /// narzędzi. Liczone z KROKÓW, więc rośnie w miarę tury.
    private var contextDescriptor: String? {
        var parts: [String] = []
        for step in steps {
            let tool = step.tool.lowercased()
            let word: String?
            if tool.contains("recipe") || tool.contains("ingredient") {
                word = "przepisy"
            } else if tool.contains("household") || tool.contains("split") {
                word = "cele domowników"
            } else if tool.contains("shopping") {
                word = "zakupy"
            } else if tool.contains("memory") || tool.contains("note") {
                word = "pamięć domu"
            } else if tool.contains("plan") || tool.contains("balance") || tool.contains("conflict") || tool.contains("meal") || tool.contains("macro") {
                word = "plan"
            } else {
                word = nil
            }
            if let word, !parts.contains(word) { parts.append(word) }
        }
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: " · ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    private var settledLabel: String {
        settledDuration == nil ? "Myślałem chwilę" : "Myślałem"
    }

    private var activeLabel: String { isWorking ? workingLabel : settledLabel }

    private var settleAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: Self.settleDuration)
    }

    /// Rozmycie 2 pt + krycie, jak w pierwowzorze; przy Reduce Motion samo krycie.
    private var labelTransition: AnyTransition {
        reduceMotion ? .opacity : .blurFade(radius: 2)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -4)),
            removal: .opacity
        )
    }

    // MARK: Widok

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasTrace {
                Button { toggle() } label: { head }
                    .buttonStyle(.plain)
                    .accessibilityHint(isOpen ? "Zwija kroki" : "Pokazuje kroki")
                    .accessibilityValue("kroki: \(steps.count)")
            } else {
                // Bez kroków wiersz nie jest przyciskiem — przycisk, który
                // nic nie rozwija, jest gorszy niż brak przycisku.
                head
            }

            if isWorking {
                activity
                    .transition(.opacity)
            }

            if isOpen {
                trace
                    .transition(stepTransition)
            }

            if showsPatience, isWorking {
                Text("Możesz wyjść — wrócę z odpowiedzią.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scFaint(scheme))
                    .padding(.leading, Self.indent)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .onAppear { reveal() }
        // Raz na epokę tury; po domknięciu `startedAt` jest `nil` i linijka
        // znika razem z fazą. Sam się anuluje, gdy wiersz schodzi.
        .task(id: startedAt) {
            showsPatience = false
            guard let startedAt else { return }
            let wait = Self.patienceAfter - Date().timeIntervalSince(startedAt)
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.4)) { showsPatience = true }
        }
        // VoiceOver słyszy zmianę ETAPU (planista, zapis) i koniec tury —
        // nie każdy krok, bo kroków bywa kilkanaście.
        .onChange(of: inPlanning) { _, now in
            if now, let label = steps.last?.label { announce(label) }
        }
        .onChange(of: hasWritten) { _, now in
            if now, let label = steps.last?.label { announce(label) }
        }
        .onChange(of: isWorking) { _, working in
            if !working { announce(settledAnnouncement) }
        }
    }

    /// Glif · etykieta · licznik · chevron. Jeden zegar dla całej głowy;
    /// po domknięciu zegar STAJE (`paused`) i nic już tu nie tyka.
    private var head: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isWorking)) { context in
            let t = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            HStack(alignment: .center, spacing: 8) {
                glyph(t: t)

                HStack(alignment: .center, spacing: 5) {
                    label(t: t)
                    timer(t: t)
                    chevron
                }
                .layoutPriority(1)

                Spacer(minLength: 0)
            }
            .frame(height: 22)
            // Osiadanie i zmiana etykiety w JEDNEJ transakcji na całej głowie:
            // etykieta zmienia szerokość, licznik ZJEŻDŻA za nią (ruch układu
            // animuje się tylko, gdy transakcja rodzica jest animowana — sam
            // modyfikator na etykiecie zostawiłby licznik ze skokiem).
            .animation(settleAnimation, value: activeLabel)
            .animation(settleAnimation, value: isWorking)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isWorking ? workingLabel : settledAnnouncement)
        .accessibilityAddTraits(accessibilityTraits)
    }

    /// Linia aktywności i opis kontekstu pod statusem.
    ///
    /// To NIE jest pasek postępu: nie ma procentu i nigdy nie „dojeżdża”
    /// do końca — jest samym sygnałem, że coś się dzieje, w kolorze etapu.
    /// Przy Reduce Motion podświetlenie stoi (bez przesuwającego się pasma).
    private var activity: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isWorking)) { context in
            let t = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            VStack(alignment: .leading, spacing: 6) {
                AssistantActivityLine(t: t, color: accent, still: reduceMotion)
                if let contextDescriptor {
                    Text(contextDescriptor)
                        .font(.system(size: 12))
                        .tracking(-0.1)
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .padding(.leading, Self.indent)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.25), value: contextDescriptor)
        }
        .accessibilityHidden(true)
    }

    /// Jawny typ: `[]` i `.updatesFrequently` w jednym wyrażeniu warunkowym
    /// nie mają skąd wziąć typu bez podpowiedzi.
    private var accessibilityTraits: AccessibilityTraits {
        isWorking ? .updatesFrequently : []
    }

    /// Oddychający znak w trakcie tury; po domknięciu ten sam znak, cichy.
    /// Przenikanie w miejscu: kolor etapu gaśnie do `scFaint`.
    @ViewBuilder
    private func glyph(t: TimeInterval) -> some View {
        ZStack {
            if isWorking {
                SCThinkingGlyph(
                    t: t,
                    color: accent,
                    size: Self.glyphSize,
                    still: reduceMotion,
                    period: Self.breathPeriod
                )
                .transition(.opacity)
            } else {
                SCMarkShape()
                    .fill(Color.scFaint(scheme))
                    .frame(width: Self.glyphSize, height: Self.glyphSize)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.glyphSize, height: Self.glyphSize)
        .accessibilityHidden(true)
    }

    /// Etykieta w dwóch warstwach: NIEWIDOCZNY tekst bieżącej etykiety
    /// wymiaruje wiersz (to on przesuwa licznik), a nakładka rysuje stary
    /// i nowy tekst jeden na drugim — stary rozmywa się i gaśnie, nowy
    /// wyostrza. Nakładka nie liczy się do układu, więc wiersz nie trzyma
    /// szerokości schodzącego tekstu do końca przejścia. Oba teksty mają
    /// ten sam krój i to samo ucięcie (`lineLimit(1)`, bez `fixedSize`), więc
    /// w stanie spoczynku nakładka pokrywa się z wymiarującym tekstem co do
    /// punktu, a długi krok („Składam tydzień tak, żeby…") ucina się tak samo
    /// w obu i nigdy nie wchodzi pod licznik.
    private func label(t: TimeInterval) -> some View {
        Text(activeLabel)
            .font(.system(size: 15))
            .lineLimit(1)
            .opacity(0)
            .accessibilityHidden(true)
            .overlay(alignment: .leading) {
                ZStack(alignment: .leading) {
                    if isWorking {
                        SCShimmerText(
                            text: workingLabel,
                            t: t,
                            still: reduceMotion,
                            period: Self.shimmerPeriod
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .id("work|" + workingLabel)
                        .transition(labelTransition)
                    } else {
                        Text(settledLabel)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.scMuted(scheme))
                            .lineLimit(1)
                            .id("done|" + settledLabel)
                            .transition(labelTransition)
                    }
                }
                .animation(settleAnimation, value: activeLabel)
            }
    }

    /// Licznik od pierwszej dziesiątej sekundy — jak w pierwowzorze: cyfry
    /// stałej szerokości, bez rolowania (dziesięć zmian na sekundę z animacją
    /// byłoby smugą). Po domknięciu ten sam licznik zostaje z czasem z serwera
    /// i ciemnieje o stopień: to już fakt, nie sygnał życia.
    @ViewBuilder
    private func timer(t: TimeInterval) -> some View {
        if let text = timerText(t: t) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isWorking ? Color.scFaint(scheme) : Color.scMuted(scheme))
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    private func timerText(t: TimeInterval) -> String? {
        switch phase {
        case .working:
            return Self.clock(t)
        case let .settled(duration):
            return duration.map(Self.clock)
        }
    }

    /// Chevron tylko, gdy jest co rozwinąć; obraca się o 180° przy otwarciu.
    private var chevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.scFaint(scheme))
            .rotationEffect(.degrees(isOpen ? 180 : 0))
            .opacity(hasTrace ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: isOpen)
            .animation(.easeOut(duration: 0.2), value: hasTrace)
            .accessibilityHidden(true)
    }

    /// Ślad kroków. Tożsamość po pozycji: serwer tylko dopisuje, więc nowy
    /// krok to nowa pozycja (wjeżdża z góry), a poprzednia zostaje i dostaje
    /// ptaszek w miejscu. Osobny, wolniejszy zegar — tylko dla pulsu kropki.
    private var trace: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion || !isWorking)) { context in
            let t = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    let done = !isWorking || index < steps.count - 1
                    HStack(alignment: .center, spacing: 8) {
                        mark(done: done, t: t)
                        Text(step.label)
                            .font(.system(size: 13))
                            .foregroundStyle(stepColor(step, done: done))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(stepTransition)
                }
            }
            .padding(.leading, Self.indent)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .animation(.easeOut(duration: 0.2), value: steps.count)
        }
        .accessibilityHidden(true)
    }

    /// Ptaszek po kroku; pulsująca kropka w kolorze etapu przy bieżącym.
    @ViewBuilder
    private func mark(done: Bool, t: TimeInterval) -> some View {
        ZStack {
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            } else {
                let pulse = reduceMotion
                    ? 1.0
                    : 0.55 + 0.45 * (1 - cos(t * 2 * .pi / Self.breathPeriod)) / 2
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .opacity(pulse)
                    .transition(.opacity)
            }
        }
        .frame(width: Self.glyphSize, height: Self.glyphSize)
        .animation(.easeOut(duration: 0.2), value: done)
    }

    /// Zrobione kroki gasną do `scFaint`; bieżący jest o stopień jaśniejszy.
    /// Tony etapów zostają w obu: szałwia = zapis, indygo = planista.
    private func stepColor(_ step: AgentProgressStepDTO, done: Bool) -> Color {
        if step.writes == true { return SCPalette.sage.opacity(done ? 0.75 : 1) }
        if step.isHandoff { return SCPalette.indigo.opacity(done ? 0.75 : 1) }
        return done ? Color.scFaint(scheme) : Color.scMuted(scheme)
    }

    // MARK: Akcje i teksty

    /// `withAnimation`, nie `.animation(value:)`: rozwinięcie ZMIENIA układ
    /// sąsiadów w `LazyVStack`, a modyfikator na samym wierszu tego nie obejmie.
    private func toggle() {
        guard hasTrace else { return }
        withAnimation(settleAnimation) {
            if isWorking {
                isOpenWhileWorking.toggle()
            } else {
                isExpanded.toggle()
            }
        }
    }

    private func reveal() {
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    private var settledAnnouncement: String {
        guard let duration = settledDuration else { return "Myślałem chwilę" }
        return "Myślałem \(Self.spoken(duration))"
    }

    /// „12,3 s", od minuty „1 min 12,3 s" — dziesiąte, jak w pierwowzorze,
    /// z polskim przecinkiem.
    static func clock(_ seconds: TimeInterval) -> String {
        let tenths = max(0, Int((seconds * 10).rounded(.down)))
        if tenths < 600 { return "\(tenths / 10),\(tenths % 10) s" }
        let minutes = tenths / 600
        let rest = tenths % 600
        return "\(minutes) min \(rest / 10),\(rest % 10) s"
    }

    /// Dla VoiceOver: bez dziesiątych, pełnymi słowami.
    static func spoken(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        if whole < 60 { return "\(whole) sekund" }
        let minutes = whole / 60
        let rest = whole % 60
        return rest == 0 ? "\(minutes) minut" : "\(minutes) minut \(rest) sekund"
    }
}

// MARK: - Linia aktywności

/// Cienka linia z pasmem światła, które płynie od lewej do prawej — czysta
/// funkcja czasu `t` od rodzica, bez własnego zegara. Faza liniowa: easing
/// robiłby z płynięcia „pulsowanie”. Pasmo zaczyna i kończy poza linią, więc
/// zawinięcie cyklu jest niewidoczne.
struct AssistantActivityLine: View {
    let t: TimeInterval
    let color: Color
    var still: Bool = false
    var period: TimeInterval = 1.9

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let phase = t.truncatingRemainder(dividingBy: period) / period
        let p = -0.5 + phase * 2.0
        Capsule()
            .fill(Color.scBarTrack(scheme))
            .frame(height: 2)
            .overlay {
                if still {
                    Capsule().fill(color.opacity(0.5))
                } else {
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: color.opacity(0), location: 0),
                                    .init(color: color, location: 0.5),
                                    .init(color: color.opacity(0), location: 1),
                                ],
                                startPoint: UnitPoint(x: p - 0.3, y: 0.5),
                                endPoint: UnitPoint(x: p + 0.3, y: 0.5)
                            )
                        )
                }
            }
            .frame(maxWidth: 160)
            .animation(.smooth(duration: 0.5), value: color)
    }
}

// MARK: - Przejście z rozmyciem

/// Krycie + rozmycie, jak `filter: blur()` w pierwowzorze: tekst nie tyle
/// znika, ile traci ostrość, a nowy ją zyskuje — dwa zdania w tym samym
/// miejscu przestają być dwoma zdaniami.
private struct BlurFadeModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static func blurFade(radius: CGFloat = 2) -> AnyTransition {
        .modifier(
            active: BlurFadeModifier(radius: radius, opacity: 0),
            identity: BlurFadeModifier(radius: 0, opacity: 1)
        )
    }
}

#Preview("Wiersz tury") {
    struct Demo: View {
        @State private var expanded = false
        @State private var working = true
        private let steps = [
            AgentProgressStepDTO(tool: "read", label: "Czytam pytanie", at: "2026-09-19T10:00:00.000Z", writes: nil, phase: nil, transient: true),
            AgentProgressStepDTO(tool: "get_week_plan", label: "Czytam plan tygodnia", at: "2026-09-19T10:00:02.000Z", writes: false, phase: nil, transient: nil),
            AgentProgressStepDTO(tool: "start_planning", label: "Biorę się za plan", at: "2026-09-19T10:00:05.000Z", writes: nil, phase: "PLANNING", transient: nil),
            AgentProgressStepDTO(tool: "apply_week_plan", label: "Zapisuję plan tygodnia", at: "2026-09-19T10:00:09.000Z", writes: true, phase: nil, transient: nil),
            AgentProgressStepDTO(tool: "write", label: "Piszę odpowiedź", at: "2026-09-19T10:00:12.000Z", writes: nil, phase: nil, transient: true),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                AssistantThoughtLine(
                    phase: working
                        ? .working(startedAt: Date().addingTimeInterval(-7), isStopping: false)
                        : .settled(duration: 12.3),
                    steps: working ? steps : steps.filter { !$0.isTransient },
                    isExpanded: $expanded
                )
                Toggle("Tura biegnie", isOn: $working)
            }
            .padding(24)
            .animation(.easeOut(duration: 0.35), value: working)
        }
    }
    return Demo()
}
