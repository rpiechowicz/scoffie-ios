import SwiftUI

/// Arkusz Kroki — stuknięcie w pierścień kroków obok krzyżyka. Przegląd
/// całego gotowania: wszystkie kroki jeden pod drugim, co i jak.
///
/// Runda 7 testów („nie dawaj tak, że jak klikam, to mi się otwiera;
/// czytelnie, wykorzystaj całą przestrzeń”): arkusz od razu na cały ekran
/// (bez połowy, która rozwijała się pod palcem), wiersze NIE przenoszą do
/// kroku — to podgląd, krok zmienia się dalej z doku. Pod nagłówkiem pasek
/// postępu (`SCStepProgress`, ten sam co w kreatorze). Wiersz: krążek
/// z numerem (zrobiony — ptaszek w szałwii, bieżący — numer na terakocie,
/// dalszy — numer na polu chipa), tytuł kroku, pod nim dwie linie opisu
/// (bieżący — do czterech, na karcie w tincie terakoty), etap tylko tam,
/// gdzie się zmienia, i etykiety: „Teraz” oraz timer kroku słowem.
///
/// Otwiera się na bieżącym kroku, z poprzednim nad nim.
struct CookStepsSheet: View {
    let session: CookSession
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                EditorialSheetHeader(
                    eyebrow: "Krok \(session.stepIndex + 1) z \(session.stepCount)",
                    title: "Kroki",
                    icon: "list.number",
                    accent: SCPalette.terracotta,
                    compact: true,
                    onClose: onClose
                )
                SCStepProgress(step: session.stepIndex + 1, total: session.stepCount)
            }
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.top, 20)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.steps.enumerated()), id: \.element.id) { index, step in
                            CookStepListRow(session: session, index: index, step: step)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, SCCook.Spacing.page)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
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
/// są półprzezroczyste, a tło arkusza ma poświatę).
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
    /// Krążek od góry wiersza; tytuł (17 pt, linia ~21) dosunięty tak, żeby
    /// jego pierwsza linia stała na środku krążka.
    private var badgeTop: CGFloat { 12 }
    private var railGap: CGFloat { 4 }
    private var titleTop: CGFloat { badgeTop + (badge - 21) / 2 }

    private var isLast: Bool { index == session.steps.count - 1 }

    private func phase(at position: Int) -> Phase {
        if position == session.stepIndex { return .current }
        // Krok przeskoczony nie jest „zrobiony”.
        if position < session.stepIndex, session.visitedStepIds.contains(session.steps[position].id) {
            return .done
        }
        return .upcoming
    }

    private var phase: Phase { phase(at: index) }

    /// Etap nad tytułem — tylko tam, gdzie się zmienia.
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
                    .padding(.top, index == 0 ? 0 : 12)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .leading) { railSegment(above) }
            }

            HStack(alignment: .top, spacing: 14) {
                badgeView
                    .frame(width: badge, height: badge)
                    .padding(.top, badgeTop)

                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title)
                        .font(.system(size: 17, weight: phase == .current ? .bold : .semibold))
                        .foregroundStyle(phase == .done ? SCCook.Palette.caption(scheme) : Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(session.package.body(for: step, portions: session.portions))
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .foregroundStyle(phase == .current ? SCCook.Palette.body(scheme) : SCCook.Palette.caption(scheme))
                        .lineLimit(phase == .current ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(phase == .done ? 0.8 : 1)

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
                        .padding(.top, 2)
                    }
                }
                .padding(.top, titleTop)
                .padding(.bottom, 16)
                .padding(.trailing, phase == .current ? 4 : 0)
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
            // Bieżący krok na karcie w tincie terakoty — wystaje poza
            // margines treści o 10 pt, oś leży nad nią.
            .background {
                if phase == .current {
                    let shape = RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous)
                    shape
                        .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.12 : 0.07))
                        .overlay(shape.strokeBorder(SCPalette.terracotta.opacity(0.22), lineWidth: 1))
                        .padding(.horizontal, -10)
                        .padding(.vertical, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Krok \(index + 1): \(step.title)")
        .accessibilityValue(accessibilityState)
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
