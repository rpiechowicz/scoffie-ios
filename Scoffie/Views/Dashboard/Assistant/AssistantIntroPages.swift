import SwiftUI

// Wprowadzenie Asystenta v2 (24.09.2026) — makieta Claude Design
// „Scoffie — Asystent · Wprowadzenie v2”
// (claude.ai/artifact/6pXaTCJ3VDrcrTSmmPCGwU).
//
// Cztery ekrany zamiast sześciu: Powitanie → Planowanie → Ty decydujesz →
// Zgoda (`AssistantConsentGateView`). Zgoda stoi NA KOŃCU — decyduje ktoś,
// kto już wie, o co chodzi, a po niej od razu jest rozmowa. Trzy pierwsze
// ekrany żyją tutaj i są wspólne dla zakładki (`AssistantView.introFlow`)
// i arkusza z menu ⋯ „Jak działa Asystent” (`AssistantHowItWorksView`).
//
// Anatomia jak krok przewodnika „Poznaj aplikację” (`TourStepView`): u góry
// scenka zamiast zdjęcia — żywa, na prawdziwych daniach z katalogu — pod nią
// nagłówek kroku (`SCStepHeader`: tytuł i opis PISZĄ SIĘ, jak powitanie
// Asystenta) i trzy punkty w karcie (`SCStepFeatureCard`, kaskada). Liczby
// liczą się od zera (`CountingNumber`), tytuły przycisków rolują
// (`numericText`). Strona ma się mieścić bez przewijania: scenka bierze to,
// co zostaje po ZMIERZONYM tekście (jak zdjęcie w `TourMedia`).
//
// Każda obietnica sprawdzona w kodzie 24.09.2026 (zmieniasz funkcję —
// popraw punkt):
// - dzień / tydzień / dania do wyboru / podmiana z różnicą kalorii i czasu —
//   narzędzia `propose_day_plan`, `propose_week_plan`, `offer_options`,
//   `propose_swap` (backend `src/agent/tools/agent-tools.ts`);
// - „danie z alergenem nie wejdzie do planu” — `collectPlanViolations`
//   w `weekly-plans.service.ts` (`RECIPE_ALLERGEN_CONFLICT`) sprawdza przy
//   zapisie alergeny KAŻDEGO domownika z audytorium, niezależnie od modelu;
// - cofnięcie świeżego zapisu — `canUndo` karty (okno
//   `AI_PROPOSAL_UNDO_WINDOW_MS`, domyślnie godzina — stąd „świeży”, nie
//   „w ciągu doby”);
// - pamięć domu — narzędzie `remember_note` i menu ⋯ → „Pamięć domu”.

/// Strona wprowadzenia (bez zgody, która ma własny widok).
enum AssistantIntroPage: Int, CaseIterable, Identifiable {
    case hello, plan, trust

    var id: Int { rawValue }
}

/// Jedna strona wprowadzenia — bez stopki. Stopkę (`SCStepFooter`) składa
/// rodzic poza animowaną treścią, żeby pasek kroków i przyciski stały
/// w miejscu, gdy strony przejeżdżają na bok.
struct AssistantIntroPageView: View {
    let page: AssistantIntroPage
    /// Odstęp nad treścią — w arkuszu większy, bo w rogu stoi krzyżyk.
    var topPadding: CGFloat = AssistantIntroLayout.top

    var body: some View {
        switch page {
        case .hello:
            AssistantIntroHelloPage(topPadding: topPadding)
        case .plan:
            AssistantIntroPlanPage(topPadding: topPadding)
        case .trust:
            AssistantIntroTrustPage(topPadding: topPadding)
        }
    }
}

enum AssistantIntroLayout {
    /// Margines stron aplikacji — ten sam, co w stopce kroków.
    static let horizontal: CGFloat = SCPageMetrics.horizontal
    /// Jak strona przewodnika (`TourLayout.top`): treść zaczyna się tuż pod
    /// Dynamic Island, bez nagłówka zakładki nad nią.
    static let top: CGFloat = TourLayout.top
    /// W arkuszu z menu nad treścią stoi krzyżyk.
    static let sheetTop: CGFloat = 58
    /// Cień stopki (`SCEdgeShade`) leży na treści — strona kończy się nad nim.
    static let bottom: CGFloat = SCEdgeShade.bottomHeight + 8
    static let stageGap: CGFloat = 16
    /// Promień kadru scenki — ten sam, co zdjęcia kroku przewodnika
    /// (`TourMedia`). Tu, a nie w `AssistantIntroStage`: typ generyczny nie
    /// może mieć statycznej stałej.
    static let stageRadius: CGFloat = 26
    /// Scenka nie schodzi poniżej tego — niżej zdjęcia w kafelkach spadają
    /// pod 44 pt, a przycisk decyzji wychodzi poza kadr; wtedy lepiej
    /// przewinąć (iPhone SE, duża czcionka). Na 16 / 16e scenka ma
    /// ~178 pt przy dwuwierszowym tytule i opisie.
    static let stageMinimum: CGFloat = 172
    static let stageMaximum: CGFloat = 214
    /// Przed pierwszym pomiarem (typowy iPhone 6,1").
    static let stageNatural: CGFloat = 176
}

// MARK: - Rusztowanie strony

/// Przewijana strona wprowadzenia — jak `TourPage`: ma się mieścić bez
/// przewijania, a `ScrollView` jest zabezpieczeniem na małe ekrany i dużą
/// czcionkę (`.basedOnSize` gasi gumowanie, gdy wszystko się mieści).
/// Treść dostaje wysokość, która mieści się bez przewijania (0 przed
/// pierwszym pomiarem).
private struct AssistantIntroScroll<Content: View>: View {
    let topPadding: CGFloat
    let content: (CGFloat) -> Content

    @State private var viewport: CGFloat = 0

    init(topPadding: CGFloat, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.topPadding = topPadding
        self.content = content
    }

    private var available: CGFloat {
        max(0, viewport - topPadding - AssistantIntroLayout.bottom)
    }

    var body: some View {
        ScrollView {
            content(available)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AssistantIntroLayout.horizontal)
                .padding(.top, topPadding)
                .padding(.bottom, AssistantIntroLayout.bottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Przewinięta strona (SE) gaśnie pod Dynamic Island zamiast
        // ucinać się na twardej krawędzi.
        .scScrollEdgeFade()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            viewport = height
        }
    }
}

/// Strona z funkcją: scenka · nagłówek kroku · trzy punkty.
private struct AssistantIntroFeaturePage<SceneContent: View>: View {
    let topPadding: CGFloat
    let accent: Color
    let eyebrow: String
    let title: String
    let lead: String
    let points: [SCStepFeature]
    @ViewBuilder var scene: () -> SceneContent

    /// Nagłówek i karta punktów — reszta strony idzie na scenkę. 330 do
    /// pierwszego pomiaru (dwuwierszowy tytuł, trzy punkty).
    @State private var textHeight: CGFloat = 330
    /// Punkty wchodzą kaskadą, gdy tytuł jest już w połowie pisania.
    @State private var pointsShown = false

    var body: some View {
        AssistantIntroScroll(topPadding: topPadding) { available in
            VStack(alignment: .leading, spacing: 0) {
                AssistantIntroStage(accent: accent) {
                    scene()
                }
                .frame(height: stageHeight(available))
                // Scenka wychodzi 4 pt poza margines tekstu — jak zdjęcie
                // kroku przewodnika (`TourLayout.mediaHorizontal`).
                .padding(.horizontal, -4)
                .padding(.bottom, AssistantIntroLayout.stageGap)

                VStack(alignment: .leading, spacing: 0) {
                    SCStepHeader(
                        accent: accent,
                        eyebrow: eyebrow,
                        title: title,
                        subtitle: lead,
                        typing: 0
                    )
                    .padding(.bottom, 12)

                    SCStepFeatureCard(features: points, revealed: pointsShown, compact: true)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    textHeight = height
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(420))
            if Task.isCancelled { return }
            pointsShown = true
        }
    }

    private func stageHeight(_ available: CGFloat) -> CGFloat {
        guard available > 0 else { return AssistantIntroLayout.stageNatural }
        let room = available - textHeight - AssistantIntroLayout.stageGap
        return min(AssistantIntroLayout.stageMaximum, max(AssistantIntroLayout.stageMinimum, room))
    }
}

/// Kadr scenki: karta aplikacji (`scTileBg` + `scTileStroke`, bez cienia),
/// promień zdjęcia kroku przewodnika i poświata w akcencie kroku od góry —
/// ta sama, co pod zdjęciami w `TourMedia`.
private struct AssistantIntroStage<Content: View>: View {
    let accent: Color
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RadialGradient(
                    colors: [accent.opacity(scheme == .dark ? 0.20 : 0.14), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 240
                )
            )
            .background(
                RoundedRectangle(cornerRadius: AssistantIntroLayout.stageRadius, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .clipShape(RoundedRectangle(cornerRadius: AssistantIntroLayout.stageRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AssistantIntroLayout.stageRadius, style: .continuous)
                    .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
            )
    }
}

// MARK: - 1. Powitanie

/// „Cześć! Jestem Twoim Asystentem” — Asystent przedstawia się sam, tym
/// samym głosem, którym potem odpowiada. Żywy znak zamiast kafelka z ikoną,
/// a na dole pole wiadomości, w którym przykładowe prośby piszą się same:
/// pokazuje, JAK się z nim rozmawia, zamiast o tym opowiadać. Pole stoi tam,
/// gdzie po wprowadzeniu będzie prawdziwe — nad stopką, pod kciukiem.
private struct AssistantIntroHelloPage: View {
    let topPadding: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var markShown = false
    /// Podbicie = znak podskakuje — „cześć”, gdy tytuł się dopisze.
    @State private var cheer = 0
    /// Pole z przykładami wchodzi, gdy tytuł jest napisany. Wcześniej
    /// stałoby w pierwszej klatce pod opisem — zanim strona zmierzy wolne
    /// miejsce — i zjeżdżało na dół skokiem.
    @State private var composerShown = false

    private static let markSize: CGFloat = 48

    var body: some View {
        AssistantIntroScroll(topPadding: topPadding) { available in
            VStack(alignment: .leading, spacing: 0) {
                SCLivingMark(
                    mood: .idle,
                    color: AssistantLook.terraFill(scheme),
                    size: Self.markSize,
                    cheer: cheer,
                    lively: true
                )
                .frame(width: Self.markSize, height: Self.markSize)
                .scaleEffect(markShown || reduceMotion ? 1 : 0.4)
                .opacity(markShown ? 1 : 0)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.35),
                    value: markShown
                )
                .padding(.top, 6)
                .padding(.bottom, 22)
                .accessibilityHidden(true)

                SCStepHeader(
                    accent: SCPalette.terracotta,
                    eyebrow: "Asystent Scoffie",
                    title: "Cześć! Jestem Twoim Asystentem",
                    subtitle: "Napisz zwykłym zdaniem, czego potrzebujesz. Ułożę posiłki z katalogu przepisów — pod dietę, alergeny i cele całego domu.",
                    typing: 0
                )

                Spacer(minLength: 28)

                AssistantIntroComposerDemo(isShown: composerShown)
            }
            // Pole na dole wolnego miejsca, gdy strona mieści się bez
            // przewijania; na małym ekranie po prostu pod opisem.
            .frame(minHeight: available, alignment: .top)
        }
        .task {
            // Klatka oddechu — zmiana w klatce wstawienia nie gra.
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled { return }
            markShown = true
            if reduceMotion {
                composerShown = true
                return
            }
            try? await Task.sleep(for: .milliseconds(820))
            if Task.isCancelled { return }
            cheer += 1
            composerShown = true
        }
    }
}

/// Pole wiadomości z przykładami, które piszą się po kolei — ilustracja, nie
/// kontrolka: nie przyjmuje fokusu, a do VoiceOver trafia jako jedna lista
/// przykładów. Ten sam kształt i kolor, co prawdziwe pole (`AssistantLook.input`).
private struct AssistantIntroComposerDemo: View {
    /// Pole wchodzi (i zaczyna pisać) dopiero na znak od strony.
    let isShown: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Zakładki żyją wszystkie naraz — na niewybranej pętla stoi.
    @Environment(\.scTabIsActive) private var isActiveTab

    static let prompts = [
        "Coś lekkiego na kolację",
        "Ułóż mi cały tydzień obiadów",
        "Co kupić na jutrzejszy obiad?",
        "Zapamiętaj, że w piątki jemy rybę",
    ]
    /// Tempo pisania człowieka, nie Asystenta — wolniej niż powitanie.
    private static let rate: Double = 26
    private static let typingDelay: Double = 0.2
    /// Ile gotowy przykład stoi, zanim zacznie się następny.
    private static let hold: Double = 1.6

    @State private var index = 0
    @State private var sendPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Napisz na przykład")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.scFaint(scheme))
                .padding(.leading, 6)

            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    // Każdy przykład to NOWY tekst (`.id`) — rodzi się jako
                    // „do napisania”, bez mignięcia gotowym zdaniem. Przed
                    // wejściem pola nie ma go wcale, więc pierwszy przykład
                    // też pisze się na oczach.
                    if isShown {
                        SCTypedText(Self.prompts[index], playKey: 0, rate: Self.rate, delay: Self.typingDelay)
                            .id(index)
                            .transition(.opacity)
                    }
                }
                .font(.system(size: 16))
                .tracking(-0.3)
                .foregroundStyle(AssistantLook.ink(scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AssistantLook.terra(scheme))
                    .frame(width: 38, height: 38)
                    .scSoftSurface(Circle(), accent: AssistantLook.terra(scheme))
                    .scaleEffect(sendPressed ? 0.86 : 1)
            }
            .padding(.leading, 18)
            .padding(.trailing, 7)
            .frame(height: 52)
            .background(Capsule(style: .continuous).fill(AssistantLook.input(scheme)))
            .overlay(Capsule(style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))

            // Który przykład — jak kropki kart, bieżący rozciągnięty.
            HStack(spacing: 5) {
                ForEach(Self.prompts.indices, id: \.self) { item in
                    Capsule(style: .continuous)
                        .fill(item == index ? AssistantLook.terraFill(scheme) : Color.scBarTrack(scheme))
                        .frame(width: item == index ? 16 : 6, height: 4)
                }
            }
            .padding(.leading, 6)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
        }
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown || reduceMotion ? 0 : 10)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.5), value: isShown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Przykłady próśb do Asystenta: \(Self.prompts.joined(separator: ", "))")
        .task(id: isActiveTab && isShown) {
            guard isActiveTab, isShown, !reduceMotion else { return }
            while !Task.isCancelled {
                let typing = Self.typingDelay + SCTypedText.duration(Self.prompts[index], rate: Self.rate)
                try? await Task.sleep(for: .seconds(typing + 0.25))
                if Task.isCancelled { return }
                // „Wysłanie”: krążek się wciska i puszcza.
                withAnimation(.easeOut(duration: 0.12)) { sendPressed = true }
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { sendPressed = false }
                try? await Task.sleep(for: .seconds(Self.hold))
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    index = (index + 1) % Self.prompts.count
                }
            }
        }
    }
}

// MARK: - 2. Planowanie

/// Dzień, tydzień, dania do wyboru, podmiana. Scenka to najczęstsza rozmowa:
/// „coś lekkiego na kolację” → trzy dania ze zdjęciem, kaloriami i czasem,
/// jak w arkuszu wyboru posiłku.
private struct AssistantIntroPlanPage: View {
    let topPadding: CGFloat

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore

    /// Losowane RAZ na wejście strony — dania nie tasują się przy
    /// przerysowaniu.
    @State private var dishes: [AssistantIntroDish] = AssistantIntroDish.fallbackDinners

    var body: some View {
        AssistantIntroFeaturePage(
            topPadding: topPadding,
            accent: SCPalette.terracotta,
            eyebrow: "Planowanie",
            title: "Dzień, tydzień albo jedno danie",
            lead: "Napisz, na co masz ochotę. Dania biorę z katalogu przepisów i od razu liczę kalorie.",
            points: [
                SCStepFeature(icon: "calendar", accent: SCPalette.terracotta, title: "Dzień albo cały tydzień", subtitle: "Z kaloriami na każdy dzień"),
                SCStepFeature(icon: "square.grid.2x2.fill", accent: SCPalette.terracotta, title: "Dania do wyboru", subtitle: "Ze zdjęciem, kaloriami i czasem"),
                SCStepFeature(icon: "arrow.triangle.2.circlepath", accent: SCPalette.terracotta, title: "Podmiana dania", subtitle: "Z różnicą kalorii i czasu"),
            ]
        ) {
            AssistantIntroOptionsScene(dishes: dishes)
        }
        // Przy wejściu — i jeszcze raz, gdy katalog doładuje się później
        // (arkusz „Jak działa” otwarty tuż po starcie): wtedy stały tu dania
        // zastępcze bez zdjęć. Raz dobrane prawdziwe dania już nie tasują się.
        .onChange(of: recipeCatalogStore.recipes.count, initial: true) { _, _ in
            guard dishes.contains(where: { $0.imageURL == nil }) else { return }
            let picked = AssistantIntroDish.lightDinners(from: recipeCatalogStore.recipes)
            if !picked.isEmpty { dishes = picked }
        }
    }
}

/// Dymek prośby, który się dopisuje, i trzy dania wchodzące kaskadą —
/// kalorie liczą się od zera, gdy danie się pojawia.
private struct AssistantIntroOptionsScene: View {
    let dishes: [AssistantIntroDish]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var bubbleShown = false
    @State private var dishesShown = false

    private static let request = "Coś lekkiego na kolację"
    private static let requestRate: Double = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AssistantIntroRequestBubble(text: Self.request, rate: Self.requestRate, shown: bubbleShown)

            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(dishes.prefix(3).enumerated()), id: \.element.id) { order, dish in
                    AssistantIntroDishTile(dish: dish, shown: dishesShown, order: order)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Przykład: prośba „\(Self.request)” i trzy dania do wyboru: \(dishes.prefix(3).map(\.name).joined(separator: ", "))")
        .task {
            if reduceMotion {
                bubbleShown = true
                dishesShown = true
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
            bubbleShown = true
            let typing = AssistantIntroRequestBubble.typingDelay + SCTypedText.duration(Self.request, rate: Self.requestRate)
            try? await Task.sleep(for: .seconds(typing + 0.2))
            if Task.isCancelled { return }
            dishesShown = true
        }
    }
}

/// Dymek użytkownika jak w rozmowie (`AssistantUserBubble`: tint terakoty,
/// ścięty róg przy krawędzi), mniejszy o stopień pisma — w scence stoi obok
/// trzech kafli.
private struct AssistantIntroRequestBubble: View {
    let text: String
    let rate: Double
    let shown: Bool

    static let typingDelay: Double = 0.12

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 6,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Group {
                if shown {
                    SCTypedText(text, playKey: 0, rate: rate, delay: Self.typingDelay)
                } else {
                    // Układ od pierwszej klatki — dymek nie rośnie przy wejściu.
                    Text(text).hidden()
                }
            }
            .font(.system(size: 15))
            .tracking(-0.3)
            .foregroundStyle(AssistantLook.ink(scheme))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(shape.fill(AssistantLook.terraTint2(scheme)))
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4), value: shown)
        }
    }
}

/// Danie w scenie: zdjęcie (bierze wysokość, która zostaje w kadrze), nazwa
/// w dwóch liniach i „424 kcal · 10 min” z liczącymi się kaloriami.
private struct AssistantIntroDishTile: View {
    let dish: AssistantIntroDish
    let shown: Bool
    let order: Int

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var delay: Double { Double(order) * 0.08 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AssistantIntroDishPhoto(dish: dish, radius: 12)
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: .infinity)

            Text(dish.name)
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(2, reservesSpace: true)
                .padding(.top, 7)

            HStack(spacing: 0) {
                CountingNumber(
                    target: shown ? dish.kcal : 0,
                    changeAnimation: Animation.easeOut(duration: 0.9).delay(0.1 + delay)
                )
                .fontWeight(.semibold)
                .foregroundStyle(Color.scLabel(scheme))
                Text(" kcal · \(dish.minutes) min")
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .font(.system(size: 11.5))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 12)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.5).delay(delay),
            value: shown
        )
    }
}

/// Zdjęcie dania z katalogu, bez zdjęcia — gradient pory i jej ikona (jak
/// kafel Planu bez fotografii).
private struct AssistantIntroDishPhoto: View {
    let dish: AssistantIntroDish
    let radius: CGFloat

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .overlay {
                if let url = dish.imageURL {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            dish.slot.cozyGradient.opacity(0.55)
            Image(systemName: dish.slot.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }
}

// MARK: - 3. Ty decydujesz

/// Nic nie zapisuje się samo. Scenka to chwila decyzji: propozycja obiadu
/// na jutro z dwoma sprawdzeniami, a po chwili „Dodaj do planu” sam się
/// wciska i roluje w „Jest w planie” — obok wjeżdża „Cofnij”.
private struct AssistantIntroTrustPage: View {
    let topPadding: CGFloat

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore

    @State private var dish: AssistantIntroDish = AssistantIntroDish.fallbackLunch

    var body: some View {
        AssistantIntroFeaturePage(
            topPadding: topPadding,
            accent: SCPalette.sage,
            eyebrow: "Ty decydujesz",
            title: "Nic nie trafia do planu bez Ciebie",
            lead: "Każda propozycja przychodzi jako karta. Zapisujesz ją jednym stuknięciem albo prosisz o zmianę.",
            points: [
                SCStepFeature(icon: "checkmark.shield.fill", accent: SCPalette.sage, title: "Alergeny całego domu", subtitle: "Danie z alergenem nie wejdzie do planu"),
                SCStepFeature(icon: "arrow.uturn.backward", accent: SCPalette.sage, title: "Cofnięcie zapisu", subtitle: "Świeży zapis zdejmiesz jednym stuknięciem"),
                SCStepFeature(icon: "brain.head.profile", accent: SCPalette.sage, title: "Pamięć domu", subtitle: "Stałe zwyczaje, np. ryba w piątki"),
            ]
        ) {
            AssistantIntroDecisionScene(dish: dish)
        }
        // Jak na Planowaniu: przy wejściu i po doładowaniu katalogu, dopóki
        // stoi danie zastępcze.
        .onChange(of: recipeCatalogStore.recipes.count, initial: true) { _, _ in
            guard dish.imageURL == nil else { return }
            if let picked = AssistantIntroDish.lunch(from: recipeCatalogStore.recipes) {
                dish = picked
            }
        }
    }
}

/// Propozycja z decyzją. Choreografia: danie wchodzi (kalorie liczą się od
/// zera) → dwa sprawdzenia → przycisk sam się wciska i roluje tytuł, obok
/// wjeżdża „Cofnij”. Przy „Ogranicz ruch” — od razu stan po zapisie.
private struct AssistantIntroDecisionScene: View {
    let dish: AssistantIntroDish

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown = false
    @State private var checksShown = false
    @State private var pressed = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                AssistantIntroDishPhoto(dish: dish, radius: 15)
                    .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: dish.slot.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text("\(dish.slot.title) · jutro")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(dish.slot.cozyAccent)

                    Text(dish.name)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 0) {
                        Text("\(dish.minutes) min · ")
                            .foregroundStyle(Color.scMuted(scheme))
                        CountingNumber(
                            target: shown ? dish.kcal : 0,
                            changeAnimation: Animation.easeOut(duration: 0.9).delay(0.1)
                        )
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.scLabel(scheme))
                        Text(" kcal")
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                }
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.5), value: shown)

            HStack(spacing: 14) {
                check("Alergeny sprawdzone", order: 0)
                check("W celu dnia", order: 1)
            }
            .padding(.top, 9)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if saved {
                    AssistantIntroGhostChip(title: "Cofnij", icon: "arrow.uturn.backward")
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                acceptButton
            }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82), value: saved)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Przykład: propozycja „\(dish.name)” na jutro, alergeny sprawdzone, po zatwierdzeniu jest w planie i można ją cofnąć.")
        .task { await play() }
    }

    private func check(_ title: String, order: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(AssistantLook.sage(scheme))
        .opacity(checksShown ? 1 : 0)
        .scaleEffect(checksShown || reduceMotion ? 1 : 0.85, anchor: .leading)
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7).delay(Double(order) * 0.12),
            value: checksShown
        )
    }

    /// Zgoda w szałwii — jak `ProposalAcceptButton` w arkuszu propozycji.
    private var acceptButton: some View {
        let tone = AssistantLook.sage(scheme)
        return HStack(spacing: 7) {
            Image(systemName: saved ? "checkmark" : "plus")
                .font(.system(size: 13, weight: .heavy))
                .contentTransition(.symbolEffect(.replace))
            Text(saved ? "Jest w planie" : "Dodaj do planu")
                .font(.system(size: 14, weight: .bold))
                .tracking(-0.1)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .foregroundStyle(tone)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .scSoftCapsule(tone)
        .scaleEffect(pressed ? 0.95 : 1)
        .animation(SCMotion.textRoll, value: saved)
    }

    private func play() async {
        if reduceMotion {
            shown = true
            checksShown = true
            saved = true
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        shown = true
        try? await Task.sleep(for: .milliseconds(650))
        if Task.isCancelled { return }
        checksShown = true
        try? await Task.sleep(for: .milliseconds(1000))
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.12)) { pressed = true }
        try? await Task.sleep(for: .milliseconds(140))
        if Task.isCancelled { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.6)) { pressed = false }
        saved = true
    }
}

/// Neutralna kapsuła obok przycisku zgody — „Cofnij” z karty po zapisie.
private struct AssistantIntroGhostChip: View {
    let title: String
    let icon: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 13.5, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.scLabel(scheme))
        .padding(.horizontal, 15)
        .frame(height: 40)
        .overlay(Capsule(style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))
        .fixedSize()
    }
}

// MARK: - Dania do scenek

/// Danie w scence — prawdziwy przepis z katalogu, żeby zdjęcia i liczby były
/// takie, jak zobaczy się potem w rozmowie.
struct AssistantIntroDish: Identifiable {
    let id: String
    let name: String
    let imageURL: URL?
    let kcal: Int
    let minutes: Int
    let slot: MealSlot

    init(id: String, name: String, imageURL: URL?, kcal: Int, minutes: Int, slot: MealSlot) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.kcal = kcal
        self.minutes = minutes
        self.slot = slot
    }

    init(recipe: Recipe, slot: MealSlot) {
        self.init(
            id: recipe.id.uuidString,
            name: recipe.name,
            imageURL: recipe.imageURL,
            kcal: Int(recipe.nutritionPerServing.kcal.rounded()),
            minutes: recipe.prepTimeMinutes,
            slot: slot
        )
    }

    /// Pula dań, które wolno pokazać TEJ osobie: ze zdjęciem, z policzonymi
    /// makrami i bez tego, co jej dieta i alergeny z Ustawień i tak chowają —
    /// scenka o pilnowaniu alergenów nie może podsuwać dania z alergenem.
    @MainActor
    private static func pool(from recipes: [Recipe], slot: MealSlot, maxMinutes: Int) -> [Recipe] {
        let defaults = UserDefaults.standard
        let profile = RecipePersonalization(
            dietRaw: defaults.string(forKey: RecipePersonalization.Keys.diet) ?? "",
            allergensRaw: defaults.string(forKey: RecipePersonalization.Keys.allergens) ?? "",
            goalRaw: defaults.string(forKey: RecipePersonalization.Keys.goal) ?? "",
            calorieGoal: defaults.integer(forKey: RecipePersonalization.Keys.calorieGoal),
            isEnabled: true
        )
        return recipes.filter { recipe in
            recipe.fits(slot)
                && recipe.imageURL != nil
                && recipe.hasNutritionData
                && recipe.prepTimeMinutes > 0
                && recipe.prepTimeMinutes <= maxMinutes
                && !profile.excludes(recipe)
        }
    }

    /// Trzy lekkie kolacje: z najlżejszej ćwiartki puli, losowo — każde
    /// wejście może pokazać inne, ale zawsze pasujące do „coś lekkiego”.
    /// Przy wąskiej diecie (mało szybkich kolacji ze zdjęciem) pula
    /// rozszerza się o dłuższe gotowanie, zanim scenka zejdzie do dań
    /// zastępczych.
    @MainActor
    static func lightDinners(from recipes: [Recipe]) -> [AssistantIntroDish] {
        for maxMinutes in [30, 90] {
            let light = pool(from: recipes, slot: .dinner, maxMinutes: maxMinutes)
                .sorted { $0.nutritionPerServing.kcal < $1.nutritionPerServing.kcal }
            let candidates = Array(light.prefix(max(9, light.count / 4)))
            guard candidates.count >= 3 else { continue }
            return candidates.shuffled()
                .prefix(3)
                .sorted { $0.nutritionPerServing.kcal < $1.nutritionPerServing.kcal }
                .map { AssistantIntroDish(recipe: $0, slot: .dinner) }
        }
        return []
    }

    /// Obiad na jutro do scenki decyzji.
    @MainActor
    static func lunch(from recipes: [Recipe]) -> AssistantIntroDish? {
        pool(from: recipes, slot: .lunch, maxMinutes: 45)
            .randomElement()
            .map { AssistantIntroDish(recipe: $0, slot: .lunch) }
    }

    /// Zanim katalog się wczyta (albo gdy jest pusty) — dania z katalogu
    /// zapisane na sztywno, bez zdjęć: kafel pory zamiast fotografii.
    /// Wegetariańskie, bo tu nie da się odsiać diety.
    static let fallbackDinners: [AssistantIntroDish] = [
        AssistantIntroDish(id: "fallback-1", name: "Sałatka z jajkiem i rzodkiewką", imageURL: nil, kcal: 489, minutes: 20, slot: .dinner),
        AssistantIntroDish(id: "fallback-2", name: "Sałatka z brokułem i jajkiem", imageURL: nil, kcal: 490, minutes: 20, slot: .dinner),
        AssistantIntroDish(id: "fallback-3", name: "Bruschetta z pomidorami i bazylią", imageURL: nil, kcal: 507, minutes: 20, slot: .dinner),
    ]

    static let fallbackLunch = AssistantIntroDish(
        id: "fallback-lunch",
        name: "Risotto z dynią i parmezanem",
        imageURL: nil,
        kcal: 666,
        minutes: 45,
        slot: .lunch
    )
}

#Preview("Powitanie · Dark") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        VStack(spacing: 0) {
            AssistantIntroPageView(page: .hello)
            SCStepFooter(slot: .link("Pomiń wprowadzenie"), onSlotTap: {}, backPlacement: .besidePrimary, primaryTitle: "Zobacz, jak działa", onPrimary: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Planowanie · Light") {
    ZStack {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        VStack(spacing: 0) {
            AssistantIntroPageView(page: .plan)
            SCStepFooter(slot: .progress(step: 1, total: 3), showsBack: true, onBack: {}, backPlacement: .besidePrimary, primaryTitle: "Dalej", onPrimary: {})
        }
    }
    .preferredColorScheme(.light)
}

#Preview("Ty decydujesz · Dark") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        VStack(spacing: 0) {
            AssistantIntroPageView(page: .trust)
            SCStepFooter(slot: .progress(step: 2, total: 3), showsBack: true, onBack: {}, backPlacement: .besidePrimary, primaryTitle: "Dalej", onPrimary: {})
        }
    }
    .preferredColorScheme(.dark)
}
