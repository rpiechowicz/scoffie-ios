import SwiftUI

/// Ekran kroku (Y3K1–3): u góry pierścień kroków i krzyżyk, scena (etap ·
/// tytuł · opis · adnotacja) pod zdjęciem dania, na dole dok. Tekst przewija
/// się pod dokiem, a jego koniec staje nad nim (`spacing.cookDockReserve`).
struct CookStepView: View {
    let session: CookSession
    let step: CookStep
    /// Skąd przyszedł krok — nowy wjeżdża z tej strony.
    let direction: Edge
    @Binding var card: CookDock.Card?
    let onClose: () -> Void
    let onBack: () -> Void
    let onNext: () -> Void
    let onTimer: (CookTimerAction) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.scPageBase(scheme).ignoresSafeArea()

            ScrollView {
                ZStack(alignment: .topLeading) {
                    CookHeaderPhoto(url: session.imageURL)
                    scene
                        .id(step.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: direction).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .simultaneousGesture(swipe)

            topBar
        }
        .overlay {
            if card != nil {
                SCCook.Palette.scrim(scheme)
                    .ignoresSafeArea()
                    .onTapGesture { card = nil }
                    .transition(.opacity)
                    .accessibilityLabel("Zamknij kartę")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .overlay(alignment: .bottom) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CookDock(
                    session: session,
                    now: context.date,
                    card: $card,
                    onBack: onBack,
                    onNext: onNext,
                    onTimer: onTimer
                )
            }
        }
        .animation(SCCook.Motion.dock, value: card)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CookStepRing(count: session.stepCount, current: session.stepIndex)
                .frame(maxWidth: .infinity, alignment: .leading)
            SCSheetCloseButton(onImage: true, action: onClose)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .padding(.top, 11)
    }

    private var scene: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SCCook.Spacing.titleTop)

            if let stage = step.stageLabel {
                Text(stage)
                    .cookText(SCCook.Typography.stage)
                    .foregroundStyle(SCPalette.sage)
                    .padding(.bottom, 8)
            }

            Text(step.title)
                .cookText(titleStyle)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

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

            Color.clear.frame(height: SCCook.Spacing.dockReserve + 24)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tytuł ≤ 30 znaków mieści się w dwóch liniach 40 pt (zasady .5, D37);
    /// dłuższy (scenariusze sprzed zasad .5) schodzi do 32 pt.
    private var titleStyle: SCCookTextStyle {
        step.title.count > 30 ? SCCook.Typography.stepTitleCompact : SCCook.Typography.stepTitle
    }

    /// Przesunięcie w bok = krok dalej / wstecz (§4.2). Równolegle
    /// z przewijaniem — liczy się tylko wyraźnie poziomy ruch.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.6, card == nil else { return }
                if dx < 0 {
                    if !session.isLastStep { onNext() }
                } else if !session.isFirstStep {
                    onBack()
                }
            }
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
