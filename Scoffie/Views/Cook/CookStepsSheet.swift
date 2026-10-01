import SwiftUI

/// Arkusz Kroki — stuknięcie w pierścień kroków obok krzyżyka (runda 6
/// testów: „niech się otworzy sheet ze stepperami jedno pod drugim, aby było
/// wiadome co i jak, ładnie, czytelnie i pokrótce”).
///
/// Oś kroków: krążek z numerem (zrobiony — ptaszek w szałwii, bieżący —
/// numer na pełnej terakocie, dalszy — numer na polu chipa), obok sam TYTUŁ
/// kroku (polecenie ze scenariusza), etap nad nim tylko tam, gdzie się
/// zmienia, i etykiety: „Teraz” przy bieżącym, timer przy kroku, który go
/// niesie. Opisu kroku tu nie ma — od tego jest ekran kroku. Stuknięcie
/// w wiersz przenosi na ten krok (`CookSession.jump`) i zamyka arkusz.
///
/// Pół ekranu, przewijanie rozwija na cały (jak Składniki); przy otwarciu
/// lista stoi na bieżącym kroku, z poprzednim nad nim.
struct CookStepsSheet: View {
    let session: CookSession
    let onJump: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetHeader(
                eyebrow: "Krok \(session.stepIndex + 1) z \(session.stepCount)",
                title: "Kroki",
                icon: "list.number",
                accent: SCPalette.terracotta,
                compact: true,
                onClose: onClose
            )
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.top, 20)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                            Button { onJump(index) } label: {
                                CookStepListRow(session: session, index: index, step: step)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, SCCook.Spacing.page)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
                .onAppear {
                    proxy.scrollTo(max(0, session.stepIndex - 1), anchor: .top)
                }
            }
        }
    }
}

/// Wiersz osi kroków. Oś ciągnie się przez etap nad tytułem, więc kroki
/// czytają się jako jedna linia; przy krążku urywa się o `railGap` (krążki
/// są półprzezroczyste, a tło arkusza ma poświatę — kryjący krążek by ją
/// zdradzał).
private struct CookStepListRow: View {
    enum Phase {
        case done
        case current
        case upcoming
    }

    let session: CookSession
    let index: Int
    let step: CookStep

    @Environment(\.colorScheme) private var scheme

    private var badge: CGFloat { SCCook.Size.stepBadge }
    private var rail: CGFloat { SCCook.Stroke.stepRail }
    /// Krążek od góry wiersza; tytuł (16 pt, linia ~20) dosunięty tak, żeby
    /// jego pierwsza linia stała na środku krążka.
    private var badgeTop: CGFloat { 8 }
    private var railGap: CGFloat { 4 }
    private var titleTop: CGFloat { badgeTop + (badge - 20) / 2 }

    private var isLast: Bool { index == session.steps.count - 1 }

    private func phase(at position: Int) -> Phase {
        if position == session.stepIndex { return .current }
        // Krok przeskoczony skokiem z tej listy nie jest „zrobiony”.
        if position < session.stepIndex, session.visitedStepIds.contains(session.steps[position].id) {
            return .done
        }
        return .upcoming
    }

    private var phase: Phase { phase(at: index) }

    /// Etap nad tytułem — tylko tam, gdzie się zmienia (jak nagłówek
    /// sekcji, ale bez przerywania osi).
    private var stage: String? {
        guard let label = step.stageLabel else { return nil }
        guard index > 0 else { return label }
        return session.steps[index - 1].stageLabel == label ? nil : label
    }

    /// Odcinek osi między krokiem `from` a następnym: szałwia, gdy prowadzi
    /// od zrobionego do zrobionego albo do bieżącego.
    private func railColor(from position: Int) -> Color {
        let next = position + 1
        guard position >= 0, session.steps.indices.contains(next) else { return .clear }
        let reached = phase(at: position) == .done && phase(at: next) != .upcoming
        return reached ? SCPalette.sage : Color.scTileStroke(scheme)
    }

    var body: some View {
        let above = railColor(from: index - 1)
        VStack(alignment: .leading, spacing: 0) {
            if let stage {
                Text(stage)
                    .cookText(SCCook.Typography.stage)
                    .foregroundStyle(SCPalette.sage)
                    .padding(.leading, badge + 14)
                    .padding(.top, index == 0 ? 0 : 10)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .leading) { railSegment(above) }
            }

            HStack(alignment: .top, spacing: 14) {
                badgeView
                    .frame(width: badge, height: badge)
                    .padding(.top, badgeTop)

                VStack(alignment: .leading, spacing: 8) {
                    Text(step.title)
                        .font(.system(size: 16, weight: phase == .current ? .bold : .semibold))
                        .foregroundStyle(phase == .done ? SCCook.Palette.caption(scheme) : Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if phase == .current || step.timer != nil {
                        AllergenChipFlow(spacing: 6) {
                            if phase == .current {
                                SCTag(title: "Teraz", icon: "arrow.right", accent: SCPalette.terracotta)
                            }
                            if let timer = step.timer {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    timerTag(timer, now: context.date)
                                }
                            }
                        }
                    }
                }
                .padding(.top, titleTop)
                .padding(.bottom, 14)
            }
            .frame(minHeight: SCCook.Height.stepRow, alignment: .top)
            .background(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    railSegment(above)
                        .frame(height: max(0, badgeTop - railGap))
                    Color.clear
                        .frame(width: 1, height: badge + railGap * 2)
                    railSegment(isLast ? .clear : railColor(from: index))
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Krok \(index + 1): \(step.title)")
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(phase == .current ? [.isSelected] : [])
        .accessibilityHint(phase == .current ? "" : "Przechodzi do tego kroku")
    }

    private func railSegment(_ color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: rail)
            .frame(maxHeight: .infinity)
            .padding(.leading, (badge - rail) / 2)
    }

    @ViewBuilder
    private var badgeView: some View {
        switch phase {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(SCPalette.sage)
                .frame(width: badge, height: badge)
                .background(Circle().fill(SCPalette.sage.opacity(scheme == .dark ? 0.2 : 0.14)))
        case .current:
            Text("\(index + 1)")
                .cookText(SCCook.Typography.stepNumber)
                .monospacedDigit()
                .foregroundStyle(Color.scPageBase(scheme))
                .frame(width: badge, height: badge)
                .background(Circle().fill(SCPalette.terracotta))
                .background(Circle().fill(SCPalette.terracotta.opacity(0.18)).padding(-railGap))
        case .upcoming:
            Text("\(index + 1)")
                .cookText(SCCook.Typography.stepNumber)
                .monospacedDigit()
                .foregroundStyle(Color.scMuted(scheme))
                .frame(width: badge, height: badge)
                .background(Circle().fill(Color.scChipBg(scheme)))
                .overlay(Circle().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        }
    }

    /// Etykieta timera kroku — kolor TEGO timera (jak w doku); zrobiony,
    /// pominięty i wstrzymany przygaszone. Słowa zamiast tykającego czasu:
    /// odliczanie jest w doku, tu chodzi o to, co i gdzie.
    private func timerTag(_ timer: CookTimer, now: Date) -> some View {
        let accent = session.timers[timer.id]?.accent ?? session.accent(for: timer.id)
        let muted = Color.scMuted(scheme)
        let (text, icon, color): (String, String, Color) = {
            if session.timers[timer.id]?.state == .skipped {
                return ("pominięty", "forward.fill", muted)
            }
            switch session.status(of: timer.id, now: now) {
            case .running: return ("trwa", "timer", accent.color)
            case .paused: return ("wstrzymany", "pause.fill", muted)
            case .overdue: return ("po czasie", "bell.fill", accent.color)
            case .finished: return ("gotowe", "checkmark", muted)
            case .pending, nil: return (CookClock.duration(timer), "timer", accent.color)
            }
        }()
        return SCTag(title: "\(timer.label) · \(text)", icon: icon, accent: color)
    }

    private var accessibilityState: String {
        switch phase {
        case .done: "zrobiony"
        case .current: "teraz"
        case .upcoming: ""
        }
    }
}
