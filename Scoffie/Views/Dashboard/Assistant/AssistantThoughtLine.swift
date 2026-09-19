import SwiftUI

/// Wiersz tury — 1:1 z makietą „2 · Asystent pracuje” i „14 · Thought summary”.
///
/// W TRAKCIE tury (`LWorking`): znak marki orbituje w pulsującej poświacie
/// 44 pt, obok JEDEN bieżący status (16/600, połysk w kolorze fazy — indygo
/// dla analizy i planowania, szałwia dla zapisu), po prawej realny czas
/// w całych sekundach, pod statusem kontekst trzema słowami, niżej pasek
/// aktywności NIEOKREŚLONY (sunie, nie pokazuje procentu), a po 18 s zdanie
/// „Możesz wyjść — wrócę z odpowiedzią.”. Żadnej listy ukończonych kroków:
/// status zmienia się w miejscu.
///
/// PO turze (`LThought`): „Myślałem 42 s” z chevronem, wcięte pod tekst
/// odpowiedzi (28 pt), a po rozwinięciu kroki jako kropka + zdanie po
/// ludzku — wgląd dla ciekawych, nie log.
///
/// Zatrzymane przez użytkownika: szary znak, bez poświaty i bez paska.
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

    private var phaseTint: Color {
        hasWritten ? AssistantLook.sageTint(scheme) : AssistantLook.indigoTint(scheme)
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
            HStack(alignment: .top, spacing: 14) {
                glyph(t: t)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        statusText(t: t)
                        Spacer(minLength: 0)
                        if !isStopping {
                            Text("\(Int(t)) s")
                                .font(.system(size: 12.5))
                                .monospacedDigit()
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

                    if !isStopping {
                        AssistantActivityLine(t: t, color: phaseColor, tint: phaseTint, still: reduceMotion)
                            .padding(.top, 12)
                    }

                    if showsPatience, !isStopping {
                        Text("Możesz wyjść — wrócę z odpowiedzią.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(AssistantLook.faint(scheme))
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                }
                .padding(.top, 1)
                .animation(.easeInOut(duration: 0.25), value: contextDescriptor)
                .animation(.easeInOut(duration: 0.25), value: status)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Znak marki 26 pt orbituje w poświacie 44 pt (`kesHalo` 2,8 s).
    /// Zatrzymane: szary znak, bez poświaty.
    private func glyph(t: TimeInterval) -> some View {
        ZStack {
            if !isStopping {
                let pulse = reduceMotion ? 0.5 : (1 - cos(t * 2 * .pi / 2.8)) / 2
                Circle()
                    .fill(phaseTint)
                    .scaleEffect(1 + 0.18 * pulse)
                    .opacity(0.55 - 0.35 * pulse)
                    .animation(.smooth(duration: 0.5), value: hasWritten)
            }
            AssistantSpinningMark(
                size: 26,
                color: isStopping ? AssistantLook.ink(scheme).opacity(0.35) : AssistantLook.terraFill(scheme),
                spinning: !isStopping
            )
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
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

// MARK: - Pasek aktywności

/// Pasek aktywności z makiety (`lBar`): tor 3 pt w tincie fazy, pasmo 38 %
/// szerokości w kolorze fazy sunie od lewej do prawej co 2,2 s
/// (`cubic-bezier(.4,0,.6,1)`). To NIE jest pasek postępu — nigdy nie
/// „dojeżdża” do końca. Przy Reduce Motion pasmo stoi na środku.
struct AssistantActivityLine: View {
    let t: TimeInterval
    let color: Color
    var tint: Color? = nil
    var still: Bool = false
    var period: TimeInterval = 2.2

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let band = width * 0.38
            let phase = still ? 0.5 : Self.eased(t.truncatingRemainder(dividingBy: period) / period)
            let x = -band + (width + band) * phase
            ZStack(alignment: .leading) {
                Capsule().fill(tint ?? color.opacity(0.12))
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: band)
                    .offset(x: still ? (width - band) / 2 : x)
            }
            .clipShape(Capsule())
        }
        .frame(height: 3)
        .animation(.smooth(duration: 0.5), value: color)
        .accessibilityHidden(true)
    }

    private static func eased(_ p: Double) -> Double {
        // Przybliżenie cubic-bezier(.4,0,.6,1): łagodny start i koniec.
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
