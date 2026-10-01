import SwiftUI

/// Krok (Y3K1–3) — treść pod zdjęciem na wspólnym ekranie trybu
/// (`CookScreen`): etap · tytuł · opis · adnotacja. Pierścień kroków
/// i krzyżyk stoją w pasku ekranu, dok pływa nad treścią. Tekst przewija się
/// pod dokiem, a jego koniec staje nad nim (`spacing.cookDockReserve`).
///
/// Ruch (§8.2, `motion.cookStep`): przy wejściu sekcje wjeżdżają kaskadą,
/// przy zmianie kroku nagłówek (etap i tytuł) ROLUJE się w miejscu jak danie
/// w arkuszu wyboru posiłku, a opis wjeżdża z boku, z którego przyszedł krok,
/// o chwilę później — nagłówek szybciej niż „jak”. Nowy opis i stary leżą
/// w tym samym `ZStack`, więc nic pod nimi nie skacze.
struct CookStepScene: View {
    let session: CookSession
    let step: CookStep
    /// Skąd przyszedł krok — nowy opis wjeżdża z tej strony.
    let direction: Edge

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SCCook.Spacing.titleTop)

            header
                .cookReveal(hasAppeared, order: 0)

            ZStack(alignment: .topLeading) {
                details
                    .id(step.id)
                    .transition(detailsTransition)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cookReveal(hasAppeared, order: 1)

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

    /// Etap i tytuł — ten sam widok przez wszystkie kroki, tekst roluje się
    /// w miejscu (wstecz = w drugą stronę).
    private var header: some View {
        let backwards = direction == .leading
        return VStack(alignment: .leading, spacing: 0) {
            if let stage = step.stageLabel {
                Text(stage)
                    .cookText(SCCook.Typography.stage)
                    .foregroundStyle(SCPalette.sage)
                    .cookRoll(stage, countsDown: backwards)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

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

    /// Opis, adnotacja i dopisek o porcjach — nowy krok = nowy widok, który
    /// wjeżdża z boku.
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(session.package.body(for: step, portions: session.portions))
                .cookText(SCCook.Typography.stepBody)
                .foregroundStyle(SCCook.Palette.body(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            if let note = step.note {
                CookNoteCard(kind: note.kind, text: note.text)
                    .padding(.top, 14)
            }

            if let scaleNote = session.package.scaleNote(for: step, portions: session.portions) {
                CookNoteCard(kind: .tip, text: scaleNote, label: "WIĘCEJ PORCJI", systemImage: "person.2")
                    .padding(.top, step.note == nil ? 14 : 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nowy opis wjeżdża z boku z lekkim opóźnieniem za nagłówkiem, stary
    /// gaśnie od razu w miejscu. Przy „Ogranicz ruch” — samo przenikanie.
    private var detailsTransition: AnyTransition {
        if reduceMotion {
            return .opacity.animation(.easeInOut(duration: 0.2))
        }
        let shift: CGFloat = direction == .trailing ? 44 : -44
        return .asymmetric(
            insertion: .offset(x: shift)
                .combined(with: .opacity)
                .animation(SCCook.Motion.step.delay(0.06)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
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
