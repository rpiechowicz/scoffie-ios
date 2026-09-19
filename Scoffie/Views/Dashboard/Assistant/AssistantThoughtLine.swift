import SwiftUI

/// Wiersz tury — 1:1 z makietą „Stan pracy · finał: Oddech łuku”
/// (`MWorking`) i „14 · Thought summary” (`LThought`).
///
/// W TRAKCIE tury: znak marki stoi NIERUCHOMO w terakocie w środku
/// pierścienia 44 pt, a wokół niego krąży łuk w kolorze fazy (indygo dla
/// analizy i planowania, szałwia dla zapisu) — obrót 2,4 s liniowo, a łuk
/// jednocześnie „oddycha” 1,8 s: rośnie od kropki (5 % obwodu) do ok. 55 %
/// i kurczy się z powrotem. Obwód nigdy się nie zamyka — to aktywność, nie
/// postęp. Obok JEDEN bieżący status (16/600, przebłysk w kolorze fazy
/// 2,6 s), po prawej realny licznik sekund, pod statusem kontekst słowami
/// z aplikacji, a po 18 s „Możesz wyjść — wrócę z odpowiedzią.”. Bez paska,
/// bez procentu, bez listy kroków i bez nazw narzędzi.
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

    /// Kolor fazy: analiza i planowanie w indygo, zapis w szałwii.
    private var phaseColor: Color {
        hasWritten ? AssistantLook.sage(scheme) : AssistantLook.indigo(scheme)
    }

    /// Jeden bieżący status — ostatni krok z serwera, gotowe zdanie po polsku.
    private var status: String {
        if isStopping { return "Zatrzymuję…" }
        return steps.last?.label ?? "Czytam pytanie"
    }

    /// Kontekst pod statusem: z czego asystent właśnie korzysta, słowami
    /// z aplikacji („Przepisy · cele domowników · plan”), nigdy nazwami
    /// narzędzi. Liczone z KROKÓW, więc rośnie w miarę tury.
    private var contextDescriptor: String? {
        if isStopping { return "Nic nie zmieniłem w planie." }
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

    private var working: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || isStopping)) { context in
            let t = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            // Wyśrodkowane w pionie: bez kontekstu pod statusem sam status
            // wisiał przy górnej krawędzi 44-punktowego pierścienia.
            HStack(alignment: .center, spacing: 14) {
                glyph(t: t)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        statusText(t: t)
                        Spacer(minLength: 0)
                        if !isStopping {
                            // Sekundy rolują się jak czas w szczegółach posiłku.
                            SCRollingNumber(value: Int(t), unit: "s")
                                .font(.system(size: 12.5))
                                .foregroundStyle(AssistantLook.faint(scheme))
                                .fixedSize()
                                .accessibilityHidden(true)
                        }
                    }

                    if let contextDescriptor {
                        Text(contextDescriptor)
                            .font(.system(size: 13.5))
                            .foregroundStyle(AssistantLook.muted(scheme))
                            .lineLimit(1)
                            .padding(.top, 3)
                            .transition(.opacity)
                    }

                    if showsPatience, !isStopping {
                        Text("Możesz wyjść — wrócę z odpowiedzią.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(AssistantLook.faint(scheme))
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: contextDescriptor)
                .animation(.easeInOut(duration: 0.25), value: status)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// `SpinDash` 44: pierścień-tor w tincie fazy (12 %), łuk w kolorze fazy
    /// krąży i oddycha wokół NIERUCHOMEGO znaku w terakocie (22 pt = 50 %).
    /// Zatrzymane: łuk znika, tor szarzeje, znak szary.
    private func glyph(t: TimeInterval) -> some View {
        AssistantArcSpinner(
            size: 44,
            color: phaseColor,
            t: t,
            stopped: isStopping,
            still: reduceMotion
        )
        .animation(.smooth(duration: 0.5), value: hasWritten)
    }

    /// Status 16/600 z połyskiem w kolorze fazy (`lShimmer` 2,6 s).
    @ViewBuilder
    private func statusText(t: TimeInterval) -> some View {
        if isStopping {
            Text(status)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(AssistantLook.muted(scheme))
                .lineLimit(1)
        } else if reduceMotion {
            Text(status)
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(phaseColor)
                .lineLimit(1)
        } else {
            let phase = t.truncatingRemainder(dividingBy: 2.6) / 2.6
            let p = 1.2 - phase * 2.4
            Text(status)
                .font(.system(size: 16, weight: .semibold))
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
                .animation(.smooth(duration: 0.5), value: hasWritten)
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
            SCMarkShape()
                .fill(stopped ? AssistantLook.ink(scheme).opacity(0.35) : AssistantLook.terraFill(scheme))
                .frame(width: (size * 0.4).rounded(), height: (size * 0.4).rounded())
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
            AgentProgressStepDTO(tool: "read", label: "Czytam pytanie", at: "2026-09-19T10:00:00.000Z", writes: nil, phase: nil, transient: true),
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
