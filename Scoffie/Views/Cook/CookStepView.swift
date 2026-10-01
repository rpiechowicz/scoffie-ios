import SwiftUI

/// Krok (Y3K1–3) — treść pod zdjęciem na wspólnym ekranie trybu
/// (`CookScreen`): nadtytuł „KROK 4 Z 12 · ETAP” · tytuł · opis · karty rad. Pierścień kroków i krzyżyk stoją w pasku ekranu, dok
/// pływa nad treścią. Tekst przewija się pod dokiem, a jego koniec staje nad
/// nim (`spacing.cookDockReserve`).
///
/// Runda 9 („czytelniej”; „tytuł się rusza, subtitle tylko jak się pojawia,
/// całość nieruszalna”; „opis i cała reszta z tą samą animacją tekstu co
/// w reszcie aplikacji”): nadtytuł to JEDEN stały wiersz — numer kroku jest
/// zawsze, etap dochodzi obok, więc tytuł nie skacze, gdy etap się pojawia
/// albo znika. Składniki są w arkuszu z wyspy — kapsułki pod tytułem z rundy
/// 9 odpadły („mam je w sheet, wcześniej było lepiej”). Przy zmianie kroku
/// nic nie wjeżdża z boku: widoki stoją, a tytuł, etap, opis i rady ROLUJĄ
/// się w miejscu (`cookRoll` = `SCMotion.textRoll`, wstecz — w drugą stronę).
struct CookStepScene: View {
    let session: CookSession
    let step: CookStep
    /// Kierunek przejścia — wstecz tekst roluje się w drugą stronę.
    let direction: Edge

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme

    private var backwards: Bool { direction == .leading }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SCCook.Spacing.titleTop)

            header
                .cookReveal(hasAppeared, order: 0)

            Text(session.package.body(for: step, portions: session.portions))
                .cookText(SCCook.Typography.stepBody)
                .foregroundStyle(SCCook.Palette.body(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cookRoll(step.id, countsDown: backwards)
                .padding(.top, 16)
                .cookReveal(hasAppeared, order: 1)

            notes
                .cookReveal(hasAppeared, order: 2)

            Color.clear.frame(height: SCCook.Spacing.dockReserve + 24)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
    }

    /// Nadtytuł i tytuł — te same widoki przez wszystkie kroki.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("KROK \(session.stepIndex + 1) Z \(session.stepCount)")
                    .foregroundStyle(SCCook.Palette.caption(scheme))
                    .cookRoll(session.stepIndex)
                if let stage = step.stageLabel {
                    HStack(spacing: 6) {
                        Text("·")
                            .foregroundStyle(SCCook.Palette.caption(scheme))
                        Text(stage)
                            .foregroundStyle(SCPalette.sage)
                            .cookRoll(stage, countsDown: backwards)
                    }
                    .transition(.opacity.combined(with: .offset(x: -6)))
                }
            }
            .cookText(SCCook.Typography.stage)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)

            Text(step.title)
                .cookText(titleStyle)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .cookRoll(step.title, countsDown: backwards)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Adnotacja i dopisek o porcjach — ta sama karta rady co na zakończeniu.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = step.note {
                CookNoteCard(kind: note.kind, text: note.text)
                    .cookRoll(note.text, countsDown: backwards)
                    .transition(.opacity)
            }
            if let scaleNote = session.package.scaleNote(for: step, portions: session.portions) {
                CookNoteCard(kind: .tip, text: scaleNote, label: "WIĘCEJ PORCJI", systemImage: "person.2")
                    .cookRoll(scaleNote, countsDown: backwards)
                    .transition(.opacity)
            }
        }
        .padding(.top, step.note == nil && session.package.scaleNote(for: step, portions: session.portions) == nil ? 0 : 16)
    }

    /// Tytuł ≤ 30 znaków mieści się w dwóch liniach 40 pt (zasady .5, D37);
    /// dłuższy (scenariusze sprzed zasad .5) schodzi do 32 pt.
    private var titleStyle: SCCookTextStyle {
        step.title.count > 30 ? SCCook.Typography.stepTitleCompact : SCCook.Typography.stepTitle
    }
}

/// Karta rady — adnotacja kroku (uwaga, po czym poznać, rada, więcej
/// porcji) i „Na następny raz” na zakończeniu: JEDNA zwarta karta w obu
/// miejscach (runda 8: „tipy na kroku zrób tak samo jak na zakończeniu, tylko
/// bardziej skondensowane, tu i tu”). Krążek z ikoną w kolorze rodzaju,
/// nadtytuł w tym kolorze, zdanie 14 pt. Uwaga stoi na tincie masła, reszta
/// na kaflu aplikacji (`scTileBg` + `scTileStroke`).
struct CookNoteCard: View {
    let kind: CookNoteKind
    let text: String
    /// Nadtytuł; `nil` = z rodzaju („UWAGA”, „PO CZYM POZNAĆ”, „RADA”).
    var label: String? = nil
    var systemImage: String? = nil

    @Environment(\.colorScheme) private var scheme

    private var icon: String {
        if let systemImage { return systemImage }
        switch kind {
        case .warning: return "exclamationmark.triangle"
        case .cue: return "eye"
        case .tip, .unknown: return "lightbulb"
        }
    }

    private var tint: Color {
        switch kind {
        case .warning: SCPalette.butter
        case .cue: SCPalette.sage
        case .tip, .unknown: SCPalette.butter
        }
    }

    private var eyebrow: String {
        if let label { return label }
        switch kind {
        case .warning: return "UWAGA"
        case .cue: return "PO CZYM POZNAĆ"
        case .tip, .unknown: return "RADA"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.note, style: .continuous)
        let isWarning = kind == .warning
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: SCCook.Size.noteIcon, height: SCCook.Size.noteIcon)
                .background(Circle().fill(tint.opacity(scheme == .dark ? 0.18 : 0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(tint)
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .lineSpacing(2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(shape.fill(isWarning ? tint.opacity(scheme == .dark ? 0.12 : 0.09) : Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(isWarning ? tint.opacity(0.3) : Color.scTileStroke(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityPrefix + text)
    }

    private var accessibilityPrefix: String {
        if let label { return label + ": " }
        switch kind {
        case .warning: return "Uwaga: "
        case .cue: return "Po czym poznać: "
        case .tip, .unknown: return "Rada: "
        }
    }
}
