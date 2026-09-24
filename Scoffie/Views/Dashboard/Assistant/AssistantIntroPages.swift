import SwiftUI

// Wprowadzenie Asystenta — makieta Claude Design „Scoffie — Asystent ·
// Wprowadzenie v2” (claude.ai/artifact/6pXaTCJ3VDrcrTSmmPCGwU).
//
// Cztery ekrany: Powitanie → Planowanie → Ty decydujesz → Zgoda
// (`AssistantConsentGateView`). Zgoda stoi NA KOŃCU — decyduje ktoś, kto już
// wie, o co chodzi, a po niej od razu jest rozmowa. Trzy pierwsze ekrany żyją
// tutaj i są wspólne dla zakładki (`AssistantView.introFlow`) i arkusza
// z menu ⋯ „Jak działa Asystent” (`AssistantHowItWorksView`).
//
// v3 (24.09.2026, Rafał: „na 1 widoku dużo wolnej przestrzeni”, „od góry
// trochę za bardzo przycięte”, „widok, gdzie user wpisuje prompt i ma
// odpowiedzi — zrób to ładniej”):
// - powitanie to JEDEN zwarty blok na środku wolnego miejsca, a znak ma nad
//   sobą oddech na poświatę i podskok — w v2 stał 22 pt pod górną krawędzią
//   przewijanej strony, która ucinała poświatę poziomą linią, a pole
//   z przykładami stało przy stopce, z dziurą nad sobą;
// - scenki stoją na PRAWDZIWYCH klockach rozmowy: dymek jak
//   `AssistantUserBubble`, `AssistantCard` + `AssistantCardHead` +
//   `AssistantMealRow` + `AssistantCardActions` — wyglądają dokładnie tak, jak
//   to, co przyjdzie potem w rozmowie. Bez ramki wokół: karta w karcie
//   ściskała wszystko (ten sam powód zdjął ramkę z kart „Poznaj” w v1);
// - punkty to etykiety z ikoną (`SCTag`, strój etykiet alergenów) zamiast
//   karty trzech wierszy — scenka ma miejsce, a tekstu jest mniej.
//
// Ruch: tytuł i opis PISZĄ SIĘ (`SCStepHeader(typing:)`), dymek też, liczby
// liczą się od zera (`CountingNumber` w `AssistantMealRow`), a tytuły
// przycisków karty rolują (`numericText`) przy zmianie stanu.
//
// Każda obietnica sprawdzona w kodzie 24.09.2026 (zmieniasz funkcję —
// popraw etykietę):
// - dzień / tydzień / dania do wyboru / podmiana — narzędzia
//   `propose_day_plan`, `propose_week_plan`, `offer_options`, `propose_swap`
//   (backend `src/agent/tools/agent-tools.ts`);
// - „sprawdzona pod alergeny całego domu” — `collectPlanViolations`
//   w `weekly-plans.service.ts` (`RECIPE_ALLERGEN_CONFLICT`) sprawdza przy
//   zapisie alergeny KAŻDEGO domownika z audytorium, niezależnie od modelu;
// - cofnięcie świeżego zapisu — `canUndo` karty (okno
//   `AI_PROPOSAL_UNDO_WINDOW_MS`, domyślnie godzina — nie „w ciągu doby”);
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
    /// Jak strona przewodnika (`TourLayout.top`): treść zaczyna się pod
    /// Dynamic Island, bez nagłówka zakładki nad nią.
    static let top: CGFloat = TourLayout.top
    /// W arkuszu z menu nad treścią stoi krzyżyk.
    static let sheetTop: CGFloat = 58
    /// Cień stopki (`SCEdgeShade`) leży na treści — strona kończy się nad nim.
    static let bottom: CGFloat = SCEdgeShade.bottomHeight + 8
    /// Scenka → nagłówek kroku.
    static let sceneGap: CGFloat = 20
    /// Nagłówek kroku → etykiety.
    static let tagsGap: CGFloat = 14
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

/// Strona z funkcją: scenka z prawdziwych klocków rozmowy · nagłówek kroku ·
/// etykiety.
private struct AssistantIntroFeaturePage<SceneContent: View>: View {
    let topPadding: CGFloat
    let accent: Color
    let eyebrow: String
    let title: String
    let lead: String
    let tags: [AssistantIntroTag]
    @ViewBuilder var scene: () -> SceneContent

    /// Etykiety wchodzą kaskadą, gdy tytuł jest w połowie pisania.
    @State private var tagsShown = false

    var body: some View {
        AssistantIntroScroll(topPadding: topPadding) { _ in
            VStack(alignment: .leading, spacing: 0) {
                scene()
                    .padding(.bottom, AssistantIntroLayout.sceneGap)

                SCStepHeader(
                    accent: accent,
                    eyebrow: eyebrow,
                    title: title,
                    subtitle: lead,
                    typing: 0
                )

                AssistantIntroTagRow(tags: tags, shown: tagsShown)
                    .padding(.top, AssistantIntroLayout.tagsGap)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(420))
            if Task.isCancelled { return }
            tagsShown = true
        }
    }
}

// MARK: - Etykiety

/// Punkt strony jako etykieta (`SCTag`).
struct AssistantIntroTag: Identifiable {
    let title: String
    let icon: String
    let accent: Color

    var id: String { title }
}

/// Etykiety w chmurze (`AllergenChipFlow` — ta sama, co chipy powitania),
/// wchodzące kaskadą.
private struct AssistantIntroTagRow: View {
    let tags: [AssistantIntroTag]
    let shown: Bool

    var body: some View {
        AllergenChipFlow(spacing: 8) {
            ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                SCTag(title: tag.title, icon: tag.icon, accent: tag.accent)
                    .scReveal(shown, order: index)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 1. Powitanie

/// „Cześć! Jestem Twoim Asystentem” — Asystent przedstawia się sam, tym
/// samym głosem, którym potem odpowiada. Jeden zwarty blok: żywy znak,
/// nagłówek, pole wiadomości, w którym przykładowe prośby piszą się same
/// (pokazuje, JAK się z nim rozmawia), i trzy etykiety tego, pod co układa.
private struct AssistantIntroHelloPage: View {
    let topPadding: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var markShown = false
    /// Podbicie = znak podskakuje — „cześć”, gdy tytuł się dopisze.
    @State private var cheer = 0
    /// Pole z przykładami i etykiety wchodzą, gdy tytuł jest napisany —
    /// pierwszy przykład nie pisze się razem z tytułem.
    @State private var composerShown = false
    @State private var tagsShown = false

    private static let markSize: CGFloat = 52
    /// Oddech nad znakiem. Poświata `lively` sięga 1,2 boku od środka,
    /// a podskok unosi znak o 0,3 boku — razem z odstępem strony (16) to
    /// musi zmieścić się pod górną krawędzią przewijanej strony. W v2 znak
    /// stał 22 pt pod nią i poświatę ucinała pozioma linia („za bardzo
    /// przycięte od góry”).
    private static let markHeadroom: CGFloat = 38

    private static let tags = [
        AssistantIntroTag(title: "Pod Twoją dietę", icon: "leaf.fill", accent: SCPalette.sage),
        AssistantIntroTag(title: "Dla całego domu", icon: "person.2.fill", accent: SCPalette.indigo),
        AssistantIntroTag(title: "Z katalogu przepisów", icon: "book.fill", accent: SCPalette.butter),
    ]

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
                .padding(.top, Self.markHeadroom)
                .padding(.bottom, 22)
                .accessibilityHidden(true)

                SCStepHeader(
                    accent: SCPalette.terracotta,
                    eyebrow: "Asystent Scoffie",
                    title: "Cześć! Jestem Twoim Asystentem",
                    subtitle: "Napisz zwykłym zdaniem, czego potrzebujesz. Resztą zajmę się ja — od planu po zakupy.",
                    typing: 0
                )

                AssistantIntroComposerDemo(isShown: composerShown)
                    .padding(.top, 22)

                AssistantIntroTagRow(tags: Self.tags, shown: tagsShown)
                    .padding(.top, 20)
            }
            // Zwarty blok na środku wolnego miejsca: bez dziury między
            // opisem a polem (v2 dosuwało pole do stopki).
            .frame(minHeight: available, alignment: .leading)
            // Do pierwszego pomiaru (`available == 0`) blok stałby u góry
            // i w następnej klatce przeskakiwał na środek — niech go nie widać.
            .opacity(available > 0 ? 1 : 0)
        }
        .task {
            // Klatka oddechu — zmiana w klatce wstawienia nie gra.
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled { return }
            markShown = true
            if reduceMotion {
                composerShown = true
                tagsShown = true
                return
            }
            try? await Task.sleep(for: .milliseconds(820))
            if Task.isCancelled { return }
            cheer += 1
            composerShown = true
            try? await Task.sleep(for: .milliseconds(260))
            if Task.isCancelled { return }
            tagsShown = true
        }
    }
}

/// Pole wiadomości z przykładami, które piszą się po kolei — ilustracja, nie
/// kontrolka: nie przyjmuje fokusu, a do VoiceOver trafia jako jedna lista
/// przykładów. Wygląd prawdziwego pola (`AssistantView.composerField`):
/// kapsuła 50 pt w `AssistantLook.input`, a obok osobny krążek wysyłania
/// w wariancie „soft”.
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

            HStack(spacing: 10) {
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
                .font(.system(size: 16.5))
                .tracking(-0.3)
                .foregroundStyle(AssistantLook.ink(scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .background(Capsule(style: .continuous).fill(AssistantLook.input(scheme)))
                .overlay(Capsule(style: .continuous).stroke(AssistantLook.cardStroke(scheme), lineWidth: 1))

                ZStack {
                    Color.clear
                        .scSoftSurface(Circle())
                    Image(systemName: "arrow.up")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                }
                .frame(width: 50, height: 50)
                .scaleEffect(sendPressed ? 0.86 : 1)
            }

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

/// Dzień, tydzień, dania do wyboru, podmiana. Scenka to najczęstsza rozmowa
/// w jej prawdziwym stroju: „Coś lekkiego na kolację” → karta „Do wyboru”
/// z trzema daniami → wybór jednego.
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
            tags: [
                // Krótkie, żeby stały w JEDNYM wierszu także na 16e (350 pt) —
                // „Dzień i tydzień” zawijało wiersz i strona zaczynała się
                // przewijać; dzień i tydzień mówi już tytuł.
                AssistantIntroTag(title: "Do wyboru", icon: "square.grid.2x2.fill", accent: SCPalette.terracotta),
                AssistantIntroTag(title: "Podmiana", icon: "arrow.triangle.2.circlepath", accent: SCPalette.terracotta),
                AssistantIntroTag(title: "Zakupy", icon: "cart.fill", accent: SCPalette.terracotta),
            ]
        ) {
            AssistantIntroOptionsScene(dishes: dishes)
        }
        // Przy wejściu — i jeszcze raz, gdy katalog doładuje się później
        // (arkusz „Jak działa” otwarty tuż po starcie): wtedy stały tu dania
        // zastępcze bez zdjęć. Raz dobrane prawdziwe dania już nie tasują się.
        .onChange(of: recipeCatalogStore.recipes.count, initial: true) { _, _ in
            guard dishes.contains(where: { !$0.fromCatalog }) else { return }
            let picked = AssistantIntroDish.lightDinners(from: recipeCatalogStore.recipes)
            if !picked.isEmpty { dishes = picked }
        }
    }
}

/// Rozmowa w miniaturze: dymek prośby, który się dopisuje, karta „Do wyboru”
/// jak w rozmowie (`AssistantOptionsCard`: nagłówek, dania z miniaturą
/// i kaloriami), a po chwili wybór — przy daniu ptaszek w szałwii, reszta
/// przygasa, tak jak po „Wybieram: …”.
private struct AssistantIntroOptionsScene: View {
    let dishes: [AssistantIntroDish]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var bubbleShown = false
    @State private var cardShown = false
    @State private var chosen = false

    private static let request = "Coś lekkiego na kolację"
    private static let requestRate: Double = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AssistantIntroRequestBubble(text: Self.request, rate: Self.requestRate, shown: bubbleShown)

            AssistantCard {
                AssistantCardHead(eyebrow: "Do wyboru", eyebrowDetail: "kolacja", title: "Trzy lekkie kolacje")

                VStack(spacing: 12) {
                    ForEach(Array(dishes.prefix(3).enumerated()), id: \.element.id) { order, dish in
                        optionRow(dish, order: order)
                            .scReveal(cardShown, order: order + 1)
                    }
                }
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
            // Karta stoi w układzie od pierwszej klatki (nagłówek kroku pod
            // nią nie skacze) i tylko się pokazuje.
            .opacity(cardShown ? 1 : 0)
            .offset(y: cardShown || reduceMotion ? 0 : 14)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.5), value: cardShown)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Przykład: prośba „\(Self.request)” i karta z trzema daniami do wyboru: \(dishes.prefix(3).map(\.name).joined(separator: ", "))")
        .task { await play() }
    }

    /// Wiersz jak w karcie „Do wyboru” (`anchorRow`): wybrane danie
    /// pogrubione z ptaszkiem, pozostałe przygaszone. Kalorie wchodzą razem
    /// z kartą i liczą się od zera (`AssistantMealRow` pokazuje je od `kcal > 0`).
    private func optionRow(_ dish: AssistantIntroDish, order: Int) -> some View {
        let isFirst = order == 0
        let picked = chosen && isFirst
        return HStack(spacing: 8) {
            AssistantMealRow(
                slot: nil,
                title: dish.name,
                imageUrl: dish.imageURL?.absoluteString,
                kcal: cardShown ? dish.kcal : 0,
                size: 40,
                muted: chosen && !isFirst,
                titleWeight: picked ? .semibold : .medium,
                kcalAnimation: AssistantIntroDish.countAnimation(order: order)
            )
            if picked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AssistantLook.sage(scheme))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: chosen)
    }

    private func play() async {
        if reduceMotion {
            bubbleShown = true
            cardShown = true
            chosen = true
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        bubbleShown = true
        let typing = AssistantIntroRequestBubble.typingDelay + SCTypedText.duration(Self.request, rate: Self.requestRate)
        try? await Task.sleep(for: .seconds(typing + 0.2))
        if Task.isCancelled { return }
        cardShown = true
        try? await Task.sleep(for: .milliseconds(1400))
        if Task.isCancelled { return }
        chosen = true
    }
}

/// Dymek użytkownika w stroju rozmowy (`AssistantUserBubble`: 16/−0,3,
/// tint terakoty, ścięty róg przy krawędzi), który się dopisuje.
private struct AssistantIntroRequestBubble: View {
    let text: String
    let rate: Double
    let shown: Bool

    static let typingDelay: Double = 0.12

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 6,
            topTrailingRadius: 20,
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
            .font(.system(size: 16))
            .tracking(-0.3)
            .foregroundStyle(AssistantLook.ink(scheme))
            .lineLimit(1)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(shape.fill(AssistantLook.terraTint2(scheme)))
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.4), value: shown)
        }
    }
}

// MARK: - 3. Ty decydujesz

/// Nic nie zapisuje się samo. Scenka to prawdziwa karta propozycji dnia:
/// najpierw „Do zatwierdzenia” z [Inny zestaw] [Zapisz dzień], po chwili
/// przycisk sam się wciska (kręciołek), karta przechodzi w szałwię,
/// plakietka w „Zapisane”, a stopka w [Cofnij] [Otwórz plan].
private struct AssistantIntroTrustPage: View {
    let topPadding: CGFloat

    @Environment(\.recipeCatalogStore) private var recipeCatalogStore

    @State private var day: [AssistantIntroDish] = AssistantIntroDish.fallbackDay

    var body: some View {
        AssistantIntroFeaturePage(
            topPadding: topPadding,
            accent: SCPalette.sage,
            eyebrow: "Ty decydujesz",
            title: "Nic nie trafia do planu bez Ciebie",
            lead: "Każda propozycja przychodzi jako karta. Do planu trafia dopiero po Twoim stuknięciu.",
            tags: [
                AssistantIntroTag(title: "Alergeny", icon: "checkmark.shield.fill", accent: SCPalette.sage),
                AssistantIntroTag(title: "Cofnięcie", icon: "arrow.uturn.backward", accent: SCPalette.sage),
                AssistantIntroTag(title: "Pamięć domu", icon: "brain.head.profile", accent: SCPalette.sage),
            ]
        ) {
            AssistantIntroDecisionScene(day: day)
        }
        // Jak na Planowaniu: przy wejściu i po doładowaniu katalogu, dopóki
        // stoją dania zastępcze.
        .onChange(of: recipeCatalogStore.recipes.count, initial: true) { _, _ in
            guard day.contains(where: { !$0.fromCatalog }) else { return }
            let picked = AssistantIntroDish.day(from: recipeCatalogStore.recipes)
            if !picked.isEmpty { day = picked }
        }
    }
}

/// Karta propozycji dnia na klockach rozmowy. Przy „Ogranicz ruch” — od razu
/// stan po zapisie.
private struct AssistantIntroDecisionScene: View {
    let day: [AssistantIntroDish]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown = false
    @State private var busy = false
    @State private var saved = false

    private var status: AssistantCardStatus { saved ? .applied : .pending }

    /// Te same słowa, co karta dnia w rozmowie (`AssistantPlanDayCard`:
    /// „Zapisz dzień” / „Inny zestaw”, po zapisie „Otwórz plan” / „Cofnij”).
    private var primary: AssistantCardAction {
        saved
            ? AssistantCardAction(title: "Otwórz plan", icon: "arrow.right", action: {})
            : AssistantCardAction(title: "Zapisz dzień", action: {})
    }

    private var secondary: AssistantCardAction {
        saved
            ? AssistantCardAction(title: "Cofnij", icon: "arrow.uturn.backward", action: {})
            : AssistantCardAction(title: "Inny zestaw", action: {})
    }

    var body: some View {
        AssistantCard(tone: status.tone) {
            AssistantCardHead(
                eyebrow: "Propozycja",
                eyebrowDetail: "jutro",
                title: nil,
                // Obietnica tylko przy daniach z katalogu, odsianych dietą
                // i alergenami z Ustawień — zastępcze (katalog się nie wczytał)
                // przez ten filtr nie przeszły.
                subtitle: day.allSatisfy(\.fromCatalog) ? "Sprawdzona pod alergeny całego domu" : nil,
                status: status
            )

            VStack(spacing: 10) {
                ForEach(Array(day.enumerated()), id: \.element.id) { order, dish in
                    AssistantMealRow(
                        slot: dish.slot.title,
                        title: dish.name,
                        imageUrl: dish.imageURL?.absoluteString,
                        kcal: shown ? dish.kcal : 0,
                        size: 36,
                        kcalAnimation: AssistantIntroDish.countAnimation(order: order)
                    )
                    .scReveal(shown, order: order + 1)
                }
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 12)
            .padding(.bottom, 14)

            AssistantCardActions(
                primary: primary,
                secondary: secondary,
                tone: status.tone,
                isBusy: busy
            )
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 14)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.5), value: shown)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Przykład: propozycja na jutro — \(day.map(\.name).joined(separator: ", ")). Po zatwierdzeniu jest w planie i można ją cofnąć.")
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            shown = true
            saved = true
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        shown = true
        try? await Task.sleep(for: .milliseconds(1650))
        if Task.isCancelled { return }
        withAnimation(.smooth(duration: 0.2)) { busy = true }
        try? await Task.sleep(for: .milliseconds(700))
        if Task.isCancelled { return }
        withAnimation(.smooth(duration: 0.4)) {
            busy = false
            saved = true
        }
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
    /// Prawdziwy przepis, odsiany dietą i alergenami z Ustawień (`pool`).
    /// `false` = danie zastępcze, zanim katalog się wczyta.
    let fromCatalog: Bool

    init(id: String, name: String, imageURL: URL?, kcal: Int, minutes: Int, slot: MealSlot, fromCatalog: Bool = false) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.kcal = kcal
        self.minutes = minutes
        self.slot = slot
        self.fromCatalog = fromCatalog
    }

    init(recipe: Recipe, slot: MealSlot) {
        self.init(
            id: recipe.id.uuidString,
            name: recipe.name,
            imageURL: recipe.imageURL,
            kcal: Int(recipe.nutritionPerServing.kcal.rounded()),
            minutes: recipe.prepTimeMinutes,
            slot: slot,
            fromCatalog: true
        )
    }

    /// Kalorie wiersza liczą się od zera, gdy wiersz jest już prawie cały
    /// widoczny — `scReveal` wpuszcza wiersz `order + 1` z opóźnieniem
    /// 0,10 + 0,05 · n; liczenie rusza chwilę po nim.
    static func countAnimation(order: Int) -> Animation {
        .easeOut(duration: 0.9).delay(0.35 + 0.05 * Double(order))
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

    /// Dzień do karty propozycji: śniadanie, obiad i kolacja — po jednym,
    /// losowo, bez powtórki. Jak przy kolacjach: gdy w zwykłym czasie nie ma
    /// kandydata (wąska dieta), pula rozszerza się o dłuższe gotowanie.
    /// Pusta lista dopiero wtedy, gdy którejś pory nie da się obsadzić
    /// w ogóle (zostają dania zastępcze, bez obietnicy o alergenach).
    @MainActor
    static func day(from recipes: [Recipe]) -> [AssistantIntroDish] {
        let plan: [(MealSlot, Int)] = [(.breakfast, 30), (.lunch, 60), (.dinner, 45)]
        var picked: [AssistantIntroDish] = []
        var used = Set<UUID>()
        for (slot, maxMinutes) in plan {
            var chosen: Recipe?
            for limit in [maxMinutes, 90, Int.max] {
                let candidates = pool(from: recipes, slot: slot, maxMinutes: limit)
                    .filter { !used.contains($0.id) }
                if let recipe = candidates.randomElement() {
                    chosen = recipe
                    break
                }
            }
            guard let recipe = chosen else { return [] }
            used.insert(recipe.id)
            picked.append(AssistantIntroDish(recipe: recipe, slot: slot))
        }
        return picked
    }

    /// Zanim katalog się wczyta (albo gdy jest pusty) — dania z katalogu
    /// zapisane na sztywno, bez zdjęć: miniatura z widelcem zamiast
    /// fotografii. Wegetariańskie, bo tu nie da się odsiać diety.
    static let fallbackDinners: [AssistantIntroDish] = [
        AssistantIntroDish(id: "fallback-1", name: "Sałatka z jajkiem i rzodkiewką", imageURL: nil, kcal: 489, minutes: 20, slot: .dinner),
        AssistantIntroDish(id: "fallback-2", name: "Sałatka z brokułem i jajkiem", imageURL: nil, kcal: 490, minutes: 20, slot: .dinner),
        AssistantIntroDish(id: "fallback-3", name: "Bruschetta z pomidorami i bazylią", imageURL: nil, kcal: 507, minutes: 20, slot: .dinner),
    ]

    static let fallbackDay: [AssistantIntroDish] = [
        AssistantIntroDish(id: "fallback-day-1", name: "Owsianka ze skyrem i truskawkami", imageURL: nil, kcal: 418, minutes: 12, slot: .breakfast),
        AssistantIntroDish(id: "fallback-day-2", name: "Risotto z dynią i parmezanem", imageURL: nil, kcal: 666, minutes: 45, slot: .lunch),
        AssistantIntroDish(id: "fallback-day-3", name: "Sałatka z brokułem i jajkiem", imageURL: nil, kcal: 490, minutes: 20, slot: .dinner),
    ]
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
