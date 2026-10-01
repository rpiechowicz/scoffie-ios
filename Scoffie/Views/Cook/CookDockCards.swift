import SwiftUI

/// Powierzchnia karty Timery: ta sama co wyspa (`cook.dockSurface`, obwódka,
/// cień), róg `radius.cookDockCard`.
private struct CookDockCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.dockCard, style: .continuous)
        content
            .background(shape.fill(SCCook.Palette.dockSurface(scheme)))
            .overlay(shape.strokeBorder(SCCook.Palette.dockStroke(scheme), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 18, y: 14)
    }
}

/// Nagłówek sekcji listy składników: „TERAZ”, „ZA CHWILĘ · KROK 4”…
private struct CookSectionHeader: View {
    let title: String
    let color: Color
    var count: Int?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            Text(title)
                .cookText(SCCook.Typography.sectionLabel)
                .foregroundStyle(color)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)")
                    .font(.system(size: 13))
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

/// Karta Timery — w miejscu kapsuł, wyspa zostaje pod nią (ST5, Y3T1–3).
///
/// JEDNA lista w kolejności kroków (`CookSession.timerLineup`), bez sekcji
/// „Trwa / W tym kroku / Wstrzymany” (runda 2 testów): wiersz zostaje na
/// swoim miejscu przez cały czas swojego timera, a stan mówi kolor,
/// podpis i glif w pierścieniu — jak w kapsule. Wcześniej start czy pauza
/// przenosiły wiersz do innej sekcji i karta skakała pod palcem.
struct CookTimersCard: View {
    let session: CookSession
    let now: Date
    let onTimer: (CookTimerAction) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let items = session.timerLineup(now: now)
        let summaryText = summary(items)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Timery")
                    .cookText(SCCook.Typography.sheetTitle)
                    .foregroundStyle(Color.scLabel(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(summaryText)
                    .font(.system(size: 13))
                    .foregroundStyle(SCCook.Palette.caption(scheme))
                    .lineLimit(1)
                    .cookRoll(summaryText)
            }
            .padding(.bottom, 6)

            ForEach(items) { item in
                CookTimerRow(item: item, onTimer: onTimer)
                    .transition(.opacity)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .modifier(CookDockCardSurface())
    }

    private func summary(_ items: [CookDockTimer]) -> String {
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
        return parts.joined(separator: " · ")
    }
}

/// Wiersz karty Timery — ten sam układ w każdym stanie: pierścień-przycisk
/// (glif ruchu w środku), nazwa z podpisem i czas. Zmienia się kolor, glif
/// i podpis, nie miejsce.
private struct CookTimerRow: View {
    let item: CookDockTimer
    let onTimer: (CookTimerAction) -> Void

    @Environment(\.colorScheme) private var scheme

    private var isOverdue: Bool { if case .overdue = item.status { true } else { false } }
    private var isPending: Bool { if case .pending = item.status { true } else { false } }
    private var isPaused: Bool { if case .paused = item.status { true } else { false } }
    private var isRunning: Bool { if case .running = item.status { true } else { false } }

    /// Kolor stanu: trwa — kolor timera, czeka i po czasie — terakota,
    /// wstrzymany — przygaszony.
    private var tone: Color {
        if isPaused { return Color.scMuted(scheme) }
        if isPending || isOverdue { return SCPalette.terracotta }
        return item.accent.color
    }

    var body: some View {
        let time = CookDockLabels.time(item.status)
        let captionText = caption
        HStack(spacing: 12) {
            control

            VStack(alignment: .leading, spacing: 2) {
                Text(item.timer.label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isPaused ? Color.scMuted(scheme) : Color.scLabel(scheme))
                    .lineLimit(1)
                Text(captionText)
                    .font(.system(size: 12))
                    .foregroundStyle(isOverdue ? SCPalette.terracotta : SCCook.Palette.caption(scheme))
                    .lineLimit(1)
                    .cookRoll(captionText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(time)
                .cookText(SCCook.Typography.sheetTime)
                .monospacedDigit()
                .foregroundStyle(isPending ? Color.scLabel(scheme) : tone)
                .cookTicking(time, countsDown: !isOverdue)
        }
        .frame(minHeight: SCCook.Height.timerRow)
        .accessibilityElement(children: .contain)
        // Zmiana stanu z zegara (koniec odliczania) — kolory przechodzą
        // sprężyną doku, a nie w klatce.
        .animation(SCCook.Motion.dock, value: item.status.phase)
    }

    private var caption: String {
        switch item.status {
        case .pending: "Start: \(item.timer.startLabel.lowercasedFirst)"
        case .running: "krok \(item.stepIndex + 1) · z \(CookClock.duration(item.timer))"
        case .paused: "wstrzymany — nie zadzwoni"
        case .overdue: "po czasie · krok \(item.stepIndex + 1)"
        case .finished: ""
        }
    }

    /// Pierścień-przycisk 46 pt: łuk pozostałego czasu (trwa, wstrzymany)
    /// albo pełny krążek terakoty (czeka — ▶, po czasie — ✓).
    private var control: some View {
        let side = SCCook.Size.sheetTimerRing
        let filled = isPending || isOverdue
        return Button {
            if let action = item.primaryAction { onTimer(action) }
        } label: {
            ZStack {
                Circle().fill(filled ? SCPalette.terracotta : .clear)
                CookTimerRing(fraction: item.status.remainingFraction, color: tone, lineWidth: SCCook.Stroke.sheetTimerRing)
                    .opacity(isRunning || isPaused ? 1 : 0)
                Image(systemName: item.primaryIcon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(filled ? Color.scPageBase(scheme) : (isPaused ? Color.scLabel(scheme) : tone))
                    .offset(x: item.primaryIcon == "play.fill" ? 1 : 0)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .cookInvitePulse(Circle(), isActive: isPending)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.primaryLabel)
    }
}

// MARK: - Składniki

/// Treść karty Składniki — leży w wyspie (`CookDock.island`), która rozwija
/// się w kartę, więc nie ma własnej powierzchni ani wiersza wyspy: lista nad
/// kreską, pod nią zostaje wiersz wyspy z podświetlonym „Składniki” (KM1,
/// KM2). Bez odhaczania (D7).
struct CookIngredientsPanel: View {
    enum Scope: Hashable {
        case step
        case recipe
    }

    let session: CookSession

    @State private var scope: Scope = .step
    @Environment(\.colorScheme) private var scheme

    private struct LineGroup: Identifiable {
        let id: String
        let title: String
        let color: Color
        let lines: [CookIngredientLine]
        let isDone: Bool
    }

    private var index: Int { session.stepIndex }

    private func lines(at stepIndex: Int) -> [CookIngredientLine] {
        guard session.steps.indices.contains(stepIndex) else { return [] }
        return session.package.lines(for: session.steps[stepIndex], portions: session.portions)
    }

    private var sections: [LineGroup] {
        let caption = SCCook.Palette.caption(scheme)
        var result = [
            LineGroup(id: "now", title: "TERAZ", color: SCPalette.terracotta, lines: lines(at: index), isDone: false),
            LineGroup(id: "next", title: "ZA CHWILĘ · KROK \(index + 2)", color: caption, lines: lines(at: index + 1), isDone: false),
        ]
        if scope == .recipe {
            let later = session.steps.indices.filter { $0 > index + 1 }.flatMap { lines(at: $0) }
            let done = session.steps.indices.filter { $0 < index }.flatMap { lines(at: $0) }
            result.append(LineGroup(id: "later", title: "PÓŹNIEJ", color: caption, lines: later, isDone: false))
            result.append(LineGroup(id: "done", title: "JUŻ W DANIU", color: caption, lines: done, isDone: true))
        }
        return result.filter { !$0.lines.isEmpty }
    }

    /// „Cały przepis N” = wiersze listy (składnik dzielony między kroki to
    /// kilka wierszy — sól ×3), tak jak liczą sekcje.
    private var recipeCount: Int {
        session.steps.indices.reduce(0) { $0 + lines(at: $1).count }
    }

    var body: some View {
        // Raz na przebieg: dok przerysowuje się co sekundę (zegary).
        let groups = sections
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Składniki")
                        .cookText(SCCook.Typography.sheetTitle)
                        .foregroundStyle(Color.scLabel(scheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("KROK \(index + 1) Z \(session.stepCount)")
                        .cookText(SCCook.Typography.sectionLabel)
                        .foregroundStyle(SCPalette.terracotta)
                }

                scopePicker
                    .padding(.top, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { section in
                            CookSectionHeader(title: section.title, color: section.color, count: section.lines.count)
                            ForEach(Array(section.lines.enumerated()), id: \.element.id) { offset, line in
                                row(line, isDone: section.isDone)
                                if offset < section.lines.count - 1 {
                                    Rectangle()
                                        .fill(Color.scChipBg(scheme))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .frame(maxHeight: 440)
            }
            .padding(.top, 20)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.scChipBg(scheme))
                .frame(height: 1)
                .padding(.horizontal, 16)
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
                    .font(.system(size: 14, weight: selected ? .bold : .semibold))
                Text("\(count)")
                    .font(.system(size: 14, weight: selected ? .bold : .semibold))
                    .monospacedDigit()
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? Color.scLabel(scheme) : Color.scMuted(scheme))
            .frame(maxWidth: .infinity)
            .frame(height: SCCook.Height.segment)
            .background(Capsule().fill(selected ? SCCook.Palette.badge(scheme) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func row(_ line: CookIngredientLine, isDone: Bool) -> some View {
        let tint = CookIngredientLook.color(line.department)
        let dim = SCCook.Palette.caption(scheme)
        let stepNumber = (session.steps.firstIndex { $0.id == line.stepId } ?? 0) + 1
        let caption = isDone ? "krok \(stepNumber)" : line.partLabel
        return HStack(spacing: 12) {
            Group {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(dim)
                        .frame(width: SCCook.Size.ingredientIcon, height: SCCook.Size.ingredientIcon)
                        .background(Circle().fill(Color.scTileStroke(scheme)))
                } else {
                    Image(systemName: CookIngredientLook.icon(line.department))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: SCCook.Size.ingredientIcon, height: SCCook.Size.ingredientIcon)
                        .background(Circle().fill(tint.opacity(0.12)))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDone ? dim : Color.scLabel(scheme))
                    .lineLimit(1)
                if let caption {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(line.amountText)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isDone ? dim : Color.scLabel(scheme))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minHeight: caption == nil ? SCCook.Height.ingredientRow : SCCook.Height.ingredientRow + 6)
        .accessibilityElement(children: .combine)
    }
}

extension String {
    /// „Kotlety na patelni” → „kotlety na patelni” — do podpisu „Start: …”.
    var lowercasedFirst: String {
        guard let first else { return self }
        return String(first).lowercased(with: Locale(identifier: "pl_PL")) + dropFirst()
    }
}
