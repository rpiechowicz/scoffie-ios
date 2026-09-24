import SwiftUI

/// Wiersz tury — 1:1 z makietą „Stan pracy · finał: Oddech łuku”
/// (`MWorking`) i „14 · Thought summary” (`LThought`).
///
/// W TRAKCIE tury (poprawka 21.09.2026): dziennik w JEDNEJ kolumnie,
/// od góry — najpierw ślad zrobionych kroków (ptaszek + zdanie, do ośmiu
/// ostatnich; zapis ma ptaszek w szałwii), POD nim bieżący krok: łuk 18 pt
/// (obrót 2,4 s, oddech 5 → 55 % obwodu 1,8 s, nigdy zamknięty), status
/// 15/600 z przebłyskiem i realny licznik sekund po prawej. Kolumna ikon ma
/// szerokość znaku marki przy odpowiedzi (18 + 10 pt), więc ptaszki, łuk
/// i tekst stoją w liniach odpowiedzi. Po 18 s pod statusem, wcięte do
/// tekstu: „Możesz wyjść — wrócę z odpowiedzią.”. Łuk i status w TERAKOCIE
/// (decyzja Rafała 21.09.2026). Bez paska, procentu i nazw narzędzi.
///
/// PO turze (`LThought`): „Myślałem 42 s” z chevronem, wcięte pod tekst
/// odpowiedzi (28 pt); licznik z wiersza pracy STAJE SIĘ tą liczbą.
/// Po rozwinięciu kroki jako kropka + zdanie po ludzku.
///
/// Zatrzymane (`MStopped`): łuk znika, zostaje cichy pierścień i szary znak.
struct AssistantThoughtLine: View {
    enum Phase: Equatable {
        /// Tura biegnie. `startedAt` = epoka zegara.
        case working(startedAt: Date, isStopping: Bool)
        /// Tura domknięta. `nil` = czasu nie dało się policzyć.
        case settled(duration: TimeInterval?)
    }

    let phase: Phase
    /// Kroki tury: na żywo wszystkie (bieżący status = ostatni), po turze
    /// tylko narzędzia i zapis.
    let steps: [AgentProgressStepDTO]
    /// Rozwinięcie kroków PO turze — stan trzyma ekran po id wiadomości.
    @Binding var isExpanded: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPatience = false
    @State private var appeared = false

    /// Po tylu sekundach warto powiedzieć, że nie trzeba tu siedzieć.
    private static let patienceAfter: TimeInterval = 18

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

    /// Zapis to fakt, który się nie cofa.
    private var hasWritten: Bool { steps.contains { $0.writes == true } }

    /// Kolor pracy: terakota marki — ten sam co znak w środku pierścienia,
    /// więc łuk, status i znak czytają się jako jedna rzecz. (Indygo/szałwia
    /// z makiety wyglądały w aplikacji jak obcy element.) Zapis wyróżnia
    /// szałwiowy ptaszek w śladzie kroków, nie zmiana koloru całości.
    private var phaseColor: Color { AssistantLook.terra(scheme) }

    /// Jeden bieżący status — ostatni krok z serwera, gotowe zdanie po polsku.
    private var status: String {
        if isStopping { return "Zatrzymuję…" }
        return steps.last?.label ?? "Już się tym zajmuję"
    }

    /// Ślad pod statusem: co asystent JUŻ zrobił w tej turze. Wszystko przed
    /// bieżącym krokiem, bez powtórzeń pod rząd. Do 23.09.2026 na ekranie
    /// stały trzy ostatnie (z bieżącym — cztery pozycje) i dłuższa tura
    /// gubiła, co już sprawdzono. Osiem mieści całe planowanie tygodnia;
    /// dopiero dłuższy ślad przesuwa się, a najstarszy widoczny przygasa.
    ///
    /// Kolejność DOPISYWANIA (24.09.2026, Rafał: „checked zmieniają się
    /// miejscami”): ślad rośnie tylko w dół. Dawniej wiersz znikał, gdy bieżący
    /// krok miał to samo zdanie (serwer przeplata przejściowe „Zastanawiam
    /// się…” z narzędziami), i wracał w starym miejscu przy następnym kroku —
    /// lista przeskakiwała pod okiem. Teraz: kroki przejściowe (`transient`,
    /// „teraz”, nie etap) nigdy nie wchodzą do śladu, każde zdanie stoi raz,
    /// w miejscu PIERWSZEGO pojawienia się, a id to samo zdanie — powtórzone
    /// narzędzie nie przestawia wiersza.
    private struct DoneStep: Identifiable, Equatable {
        let id: String
        let label: String
        let wrote: Bool
    }

    private static let trailLimit = 8

    private var doneSteps: [DoneStep] {
        guard !isStopping, steps.count > 1 else { return [] }
        var result: [DoneStep] = []
        var seen: [String: Int] = [:]
        for step in steps.dropLast() where !step.isTransient {
            if let at = seen[step.label] {
                // Ten sam krok jeszcze raz: zostaje na swoim miejscu, tylko
                // zapis (szałwia) może go „awansować”.
                if step.writes == true, !result[at].wrote {
                    result[at] = DoneStep(id: step.label, label: step.label, wrote: true)
                }
                continue
            }
            seen[step.label] = result.count
            result.append(DoneStep(id: step.label, label: step.label, wrote: step.writes == true))
        }
        return Array(result.suffix(Self.trailLimit))
    }

    private var settledLabel: String {
        guard let duration = settledDuration else { return "Myślałem chwilę" }
        return "Myślałem \(Self.clock(duration))"
    }

    private var hasTrace: Bool { !steps.isEmpty }

    // MARK: Widok

    var body: some View {
        Group {
            if isWorking {
                working
            } else {
                thought
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .onAppear { reveal() }
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
        .onChange(of: hasWritten) { _, now in
            if now, let label = steps.last?.label { announce(label) }
        }
        .onChange(of: isWorking) { _, working in
            if !working { announce(settledLabel) }
        }
    }

    // MARK: Praca

    /// Kolumna ikon: tyle, ile znak marki przy odpowiedzi (`AssistantVoice`,
    /// 18 pt + 10 pt odstępu). Ptaszki, łuk i tekst stoją w tych samych
    /// liniach co odpowiedź, która za chwilę pojawi się pod spodem.
    private static let iconColumn: CGFloat = 18
    private static let iconGap: CGFloat = 10
    /// Wspólna wysokość wiersza — ślad i bieżący status mają jeden rytm.
    private static let rowHeight: CGFloat = 22

    /// Dziennik tury, od góry: to, co JUŻ zrobione (ptaszki), a pod spodem
    /// to, co dzieje się teraz (łuk + status + sekundy). Nowy krok przesuwa
    /// bieżący status w dół, a stary staje się ptaszkiem nad nim — czyta się
    /// jak lista, która rośnie, a nie jak napis, pod którym coś się dzieje.
    private var working: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || isStopping)) { context in
            let t = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            VStack(alignment: .leading, spacing: 6) {
                ForEach(doneSteps) { step in
                    doneRow(step, isOldest: step.id == doneSteps.first?.id && doneSteps.count == Self.trailLimit)
                        .transition(doneTransition)
                }

                currentRow(t: t)

                if isStopping {
                    Text("Nic nie zmieniłem w planie.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .padding(.leading, Self.iconColumn + Self.iconGap)
                        .transition(.opacity)
                }

                if showsPatience, !isStopping {
                    Text("Możesz wyjść — wrócę z odpowiedzią.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .padding(.leading, Self.iconColumn + Self.iconGap)
                        .padding(.top, 2)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4), value: status)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4), value: doneSteps)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Bieżący krok: łuk w kolumnie ikon, status z przebłyskiem, sekundy
    /// po prawej — wszystko na jednej osi.
    private func currentRow(t: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: Self.iconGap) {
            glyph(t: t)
                .frame(width: Self.iconColumn, height: Self.iconColumn)

            ZStack(alignment: .leading) {
                // Zmiana stanu: stary status odpływa w górę, nowy wpływa od
                // dołu — widać, że COŚ się stało, a nie że podmienił się napis.
                statusText(t: t)
                    .id(status)
                    .transition(statusTransition)
            }
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            .clipped()

            if !isStopping {
                // Sekundy rolują się jak czas w szczegółach posiłku.
                SCRollingNumber(value: Int(t), unit: "s")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: Self.rowHeight)
    }

    private var statusTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity.combined(with: .offset(y: -10))
        )
    }

    private var doneTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: -6))
        )
    }

    /// Zrobiony krok: ptaszek + zdanie. Zapis ma ptaszek w szałwii — to
    /// jedyny krok, który coś zmienił. Gdy ślad jest pełny, najstarszy
    /// przygasa, żeby było widać, że lista się przesuwa, a nie urywa.
    private func doneRow(_ step: DoneStep, isOldest: Bool) -> some View {
        HStack(alignment: .center, spacing: Self.iconGap) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(step.wrote ? AssistantLook.sage(scheme) : AssistantLook.terra(scheme).opacity(0.75))
                .frame(width: Self.iconColumn, height: Self.iconColumn)
            Text(step.label)
                .font(.system(size: 13.5))
                .foregroundStyle(AssistantLook.muted(scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Self.rowHeight)
        .opacity(isOldest ? 0.55 : 1)
    }

    /// `SpinDash` 44: pierścień-tor w tincie fazy (12 %), łuk w kolorze fazy
    /// krąży i oddycha wokół NIERUCHOMEGO znaku w terakocie (22 pt = 50 %).
    /// Zatrzymane: łuk znika, tor szarzeje, znak szary.
    private func glyph(t: TimeInterval) -> some View {
        AssistantArcSpinner(
            size: Self.iconColumn,
            color: phaseColor,
            t: t,
            stopped: isStopping,
            still: reduceMotion
        )
    }

    /// Status 16/600 z połyskiem w kolorze fazy (`lShimmer` 2,6 s).
    @ViewBuilder
    private func statusText(t: TimeInterval) -> some View {
        if isStopping {
            Text(status)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(AssistantLook.muted(scheme))
                .lineLimit(1)
        } else if reduceMotion {
            Text(status)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(phaseColor)
                .lineLimit(1)
        } else {
            let phase = t.truncatingRemainder(dividingBy: 2.6) / 2.6
            let p = 1.2 - phase * 2.4
            Text(status)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)
                .lineLimit(1)
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: phaseColor, location: 0),
                            .init(color: phaseColor, location: 0.35),
                            .init(color: phaseColor.opacity(0.4), location: 0.5),
                            .init(color: phaseColor, location: 0.65),
                            .init(color: phaseColor, location: 1),
                        ],
                        startPoint: UnitPoint(x: p - 1.2, y: 0.5),
                        endPoint: UnitPoint(x: p + 1.2, y: 0.5)
                    )
                )
        }
    }

    // MARK: Po turze

    private var thought: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if hasTrace {
                    Button {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35)) {
                            isExpanded.toggle()
                        }
                    } label: { thoughtHead }
                    .buttonStyle(.plain)
                    .accessibilityHint(isExpanded ? "Zwija kroki" : "Pokazuje kroki")
                    .accessibilityValue("kroki: \(steps.count)")
                } else {
                    thoughtHead
                }
            }

            if isExpanded, hasTrace {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .center, spacing: 9) {
                            Circle()
                                .fill(AssistantLook.ink(scheme).opacity(0.35))
                                .frame(width: 4, height: 4)
                            Text(step.label)
                                .font(.system(size: 13))
                                .foregroundStyle(AssistantLook.faint(scheme))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -4)))
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, 28)
    }

    private var thoughtHead: some View {
        HStack(spacing: 2) {
            Text(settledLabel)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AssistantLook.faint(scheme))
                .lineLimit(1)
            if hasTrace {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AssistantLook.faint(scheme))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeOut(duration: 0.2), value: isExpanded)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settledLabel)
    }

    // MARK: Akcje i teksty

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

    /// „42 s”, od minuty „1 min 12 s” — całe sekundy, jak na makiecie.
    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds.rounded()))
        if whole < 60 { return "\(whole) s" }
        let minutes = whole / 60
        let rest = whole % 60
        return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
    }
}

// MARK: - Oddech łuku

/// `SpinDash` z makiety w trzech rozmiarach: 44 (wiersz statusu), 28
/// (kapsułka), 20 (inline). Grubość łuku = 6,8 % rozmiaru (3 pt przy 44,
/// 2 pt przy 28), znak = 40 % rozmiaru (makieta ma 50 %, ale na telefonie
/// znak wypełniał pierścień i zlewał się z łukiem), tor = kolor fazy 22 %
/// — na ciemnym tle 12 % ginęło i pierścień wyglądał na szary.
///
/// Dwa niezależne rytmy, jak w CSS: obrót całego łuku 2,4 s liniowo
/// (`spArc`) i „oddech” 1,8 s ease-in-out (`spDash`: dasharray 6 → 70 → 6
/// z 126, offset 0 → −30 → −126), więc łuk rośnie do ok. 55 % obwodu, kurczy
/// się do kropki i przy tym przesuwa się po torze. Nigdy się nie zamyka.
/// Czas `t` przychodzi z zewnątrz (jeden `TimelineView` na wiersz), żeby
/// łuk, licznik i przebłysk statusu szły z tego samego zegara.
///
/// Reduce Motion: łuk stoi na 30 % obwodu. `stopped`: łuk znika, zostaje
/// szary tor i szary znak (`MStopped`).
struct AssistantArcSpinner: View {
    var size: CGFloat = 44
    let color: Color
    let t: TimeInterval
    var stopped: Bool = false
    var still: Bool = false

    @Environment(\.colorScheme) private var scheme

    private var lineWidth: CGFloat { max(2, (size * 0.068).rounded()) }

    var body: some View {
        let arc = Self.arc(at: t, still: still)
        ZStack {
            Circle()
                .stroke(stopped ? AssistantLook.ink(scheme).opacity(0.10) : color.opacity(0.22), lineWidth: lineWidth)
            if !stopped {
                Circle()
                    .trim(from: 0, to: arc.length)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(arc.start * 360))
            }
            // Poniżej 20 pt znak w środku to kilka punktów szumu — w wierszu
            // tury (18 pt) łuk mówi sam za siebie.
            if size >= 20 {
                SCMarkShape()
                    .fill(stopped ? AssistantLook.ink(scheme).opacity(0.35) : AssistantLook.terraFill(scheme))
                    .frame(width: (size * 0.4).rounded(), height: (size * 0.4).rounded())
            }
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Początek łuku (ułamek obwodu, rośnie zgodnie z ruchem wskazówek)
    /// i jego długość (ułamek obwodu).
    static func arc(at t: TimeInterval, still: Bool) -> (start: Double, length: Double) {
        if still { return (start: -0.25, length: 0.30) }
        let spin = t.truncatingRemainder(dividingBy: 2.4) / 2.4
        let breath = t.truncatingRemainder(dividingBy: 1.8) / 1.8
        let dash: Double
        let shift: Double
        if breath < 0.5 {
            let e = easeInOut(breath / 0.5)
            dash = 6 + 64 * e
            shift = 30 * e
        } else {
            let e = easeInOut((breath - 0.5) / 0.5)
            dash = 70 - 64 * e
            shift = 30 + 96 * e
        }
        return (start: spin + shift / 126, length: dash / 126)
    }

    /// `ease-in-out` (`cubic-bezier(.42,0,.58,1)`) — przybliżenie.
    private static func easeInOut(_ p: Double) -> Double {
        p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
    }
}

// MARK: - Przejście z rozmyciem

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
            AgentProgressStepDTO(tool: "read", label: "Już się tym zajmuję", at: "2026-09-19T10:00:00.000Z", writes: nil, phase: nil, transient: true),
            AgentProgressStepDTO(tool: "get_week_plan", label: "Sprawdzam plan tygodnia", at: "2026-09-19T10:00:02.000Z", writes: false, phase: nil, transient: nil),
            AgentProgressStepDTO(tool: "start_planning", label: "Układam propozycję tygodnia", at: "2026-09-19T10:00:05.000Z", writes: nil, phase: "PLANNING", transient: nil),
            AgentProgressStepDTO(tool: "apply_week_plan", label: "Zapisuję plan tygodnia", at: "2026-09-19T10:00:09.000Z", writes: true, phase: nil, transient: nil),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                AssistantThoughtLine(
                    phase: working
                        ? .working(startedAt: Date().addingTimeInterval(-7), isStopping: false)
                        : .settled(duration: 42),
                    steps: working ? steps : steps.filter { !$0.isTransient },
                    isExpanded: $expanded
                )
                Toggle("Tura biegnie", isOn: $working)
            }
            .padding(24)
        }
    }
    return Demo()
}
