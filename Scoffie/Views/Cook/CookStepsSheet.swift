import SwiftUI

/// Arkusz Kroki — stuknięcie w pierścień kroków obok krzyżyka. Przegląd
/// całego gotowania: wszystkie kroki jeden pod drugim, co i jak. Sam podgląd
/// na cały ekran (runda 7) — wiersz nie przenosi do kroku, krok zmienia się
/// z doku.
///
/// Runda 9 („popraw listę wszystkich kroków w sheet na stepper”): pod
/// nagłówkiem pasek postępu i jedno zdanie „3 zrobione · 9 przed Tobą”;
/// kroki w ETAPACH (nagłówek etapu z liczbą kroków; bez etapu w danych —
/// faza: przygotowanie, gotowanie, wykończenie, podanie); zrobione zwinięte
/// do jednej linii, żeby nie zabierały miejsca; bieżący na karcie w tincie
/// terakoty z CAŁYM opisem; dalsze z tytułem i dwiema liniami opisu. Oś
/// krążków łączy wszystko w jedną linię, także przez nagłówki etapów.
///
/// Otwiera się na bieżącym kroku, z poprzednim nad nim.
struct CookStepsSheet: View {
    let session: CookSession
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var doneCount: Int {
        session.steps.indices.filter { CookStepListRow.phase(of: $0, in: session) == .done }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                EditorialSheetHeader(
                    eyebrow: "Krok \(session.stepIndex + 1) z \(session.stepCount)",
                    title: "Kroki",
                    icon: "list.number",
                    accent: SCPalette.terracotta,
                    compact: true,
                    onClose: onClose
                )
                VStack(alignment: .leading, spacing: 8) {
                    SCStepProgress(step: session.stepIndex + 1, total: session.stepCount)
                    Text(summary)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SCCook.Palette.caption(scheme))
                }
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
                    .padding(.top, 8)
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

    /// „3 zrobione · 9 przed Tobą” — przed Tobą liczy bieżący.
    private var summary: String {
        let ahead = session.stepCount - session.stepIndex
        let done = doneCount
        let aheadText = "\(ahead) przed Tobą"
        guard done > 0 else { return aheadText }
        let doneText = "\(done) \(PolishPlural.form(done, one: "zrobiony", few: "zrobione", many: "zrobionych"))"
        return "\(doneText) · \(aheadText)"
    }
}

/// Wiersz osi kroków. Oś ciągnie się przez nagłówek etapu nad wierszem, więc
/// kroki czytają się jako jedna linia; przy krążku urywa się o `railGap`
/// (krążki są półprzezroczyste, a tło arkusza ma poświatę).
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
    private var railGap: CGFloat { 4 }
    /// Krążek od góry wiersza (zwinięty zrobiony krok — niżej, bo nie ma
    /// karty ani opisu); tytuł dosunięty tak, żeby jego pierwsza linia stała
    /// na środku krążka.
    private var badgeTop: CGFloat { phase == .current ? 14 : 8 }
    private var titleLine: CGFloat {
        switch phase {
        case .done: 18
        case .current: 22
        case .upcoming: 20
        }
    }
    private var titleTop: CGFloat { badgeTop + (badge - titleLine) / 2 }

    private var isLast: Bool { index == session.steps.count - 1 }

    static func phase(of position: Int, in session: CookSession) -> Phase {
        if position == session.stepIndex { return .current }
        // Krok przeskoczony nie jest „zrobiony”.
        if position < session.stepIndex, session.visitedStepIds.contains(session.steps[position].id) {
            return .done
        }
        return .upcoming
    }

    private func phase(at position: Int) -> Phase { Self.phase(of: position, in: session) }

    private var phase: Phase { phase(at: index) }

    /// Etap kroku — z danych, a bez nich z fazy, żeby każdy krok miał swoją
    /// grupę.
    private static func group(of step: CookStep) -> String {
        if let label = step.stageLabel { return label }
        switch step.phase {
        case .prep: return "PRZYGOTOWANIE"
        case .cook: return "GOTOWANIE"
        case .finish: return "WYKOŃCZENIE"
        case .serve: return "PODANIE"
        case .unknown: return "KROKI"
        }
    }

    /// Nagłówek etapu — nad pierwszym krokiem grupy, z liczbą jej kroków.
    private var section: (title: String, count: Int)? {
        let title = Self.group(of: step)
        if index > 0, Self.group(of: session.steps[index - 1]) == title { return nil }
        var count = 0
        for next in session.steps[index...] {
            guard Self.group(of: next) == title else { break }
            count += 1
        }
        return (title, count)
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
            if let section {
                HStack(spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(SCPalette.sage)
                    Text("\(section.count)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(SCCook.Palette.caption(scheme))
                }
                .padding(.leading, badge + 14)
                .padding(.top, index == 0 ? 2 : 18)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) { railSegment(above) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }

            HStack(alignment: .top, spacing: 14) {
                badgeView
                    .frame(width: badge, height: badge)
                    .padding(.top, badgeTop)

                content
                    .padding(.top, titleTop)
                    .padding(.bottom, phase == .done ? 8 : 16)
                    .padding(.trailing, phase == .current ? 6 : 0)
            }
            .frame(minHeight: phase == .done ? badge + 16 : SCCook.Height.stepRow, alignment: .top)
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

    /// Treść wiersza według stanu: zrobiony — sam tytuł w jednej linii;
    /// bieżący — tytuł, cały opis, „Teraz” i timer; dalszy — tytuł, dwie
    /// linie opisu i timer.
    @ViewBuilder
    private var content: some View {
        switch phase {
        case .done:
            Text(step.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SCCook.Palette.caption(scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .current:
            VStack(alignment: .leading, spacing: 8) {
                Text(step.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.package.body(for: step, portions: session.portions))
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(SCCook.Palette.body(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                tags
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .upcoming:
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.package.body(for: step, portions: session.portions))
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(SCCook.Palette.caption(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if step.timer != nil {
                    tags
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// „Teraz” przy bieżącym i timer kroku słowem.
    private var tags: some View {
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
