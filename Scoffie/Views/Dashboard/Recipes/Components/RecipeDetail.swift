import SwiftUI

// Szczegóły posiłku v2 — wariant „final” z makiety Claude Design
// „Scoffie — Szczegóły Posiłku v2” (`components/detail-v2.jsx`: `TopEditorial`
// z tagami, `NutriZDonutThick`, `StepsList`, `IngrCheckGrouped`, `MealDetail`
// z `nutriStepper`).
//
// Od góry: zdjęcie 340 pt wtapiające się w tło arkusza, wiersz tagów
// (kategoria · „pasuje też na” przerywaną obwódką · czas), duży tytuł z lede,
// a pod nim trzy sekcje z akcentowym pręcikiem:
//   • (tylko posiłek z planu z porcjami osób) „Kto ile je” (masło) — pasek
//     podziału garnka w kolorach osób i wiersz na osobę: awatar, „TY”, kcal
//     jej porcji, stepper co 0,5. Stoi PRZED makrami, które liczą się
//     z porcji patrzącego.
//   • „Wartości odżywcze” (terakota) — stepper porcji siedzi W NAGŁÓWKU tej
//     sekcji, a nie w osobnej karcie: porcje zmieniają wszystko niżej naraz
//     (makra i gramatury), więc eyebrow każdej sekcji mówi, na ile porcji są
//     jej liczby. Pod spodem porcja na tle celu dnia — pierścienie i legenda
//     z arkusza „Cel dnia” (odejście od donuta z makiety, patrz
//     `DetailNutritionCard`).
//   • „Przygotowanie” (szałwia) — numerowane kroki w jednej karcie.
//   • „Składniki” (indygo) — pogrupowane w działy w kolejności alejek sklepu
//     i z polem „mam w domu”. Brakujące idą przyciskiem „Do zakupów” NA
//     PRAWDZIWĄ listę zakupów tygodnia (`weeklyPlans:addRecipeExtras`) —
//     serwer liczy ilości sam, z tych samych danych co listę z planu.
// Na dole pasek z jednym przyciskiem, którego rola zależy od `context`.
// Obok krzyżyka „Udostępnij” (link do przepisu, `RecipeShareKit.swift`), a cudzy
// przepis z linku (`.shared`) jest tylko do odczytu: bez serca, zakupów
// i „mam w domu”, za to z „Zapisz u siebie” obok planu.
//
// Makra w kolorach `SCMacroPalette`, a przyciski w wariancie „soft” — jak
// wszędzie indziej w aplikacji, a nie jak w makiecie (decyzja Rafała 21.09).

/// Skąd otwarto szczegóły posiłku.
///
/// Ten sam ekran obsługuje trzy wejścia, ale nie wszędzie znaczy to samo:
/// w katalogu przepis dopiero wybieramy, a z planu i z kalendarza patrzymy na
/// posiłek, który ma już swój dzień i slot. Bez tego rozróżnienia przycisk na
/// dole musiałby zgadywać, czy zakłada nowy wpis, czy poprawia istniejący.
enum RecipeDetailContext {
    case catalog
    case planned(day: Date, slot: MealSlot)
    /// Przepis INNEGO domu otwarty linkiem (`recipes:openShared`, `SHARED`).
    /// Tylko do odczytu: serwer odrzuci na nim ulubione, zakupy i plan, więc
    /// wszystko, co go zmienia, idzie przez kopię — „Zapisz u siebie”
    /// (`recipes:saveShared`) i plan na zapisanej kopii. `savedRecipeId` =
    /// kopia, którą dom już ma: przycisk od razu mówi „Zapisano”.
    case shared(token: String, savedRecipeId: UUID?)
}

/// Porcje osób posiłku z planu — KAŻDEGO, nie tylko ułożonego przez
/// Asystenta. Ekran pokazuje porcję każdego jedzącego ze stepperem co 0,5
/// zamiast steppera porcji łącznych. Posiłek bez alokacji startuje od
/// równego podziału; pierwsze zapisanie ustawia porcje osób (`REPLACE`).
struct RecipeDetailPortions {
    struct Person {
        let memberId: String
        let name: String
        /// Domownik z listy gospodarstwa — awatar i kolor osoby (ten sam co
        /// w Planie). `nil`, gdy ktoś z alokacji już z domu wyszedł.
        var member: HouseholdMemberSnapshot? = nil
    }

    /// Jedzący, w kolejności do pokazania.
    let people: [Person]
    /// Jednostki 1/20 porcji (`PlanPortions`).
    let units: [String: Int]
    /// Kto patrzy — jego porcja idzie do „Twoja porcja” i do makr.
    let viewerId: String?
    /// Są tokeny do zapisu (`PlanMeal.canEditPortions`); bez nich porcje
    /// tylko do odczytu, do najbliższego odświeżenia planu.
    let isEditable: Bool
}

extension RecipeDetailPortions {
    /// Model dla posiłku z planu. Osoby = klucze alokacji (serwer trzyma je
    /// równe audytorium), a bez alokacji — audytorium („Wspólne” = cały dom);
    /// patrzący pierwszy. `nil`, gdy nie wiadomo, kto je (lista domowników
    /// jeszcze nie dojechała) — wtedy zostaje stepper porcji łącznych.
    init?(meal: PlanMeal, members: [HouseholdMemberSnapshot], viewerId: String?) {
        let byId = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = byId.mapValues(\.displayName)
        let units: [String: Int]
        if meal.hasPortions {
            units = meal.portionUnits
        } else {
            let current = Set(members.map(\.id))
            let eaters = meal.isShared ? Array(current) : meal.participantIds.filter { current.contains($0) }
            let total = meal.effectiveServings(householdMemberCount: members.count) * PlanPortions.unitsPerServing
            // Więcej niż 6 na osobę (gotowanie na zapas) — zostaje stepper
            // porcji łącznych, żeby nie obciąć liczby.
            guard PlanPortions.fitsPerPerson(totalUnits: total, eaterCount: eaters.count) else { return nil }
            units = PlanPortions.seededUnits(eaters: eaters, totalUnits: total)
        }
        let ids = units.keys.sorted { lhs, rhs in
            if lhs == viewerId { return true }
            if rhs == viewerId { return false }
            return (names[lhs] ?? lhs).localizedCompare(names[rhs] ?? rhs) == .orderedAscending
        }
        self.init(
            people: ids.map { Person(memberId: $0, name: names[$0] ?? "Domownik", member: byId[$0]) },
            units: units,
            viewerId: viewerId,
            // Bez alokacji token pozycji jest opcjonalny — pozycję z syntetycznym
            // id (przed ackiem) i tak zna serwer po parze (pora, przepis).
            isEditable: meal.hasPortions ? meal.canEditPortions : true
        )
    }
}

struct RecipeDetailView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.toasts) private var toasts
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let recipe: Recipe
    /// Zapis ulubionych — z docelową wartością (`nil` = serce ukryte).
    var onSetFavourite: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    /// Liczba porcji, od której startuje stepper. Katalog otwiera się na
    /// jednej porcji, a wejście z planu podstawia tu `plannedServings` slotu,
    /// żeby ekran pokazywał to, co użytkownik już wcześniej ustawił.
    let initialServings: Int

    /// Kontekst wywołania — decyduje o przycisku w dolnym pasku i o tym, czy
    /// składniki da się dopisać do listy zakupów.
    let context: RecipeDetailContext

    /// Wołane przyciskiem „Zapisz porcje" w kontekście `.planned`.
    var onSaveServings: ((Int) -> Void)?

    /// Wołane po tym, jak `AddToPlanSheet` wstawi posiłek do planu — z dniem
    /// i slotem, na które trafił, żeby ekran pod spodem mógł się odświeżyć.
    var onAddedToPlan: ((Date, MealSlot) -> Void)?

    /// Porcje per osoba (tylko `.planned`); `nil` = zwykły stepper porcji.
    let personalPortions: RecipeDetailPortions?

    /// Wołane „Zapisz porcje” w trybie porcji osób: pełna mapa (dla
    /// posiłku bez alokacji — `REPLACE`) i ZMIENIONE osoby (dla posiłku
    /// z alokacją — osobne `setPortion`). Jednostki 1/20.
    var onSavePortions: ((_ all: [String: Int], _ changed: [String: Int]) -> Void)?

    /// Porcje per osoba w edycji — makra i składniki liczą się na bieżąco
    /// z tego, co widać na stepperach, a nie z zapisanego stanu.
    @State private var draftPortions: [String: Int]

    private var portionUnits: [String: Int] { draftPortions }

    /// Widełki są te same, co limit `plannedServings` w backendzie — powyżej
    /// dwunastu porcji to już nie jest gotowanie na tydzień, tylko catering.
    private static let servingsRange = 1...12

    /// Porcje łączne w jednostkach 1/20: w katalogu stepper co 0,5, w planie
    /// (gdy nie ma porcji osób) co 1 — `plannedServings` to liczba całkowita.
    @State private var servingsUnits: Int
    @State private var isAddToPlanPresented = false
    /// Półarkusz „Kto ile je” spod przyczepionej pigułki porcji.
    @State private var isPortionsSheetPresented = false

    /// Czy użytkownik dotknął steppera na tym ekranie.
    ///
    /// Arkusz „Dodaj do planu" potrzebuje tego, żeby wiedzieć, czy wolno mu
    /// przeliczyć porcje z audytorium. Samo porównanie `servings != 1` tu nie
    /// wystarcza: kto podbił na 2 i wrócił na 1, dokonał wyboru, a takie
    /// porównanie uznałoby go za nietkniętą wartość domyślną.
    @State private var didTouchStepper = false

    /// Podnoszona przy „Zapisz porcje" i już nieopuszczana.
    ///
    /// `onSaveServings` jest synchroniczne i tylko odpala zapis w rodzicu,
    /// więc przycisk zostaje aktywny przez całą animację zamykania arkusza —
    /// a to wystarczy, żeby drugie stuknięcie wysłało ten sam upsert po raz
    /// drugi. Flagi nie zerujemy, bo po zapisie ten ekran i tak znika:
    /// odblokowanie przycisku otwierałoby dokładnie to okno, które zamyka.
    @State private var isSavingServings = false

    /// Stan wysyłki „Gotuj w Thermomixie". Spinner + `disabled` to pierwsza
    /// linia obrony przed double-tapem; drugą jest 60-sekundowe okno
    /// idempotencji na backendzie.
    @State private var isSendingToThermomix = false
    @State private var showThermomixSuccess = false
    @State private var thermomixError: String?

    /// Start Gotuj przy trwającej sesji innego dania — pytanie o tamto.
    @State private var isReplaceCookingAsked = false

    /// Składniki odhaczone jako „mam w domu”.
    ///
    /// Stan WIZYTY, nie pamięć aplikacji: aplikacja nie ma spiżarni i nie wie,
    /// co stoi w szafce, więc po ponownym otwarciu przepisu pytamy od nowa.
    @State private var haveIngredientIds: Set<UUID> = []

    /// Wysyłka brakujących na listę zakupów.
    @State private var shoppingSend: ShoppingSendState = .idle

    /// Wjazd treści — sekcje wchodzą kolejno, donut rysuje się od góry.
    @State private var hasAppeared = false

    @State private var scrollPosition = ScrollPosition(edge: .top)

    /// Zdjęcie zjechało z ekranu — treść przewija się teraz pod pływającymi
    /// przyciskami i u góry arkusza potrzebne jest wygaszenie.
    @State private var isPastPhoto = false

    /// „Zapisz u siebie” (tylko `.shared`).
    @State private var sharedSave: SharedSaveState
    /// Kopia cudzego przepisu w tym domu — na nią idzie „Dodaj do planu”
    /// (plan przyjmuje tylko przepisy katalogu i tego domu).
    @State private var savedCopy: Recipe?
    /// „Dodaj do planu” w `.shared` najpierw zapisuje kopię.
    @State private var isPreparingPlan = false

    /// Jawny `init` zamiast memberwise'owego, bo `@State` z porcjami trzeba
    /// zasiać `initialServings`. Kolejność i domyślne wartości są dobrane tak,
    /// żeby dotychczasowe wywołania `RecipeDetailView(recipe:onSetFavourite:onClose:)`
    /// kompilowały się bez zmian.
    init(
        recipe: Recipe,
        onSetFavourite: ((Bool) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        initialServings: Int = 1,
        context: RecipeDetailContext = .catalog,
        onSaveServings: ((Int) -> Void)? = nil,
        onAddedToPlan: ((Date, MealSlot) -> Void)? = nil,
        personalPortions: RecipeDetailPortions? = nil,
        onSavePortions: ((_ all: [String: Int], _ changed: [String: Int]) -> Void)? = nil
    ) {
        self.personalPortions = personalPortions
        self.onSavePortions = onSavePortions
        _draftPortions = State(initialValue: personalPortions?.units ?? [:])
        self.recipe = recipe
        self.onSetFavourite = onSetFavourite
        self.onClose = onClose
        self.context = context
        if case .shared(_, let savedRecipeId) = context, savedRecipeId != nil {
            _sharedSave = State(initialValue: .saved)
        } else {
            _sharedSave = State(initialValue: .idle)
        }
        self.onSaveServings = onSaveServings
        self.onAddedToPlan = onAddedToPlan

        // Klamrujemy raz, przy wejściu, i trzymamy przyciętą wartość także
        // jako punkt odniesienia dla „Zapisz porcje" — inaczej slot zapisany
        // kiedyś z wartością spoza widełek wyglądałby na zmieniony od razu
        // po otwarciu ekranu.
        let seed = min(Self.servingsRange.upperBound, max(Self.servingsRange.lowerBound, initialServings))
        self.initialServings = seed
        _servingsUnits = State(initialValue: seed * PlanPortions.unitsPerServing)
    }

    /// Porcje jako `Double`, bo skalowanie makr i składników liczy się
    /// ułamkiem `porcje / recipe.servings`.
    private var portions: Double { PlanPortions.servings(fromUnits: servingsUnits) }

    /// Krok steppera porcji łącznych: w katalogu pół porcji, w planie cała
    /// (zapis `plannedServings` przyjmuje tylko liczby całkowite).
    private var totalStepUnits: Int {
        if case .planned = context { return PlanPortions.unitsPerServing }
        return PlanPortions.stepUnits
    }

    private var totalUnitsRange: ClosedRange<Int> {
        // `...` na początku linii Swift czyta jako osobną instrukcję
        // (przedrostek), a nie ciąg zakresu — getter zostawał bez `return`.
        let lower = Self.servingsRange.lowerBound * PlanPortions.unitsPerServing - PlanPortions.unitsPerServing + totalStepUnits
        let upper = Self.servingsRange.upperBound * PlanPortions.unitsPerServing
        return lower...upper
    }

    /// Całe porcje do zapisu i do listy zakupów (API przyjmuje liczby
    /// całkowite) — w górę, żeby nie zabrakło.
    private var wholeServings: Int {
        min(Self.servingsRange.upperBound, PlanPortions.plannedServings(forTotalUnits: servingsUnits))
    }

    /// Tryb porcji per osoba: posiłek z planu z alokacją.
    private var isPortionMode: Bool {
        guard case .planned = context, personalPortions != nil else { return false }
        return !portionUnits.isEmpty
    }

    /// Porcja patrzącego, jeśli je to danie.
    private var viewerUnits: Int? {
        personalPortions?.viewerId.flatMap { portionUnits[$0] }
    }

    /// Na ile porcji liczą się makra: porcja patrzącego (albo średnia
    /// jedzących, gdy sam tego nie je) — ten sam wzór co serwer.
    private var nutritionServings: Double {
        guard isPortionMode else { return portions }
        if let viewerUnits { return PlanPortions.servings(fromUnits: viewerUnits) }
        return PlanPortions.servings(fromUnits: PlanPortions.totalUnits(portionUnits)) / Double(portionUnits.count)
    }

    /// Na ile porcji liczą się składniki: przy alokacji dokładna Σ (tak liczy
    /// lista zakupów na serwerze).
    private var cookedServings: Double {
        isPortionMode ? PlanPortions.servings(fromUnits: PlanPortions.totalUnits(portionUnits)) : portions
    }

    private var nutritionEyebrow: String {
        guard isPortionMode else { return PlanPortions.spokenServings(units: servingsUnits, plural: PolishPlural.servings) }
        if let viewerUnits { return "Twoja porcja · \(PlanPortions.label(units: viewerUnits))" }
        let mean = PlanPortions.totalUnits(portionUnits) / max(1, portionUnits.count)
        return "Średnio · \(PlanPortions.label(units: mean))"
    }

    private var ingredientsEyebrow: String {
        guard isPortionMode else { return PlanPortions.spokenServings(units: servingsUnits, plural: PolishPlural.servings) }
        // Ułamek porcji łączy się z dopełniaczem: „2,5 porcji”; pełna liczba
        // odmienia się jak zwykle („3 porcje”).
        return PlanPortions.spokenServings(units: PlanPortions.totalUnits(portionUnits), plural: PolishPlural.servings)
    }

    private var look: DetailLook { DetailLook(scheme: scheme) }


    var body: some View {
        ZStack(alignment: .top) {
            DetailBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DetailHeroPhoto(url: recipe.imageURL, isRevealed: hasAppeared)

                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .detailReveal(hasAppeared, order: 0)

                    // „Kto ile je” nie jest już sekcją tutaj — to pigułka
                    // przyczepiona nad przyciskami (`portionsPill`), jak
                    // „Cel dnia” w Planie, z półarkuszem do zmian.

                    nutritionSection
                        .padding(.top, 24)
                        .detailReveal(hasAppeared, order: 1)

                    if !recipe.preparationSteps.isEmpty {
                        preparationSection
                            .padding(.top, 24)
                            .detailReveal(hasAppeared, order: 2)
                    }

                    if !recipe.ingredients.isEmpty {
                        ingredientsSection
                            .padding(.top, 24)
                            .detailReveal(hasAppeared, order: 3)
                    }

                    // Oddech nad dolnym paskiem. Sam pasek liczy system
                    // (`safeAreaBar` niżej): przewinięta do końca treść kończy
                    // się nad nim przy każdej jego wysokości — także z błędem
                    // Thermomixa nad przyciskami.
                    Color.clear.frame(height: 16)
                }
                // Szerokość treści przypięta do szerokości arkusza.
                //
                // Bez tego wystarczy, żeby jeden element policzył sobie
                // szerokość większą niż ekran (w trakcie przejść arkusza
                // geometria potrafi przyjść nieaktualna), a obszar przewijania
                // robi się szerszy niż widok — i cała karta jeździ na boki.
                .containerRelativeFrame(.horizontal)
            }
            .scrollPosition($scrollPosition)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            // Dolny pasek akcji natywnie (iOS 26 `safeAreaBar`): same szklane
            // przyciski, przepis przejeżdża pod nimi, a kończy się nad nimi.
            // Pod przyciskami tylko natywny efekt krawędzi systemu.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                primaryActionBar
            }
            // Bool, nie przesunięcie: stan zmienia się raz przy przekroczeniu
            // progu, a nie w każdej klatce przewijania.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Próg liczony od wysokości zdjęcia: wygaszenie wchodzi,
                // gdy nad przyciskami zostaje już tylko jego dolny skrawek.
                geometry.contentOffset.y + geometry.contentInsets.top > DetailHeroPhoto.height - 70
            } action: { _, isPast in
                withAnimation(.easeInOut(duration: 0.22)) { isPastPhoto = isPast }
            }
        }
        // Cień krawędzi — wzór dla całej aplikacji (`SCEdgeShade`): ten sam,
        // lustrzany, stoi nad stopką każdego arkusza.
        .overlay(alignment: .top) {
            SCEdgeShade(edge: .top, base: look.background)
                .frame(height: SCEdgeShade.topHeight)
                .opacity(isPastPhoto ? 1 : 0)
        }
        .toolbar(.hidden, for: .navigationBar)
        // Serce i krzyżyk to ten sam krążek, którym zamyka się każdy inny
        // arkusz (`SCSheetCloseButton`), w wariancie `onImage` — z kryjącym
        // tłem, bo stoją na zdjęciu, a nie na tle arkusza.
        .overlay(alignment: .topLeading) {
            // Stan serca żyje w przycisku — stuknięcie przerysowuje sam
            // przycisk, a zapis do katalogu idzie dopiero po animacji.
            RecipeFavouriteButton(isFavourite: recipe.favourite) { value in
                onSetFavourite?(value)
            }
            .opacity(onSetFavourite == nil ? 0 : 1)
            .disabled(onSetFavourite == nil)
            .padding(.leading, 20)
            .padding(.top, 16)
            .detailChrome(hasAppeared)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                // Cudzy przepis (`.shared`) nie ma własnego linku do
                // przekazania dalej — wysyła go tylko jego dom.
                if showsShareButton {
                    RecipeShareButton(recipe: recipe)
                }
                SCSheetCloseButton(onImage: true) { onClose?() }
            }
            .padding(.trailing, 20)
            .padding(.top, 16)
            .detailChrome(hasAppeared)
        }
        .onAppear { applyDebugLaunchOptions() }
        // Klatka oddechu jak w wyborze posiłku u Asystenta: arkusz zaczyna
        // wjeżdżać, dopiero potem treść. Ustawione w `onAppear` padało w tej
        // samej klatce co wstawienie widoku i wjazd sekcji w ogóle nie grał.
        .task {
            guard !hasAppeared else { return }
            try? await Task.sleep(for: .milliseconds(80))
            hasAppeared = true
        }
        // Scenariusz Gotuj w pamięci telefonu — przycisk „Gotuj” pojawia się,
        // gdy paczka jest (§4.1), i działa potem bez sieci.
        .task(id: recipe.id) {
            // Cudzy przepis (`.shared`) i tak nie ma „Gotuj” — bez zapytań.
            if case .shared = context { return }
            await sessionStore.cookScenarioStore?.prepare(recipe)
        }
        .confirmationDialog(
            "Gotujesz już inne danie",
            isPresented: $isReplaceCookingAsked,
            titleVisibility: .visible
        ) {
            // Bez `end()` tutaj: start i tak podmienia sesję, a gdyby przejście
            // się nie udało, tamta nie przepada w pół drogi.
            Button("Zakończ tamto i gotuj to", role: .destructive) {
                beginCooking()
            }
            Button("Wróć do tamtego") {
                Task { await sessionStore.resumeCooking() }
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Gotujemy jedno danie naraz — tamto ma swoje timery.")
        }
        .sheet(isPresented: $isAddToPlanPresented) {
            // Liczba porcji ze steppera jedzie do arkusza jako punkt startowy:
            // użytkownik właśnie na nią patrzył, więc przestawienie jej przy
            // dodawaniu wyglądałoby na zgubienie jego wyboru.
            AddToPlanSheet(
                // Cudzy przepis idzie do planu jako kopia tego domu.
                recipe: savedCopy ?? recipe,
                initialServings: wholeServings,
                initialUnits: servingsUnits,
                // Stepper startuje od jedynki, więc każda inna wartość znaczy,
                // że użytkownik świadomie go ruszył — i arkusz nie ma prawa
                // nadpisać jej regułą auto z chipów.
                didOverrideServings: didTouchStepper,
                onAdded: { day, slot in
                    onAddedToPlan?(day, slot)
                }
            )
        }
    }

    // MARK: - Góra: tagi, tytuł, lede

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            tagRow

            Text(recipe.name)
                .font(.system(size: 32, weight: .heavy))
                .tracking(-0.96)
                .foregroundStyle(look.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)

            if !recipe.description.isEmpty {
                Text(recipe.description)
                    .font(.system(size: 14.5))
                    .foregroundStyle(look.muted)
                    // 21 pt wiersza z makiety przy 14,5 pt pisma.
                    .lineSpacing(3.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Kategoria · „pasuje też na” · czas.
    ///
    /// Dodatkowe pory dnia idą przerywaną obwódką: to nie jest druga
    /// kategoria przepisu, tylko podpowiedź, gdzie jeszcze go postawić. Gdy
    /// wszystkie się nie mieszczą, zostaje pierwsza i „+N” — a przy bardzo
    /// wąskim ekranie sama kategoria. Czas nigdy się nie łamie.
    private var tagRow: some View {
        let extras = recipe.additionalSlots
        return ViewThatFits(in: .horizontal) {
            tagRowContent(slots: extras, overflow: 0)
            if extras.count > 1 {
                tagRowContent(slots: Array(extras.prefix(1)), overflow: extras.count - 1)
            }
            if !extras.isEmpty {
                tagRowContent(slots: [], overflow: extras.count)
            }
            tagRowContent(slots: [], overflow: 0, showsThermomix: false)
        }
    }

    private func tagRowContent(slots: [MealSlot], overflow: Int, showsThermomix: Bool = true) -> some View {
        HStack(spacing: 6) {
            DetailTagPill(
                icon: RecipesConstants.icon(for: recipe.category),
                text: RecipesConstants.shortDisplayName(for: recipe.category),
                accent: RecipeAccent.accent(for: recipe.category)
            )

            // Chip „THERMOMIX” — właściwość przepisu (ma odpowiednik
            // w Cookidoo), więc widoczny niezależnie od stanu integracji.
            if showsThermomix && recipe.isThermomix {
                DetailTagPill(icon: "cooktop.fill", text: "Thermomix", accent: SCPalette.sage)
            }

            ForEach(slots) { slot in
                DetailDashedTag(text: slot.title)
            }
            if overflow > 0 {
                DetailDashedTag(text: "+\(overflow)")
                    .accessibilityLabel("Pasuje też na \(PolishPlural.form(overflow, one: "jedną porę", few: "\(overflow) pory", many: "\(overflow) pór"))")
            }

            Spacer(minLength: 10)

            Text(verbatim: "\(recipe.prepTimeMinutes) MIN")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.1)
                .monospacedDigit()
                .foregroundStyle(look.muted)
                .fixedSize()
                .accessibilityLabel("\(recipe.prepTimeMinutes) minut")
        }
    }

    // MARK: - Wartości odżywcze

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(
                eyebrow: nutritionEyebrow,
                title: "Wartości odżywcze",
                accent: SCPalette.terracotta
            ) {
                if !isPortionMode {
                    DetailServingsStepper(
                        value: $servingsUnits,
                        range: totalUnitsRange,
                        label: { PlanPortions.label(units: $0) },
                        accessibilityValueText: { PlanPortions.spokenServings(units: $0, plural: PolishPlural.servings) },
                        next: { current, direction in
                            let candidate = current + direction * totalStepUnits
                            return totalUnitsRange.contains(candidate) ? candidate : nil
                        },
                        onChange: { didTouchStepper = true }
                    )
                }
            }

            DetailNutritionCard(nutrition: recipe.nutrition(forServings: nutritionServings))
            .padding(.horizontal, 20)
        }
    }

    /// „Kto ile je” jako PRZYCZEPIONA pigułka nad przyciskami (Rafał
    /// 4.10.2026: „może jako taki przyczepiony tab na dole jak kcal tab, że
    /// otworzy się sheet do połowy, gdzie będzie można to modyfikować, i pokaże
    /// się łączna liczba porcji, którą trzeba ugotować”). Szkło jak pigułka
    /// „Cel dnia”: awatary jedzących, „Do ugotowania · 3,5 porcji”, strzałka
    /// w górę. Stuknięcie = półarkusz z podziałem i stepperami
    /// (`portionsSheet`). Zmiany idą do tego samego szkicu (`draftPortions`),
    /// a zapis — jak dotąd — „Zapisz porcje”, który pojawia się pod pigułką.
    ///
    /// Dawniej sekcja „Kto ile je” w przewijaniu, nad wartościami odżywczymi.
    private func portionsPill(_ model: RecipeDetailPortions) -> some View {
        let total = PlanPortions.totalUnits(portionUnits)
        let spoken = PlanPortions.spokenServings(units: total, plural: PolishPlural.servings)
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return Button {
            isPortionsSheetPresented = true
        } label: {
            HStack(spacing: 12) {
                portionsAvatars(model)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Do ugotowania")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(look.muted)
                    Text(spoken)
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.2)
                        .monospacedDigit()
                        .foregroundStyle(look.fg)
                        .contentTransition(.numericText(value: Double(total)))
                        .animation(SCMotion.textRoll, value: total)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(look.muted)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .scChromeGlass(in: shape)
            .contentShape(shape)
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityLabel("Kto ile je, do ugotowania \(spoken)")
        .accessibilityHint("Otwiera porcje domowników")
        // Arkusz na samej pigułce, nie na całym ekranie: łańcuch szczegółów
        // ma już swoje arkusze, a SwiftUI gubi czasem kolejne `.sheet` na
        // tym samym widoku.
        .sheet(isPresented: $isPortionsSheetPresented) {
            portionsSheet(model)
        }
    }

    /// Do trzech awatarów jedzących na zakładkę, reszta jako „+N”.
    private func portionsAvatars(_ model: RecipeDetailPortions) -> some View {
        let size: CGFloat = 30
        let shown = Array(model.people.prefix(3))
        let rest = model.people.count - shown.count

        return HStack(spacing: -9) {
            ForEach(shown, id: \.memberId) { person in
                ProfileAvatar(
                    avatarUrl: person.member?.avatarUrl,
                    displayName: person.name,
                    size: size,
                    colorIndex: person.member?.avatarColor,
                    seed: person.memberId
                )
                .overlay(Circle().strokeBorder(look.background, lineWidth: 2))
            }
            if rest > 0 {
                Text(verbatim: "+\(rest)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(look.fg)
                    .frame(width: size, height: size)
                    .background(Circle().fill(look.background))
            }
        }
        .accessibilityHidden(true)
    }

    /// Półarkusz „Kto ile je”: łączna liczba porcji do ugotowania (duża,
    /// roluje), podział garnka w kolorach osób i wiersz na osobę ze stepperem
    /// co pół porcji. Po zmianie w stopce wjeżdża „Zapisz porcje” (Rafał
    /// 4.10.2026: „daj tam button do zapisu, jak się zmieni stan”), a obok
    /// krzyżyka „Cofnij zmiany”. Do połowy ekranu, przewijanie rozwija na cały
    /// (dom z wieloma osobami).
    private func portionsSheet(_ model: RecipeDetailPortions) -> some View {
        let hasChanges = !changedPortions.isEmpty

        return ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EditorialSheetHeader(
                        eyebrow: "Kto ile je",
                        title: "Porcje",
                        icon: "person.2.fill",
                        accent: SCPalette.butter,
                        subtitle: recipe.name,
                        onClose: { isPortionsSheetPresented = false }
                    ) {
                        if hasChanges && model.isEditable {
                            RecipeFilterClearButton(accessibilityLabel: "Cofnij zmiany porcji") {
                                withAnimation(.smooth(duration: 0.3)) {
                                    draftPortions = personalPortions?.units ?? [:]
                                }
                            }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }

                    portionsCard(model)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)
                .animation(.smooth(duration: 0.25), value: hasChanges)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scSheetFooter {
                if hasChanges && model.isEditable {
                    EditorialPrimaryActionButton(
                        title: "Zapisz porcje",
                        icon: "checkmark",
                        isEnabled: portionsSaveFeasible,
                        isLoading: isSavingServings
                    ) {
                        // Ta sama droga co przycisk pod pigułką: zapis każdej
                        // zmienionej osoby i zamknięcie szczegółów (razem
                        // z tym arkuszem).
                        performPrimaryAction()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.3), value: hasChanges)
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.resizes)
        .dashboardLiquidSheet()
    }

    /// Kolor osoby — ten sam co jej awatar w Planie.
    private func portionColor(_ person: RecipeDetailPortions.Person) -> Color {
        person.member.map { HouseholdMemberStyle.color(for: $0) } ?? SCPalette.terracotta
    }

    /// Porcje osób (4.10.2026, dwie rundy: „ładniej od nowa”, potem „bardziej
    /// czytelne, ale też ładnie UX”): karta z garnkiem i liczbą do ugotowania
    /// (`SCPortionSummary`) i lista osób z dużym stepperem (`SCPortionList`,
    /// `SCPortionRow`). Ten sam zestaw w „Dodaj do planu”
    /// (`Components/SCPortionKit.swift`).
    private func portionsCard(_ model: RecipeDetailPortions) -> some View {
        let total = PlanPortions.totalUnits(portionUnits)
        let kcal = Int(recipe.nutrition(forServings: PlanPortions.servings(fromUnits: total)).kcal.rounded())
        let totalUnits = PlanPortions.totalUnits(draftPortions)

        return VStack(spacing: 14) {
            SCPortionSummary(
                segments: model.people.map { person in
                    SCPortionSummary.Segment(
                        id: person.memberId,
                        units: portionUnits[person.memberId] ?? PlanPortions.missingEntryUnits,
                        color: portionColor(person)
                    )
                },
                kcal: kcal,
                note: !changedPortions.isEmpty && !portionsSaveFeasible
                    ? "Za dużo porcji naraz — zmniejsz jedną osobę mocniej"
                    : nil
            )

            SCPortionList {
                ForEach(Array(model.people.enumerated()), id: \.element.memberId) { index, person in
                    let units = portionUnits[person.memberId] ?? PlanPortions.missingEntryUnits
                    let saved = personalPortions?.units[person.memberId] ?? PlanPortions.missingEntryUnits
                    SCPortionRow(
                        name: person.name,
                        avatarUrl: person.member?.avatarUrl,
                        avatarColor: person.member?.avatarColor,
                        seed: person.memberId,
                        color: portionColor(person),
                        units: units,
                        kcal: Int(recipe.nutrition(forServings: PlanPortions.servings(fromUnits: units)).kcal.rounded()),
                        isViewer: person.memberId == model.viewerId,
                        isChanged: units != saved,
                        isEditable: model.isEditable,
                        canDecrement: PlanPortions.stepped(units: units, direction: -1, totalUnits: totalUnits) != nil,
                        canIncrement: PlanPortions.stepped(units: units, direction: 1, totalUnits: totalUnits) != nil,
                        showsDivider: index > 0,
                        onStep: { direction in
                            guard let next = PlanPortions.stepped(units: units, direction: direction, totalUnits: totalUnits) else { return }
                            // Ta sama krzywa co każda cyfra w aplikacji.
                            withAnimation(SCMotion.textRoll) { draftPortions[person.memberId] = next }
                        }
                    )
                }
            }

            if !model.isEditable {
                Text(PlanPortions.readOnlyMessage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(look.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Czy zapis porcji przejdzie osoba po osobie (`PlanPortions.isSequentialSaveFeasible`)
    /// — przy alokacji ponad 12 jedna osoba musi zejść bardziej.
    private var portionsSaveFeasible: Bool {
        PlanPortions.isSequentialSaveFeasible(saved: personalPortions?.units ?? [:], draft: draftPortions)
    }

    /// Osoby, których porcja różni się od zapisanej.
    private var changedPortions: [String: Int] {
        let saved = personalPortions?.units ?? [:]
        return draftPortions.filter { saved[$0.key] != $0.value }
    }

    // MARK: - Przygotowanie

    private var preparationSection: some View {
        let steps = recipe.preparationSteps.sorted { $0.stepNumber < $1.stepNumber }

        return VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(
                eyebrow: "Krok po kroku",
                title: "Przygotowanie",
                accent: SCPalette.sage
            ) { EmptyView() }

            DetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        DetailStepRow(index: index + 1, text: step.instruction)
                            .overlay(alignment: .top) {
                                if index > 0 { DetailHairline() }
                            }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Składniki

    private var ingredientsSection: some View {
        // Gramatury są przeliczone tym samym współczynnikiem co makra wyżej —
        // i eyebrow mówi wprost, na ile porcji.
        let scaled = recipe.ingredients(forServings: cookedServings)
        let groups = DetailIngredientGroup.make(from: scaled)

        return VStack(alignment: .leading, spacing: 12) {
            DetailSectionHeader(
                eyebrow: ingredientsEyebrow,
                title: "Składniki",
                accent: SCPalette.indigo
            ) {
                if showsShoppingPill {
                    shoppingPill
                        .transition(.scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
                }
            }

            DetailCard {
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.department) { groupIndex, group in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(group.department.uppercased())
                                .font(.system(size: 10.5, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(SCPalette.indigo)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(group.ingredients) { ingredient in
                                ingredientRow(ingredient)
                            }

                            Color.clear.frame(height: 6)
                        }
                        .overlay(alignment: .top) {
                            if groupIndex > 0 { DetailHairline() }
                        }
                    }

                    if showsIngredientsFooter {
                        ingredientsFooter
                            .overlay(alignment: .top) { DetailHairline() }
                    }
                }
            }
            .padding(.horizontal, 20)
            .sensoryFeedback(.selection, trigger: haveIngredientIds)
        }
    }

    @ViewBuilder
    private func ingredientRow(_ ingredient: Ingredient) -> some View {
        let amount = RecipeDetailFormat.ingredientAmount(ingredient)
        let name = RecipeDetailFormat.ingredientName(ingredient.name)

        if canSendToShopping {
            let have = haveIngredientIds.contains(ingredient.id)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if have {
                        haveIngredientIds.remove(ingredient.id)
                    } else {
                        haveIngredientIds.insert(ingredient.id)
                    }
                }
            } label: {
                DetailIngredientRow(name: name, amount: amount, have: have, showsCheckbox: true)
            }
            .buttonStyle(PlanPressStyle(scale: 0.985))
            .accessibilityLabel("\(name), \(amount)")
            .accessibilityValue(have ? "mam w domu" : "brakuje")
            .accessibilityHint("Zaznacz, jeśli masz w domu")
            .accessibilityAddTraits(have ? [.isButton, .isSelected] : .isButton)
        } else {
            DetailIngredientRow(name: name, amount: amount, have: false, showsCheckbox: false)
                .accessibilityElement(children: .combine)
        }
    }

    /// Jedna linijka pod składnikami — co się stanie z brakującymi.
    private var ingredientsFooter: some View {
        Group {
            if !canSendToShopping {
                // Posiłek z planu ma swoje składniki na liście od chwili, gdy
                // trafił do planu — dopisywanie ich drugi raz podwoiłoby zakupy.
                Text("Ten posiłek jest w planie — jego składniki są już na liście zakupów.")
                    .foregroundStyle(look.dim)
            } else if case .failed(let message) = shoppingSend {
                Text(message)
                    .foregroundStyle(SCPalette.terracotta)
            } else if isShoppingSentForCurrentState, case .sent(_, let count, let weekStart) = shoppingSend {
                let products = Text(PolishPlural.products(count))
                    .foregroundStyle(look.muted)
                    .fontWeight(.semibold)
                let verb = PolishPlural.form(count, one: "czeka", few: "czekają", many: "czeka")
                Text("Dopisane — \(products) \(verb) na liście zakupów \(Self.weekPhrase(weekStart)).")
                    .foregroundStyle(look.dim)
            } else if missingIngredientIds.isEmpty {
                Text("Masz wszystko — możesz gotować.")
                    .foregroundStyle(look.dim)
            } else {
                let count = missingIngredientIds.count
                let missing = Text("\(count) \(PolishPlural.form(count, one: "brakujący", few: "brakujące", many: "brakujących"))")
                    .foregroundStyle(look.muted)
                    .fontWeight(.semibold)
                let verb = PolishPlural.form(count, one: "trafi", few: "trafią", many: "trafi")
                Text("Zaznacz, co masz — \(missing) \(verb) na listę zakupów.")
                    .foregroundStyle(look.dim)
            }
        }
        .font(.system(size: 12.5))
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: footerKey)
    }

    /// Klucz do animacji stopki — zmienia się razem z jej treścią.
    private var footerKey: String {
        "\(missingIngredientIds.count).\(shoppingSend.key).\(isShoppingSentForCurrentState)"
    }

    /// „Do zakupów ›” w nagłówku sekcji składników.
    private var shoppingPill: some View {
        let isSent = isShoppingSentForCurrentState
        let isSending = shoppingSend == .sending
        let isEnabled = !missingIngredientIds.isEmpty && !isSending && !isSent
        let accent = isSent ? SCPalette.sage : SCPalette.indigo

        return Button(action: sendMissingToShopping) {
            HStack(spacing: 5) {
                if isSending {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(accent)
                        .transition(.scale.combined(with: .opacity))
                } else if isSent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .transition(.scale.combined(with: .opacity))
                }

                Text(isSent ? "Na liście" : "Do zakupów")
                    .contentTransition(.interpolate)

                if !isSent && !isSending {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .transition(.opacity)
                }
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .scSoftCapsule(accent)
            .fixedSize()
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .disabled(!isEnabled)
        .opacity(isEnabled || isSent || isSending ? 1 : 0.4)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: shoppingSend.key)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isSent)
        .sensoryFeedback(.success, trigger: shoppingSend.key) { _, new in new.hasPrefix("sent") }
        .accessibilityLabel(isSent ? "Brakujące są na liście zakupów" : "Dopisz brakujące do listy zakupów")
    }

    // MARK: - Lista zakupów: brakujące

    /// Dopisywać da się tylko z katalogu. Posiłek z planu ma już składniki
    /// na liście tygodnia — drugi raz podwoiłby zakupy, a cudzego przepisu
    /// (`.shared`) serwer na listę nie przyjmie.
    private var canSendToShopping: Bool {
        if case .catalog = context { return true }
        return false
    }

    /// Linijka pod składnikami mówi o zakupach — przy cudzym przepisie nie
    /// ma o czym.
    private var showsIngredientsFooter: Bool {
        if case .shared = context { return false }
        return true
    }

    /// „Udostępnij” obok krzyżyka — wszędzie poza cudzym przepisem.
    private var showsShareButton: Bool {
        if case .shared = context { return false }
        return true
    }

    /// „Do zakupów” pojawia się dopiero, gdy użytkownik zaczął odhaczać, co
    /// ma — bez tego wszystkie składniki są „brakujące” i przycisk nie ma
    /// z czego wybierać. Zostaje w trakcie i po wysyłce, żeby było widać wynik.
    private var showsShoppingPill: Bool {
        guard canSendToShopping else { return false }
        switch shoppingSend {
        case .sending, .sent, .failed: return true
        case .idle: return !haveIngredientIds.isEmpty && !missingIngredientIds.isEmpty
        }
    }

    private var missingIngredientIds: [UUID] {
        recipe.ingredients.map(\.id).filter { !haveIngredientIds.contains($0) }
    }

    private var currentShoppingSignature: ShoppingSendState.Signature {
        .init(missing: Set(missingIngredientIds), servings: servingsUnits)
    }

    /// Wysłane i od tamtej pory nic się nie zmieniło — ani odhaczenia, ani
    /// porcje. Każda zmiana przywraca „Do zakupów”, a ponowna wysyłka
    /// podmienia ilości po stronie serwera, zamiast je dublować.
    private var isShoppingSentForCurrentState: Bool {
        if case .sent(let signature, _, _) = shoppingSend {
            return signature == currentShoppingSignature
        }
        return false
    }

    /// Tydzień, na którego listę trafią brakujące: ten, który użytkownik
    /// ogląda w Planie — ale nigdy wcześniejszy niż bieżący, bo zakupy do
    /// minionego tygodnia nie mają sensu.
    private var targetWeekStart: String {
        let current = PlanWeek.dateKey(PlanWeek.monday(of: Date()))
        return max(datesViewModel.weekStartISO, current)
    }

    private func sendMissingToShopping() {
        let missing = missingIngredientIds
        guard !missing.isEmpty, shoppingSend != .sending else { return }

        let signature = currentShoppingSignature
        let weekStart = targetWeekStart
        // Lista zakupów przyjmuje całe porcje — 1,5 idzie jako 2.
        let requestedServings = wholeServings
        withAnimation { shoppingSend = .sending }

        Task { @MainActor in
            do {
                let added = try await shoppingListStore.addRecipeExtras(
                    weekStart: weekStart,
                    recipeId: recipe.id.uuidString.lowercased(),
                    servings: requestedServings,
                    ingredientIds: missing.map { $0.uuidString.lowercased() }
                )
                shoppingSend = .sent(signature: signature, count: added, weekStart: weekStart)
                toasts.success(
                    "Dopisano do listy zakupów",
                    "\(PolishPlural.products(added)) \(Self.weekPhrase(weekStart))."
                )
            } catch {
                // Błąd łączności ma w aplikacji jedno miejsce (trwały pasek
                // toastu) — `inlineMessage` oddaje wtedy `nil` i przycisk po
                // prostu wraca do stanu, w którym można go nacisnąć ponownie.
                if let message = UserFacingErrorMapper.inlineMessage(from: error) {
                    shoppingSend = .failed(message)
                } else {
                    shoppingSend = .idle
                }
            }
        }
    }

    /// „na ten tydzień” / „na przyszły tydzień” / „na tydzień od 5 października”.
    private static func weekPhrase(_ weekStart: String) -> String {
        let monday = PlanWeek.monday(of: Date())
        if weekStart == PlanWeek.dateKey(monday) { return "na ten tydzień" }
        if let next = PlanWeek.calendar.date(byAdding: .weekOfYear, value: 1, to: monday),
           weekStart == PlanWeek.dateKey(next) {
            return "na przyszły tydzień"
        }
        guard let date = PlanWeek.date(fromKey: weekStart) else { return "na tydzień \(weekStart)" }
        return "na tydzień od \(weekDayFormatter.string(from: date))"
    }

    private static let weekDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    // MARK: - Dolny pasek akcji

    /// Dolny pasek: jeden przycisk (albo dwa przy przepisie thermomixowym
    /// z połączonym Cookidoo) — SAME szklane przyciski nad treścią, BEZ tła,
    /// cienia i rozmytego pasa pod nimi. Przewijany przepis jedzie pod
    /// przyciskami i widać go przez szkło, jak w natywnych aplikacjach iOS 26.
    /// Rafał (4.10.2026, kolejny raz): „usuń ten shadow pod buttonem, zrób to
    /// natywnie, aby pokazywało się, co jest pod spodem” — nie wracać do
    /// płyty, cienia (`SCEdgeShade`) ani pasa (`SCFooterScrim`) w tym miejscu.
    private var primaryActionBar: some View {
        VStack(spacing: 10) {
            thermomixFeedback

            if isPortionMode, let personalPortions {
                portionsPill(personalPortions)
            }

            if case .shared = context {
                HStack(spacing: 10) {
                    saveSharedButton
                    planActionButton(title: splitPlanTitle)
                }
            } else if showsCook {
                // Makieta RD1/RD2: pełne „Dodaj do planu” / „Zapisz porcje”
                // mieszczą się na połowie (≈ 121 z 138 pt). Bez zapisu
                // „Gotuj” bierze całą szerokość.
                HStack(spacing: 10) {
                    if showsPlanAction {
                        planActionButton(title: primaryActionTitle)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                    cookButton
                }
            } else if showsThermomixSplit {
                HStack(spacing: 10) {
                    if showsPlanAction {
                        planActionButton(title: splitPlanTitle)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                    thermomixButton
                }
            } else if showsPlanAction {
                planActionButton(title: primaryActionTitle)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Te same marginesy co `SCSheetFooter`, tylko bez jej tła.
        .padding(.horizontal, SCPageMetrics.horizontal)
        .padding(.vertical, 12)
        // Przycisk wjeżdża, gdy jest co zapisać, i zjeżdża, gdy znów nie ma.
        .animation(.smooth(duration: 0.3), value: showsPlanAction)
    }

    /// „Zapisz porcje” stoi tylko wtedy, gdy jest co zapisać (Rafał 4.10.2026:
    /// „jak button jest zablokowany, to go ukryj, a jak się pokazuje — pokaż”).
    /// Dawniej stał od wejścia wygaszony. W trakcie zapisu zostaje, żeby nie
    /// zniknął pod palcem. „Dodaj do planu” (katalog, cudzy przepis) jest
    /// zawsze — jego blokada to chwilowa praca, a nie brak czegoś do zrobienia.
    private var showsPlanAction: Bool {
        if case .planned = context { return isPrimaryActionEnabled || isSavingServings }
        return true
    }

    /// Akcja planu w standardowym wariancie „soft" — terakota na tincie.
    private func planActionButton(title: String) -> some View {
        Button(action: performPrimaryAction) {
            HStack(spacing: 7) {
                Image(systemName: primaryActionIcon)
                    .font(.system(size: 13, weight: .heavy))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    .lineLimit(1)
            }
            .foregroundStyle(SCPalette.terracotta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .scSoftCapsule()
        }
        .buttonStyle(.plain)
        .disabled(!isPrimaryActionEnabled || isSavingServings)
        // Wygaszony tylko na chwilę pracy (zapis, przygotowanie planu) —
        // „Zapisz porcje” bez zmian w ogóle się nie pokazuje (`showsPlanAction`).
        .opacity(isPrimaryActionEnabled && !isSavingServings ? 1 : 0.45)
        .animation(.smooth(duration: 0.18), value: isPrimaryActionEnabled)
        .accessibilityLabel(primaryActionTitle)
    }

    // MARK: - Gotuj

    /// Paczka scenariusza w pamięci telefonu — bez niej „Gotuj” nie stoi
    /// (bez wyszarzonych obietnic, §4.1). Cudzy przepis (`.shared`) — nie.
    private var cookPackage: CookPackage? {
        if case .shared = context { return nil }
        return sessionStore.cookScenarioStore?.package(for: recipe)
    }

    /// Trwająca sesja TEGO przepisu — wtedy „Gotuj dalej”.
    private var cookSession: CookSession? {
        sessionStore.cookSessionStore?.activeSession(for: recipe.id)
    }

    private var showsCook: Bool {
        cookPackage != nil || cookSession != nil
    }

    /// „▶ Gotuj” — jedyny pełny terakotowy przycisk w aplikacji: główna akcja
    /// tego ekranu (makieta RD1/RD2, docs/GOTUJ.md „Wejścia”).
    private var cookButton: some View {
        Button(action: startCooking) {
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .heavy))
                Text(cookSession == nil ? "Gotuj" : "Gotuj dalej")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.scPageBase(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            // Pełna terakota jako szkło („prominent”, Liquid Glass runda 3):
            // dalej jedyny kryjący przycisk w aplikacji, ale z odblaskiem
            // i reakcją na dotyk jak przycisk obok.
            .scChromeGlass(in: Capsule(), tint: SCPalette.terracotta)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cookSession == nil ? "Gotuj" : "Wróć do gotowania")
    }

    private func startCooking() {
        if cookSession != nil {
            Task { await sessionStore.resumeCooking() }
            return
        }
        // Jedna sesja naraz (§4.7) — start innego dania pyta o tamto.
        if let other = sessionStore.cookSessionStore?.session, other.recipeId != recipe.id, other.stage != .finished {
            isReplaceCookingAsked = true
            return
        }
        beginCooking()
    }

    private func beginCooking() {
        guard let package = cookPackage else { return }
        var slot: MealSlot?
        var planDate: Date?
        var portions = didTouchStepper ? wholeServings : recipe.servings
        if case .planned(let day, let plannedSlot) = context {
            slot = plannedSlot
            planDate = day
            // Z planu: tyle, ile w planie (D11) — stepper szczegółów to te same porcje.
            portions = wholeServings
        }
        Task {
            await sessionStore.startCooking(
                recipe: recipe,
                package: package,
                portions: portions,
                slot: slot,
                planDate: planDate
            )
        }
    }

    // MARK: - Thermomix

    /// Split tylko przy potwierdzonym połączeniu — `.unknown` i brak
    /// integracji rysują zwykły pojedynczy przycisk.
    private var showsThermomixSplit: Bool {
        // Cudzego przepisu Cookidoo nie dostanie (serwer nie wyda go temu
        // domowi) — najpierw kopia, potem gotowanie z niej.
        if case .shared = context { return false }
        return recipe.isThermomix && sessionStore.cookidooIntegrationStore?.isConnected == true
    }

    /// Błąd wysyłki — jedna linijka nad przyciskami.
    ///
    /// Sukces idzie do toastu, ale błąd ZOSTAJE tutaj: toast nie ma przycisku,
    /// a to konkretna diagnoza (wygasłe hasło Cookidoo, przepis bez wersji na
    /// Thermomix) stojąca przy przycisku, który trzeba nacisnąć jeszcze raz.
    @ViewBuilder
    private var thermomixFeedback: some View {
        if let thermomixError {
            Text(thermomixError)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(SCPalette.terracotta)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Pod stopką nie ma już tła — zdanie stoi na własnym szkle,
                // żeby było czytelne nad przewijaną treścią.
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .scChromeGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity)
        }
    }

    /// Na połowie szerokości pełne „Dodaj do planu" nie mieści się bez
    /// ściskania — krótsze etykiety niosą to samo obok ikony.
    private var splitPlanTitle: String {
        switch context {
        case .catalog: return "Dodaj"
        case .planned: return "Zapisz"
        case .shared: return "Do planu"
        }
    }

    /// Prawa połowa: start gotowania. Glif wymienia się na spinner/ptaszek
    /// w stałej ramce, więc obie połówki trzymają rozmiar we wszystkich stanach.
    private var thermomixButton: some View {
        Button(action: sendToThermomix) {
            HStack(spacing: 7) {
                Group {
                    if isSendingToThermomix {
                        ProgressView()
                            .controlSize(.small)
                            .tint(SCPalette.sage)
                    } else {
                        Image(systemName: showThermomixSuccess ? "checkmark" : "play.fill")
                            .font(.system(size: 13, weight: .heavy))
                    }
                }
                .frame(width: 16, height: 17)

                Text("Gotuj w TM")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    .lineLimit(1)
            }
            .foregroundStyle(SCPalette.sage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .scSoftCapsule(SCPalette.sage)
        }
        .buttonStyle(.plain)
        .disabled(isSendingToThermomix)
        .accessibilityLabel("Gotuj w Thermomixie")
        .accessibilityHint("Wysyła przepis do planu Mój tydzień w Cookidoo na dzisiaj")
    }

    /// Zawsze dzisiejsza data w lokalnej strefie telefonu — przycisk znaczy
    /// „gotuję TERAZ", więc nawet posiłek zaplanowany na środę ląduje
    /// w Cookidoo na dziś: na ekranie TM6 kolumna dzisiejsza jest pierwsza.
    private static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func sendToThermomix() {
        guard let store = sessionStore.cookidooIntegrationStore, !isSendingToThermomix else { return }
        isSendingToThermomix = true
        thermomixError = nil
        // Ptaszek gaśnie na czas ponowienia — inaczej nieudana druga próba
        // zostawiała zielony ptaszek obok czerwonego błędu.
        showThermomixSuccess = false
        Task { @MainActor in
            let outcome = await store.sendToWeek(
                recipeId: recipe.id.uuidString.lowercased(),
                date: Self.todayDateString()
            )
            isSendingToThermomix = false
            switch outcome {
            case .sent, .alreadySent:
                // Ptaszek zostaje do końca oglądania przepisu: kapsuła toastu
                // znika, a on jest jedynym śladem, że ten przepis już poszedł.
                withAnimation(.smooth(duration: 0.2)) { showThermomixSuccess = true }
                toasts.success(
                    "Wysłano do Thermomixa",
                    "Czeka w kalendarzu \u{201E}Mój tydzień\u{201D} na dziś."
                )
            case .failed(let message):
                withAnimation(.smooth(duration: 0.2)) { thermomixError = message }
            }
        }
    }

    // MARK: - Akcja główna

    private var primaryActionTitle: String {
        switch context {
        case .catalog, .shared: return "Dodaj do planu"
        case .planned: return "Zapisz porcje"
        }
    }

    private var primaryActionIcon: String {
        switch context {
        case .catalog, .shared: return "plus"
        case .planned: return "checkmark"
        }
    }

    /// W planie zapisywać nie ma czego, dopóki liczba porcji jest ta sama, co
    /// przy wejściu — przycisk aktywny bez zmiany wysyłałby na serwer wartość,
    /// którą ten już ma.
    private var isPrimaryActionEnabled: Bool {
        switch context {
        case .catalog: return true
        case .shared: return !isPreparingPlan && sharedSave != .saving
        case .planned:
            if isPortionMode {
                return personalPortions?.isEditable == true && !changedPortions.isEmpty && portionsSaveFeasible
            }
            return servingsUnits != initialServings * PlanPortions.unitsPerServing
        }
    }

    private func performPrimaryAction() {
        switch context {
        case .catalog:
            isAddToPlanPresented = true
        case .shared:
            addSharedToPlan()
        case .planned:
            guard !isSavingServings else { return }
            if isPortionMode {
                let changed = changedPortions
                guard personalPortions?.isEditable == true, !changed.isEmpty else { return }
                isSavingServings = true
                onSavePortions?(draftPortions, changed)
                onClose?()
                return
            }
            isSavingServings = true
            onSaveServings?(wholeServings)
            onClose?()
        }
    }

    // MARK: - Cudzy przepis (`.shared`)

    /// Lewa połowa paska: „Zapisz u siebie” → „Zapisano”. Szałwia jak
    /// „Gotuj w TM”, bo to ta sama para — akcja poboczna obok planu.
    private var saveSharedButton: some View {
        let isSaved = sharedSave == .saved
        return Button(action: saveSharedCopy) {
            HStack(spacing: 7) {
                Group {
                    if sharedSave == .saving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(SCPalette.sage)
                    } else {
                        Image(systemName: isSaved ? "checkmark" : "bookmark")
                            .font(.system(size: 13, weight: .heavy))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 16, height: 17)

                Text(isSaved ? "Zapisano" : "Zapisz u siebie")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(SCPalette.sage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .scSoftCapsule(SCPalette.sage)
        }
        .buttonStyle(.plain)
        .disabled(sharedSave != .idle)
        .animation(.smooth(duration: 0.2), value: sharedSave)
        .sensoryFeedback(.success, trigger: isSaved) { _, new in new }
        .accessibilityLabel(isSaved ? "Zapisano w Twoich przepisach" : "Zapisz u siebie")
    }

    private func saveSharedCopy() {
        guard case .shared(let token, _) = context, sharedSave == .idle else { return }
        sharedSave = .saving
        Task { @MainActor in
            do {
                savedCopy = try await recipeCatalogStore.saveSharedRecipe(token: token)
                sharedSave = .saved
            } catch {
                sharedSave = .idle
                guard !UserFacingErrorMapper.isCancellation(error) else { return }
                toasts.error("Nie udało się zapisać przepisu", RecipeLinkErrorCopy.message(for: error))
            }
        }
    }

    /// Plan przyjmuje tylko przepisy tego domu — najpierw kopia (serwer
    /// oddaje istniejącą, gdy dom już ją ma), potem zwykłe „Dodaj do planu”
    /// na niej.
    private func addSharedToPlan() {
        guard case .shared(let token, _) = context, !isPreparingPlan else { return }
        if savedCopy != nil {
            isAddToPlanPresented = true
            return
        }
        isPreparingPlan = true
        Task { @MainActor in
            do {
                savedCopy = try await recipeCatalogStore.saveSharedRecipe(token: token)
                sharedSave = .saved
                isPreparingPlan = false
                isAddToPlanPresented = true
            } catch {
                isPreparingPlan = false
                guard !UserFacingErrorMapper.isCancellation(error) else { return }
                toasts.error("Nie udało się dodać do planu", RecipeLinkErrorCopy.message(for: error))
            }
        }
    }

    // MARK: - Debug

    /// `SCOFFIE_DEBUG_DETAIL_SCROLL=<pt>` przewija ekran od razu po wejściu,
    /// `SCOFFIE_DEBUG_DETAIL_SERVINGS=<n>` ustawia porcje, a
    /// `SCOFFIE_DEBUG_DETAIL_HAVE=<n>` odhacza pierwsze n składników — do
    /// porównania z artboardami makiety na zrzucie z symulatora.
    private func applyDebugLaunchOptions() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment["SCOFFIE_DEBUG_DETAIL_SERVINGS"], let count = Int(raw) {
            let whole = min(Self.servingsRange.upperBound, max(Self.servingsRange.lowerBound, count))
            servingsUnits = whole * PlanPortions.unitsPerServing
        }
        if let raw = environment["SCOFFIE_DEBUG_DETAIL_HAVE"], let count = Int(raw) {
            let ordered = DetailIngredientGroup.make(from: recipe.ingredients).flatMap(\.ingredients)
            haveIngredientIds = Set(ordered.prefix(count).map(\.id))
        }
        if let raw = environment["SCOFFIE_DEBUG_DETAIL_SCROLL"], let offset = Double(raw) {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                scrollPosition.scrollTo(y: CGFloat(offset))
            }
        }
        #endif
    }
}

// MARK: - „Zapisz u siebie”

private enum SharedSaveState: Equatable {
    case idle
    case saving
    case saved
}

// MARK: - Stan wysyłki na listę zakupów

private enum ShoppingSendState: Equatable {
    /// Co było brakujące i na ile porcji — po tym poznajemy, czy od wysyłki
    /// coś się zmieniło.
    struct Signature: Equatable {
        let missing: Set<UUID>
        /// Porcje w jednostkach 1/20 — 1,5 i 2 to różne wysyłki.
        let servings: Int
    }

    case idle
    case sending
    case sent(signature: Signature, count: Int, weekStart: String)
    case failed(String)

    var key: String {
        switch self {
        case .idle: return "idle"
        case .sending: return "sending"
        case .sent(_, let count, let week): return "sent.\(count).\(week)"
        case .failed: return "failed"
        }
    }
}

// MARK: - Tokeny ekranu

/// Liczby z makiety (`D` w `detail-v2.jsx`) dla ciemnego motywu i ich
/// odpowiedniki na kremie. Makieta jest ciemna; jasny motyw bierze akcenty
/// z palety aplikacji. Karty NIE są stąd — stoją na żetonach aplikacji
/// (`DetailCard`).
private struct DetailLook {
    let scheme: ColorScheme

    private var isDark: Bool { scheme == .dark }
    private var cream: Color { SCPalette.labelDark }
    private var ink: Color { SCPalette.labelLight }

    /// `#14100d` — tło arkusza z makiety, o ton cieplejsze od płótna.
    var background: Color {
        isDark
            ? Color(red: 20 / 255, green: 16 / 255, blue: 13 / 255)
            : SCPalette.canvasLight
    }

    var fg: Color { isDark ? cream : ink }
    var muted: Color { isDark ? cream.opacity(0.62) : ink.opacity(0.66) }
    var dim: Color { isDark ? cream.opacity(0.42) : ink.opacity(0.50) }
    var faint: Color { isDark ? cream.opacity(0.26) : ink.opacity(0.30) }

    var border: Color { isDark ? cream.opacity(0.08) : ink.opacity(0.08) }
    var rule: Color { isDark ? cream.opacity(0.07) : ink.opacity(0.08) }
    var chip: Color { isDark ? cream.opacity(0.06) : ink.opacity(0.045) }
    var checkboxStroke: Color { isDark ? cream.opacity(0.22) : ink.opacity(0.24) }
}

// MARK: - Tło

private struct DetailBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let look = DetailLook(scheme: scheme)
        look.background
            .overlay(alignment: .top) {
                // `radial-gradient(80% 30% at 50% 0%, rgba(70,45,32,0.45), transparent 60%)`
                // — ciepła poświata pod zdjęciem, widoczna, dopóki się ładuje
                // i przy przeciągnięciu arkusza w dół.
                GeometryReader { geo in
                    EllipticalGradient(
                        colors: [
                            Color(red: 70 / 255, green: 45 / 255, blue: 32 / 255)
                                .opacity(scheme == .dark ? 0.45 : 0.10),
                            .clear
                        ],
                        center: .top,
                        startRadiusFraction: 0,
                        endRadiusFraction: 0.6
                    )
                    .frame(width: geo.size.width, height: geo.size.height * 0.6)
                }
                .allowsHitTesting(false)
            }
    }
}

extension View {
    /// Arkusz szczegółów posiłku — jeden dla wszystkich czterech miejsc
    /// otwarcia (Przepisy, lista kategorii, Plan, Kalendarz).
    ///
    /// Tło prezentacji to TO SAMO tło co pod treścią, a nie `.clear`
    /// z `dashboardLiquidSheet`. W pierwszych klatkach wjazdu treść arkusza
    /// dostaje ostateczny rozmiar i dolny margines bezpieczny o klatkę za
    /// kontenerem — przy przezroczystym tle przez tę szczelinę prześwitywał
    /// jasny ekran pod spodem: cienka biała kreska przez całą szerokość na
    /// dole arkusza. Kryjące tło w kolorze strony zasłania ją u źródła.
    func recipeDetailSheet() -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(40)
            .presentationBackground { DetailBackground() }
    }
}

// MARK: - Zarys na czas wczytywania

/// Szczegół, zanim przyjdzie przepis — arkusz z linku wjeżdża od razu, więc
/// przez chwilę stoi na nim zarys: to samo tło, migoczące miejsce na zdjęcie
/// i tytuł, krzyżyk w tym samym miejscu. Treść wchodzi potem przenikaniem
/// (`RecipeLinkSheet`), bez przeskoku układu.
struct RecipeDetailPlaceholder: View {
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            DetailBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DetailHeroPhoto(url: nil)

                VStack(alignment: .leading, spacing: 12) {
                    EditorialShimmerBlock(cornerRadius: 8)
                        .frame(width: 120, height: 24)
                    EditorialShimmerBlock(cornerRadius: 10)
                        .frame(height: 34)
                    EditorialShimmerBlock(cornerRadius: 10)
                        .frame(width: 200, height: 34)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .topTrailing) {
            SCSheetCloseButton(onImage: true, action: onClose)
                .padding(.trailing, 20)
                .padding(.top, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Wczytywanie przepisu")
    }
}

// MARK: - Zdjęcie

/// Zdjęcie 340 pt od krawędzi do krawędzi, wtapiające się w tło. Przy 220 pt
/// danie ginęło pod tytułem — teraz zajmuje mniej więcej kwadrat szerokości
/// telefonu, a tytuł i tagi wchodzą tuż pod nim.
///
/// Przy przeciągnięciu w dół rośnie od dolnej krawędzi (zamiast odsłaniać
/// pustkę nad sobą), a przy przewijaniu w górę jedzie wolniej od treści —
/// oba efekty to `visualEffect`, więc nie przeliczają układu co klatkę.
private struct DetailHeroPhoto: View {
    let url: URL?
    /// Wjazd arkusza: zdjęcie startuje lekko przybliżone i osiada — ten sam
    /// ruch co zdjęcie w wyborze posiłku u Asystenta.
    var isRevealed: Bool = true

    // `nonisolated`, bo czyta ją domknięcie `onScrollGeometryChange` ekranu.
    nonisolated static let height: CGFloat = 340

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let look = DetailLook(scheme: scheme)
        // Zamknięcia `visualEffect` biegną poza głównym aktorem — biorą kopie.
        let height = Self.height
        let parallax: CGFloat = reduceMotion ? 0 : 0.3

        Color.clear
            .frame(height: height)
            .background {
                photo
                    .visualEffect { content, proxy in
                        // Paralaksa: przy przewijaniu w górę zdjęcie zostaje
                        // w tyle o 30 % drogi.
                        let minY = proxy.frame(in: .scrollView).minY
                        return content.offset(y: minY > 0 ? 0 : -minY * parallax)
                    }
            }
            .overlay(alignment: .top) {
                // Przyciski serca i zamknięcia stoją na zdjęciu — delikatny
                // cień u góry trzyma je czytelnymi na jasnym kadrze.
                LinearGradient(
                    colors: [.black.opacity(scheme == .dark ? 0.35 : 0.18), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [look.background.opacity(0), look.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .allowsHitTesting(false)
            }
            .clipped()
            .visualEffect { content, proxy in
                // Rozciągnięcie przy przeciągnięciu w dół, od dolnej krawędzi.
                let minY = proxy.frame(in: .scrollView).minY
                let stretch = minY > 0 ? (height + minY) / height : 1
                return content.scaleEffect(stretch, anchor: .bottom)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var photo: some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, variant: .large) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity.animation(.easeOut(duration: 0.35)))
                    case .empty, .failure:
                        EditorialShimmerBlock()
                    @unknown default:
                        EditorialShimmerBlock()
                    }
                }
            } else {
                EditorialShimmerBlock()
            }
        }
        .scaleEffect(isRevealed || reduceMotion ? 1 : 1.12)
        .animation(.easeOut(duration: 1.1), value: isRevealed)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - Tagi

/// `DPill` z makiety: ikona + wersaliki na tincie akcentu z obwódką.
private struct DetailTagPill: View {
    let icon: String
    let text: String
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(text.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(accent)
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(accent.opacity(scheme == .dark ? 0.20 : 0.14)))
        .overlay(Capsule().strokeBorder(accent.opacity(scheme == .dark ? 0.42 : 0.34), lineWidth: 1))
        .fixedSize()
    }
}

/// Pora, na którą przepis też pasuje — przerywana obwódka, bez tła: to
/// podpowiedź, nie druga kategoria.
private struct DetailDashedTag: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let look = DetailLook(scheme: scheme)
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.8)
            .lineLimit(1)
            .foregroundStyle(look.dim)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .overlay(
                Capsule().strokeBorder(
                    // 8 % kremu z makiety ginie przy przerywanej linii —
                    // obwódka dostaje dwa razy tyle, żeby kreski było widać.
                    scheme == .dark ? SCPalette.labelDark.opacity(0.18) : SCPalette.labelLight.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                )
            )
            .fixedSize()
    }
}

// MARK: - Nagłówek sekcji

/// `DSection`: pręcik akcentu z poświatą · eyebrow · tytuł · element z prawej.
private struct DetailSectionHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let accent: Color
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 4, height: 42)
                // `boxShadow: 0 0 16px accent/60%` — pręcik świeci, a nie
                // tylko stoi. Promień 8 = rozmycie 16 px z CSS.
                .shadow(color: accent.opacity(scheme == .dark ? 0.6 : 0.35), radius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(DetailLook(scheme: scheme).fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Karta

/// `DCard` z makiety w promieniu 18, ale na powierzchni kart aplikacji:
/// `scTileBg` + `scTileStroke` w obu motywach, bez cienia i bez światła na
/// krawędzi. Dawniej jasny motyw miał tu ciepłą biel z cieniem — jedyne
/// takie karty w aplikacji (Rafał, 23.09.2026: „wszystkie karty w tym samym
/// kolorze”).
private struct DetailCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color.scTileBg(scheme)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }
}

/// Linia między wierszami karty — od krawędzi do krawędzi, jak w makiecie.
private struct DetailHairline: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(DetailLook(scheme: scheme).rule)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Porcje osób



// MARK: - Stepper porcji

/// `DStepper` z wartością: „−  1  +” na pigułce. Minus gaśnie na dolnej
/// granicy, plus świeci terakotą. Cyfra przewija się w miejscu, a każde
/// stuknięcie daje krótki takt.
///
/// Ten sam stepper liczy porcje łączne (co 1) i porcję osoby (jednostki
/// 1/20, co 0,5 — `PlanPortions.stepped`): krok, etykietę i opis dla
/// VoiceOver podaje wołający.
private struct DetailServingsStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var label: (Int) -> String = { "\($0)" }
    var accessibilityName: String = "Liczba porcji"
    var accessibilityValueText: (Int) -> String = { PolishPlural.servings($0) }
    /// Wartość po kroku w stronę `direction` (+1 / −1) albo `nil`, gdy krok
    /// jest niedozwolony. Domyślnie ±1 w widełkach `range`.
    var next: ((Int, Int) -> Int?)? = nil
    var onChange: () -> Void = {}

    private func target(_ direction: Int) -> Int? {
        if let next { return next(value, direction) }
        let candidate = min(range.upperBound, max(range.lowerBound, value + direction))
        return candidate == value ? nil : candidate
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let look = DetailLook(scheme: scheme)

        HStack(spacing: 0) {
            stepButton(systemName: "minus", enabled: target(-1) != nil, look: look) {
                adjust(by: -1)
            }

            Text(label(value))
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(look.fg)
                .frame(minWidth: 28)
                .contentTransition(.numericText(value: Double(value)))

            stepButton(systemName: "plus", enabled: target(1) != nil, look: look) {
                adjust(by: 1)
            }
        }
        // Szklana pigułka jak `SCStepper` (Liquid Glass).
        .scChromeGlass(in: Capsule())
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(accessibilityValueText(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: 1)
            case .decrement: adjust(by: -1)
            @unknown default: break
            }
        }
    }

    private func adjust(by direction: Int) {
        guard let next = target(direction), next != value else { return }
        withAnimation(.snappy(duration: 0.25)) { value = next }
        onChange()
    }

    private func stepButton(
        systemName: String,
        enabled: Bool,
        look: DetailLook,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? SCPalette.terracotta : look.faint)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.86))
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.18), value: enabled)
    }
}

// MARK: - Wartości odżywcze: pierścienie celu dnia

/// Wartości porcji na tle dziennego celu — w tym samym języku co arkusz
/// „Cel dnia" w Planie i Kalendarzu: cztery koncentryczne pierścienie
/// (`PlanGoalRings`, kalorie na zewnątrz), obok legenda z torami
/// (`PlanGoalLegendRow`) w kolorach `SCMacroPalette`.
///
/// Makieta stawiała tu donut udziału makr z kcal w środku, ale w aplikacji
/// makra mają już swój rysunek i swoje kolory — ten sam posiłek nie może
/// w przepisie wyglądać inaczej niż w „Celu dnia". Kalorie stoją w legendzie
/// („1341 / 2000 kcal"), więc czterocyfrowa liczba nie musi mieścić się
/// w środku koła.
private struct DetailNutritionCard: View {
    let nutrition: Nutrition

    // Cel dnia — te same klucze i ta sama reguła, co Plan i Kalendarz.
    @AppStorage(RecipePersonalization.Keys.calorieGoal)
    private var calorieGoal: Int = RecipePersonalization.defaultCalorieGoal
    @AppStorage(RecipePersonalization.Keys.goal)
    private var goalRaw: String = UserGoal.healthy.rawValue
    @AppStorage(BodyMetrics.Keys.heightCm) private var profileHeightCm: Int = 0
    @AppStorage(BodyMetrics.Keys.weightKg) private var profileWeightKg: Double = 0
    @AppStorage(BodyMetrics.Keys.sex) private var profileSexRaw: String = ""
    @AppStorage(BodyMetrics.Keys.yearOfBirth) private var profileYearOfBirth: Int = 0
    @AppStorage(BodyMetrics.Keys.activityLevel)
    private var profileActivityRaw: Int = ActivityLevel.light.rawValue
    @AppStorage(DailyNutritionTargets.Keys.proteinG)
    private var proteinOverride: Int = DailyNutritionTargets.Keys.noOverride
    @AppStorage(DailyNutritionTargets.Keys.fatG)
    private var fatOverride: Int = DailyNutritionTargets.Keys.noOverride
    @AppStorage(DailyNutritionTargets.Keys.carbsG)
    private var carbsOverride: Int = DailyNutritionTargets.Keys.noOverride

    private var targets: DailyNutritionTargets {
        DailyNutritionTargets.resolve(
            calorieGoal: calorieGoal,
            goal: UserGoal(rawValue: goalRaw) ?? .healthy,
            metrics: BodyMetrics(
                heightCm: profileHeightCm,
                weightKg: profileWeightKg,
                yearOfBirth: profileYearOfBirth,
                activityRaw: profileActivityRaw,
                sexRaw: profileSexRaw
            ),
            proteinOverride: proteinOverride,
            fatOverride: fatOverride,
            carbsOverride: carbsOverride
        )
    }

    /// Kolejność wierszy = kolejność pierścieni: kalorie na zewnątrz.
    private var rows: [PlanGoalLegendRow.Row] {
        let macros = targets.macros
        return [
            .init(id: "kcal", title: "Kalorie", color: SCMacroPalette.calories,
                  value: Int(nutrition.kcal.rounded()), target: targets.kcal, unit: "kcal"),
            .init(id: "protein", title: "Białko", color: SCMacroPalette.protein,
                  value: Int(nutrition.protein.rounded()), target: macros?.proteinG, unit: "g"),
            .init(id: "fat", title: "Tłuszcze", color: SCMacroPalette.fat,
                  value: Int(nutrition.fat.rounded()), target: macros?.fatG, unit: "g"),
            .init(id: "carbs", title: "Węgle", color: SCMacroPalette.carbs,
                  value: Int(nutrition.carbs.rounded()), target: macros?.carbsG, unit: "g")
        ]
    }

    var body: some View {
        let rows = rows

        DetailCard {
            HStack(alignment: .center, spacing: 18) {
                DetailGoalRings(progresses: rows.map { $0.progress ?? 0 }, colors: rows.map(\.color))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(rows) { row in
                        DetailGoalLegendRow(row: row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
    }
}

/// Jedna krzywa dla pierścieni, torów i liczników sekcji — ruch ma się
/// czytać jako jeden. Wolniejszy i łagodniej hamujący niż w „Celu dnia”:
/// tu wykres jest główną treścią karty, a nie podsumowaniem nad listą.
private enum DetailNutritionMotion {
    /// Wjazd: 1,4 s z długim, miękkim wyhamowaniem (ease-out quint).
    static let reveal: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 1.4)
    /// Zmiana porcji: ta sama krzywa, krócej.
    static let change: Animation = .timingCurve(0.22, 1, 0.36, 1, duration: 0.8)
}

/// Koncentryczne pierścienie jak `PlanGoalRings` (te same wymiary, ten sam
/// `ActivityRing`), tylko z krzywą `DetailNutritionMotion` — i z płynnym
/// przejściem przy zmianie porcji, którego arkusz „Cel dnia” nie potrzebuje.
private struct DetailGoalRings: View {
    let progresses: [Double]
    let colors: [Color]

    @State private var isRevealed = false

    var body: some View {
        ZStack {
            ForEach(Array(progresses.enumerated()), id: \.offset) { index, progress in
                ActivityRing(
                    progress: isRevealed ? CGFloat(progress) : 0,
                    lineWidth: PlanGoalRings.lineWidth,
                    startColor: colors[index],
                    endColor: colors[index],
                    trackOpacity: 0.16
                )
                .padding(CGFloat(index) * (PlanGoalRings.lineWidth + PlanGoalRings.spacing))
            }
        }
        .frame(width: PlanGoalRings.size, height: PlanGoalRings.size)
        // Zmiana porcji — wjazd prowadzi `withAnimation` niżej, bo w jego
        // trakcie ta wartość się nie zmienia.
        .animation(DetailNutritionMotion.change, value: progresses)
        .onAppear {
            guard !isRevealed else { return }
            withAnimation(DetailNutritionMotion.reveal.delay(0.05)) { isRevealed = true }
        }
    }
}

/// Wiersz legendy jak `PlanGoalLegendRow`, z liczbą liczącą się
/// `CountingNumber` i torem na tej samej krzywej co pierścienie.
private struct DetailGoalLegendRow: View {
    let row: PlanGoalLegendRow.Row

    @Environment(\.colorScheme) private var scheme
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(row.color)
                    .frame(width: 7, height: 7)

                Text(row.title)
                    .scFont(12.5, weight: .semibold, relativeTo: .caption)
                    .tracking(-0.1)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Spacer(minLength: 6)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    CountingNumber(
                        target: row.value,
                        loadAnimation: DetailNutritionMotion.reveal,
                        changeAnimation: DetailNutritionMotion.change
                    )
                    .scFont(12.5, weight: .bold, relativeTo: .caption)
                    .foregroundStyle(row.isOverTarget ? row.color : Color.scLabel(scheme))

                    Text(row.target.map { "/ \($0) \(row.unit)" } ?? row.unit)
                        .scFont(10.5, weight: .semibold, relativeTo: .caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .lineLimit(1)
                .fixedSize()
            }

            if let progress = row.progress {
                MacroProgressTrack(
                    progress: isRevealed ? max(progress, 0) : 0,
                    color: row.color,
                    height: 3,
                    animation: isRevealed ? DetailNutritionMotion.change : DetailNutritionMotion.reveal
                )
            }
        }
        .onAppear { isRevealed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            row.target.map { "\(row.title): \(row.value) z \($0) \(row.unit)" }
                ?? "\(row.title): \(row.value) \(row.unit)"
        )
    }
}

// MARK: - Kroki

/// `StepsList`: numer w kółku szałwii, tekst 14,5 pt z wysokim wierszem.
private struct DetailStepRow: View {
    let index: Int
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let look = DetailLook(scheme: scheme)

        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(SCPalette.sage)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().strokeBorder(SCPalette.sage.opacity(scheme == .dark ? 0.6 : 0.5), lineWidth: 1.5)
                )

            Text(text)
                .font(.system(size: 14.5))
                .tracking(-0.1)
                // `lineHeight: 1.55` z makiety.
                .lineSpacing(5)
                .foregroundStyle(look.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Krok \(index). \(text)")
    }
}

// MARK: - Składniki

/// Składniki jednego działu, w kolejności obchodzenia sklepu.
private struct DetailIngredientGroup {
    let department: String
    let ingredients: [Ingredient]

    static func make(from ingredients: [Ingredient]) -> [DetailIngredientGroup] {
        let other = ProductConstants.Department.other
        let grouped = Dictionary(grouping: ingredients) { ingredient -> String in
            let department = ingredient.department?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return department.isEmpty ? other : department
        }
        // `Dictionary(grouping:)` trzyma kolejność z przepisu wewnątrz działu.
        return grouped
            .sorted { ProductConstants.isDepartment($0.key, orderedBefore: $1.key) }
            .map { DetailIngredientGroup(department: $0.key, ingredients: $0.value) }
    }
}

/// Wiersz składnika: pole „mam w domu” · nazwa · ilość.
private struct DetailIngredientRow: View {
    let name: String
    let amount: String
    let have: Bool
    let showsCheckbox: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let look = DetailLook(scheme: scheme)

        HStack(alignment: .center, spacing: 12) {
            if showsCheckbox {
                SCCheckbox(on: have, accent: SCPalette.indigo)
            }

            Text(name)
                .font(.system(size: 15))
                .tracking(-0.2)
                .foregroundStyle(have ? look.muted : look.fg)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(amount)
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(look.muted)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: have)
    }
}

// MARK: - Wjazd sekcji

// Kaskada sekcji to `scReveal(_:order:)` (`Components/SCReveal.swift`) —
// wyniesiona w rundzie 14, bo „Dodaj do planu” wjeżdża tak samo.

/// Przyciski na zdjęciu (serce, krzyżyk) pojawiają się razem z treścią,
/// a nie wiszą nad pustym kadrem, zanim zdjęcie osiądzie.
private struct DetailChrome: ViewModifier {
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.85)
            .animation(.easeOut(duration: 0.35).delay(0.05), value: isVisible)
    }
}

private extension View {
    /// Sekcje wchodzą po kolei — góra pierwsza, składniki ostatnie.
    func detailReveal(_ isVisible: Bool, order: Int) -> some View {
        scReveal(isVisible, order: order)
    }

    func detailChrome(_ isVisible: Bool) -> some View {
        modifier(DetailChrome(isVisible: isVisible))
    }
}

// MARK: - Shimmer (matches design's `Skel` primitive)

private struct EditorialShimmerBlock: View {
    var cornerRadius: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @State private var slide: CGFloat = -1

    var body: some View {
        let track = scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.06)
        let highlight = scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.10)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.10)

        GeometryReader { geo in
            ZStack {
                track

                LinearGradient(
                    stops: [
                        .init(color: track,     location: 0.0),
                        .init(color: highlight, location: 0.5),
                        .init(color: track,     location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.6)
                .offset(x: slide * geo.size.width * 1.3)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    slide = 1
                }
            }
        }
    }
}

// MARK: - Formatery

private enum RecipeDetailFormat {
    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let macroFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    static func integer(_ value: Double) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }

    static func macro(_ value: Double) -> String {
        macroFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func ingredientName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased(with: Locale(identifier: "pl_PL")) + trimmed.dropFirst()
    }

    static func ingredientAmount(_ ingredient: Ingredient) -> String {
        KitchenAmount.format(
            amount: ingredient.amount,
            unit: ingredient.unit,
            rawUnit: ingredient.rawUnit,
            department: ingredient.department,
            measure: ingredient.kitchenMeasure
        )
    }
}

// `RecipesMock` żyje w `#if DEBUG`, a makro `#Preview` rozwija się także
// w Release — bez tej bramki archiwum nie kompiluje się.
#if DEBUG

#Preview("Szczegóły v2 — Dark") {
    RecipeDetailView(recipe: RecipesMock.chickenBowl, onSetFavourite: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Szczegóły v2 — Light") {
    RecipeDetailView(recipe: RecipesMock.chickenBowl, onSetFavourite: { _ in })
        .preferredColorScheme(.light)
}

/// Wejście z planu wygląda inaczej od katalogowego w trzech miejscach naraz —
/// stepper startuje od zapisanych porcji, dolny przycisk zapisuje zamiast
/// dodawać, a składniki nie mają „mam w domu”.
#Preview("Szczegóły v2 — z planu, dark") {
    RecipeDetailView(
        recipe: RecipesMock.chickenBowl,
        onSetFavourite: { _ in },
        initialServings: 2,
        context: .planned(day: Date(), slot: .lunch),
        onSaveServings: { _ in }
    )
    .preferredColorScheme(.dark)
}

#endif
