import SwiftUI

#if DEBUG
/// Ekran do porównywania karty wyboru z makietą — tylko w kompilacji DEBUG
/// i tylko, gdy proces dostał `SCOFFIE_DEBUG_OPTIONS`:
///
///     SIMCTL_CHILD_SCOFFIE_DEBUG_OPTIONS=0 xcrun simctl launch booted <bundle id>
///
/// Wartość to strona arkusza do otwarcia (`0…n` = dania, `n` = „Coś innego”)
/// albo `card`, żeby zobaczyć samą kotwicę w rozmowie, albo `thought` —
/// wiersz tury na żywo (ślad kroków nad bieżącym statusem), albo `plate` —
/// talerz Kalendarza w oknie gotowania (oddech). Prawdziwe przepisy
/// i zdjęcia z katalogu, żeby kadr i liczby były takie jak u użytkownika.
struct AssistantOptionsDebugScreen: View {
    let page: Int?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.toasts) private var toasts

    static var requested: AssistantOptionsDebugScreen? {
        guard let raw = ProcessInfo.processInfo.environment["SCOFFIE_DEBUG_OPTIONS"] else { return nil }
        return AssistantOptionsDebugScreen(page: Int(raw))
    }

    private static let json = #"""
    {"kind": "OPTIONS", "v": 1, "eyebrow": "Śniadanie · środa", "title": "Śniadanie na dziś", "options": [
      {"recipeId": "d0d09af3-1821-47be-be95-63a208fc47bd", "title": "Jogurt naturalny z musli, truskawkami i borówkami", "kcalPerServing": 316, "prepTimeMinutes": 6, "imageUrl": "https://pub-d6de57d50783403ab7f168d38802a1a6.r2.dev/recipe-images/d0d09af3-1821-47be-be95-63a208fc47bd.png", "description": "Szybkie śniadanie na zimno z jogurtem naturalnym, chrupiącym musli, truskawkami i borówkami. Lekkie, ale dobrze sycące na poranek.", "proteinGrams": 10, "carbsGrams": 40, "fatGrams": 12, "ingredientCount": 4, "tag": "Najszybsze", "prompt": "Wybieram: Jogurt naturalny z musli, truskawkami i borówkami"},
      {"recipeId": "1a66ef3b-f1dc-4427-b6b3-3ca5d6986e80", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 450, "prepTimeMinutes": 15, "imageUrl": "https://pub-d6de57d50783403ab7f168d38802a1a6.r2.dev/recipe-images/1a66ef3b-f1dc-4427-b6b3-3ca5d6986e80.png", "description": "Puszysty omlet z dwóch jaj ze świeżym szpinakiem i fetą, smażony na maśle.", "proteinGrams": 26, "carbsGrams": 6, "fatGrams": 30, "ingredientCount": 6, "tag": "Najwięcej białka", "prompt": "Wybieram: Omlet ze szpinakiem i fetą"},
      {"recipeId": "386586d2-b4f8-41f0-9641-cce2b7c20dd7", "title": "Skyr z granolą i malinami", "kcalPerServing": 336, "prepTimeMinutes": 5, "imageUrl": "https://pub-d6de57d50783403ab7f168d38802a1a6.r2.dev/recipe-images/386586d2-b4f8-41f0-9641-cce2b7c20dd7.png", "tag": null, "prompt": "Wybieram: Skyr z granolą i malinami"}
    ], "actions": [{"type": "ASK", "proposalId": null, "label": "Coś innego", "style": "SECONDARY", "prompt": "Żadne z tych mi nie pasuje. Zaproponuj coś innego."}]}
    """#

    private static let thoughtSteps = [
        AgentProgressStepDTO(tool: "read", label: "Już się tym zajmuję", at: "2026-09-21T10:00:00.000Z", writes: nil, phase: nil, transient: true),
        AgentProgressStepDTO(tool: "get_household_context", label: "Sprawdzam, kto je i jakie ma cele", at: "2026-09-21T10:00:02.000Z", writes: false, phase: nil, transient: nil),
        AgentProgressStepDTO(tool: "get_week_plan", label: "Sprawdzam, co już stoi w planie", at: "2026-09-21T10:00:05.000Z", writes: false, phase: nil, transient: nil),
        AgentProgressStepDTO(tool: "get_week_balance", label: "Liczę bilans dnia", at: "2026-09-21T10:00:08.000Z", writes: false, phase: nil, transient: nil),
        AgentProgressStepDTO(tool: "propose_week_plan", label: "Dobieram dania na cały tydzień", at: "2026-09-21T10:00:12.000Z", writes: false, phase: nil, transient: nil),
    ]

    /// „Owsianka z bananem i borówką” z katalogu — ten sam przepis, który
    /// stoi na artboardach makiety „Szczegóły Posiłku v2”.
    static let detailRecipe = Recipe(
        id: UUID(uuidString: "9e845247-f630-4dcc-9bab-3656828cac29")!,
        name: "Owsianka z bananem i borówką",
        description: "Kremowa owsianka na mleku z dodatkiem banana i borówki. Śniadanie jest szybkie, sycące i dobre na codzienny start.",
        category: .breakfast,
        baseSlot: .breakfast,
        suitableSlots: [.breakfast, .secondBreakfast],
        servings: 2,
        prepTimeMinutes: 12,
        imageURL: URL(string: "https://pub-d6de57d50783403ab7f168d38802a1a6.r2.dev/recipe-images/9e845247-f630-4dcc-9bab-3656828cac29.png"),
        ingredients: [
            Ingredient(name: "Płatki owsiane", amount: 100, unit: .gram, department: "Zboża i makarony"),
            Ingredient(name: "Mleko", amount: 400, unit: .milliliter, department: "Nabiał"),
            Ingredient(name: "Banan", amount: 2, unit: .piece, department: "Owoce"),
            Ingredient(name: "Borówka", amount: 100, unit: .gram, department: "Owoce")
        ],
        preparationSteps: [
            PreparationStep(stepNumber: 1, instruction: "Wlej mleko do garnka i podgrzej na średnim ogniu. Wsyp płatki owsiane i mieszaj, aby nic nie przywarło."),
            PreparationStep(stepNumber: 2, instruction: "Gotuj 5–6 minut, aż owsianka zgęstnieje. W razie potrzeby dodaj odrobinę mleka."),
            PreparationStep(stepNumber: 3, instruction: "Pokrój banany i dorzuć jednego do garnka. Delikatnie wymieszaj dla naturalnej słodyczy."),
            PreparationStep(stepNumber: 4, instruction: "Przełóż owsiankę do misek i dodaj borówkę oraz drugiego banana. Podawaj od razu na ciepło.")
        ],
        nutrition: Nutrition(kcal: 894, protein: 30, fat: 21, carbs: 137, fiber: 19, salt: 0.6)
    )

    private var card: OptionsCardDTO {
        guard case .options(let card) = AssistantPreviewFixtures.card(Self.json) else { fatalError("OPTIONS") }
        return card
    }

    /// `SCOFFIE_DEBUG_OPTIONS=buttons` — zwykłe karty z akcjami, do obejrzenia
    /// stylu przycisków poza arkuszem.
    private var showsButtons: Bool {
        ProcessInfo.processInfo.environment["SCOFFIE_DEBUG_OPTIONS"] == "buttons"
    }

    private var mode: String? { ProcessInfo.processInfo.environment["SCOFFIE_DEBUG_OPTIONS"] }

    var body: some View {
        if mode == "shopping" {
            // Liczniki Zakupów na przykładowych danych — do sprawdzenia
            // `SCCountingText` bez sesji.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ShoppingEyebrowRow(eyebrow: "Ten tydzień · 21–27 wrz", meta: "12 dań · 49 produktów")
                    ShoppingProgressHeader(
                        bought: 15,
                        total: 49,
                        segments: [ShoppingProgressSegment(id: "w", bought: 8, total: 11, color: SCPalette.sage)]
                    )
                    ShoppingTodayRow(missing: 18, dishes: 4, isFiltered: false, action: {})
                    ShoppingAisleSection(
                        department: "Warzywa",
                        items: [
                            ShoppingItem(productKey: "pietruszka::g", name: "Pietruszka korzeń", totalAmount: 40, unit: "g", department: "Warzywa", isChecked: false),
                            ShoppingItem(productKey: "cebula::szt", name: "Cebula (szt)", totalAmount: 0.5, unit: "szt", department: "Warzywa", isChecked: true),
                            ShoppingItem(productKey: "ziemniak::g", name: "Ziemniak", totalAmount: 1750, unit: "g", department: "Warzywa", isChecked: false)
                        ],
                        dishSummary: { _ in "Krupnik z kaszą" }
                    )
                }
                .padding(20)
                .padding(.top, 50)
            }
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
        } else if mode == "detail" || mode == "detail-planned" {
            // Szczegóły posiłku v2 jako arkusz nad pustym tłem — tak, jak
            // otwiera je katalog. `detail-planned` = wejście z planu.
            SCPageBackground(scheme: scheme).ignoresSafeArea()
                .sheet(isPresented: .constant(true)) {
                    RecipeDetailView(
                        recipe: Self.detailRecipe,
                        onToggleFavorite: {},
                        onClose: {},
                        initialServings: 1,
                        context: mode == "detail-planned" ? .planned(day: Date(), slot: .breakfast) : .catalog,
                        onSaveServings: { _ in }
                    )
                    .presentationDetents([.large])
                    .dashboardLiquidSheet()
                    .interactiveDismissDisabled()
                }
        } else if mode == "auth" || mode == "auth-error" {
            // Ekran logowania: `auth`, z błędem: `auth-error`.
            AuthView(
                isLoading: false,
                errorMessage: mode == "auth-error" ? "Nie udało się zweryfikować logowania Apple. Spróbuj ponownie." : nil,
                onSignInWithAppleTap: {}
            )
        } else if mode == "legal" {
            // Arkusz dokumentu nad ekranem logowania.
            AuthView(isLoading: false, errorMessage: nil, onSignInWithAppleTap: {})
                .sheet(isPresented: .constant(true)) {
                    LegalDocumentSheet(title: "Warunki korzystania") { TermsOfServiceContent() }
                }
        } else if mode == "plate" {
            // Talerz w oknie gotowania — oddech talerza, poświaty i aureoli.
            ZStack {
                SCPageBackground(scheme: scheme).ignoresSafeArea()
                CalendarPlate(
                    item: CalendarPlateItem(
                        id: "debug-plate", slot: .lunch, status: .next, time: "14:00",
                        title: "Omlet ze szpinakiem i fetą",
                        imageURL: URL(string: "https://pub-d6de57d50783403ab7f168d38802a1a6.r2.dev/recipe-images/1a66ef3b-f1dc-4427-b6b3-3ca5d6986e80.png"),
                        kcal: 450, prepMinutes: 60, cookFrom: "13:00",
                        servingsNote: nil, minutesAway: 45, isMissed: false
                    ),
                    canToggle: true,
                    onToggle: {},
                    onOpenDetail: {}
                )
            }
        } else if mode == "thought" {
            // Wiersz tury na żywo: ślad trzech kroków nad bieżącym statusem,
            // pod nim szkic odpowiedzi — do porównania kolumn na zrzucie.
            ZStack(alignment: .topLeading) {
                SCPageBackground(scheme: scheme).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    AssistantUserBubble(text: "Ułóż mi obiady na przyszły tydzień", editing: false, pending: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    AssistantThoughtLine(
                        phase: .working(startedAt: Date().addingTimeInterval(-24), isStopping: false),
                        steps: Self.thoughtSteps,
                        isExpanded: .constant(false)
                    )
                    .padding(.vertical, 4)
                    AssistantVoice { AssistantAnswer(text: "Mam dla Ciebie pięć obiadów — każdy do 30 minut,") }
                }
                .padding(16)
                .padding(.top, 50)
            }
        } else if showsButtons {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AssistantSwapCard(card: AssistantPreviewFixtures.swap, isBusy: false, onApply: { _ in }, onRevise: {}, onAskNew: {}, onAsk: { _ in }, onUndo: {}, onOpenPlan: {})
                    AssistantAppliedCard(card: AssistantPreviewFixtures.applied, isBusy: false, onUndo: {}, onOpenPlan: {})
                }
                .padding(16)
                .padding(.top, 50)
            }
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
        } else {
            conversation
        }
    }

    private var conversation: some View {
        ZStack(alignment: .bottom) {
            SCPageBackground(scheme: scheme).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                AssistantUserBubble(text: "Co dziś na śniadanie?", editing: false, pending: false)
                AssistantVoice { AssistantAnswer(text: "Trzy śniadania z Twoich przepisów, wszystkie do 15 minut.") }
                AssistantOptionsCard(
                    card: card,
                    autoPresentID: page == nil ? nil : "debug-\(page ?? 0)",
                    autoPresentPage: page ?? 0,
                    onAsk: { _ in }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        // Symulator bez sesji jest „offline” — pasek o sieci zasłaniałby
        // nagłówek arkusza na zrzucie.
        .task {
            while !Task.isCancelled {
                toasts.setPersistent(nil)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}
#endif
