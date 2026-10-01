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
                CookNoteLine(kind: note.kind, text: note.text)
                    .padding(.top, 12)
            }

            if let scaleNote = session.package.scaleNote(for: step, portions: session.portions) {
                CookNoteLine(kind: .tip, text: scaleNote, systemImage: "person.2")
                    .padding(.top, 10)
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

/// Adnotacja kroku: ostrzeżenie w maśle z trójkątem (makieta), „po czym
/// poznać” i rada — cicha linijka z ikoną.
struct CookNoteLine: View {
    let kind: CookNoteKind
    let text: String
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

    private var textColor: Color {
        kind == .warning ? SCPalette.butter : SCCook.Palette.body(scheme)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .cookText(SCCook.Typography.note)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityPrefix + text)
    }

    private var accessibilityPrefix: String {
        switch kind {
        case .warning: "Uwaga: "
        case .cue: "Po czym poznać: "
        case .tip, .unknown: "Rada: "
        }
    }
}
