import SwiftUI

/// Powierzchnia kart doku: ta sama co wyspa (`canvas`, obwódka, cień), róg
/// `radius.cookDockCard`.
private struct CookDockCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.dockCard, style: .continuous)
        content
            .background(shape.fill(Color.scCanvas(scheme)))
            .overlay(shape.strokeBorder(SCCook.Palette.dockStroke(scheme), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: SCCook.Palette.dockShadow(scheme), radius: 18, y: 14)
    }
}

/// Nagłówek sekcji kart doku: „TRWA”, „W TYM KROKU”, „TERAZ”…
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
struct CookTimersCard: View {
    let session: CookSession
    let now: Date
    let onTimer: (CookTimerAction) -> Void

    @Environment(\.colorScheme) private var scheme

    private var items: [CookDockTimer] { session.dockTimers(now: now) }

    private var active: [CookDockTimer] {
        items.filter {
            switch $0.status {
            case .running, .overdue: true
            default: false
            }
        }
    }

    private var pending: [CookDockTimer] {
        items.filter { if case .pending = $0.status { true } else { false } }
    }

    private var paused: [CookDockTimer] {
        items.filter { if case .paused = $0.status { true } else { false } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Timery")
                    .cookText(SCCook.Typography.sheetTitle)
                    .foregroundStyle(Color.scLabel(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(SCCook.Palette.caption(scheme))
                    .lineLimit(1)
            }

            if !active.isEmpty {
                CookSectionHeader(
                    title: active.count == 1 ? "TRWA" : "TRWAJĄ",
                    color: active.count == 1 ? active[0].accent.color : Color.scLabel(scheme)
                )
                ForEach(active) { item in
                    activeRow(item)
                }
            }

            if !pending.isEmpty {
                CookSectionHeader(title: "W TYM KROKU", color: SCPalette.terracotta)
                ForEach(pending) { item in
                    pendingTile(item)
                        .padding(.bottom, 8)
                }
            }

            if !paused.isEmpty {
                CookSectionHeader(title: "WSTRZYMANY", color: Color.scMuted(scheme))
                ForEach(paused) { item in
                    pausedRow(item)
                }
                Text("Stoi, dopóki go nie wznowisz — nie zadzwoni.")
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(SCCook.Palette.caption(scheme))
                    .padding(.top, 6)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .modifier(CookDockCardSurface())
    }

    private var summary: String {
        var parts: [String] = []
        if !active.isEmpty {
            parts.append("\(active.count) \(PolishPlural.form(active.count, one: "trwa", few: "trwają", many: "trwa"))")
        }
        if !pending.isEmpty {
            parts.append("\(pending.count) do włączenia")
        }
        if !paused.isEmpty {
            parts.append("\(paused.count) \(PolishPlural.form(paused.count, one: "wstrzymany", few: "wstrzymane", many: "wstrzymanych"))")
        }
        return parts.joined(separator: " · ")
    }

    private func caption(_ item: CookDockTimer) -> String {
        "krok \(item.stepIndex + 1) · z \(CookClock.duration(item.timer))"
    }

    private func activeRow(_ item: CookDockTimer) -> some View {
        let color = item.accent.color
        let isOverdue: Bool = if case .overdue = item.status { true } else { false }
        return HStack(spacing: 12) {
            Button {
                onTimer(isOverdue ? .finish(item.id) : .pause(item.id))
            } label: {
                ZStack {
                    CookTimerRing(fraction: item.status.remainingFraction, color: color, lineWidth: SCCook.Stroke.sheetTimerRing)
                    Image(systemName: isOverdue ? "checkmark" : "pause.fill")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(color)
                }
                .frame(width: SCCook.Size.sheetTimerRing, height: SCCook.Size.sheetTimerRing)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOverdue ? "Gotowe: \(item.timer.label)" : "Pauza: \(item.timer.label)")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.timer.label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                Text(caption(item))
                    .font(.system(size: 12))
                    .foregroundStyle(SCCook.Palette.caption(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(CookDockLabels.time(item.status))
                .cookText(SCCook.Typography.sheetTime)
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(countsDown: !isOverdue))
        }
        .frame(minHeight: SCCook.Height.timerRow)
    }

    private func pendingTile(_ item: CookDockTimer) -> some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.timerStartTile, style: .continuous)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.timer.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SCPalette.terracotta)
                Text(CookDockLabels.time(item.status))
                    .cookText(SCCook.Typography.sheetTime)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                Text("Start: \(item.timer.startLabel.lowercasedFirst)")
                    .font(.system(size: 12))
                    .foregroundStyle(SCCook.Palette.caption(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { onTimer(.start(item.id)) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Start")
                        .font(.system(size: 16, weight: .heavy))
                }
                .foregroundStyle(Color.scPageBase(scheme))
                .padding(.leading, 14)
                .padding(.trailing, 18)
                .frame(height: SCCook.Size.sheetTimerRing)
                .background(Capsule().fill(SCPalette.terracotta))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start: \(item.timer.label)")
        }
        .padding(.vertical, 12)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .background(shape.fill(SCPalette.terracotta.opacity(SCCook.Opacity.timerFill)))
        .overlay(shape.strokeBorder(SCPalette.terracotta.opacity(SCCook.Opacity.timerStroke), lineWidth: 1))
        .cookInvitePulse(shape)
    }

    private func pausedRow(_ item: CookDockTimer) -> some View {
        HStack(spacing: 12) {
            Button { onTimer(.resume(item.id)) } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.scLabel(scheme))
                    .offset(x: 1)
                    .frame(width: SCCook.Size.sheetTimerRing, height: SCCook.Size.sheetTimerRing)
                    .background(Circle().fill(Color.scTileStroke(scheme)))
                    .overlay(Circle().strokeBorder(Color.scStrike(scheme), lineWidth: 2))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Wznów: \(item.timer.label)")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.timer.label)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                Text(caption(item))
                    .font(.system(size: 12))
                    .foregroundStyle(SCCook.Palette.caption(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(CookDockLabels.time(item.status))
                .cookText(SCCook.Typography.sheetTime)
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
        }
        .frame(minHeight: SCCook.Height.timerRow)
    }
}

// MARK: - Składniki

/// Karta Składniki — wyspa rozwinięta w kartę: lista nad kreską, wiersz wyspy
/// na dole z podświetlonym „Składniki” (KM1, KM2). Bez odhaczania (D7).
struct CookIngredientsCard<IslandRow: View>: View {
    enum Scope: Hashable {
        case step
        case recipe
    }

    let session: CookSession
    @ViewBuilder let islandRow: () -> IslandRow

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
        VStack(spacing: 0) {
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
                        ForEach(sections) { section in
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

            islandRow()
        }
        .modifier(CookDockCardSurface())
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
            withAnimation(.smooth(duration: 0.2)) { scope = value }
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
