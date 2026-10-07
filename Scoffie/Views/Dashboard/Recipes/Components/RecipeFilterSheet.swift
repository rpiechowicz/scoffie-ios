import SwiftUI

// Arkusz „Filtry” otwierany krążkiem filtrów w pływającym pasku szukania
// Przepisów (na korzeniu i w kategorii). Źródło: Claude Design, „Scoffie -
// Przepisy v3 - Filtry.html”, sekcja „Filtry · wersja finalna” (`FFSheet`
// w `components/filtry-final.jsx`).
//
// Nagłówek stoi przypięty nad przewijaną treścią (jak w każdym arkuszu,
// `scScrollEdgeFade`). Pod nim (6.10.2026 wieczór, po pięciu rundach podglądu
// — Rafał: „prościej, ale nie smutno”): w kategorii rodzaj dania jako kółka ze
// zdjęciem dania (na stałe, bez przewijania w bok) i smak jako dwa kafle ze
// zdjęciem, a w filtrach wszystkich przepisów kuchnia ze zdjęciami (G1); czas
// przygotowania jako przełącznik Liquid Glass (L2); reszta to JEDNA lista jak
// Ustawienia iOS (kolorowy kafelek ikony, wartość po prawej): mięso / pora
// kategorii, trudność i kalorie (systemowe menu), dieta, składniki i —
// w kategorii — „Więcej filtrów” (cechy, kuchnia, okazje), a globalnie
// „Okazje i sezon” i „Cechy” wprost.
// Kafelki ze zdjęciami i siatki stoją tylko na podstronach. Bez kategorii
// w zakresie, a z filtrami którejś kategorii — karta „Filtry kategorii”, żeby
// widać było wszystko, co zawęża listę. Na dole liczba przepisów i „Gotowe”.
//
// Zmiany idą OD RAZU do Przepisów (6.10.2026 — wcześniej kopia robocza
// i „Pokaż”): lista pod arkuszem i liczba w stopce zmieniają się z każdym
// stuknięciem, więc zamknięcie gestem niczego nie gubi, a „Gotowe” tylko
// zamyka. Dalsze kroki — „Więcej filtrów”, „Bez składników” i jego działy —
// to PUSH w stosie arkusza (systemowy pasek z tytułem i „wstecz”), nie
// kolejne arkusze na arkuszu.
//
// Te same Filtry stoją w „Wybierz przepis” w Planie (7.10.2026, Rafał: „na
// filtrach mam inne niż te, co są na głównych przepisach — trzeba to
// ujednolicić”; wcześniej własna strona `RecipePlanFilterPage`). Tam są
// PUSHEM w stosie arkusza wyboru (`isPushed`) — arkusz na arkuszu jest
// zakazany, a `NavigationStack` w `NavigationStack` nie działa — więc pierwszy
// ekran dostaje systemowy pasek („wstecz”, „Filtry”, różdżka i „Wyczyść”)
// zamiast nagłówka z krzyżykiem, a „Gotowe” wraca do listy (`onDone`).
// `slot` = pora, na którą się wybiera: bez aspektu „Pora w planie” (pora jest
// już wybrana), a aspekty kategorii pory liczą się dla każdego dania listy,
// także z innej kategorii (`RecipeFilterIndex(…, facetCategory:)`).
struct RecipeFilterSheet: View {
    @Binding var filters: RecipeFilterOptions
    /// Przełącznik „Dopasowane do Ciebie” — różdżka obok krzyżyka.
    @Binding var isPersonalizationEnabled: Bool

    /// Profil z Ustawień (dieta, alergeny, cel). `isEnabled` nie ma tu
    /// znaczenia — o nim decyduje `isPersonalizationEnabled`.
    let personalization: RecipePersonalization

    /// Gdzie stoi lista, z której otwarto Filtry: kategoria (ekran kategorii,
    /// zakładka kategorii w wynikach), „Ulubione” albo `nil` — wszystkie
    /// przepisy. Kategoria dokłada swoją sekcję i zawęża liczby.
    let scope: RecipesCategory?

    /// Pora wyboru przepisu do planu (`scope` = jej kategoria); `nil` = Przepisy.
    let slot: MealSlot?

    /// Ekran wepchnięty w stos innego arkusza (wybór do planu) zamiast
    /// własnego arkusza z własnym `NavigationStack`.
    let isPushed: Bool

    /// „Gotowe” — co znaczy koniec; `nil` = zamknij arkusz (`dismiss`).
    let onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var indexBox: IndexBox
    /// Wpchnięta podstrona — grupa „Więcej filtrów”, wykluczanie składników
    /// albo filtry kategorii spoza zakresu.
    @State private var openPane: Pane?

    /// Przepisy zakresu po szukaniu, ale PRZED dopasowaniem i filtrami.
    private let recipes: [Recipe]

    init(
        filters: Binding<RecipeFilterOptions>,
        isPersonalizationEnabled: Binding<Bool>,
        scope: RecipesCategory?,
        recipes: [Recipe],
        personalization: RecipePersonalization,
        slot: MealSlot? = nil,
        isPushed: Bool = false,
        onDone: (() -> Void)? = nil
    ) {
        self._filters = filters
        self._isPersonalizationEnabled = isPersonalizationEnabled
        self.scope = scope
        self.recipes = recipes
        self.personalization = personalization
        self.slot = slot
        self.isPushed = isPushed
        self.onDone = onDone
        self._indexBox = State(initialValue: IndexBox())
    }

    /// Kategoria, w której aspektach liczy się KAŻDY przepis puli — tylko
    /// w wyborze do planu (kategoria pory); na Przepisach każdy we własnej.
    private var facetCategory: RecipesCategory? {
        slot == nil ? nil : scope
    }

    /// Indeks liczony leniwie, raz na otwarcie arkusza. Nie w `init`: ten
    /// odpala się przy KAŻDYM przerysowaniu Przepisów pod arkuszem (a teraz
    /// każde stuknięcie je przerysowuje), a `State(initialValue:)` i tak
    /// wyrzuca wszystko poza pierwszą wartością.
    private var index: RecipeFilterIndex {
        if let index = indexBox.index { return index }
        let index = RecipeFilterIndex(
            recipes: recipes,
            personalization: personalization,
            facetCategory: facetCategory
        )
        indexBox.index = index
        indexBox.recipes = recipes
        return index
    }

    /// Zdjęcia kafelków Diety, Cech, Kuchni i Okazji — tak samo leniwie i raz na otwarcie.
    /// Dania ukryte przez profil (np. z alergenem z Ustawień) biorą się
    /// dopiero, gdy nic innego nie pasuje — niezależnie od przełącznika
    /// „Dopasowane do Ciebie”, żeby zdjęcie nie zmieniało się z nim.
    private var covers: RecipeFilterCovers {
        if let covers = indexBox.covers { return covers }
        let entries = index.entries
        let covers = RecipeFilterCovers(recipes: indexBox.recipes) { entries[$0].hiddenByProfile }
        indexBox.covers = covers
        return covers
    }

    /// Zdjęcia kafelków aspektów kategorii — raz na kategorię i otwarcie.
    private func facetCovers(for category: RecipesCategory) -> RecipeFacetCovers {
        if let covers = indexBox.facetCovers[category] { return covers }
        let covers = index.facetCovers(for: category, recipes: indexBox.recipes)
        indexBox.facetCovers[category] = covers
        return covers
    }

    // MARK: - Stan pochodny

    private var fit: Bool { isPersonalizationEnabled }

    private var resultCount: Int { index.count(filters, fit: fit) }

    /// Kategoria, której sekcja stoi na wierzchu arkusza.
    private var sectionCategory: RecipesCategory? {
        guard let scope, RecipesCategory.catalogSections.contains(scope) else { return nil }
        return scope
    }

    /// Kategorie z filtrami, które działają na listę, a nie mają sekcji na
    /// wierzchu (zakres bez kategorii) — karta „Filtry kategorii”.
    private var otherFilteredCategories: [RecipesCategory] {
        guard sectionCategory == nil else { return [] }
        return RecipesCategory.catalogSections.filter { filters.categoryFilters[$0]?.isActive == true }
    }

    private var lockedDiets: Set<RecipeDietFilter> {
        fit ? RecipeDietFilter.lockedByProfile(personalization) : []
    }

    /// Z profilu, a nie ma własnego kafelka w Diecie: pozostałe alergeny
    /// i diety spoza kafelków. Stoją z kłódką na górze listy działów.
    private var profileChips: [RecipeFilterChipLine.Chip] {
        guard fit else { return [] }
        var chips: [RecipeFilterChipLine.Chip] = []
        switch personalization.diet {
        case .pescatarian, .paleo, .highProtein:
            chips.append(.init(id: "diet", title: personalization.diet.title, locked: true))
        default:
            break
        }
        for allergen in Allergen.allCases
        where personalization.avoidedAllergens.contains(allergen) && allergen != .lactose && allergen != .gluten {
            chips.append(.init(id: allergen.rawValue, title: Self.chipTitle(for: allergen), locked: true))
        }
        return chips
    }

    /// Nazwa alergenu na chip — bez nawiasu, który w Ustawieniach tłumaczy,
    /// o co chodzi, a na chipie tylko go wydłuża.
    private static func chipTitle(for allergen: Allergen) -> String {
        switch allergen {
        case .milk: return "Białko mleka"
        default:    return allergen.title.components(separatedBy: " (").first ?? allergen.title
        }
    }

    /// „z 1072 przepisów” / „z 132 w tej kategorii” / „z 18 ulubionych” /
    /// „z 96 do wyboru” (wybór do planu).
    private var totalContext: String {
        if slot != nil { return "do wyboru" }
        if scope == .favourite { return "ulubionych" }
        if sectionCategory != nil { return "w tej kategorii" }
        return index.total == 1 ? "przepisu" : "przepisów"
    }

    // MARK: - Body

    var body: some View {
        if isPushed {
            // W stosie arkusza wyboru do planu — jego `NavigationStack`
            // niesie i ten ekran, i podstrony (`navigationDestination` niżej).
            withSelectionHaptics(
                page
                    .scPushedPage("Filtry")
                    .toolbar { pushedToolbar }
            )
        } else {
            withSelectionHaptics(
                NavigationStack {
                    page
                        .toolbar(.hidden, for: .navigationBar)
                }
                .tint(SCPalette.terracotta)
            )
        }
    }

    /// Pierwszy ekran z podstronami wpychanymi w stos, w którym stoi.
    private var page: some View {
        root
            .navigationDestination(item: $openPane) { pane in
                RecipeFilterPane(
                    pane: pane,
                    filters: $filters,
                    fit: fit,
                    index: index,
                    covers: covers,
                    facetCovers: { facetCovers(for: $0) },
                    profileChips: profileChips,
                    lockedDiets: lockedDiets,
                    totalContext: totalContext,
                    onDone: { finish() }
                )
            }
    }

    /// Haptyka wyboru — na stosie arkusza (albo na wepchniętym ekranie),
    /// nie na podstronach, inaczej byłaby podwójna.
    private func withSelectionHaptics<Content: View>(_ content: Content) -> some View {
        content
            .sensoryFeedback(.selection, trigger: filters.diets)
            .sensoryFeedback(.selection, trigger: filters.traits)
            .sensoryFeedback(.selection, trigger: filters.cuisines)
            .sensoryFeedback(.selection, trigger: filters.moments)
            .sensoryFeedback(.selection, trigger: filters.categoryFilters)
            .sensoryFeedback(.impact(weight: .light), trigger: isPersonalizationEnabled)
    }

    /// Pasek wepchniętego ekranu: różdżka „Dopasowane do Ciebie” (jak obok
    /// krzyżyka w arkuszu) i „Wyczyść” — tak jak na podstronach Filtrów.
    @ToolbarContentBuilder
    private var pushedToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if personalization.hasAnyPreference {
                Button {
                    withAnimation(.smooth(duration: 0.22)) { isPersonalizationEnabled.toggle() }
                } label: {
                    Image(systemName: "wand.and.stars")
                        .symbolEffect(.bounce, value: isPersonalizationEnabled)
                }
                .tint(isPersonalizationEnabled ? SCPalette.sage : nil)
                .accessibilityLabel("Dopasowane do Ciebie")
                .accessibilityValue(isPersonalizationEnabled ? "włączone" : "wyłączone")
            }

            Button("Wyczyść") { clearAll() }
                .disabled(!filters.isActive(in: scope))
                .accessibilityLabel("Wyczyść filtry")
        }
    }

    /// „Gotowe” i „Gotowe” podstron: zamknięcie arkusza albo — w stosie
    /// wyboru do planu — powrót do listy.
    private func finish() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    private var root: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Przypięty i taki sam przez cały czas. Był zwijany do samego
                // tytułu na środku — przy przewijaniu „Filtry” przeskakiwały
                // z lewej na środek, a Rafał chciał ich tam, gdzie zawsze.
                // Wepchnięty ekran ma w tym miejscu systemowy pasek.
                if !isPushed {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 12)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if isPushed {
                            // Zdanie spod tytułu arkusza — co robi różdżka
                            // z paska i gdzie działają filtry.
                            Text(headerScope)
                                .font(.sc(size: 13))
                                .foregroundStyle(Color.scMuted(scheme))
                                .fixedSize(horizontal: false, vertical: true)
                                .contentTransition(.opacity)
                                .padding(.horizontal, 6)
                                .padding(.top, 8)
                        }
                        if let category = sectionCategory {
                            dishSection(category)
                            tasteSection(category)
                        } else {
                            cuisineSection
                        }
                        timeSection
                        listSection(sectionCategory)
                        if !otherFilteredCategories.isEmpty {
                            categoryFiltersSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                // Treść gaśnie, gdy wjeżdża pod nagłówek — wspólny „cień w dół”;
                // pod systemowym paskiem — jego miękka krawędź.
                .modifier(RecipeFilterScrollEdge(isPushed: isPushed))
                // Wspólna stopka arkuszy (`scSheetFooter`): liczba przepisów
                // i „Gotowe”, przewijane sekcje przejeżdżają pod nimi.
                .scSheetFooter { footer }
            }
        }
        .animation(.smooth(duration: 0.22), value: filters.isActive(in: scope))
        .animation(.smooth(duration: 0.22), value: otherFilteredCategories)
    }

    // MARK: - Nagłówek

    private var header: some View {
        RecipeFilterHeader(
            icon: "slider.horizontal.3",
            eyebrow: headerEyebrow,
            title: "Filtry",
            scope: headerScope,
            canClear: filters.isActive(in: scope),
            onClear: { clearAll() },
            fitIsOn: personalization.hasAnyPreference ? isPersonalizationEnabled : nil,
            onToggleFit: { withAnimation(.smooth(duration: 0.22)) { isPersonalizationEnabled.toggle() } },
            onClose: { dismiss() }
        )
    }

    /// Nad tytułem — gdzie stoi lista: „Przepisy”, „Obiady”, „Ulubione”,
    /// w wyborze do planu — pora.
    private var headerEyebrow: String {
        if let slot { return slot.title }
        guard let scope else { return "Przepisy" }
        return RecipesConstants.displayName(for: scope)
    }

    /// Podtytuł mówi, co robi różdżka obok krzyżyka — dawna karta
    /// „Dopasowane do Ciebie” z przełącznikiem zajmowała górę arkusza.
    private var headerScope: String {
        guard personalization.hasAnyPreference, fit else {
            if let slot { return "Zawężają listę przepisów na \(slot.accusativeName)" }
            return "Działają od razu na listę przepisów"
        }
        let hidden = index.profileHiddenCount
        return hidden > 0
            ? "Dopasowane do Ciebie · ukrywa \(PolishPlural.recipes(hidden))"
            : "Dopasowane do Ciebie · \(profileSummary)"
    }

    // MARK: - Dopasowanie

    /// Co dopasowanie bierze pod uwagę — „Wegetariańska · bez: gluten,
    /// orzechy · cel: schudnąć”. Przejęte z arkusza, który otwierała różdżka
    /// na Przepisach: przełącznik jest teraz tylko tutaj, więc tu musi też
    /// powiedzieć, co przełącza.
    private var profileSummary: String {
        var parts: [String] = []
        if personalization.diet != .none {
            parts.append(personalization.diet.title)
        }
        let allergens = Allergen.allCases.filter { personalization.avoidedAllergens.contains($0) }
        if !allergens.isEmpty {
            let names = allergens.map { $0.pickerTitle.lowercased() }
            let shown = names.prefix(2).joined(separator: ", ")
            parts.append(names.count > 2 ? "bez: \(shown) +\(names.count - 2)" : "bez: \(shown)")
        }
        if personalization.ranksCatalog {
            parts.append("cel: \(personalization.goal.shortTitle.lowercased())")
        }
        return parts.isEmpty ? "Na podstawie Twojego profilu" : parts.joined(separator: " · ")
    }

    // MARK: - Kategoria

    /// Aspekty kategorii, które stoją w arkuszu: rodzaj dania, smak, mięso,
    /// pora. Kuchnia i okazje kategorii zostają w „Więcej filtrów”, bo to te
    /// same osie, co filtry wszystkich przepisów (dwie „Kuchnie” w jednym
    /// arkuszu czytałyby się jak błąd).
    static func inlineFacets(for category: RecipesCategory) -> [RecipeFacet] {
        RecipeCategoryFacets.facets(for: category).filter { !$0.kind.hidesEmptyOptions }
    }

    private func facet(_ kind: RecipeFacetKind, in category: RecipesCategory) -> RecipeFacet? {
        Self.inlineFacets(for: category).first { $0.kind == kind }
    }

    /// Rodzaj dania — kółka ze zdjęciem dania, na stałe (bez przewijania w bok).
    @ViewBuilder
    private func dishSection(_ category: RecipesCategory) -> some View {
        if let facet = facet(.dish, in: category) {
            let covers = facetCovers(for: category)
            // „Rodzaj dania” w każdej kategorii — aspekt przekąsek nazywa się
            // krócej („Rodzaj”), ale w arkuszu etykieta ma być jedna.
            RecipeFilterSection(title: "Rodzaj dania", top: 6) {
                RecipeFacetPhotoGrid(
                    options: facet.options,
                    accent: RecipeAccent.accent(for: category),
                    icon: RecipesConstants.icon(for: category),
                    isOn: { filters.categoryFilters[category]?.contains($0, in: .dish) ?? false },
                    cover: { covers.cover(for: $0, in: .dish) },
                    onToggle: { filters.toggle($0, in: .dish, for: category) }
                )
            }
        }
    }

    /// Smak — dwa kafle ze zdjęciem słodkiego i słonego dania z tej kategorii.
    @ViewBuilder
    private func tasteSection(_ category: RecipesCategory) -> some View {
        if let facet = facet(.taste, in: category) {
            let covers = facetCovers(for: category)
            let picks = filters.categoryFilters[category]?.picks[.taste] ?? []
            RecipeFilterSection(title: facet.title) {
                RecipeTasteTiles(
                    options: facet.options,
                    selection: picks.count == 1 ? picks.first : nil,
                    cover: { covers.cover(for: $0, in: .taste) },
                    onSelect: { filters.select($0, in: .taste, for: category) }
                )
            }
        }
    }

    // MARK: - Kuchnia (filtry globalne)

    /// Filtry wszystkich przepisów (wariant G1, 6.10.2026): rodzaj dania
    /// i smak należą do kategorii, więc na górę idzie kuchnia — 12 kółek ze
    /// zdjęciem typowego dania, ten sam klocek co rodzaj dania w kategorii.
    private var cuisineSection: some View {
        RecipeFilterSection(title: "Kuchnia", top: 6) {
            RecipeFacetPhotoGrid(
                options: RecipeCuisine.allCases.map { RecipeFacetOption(id: $0.rawValue, title: $0.title) },
                accent: SCPalette.sage,
                icon: "globe.europe.africa.fill",
                isOn: { id in RecipeCuisine(rawValue: id).map { filters.cuisines.contains($0) } ?? false },
                cover: { id in RecipeCuisine(rawValue: id).flatMap { covers.cuisines[$0] } },
                onToggle: { id in
                    if let cuisine = RecipeCuisine(rawValue: id) { filters.toggle(cuisine: cuisine) }
                }
            )
        }
    }

    /// Ikona wiersza aspektu — rodzaj dania bierze ikonę kategorii.
    static func facetIcon(_ kind: RecipeFacetKind, in category: RecipesCategory) -> String {
        switch kind {
        case .taste:   return "birthday.cake.fill"
        case .dish:    return RecipesConstants.icon(for: category)
        case .protein: return "fish.fill"
        case .slot:    return "clock.fill"
        case .cuisine: return "globe.europe.africa.fill"
        case .moment:  return "calendar"
        }
    }

    /// Filtry kategorii, które działają na listę, choć ich sekcji nie ma
    /// w arkuszu (Filtry z korzenia Przepisów) — wiersz na kategorię, push do
    /// jej aspektów. Bez tego „Wyczyść” zdejmowałby coś, czego nie widać.
    private var categoryFiltersSection: some View {
        let categories = otherFilteredCategories
        return RecipeFilterSection(title: "Filtry kategorii") {
            RecipeFilterPickerGroup {
                ForEach(Array(categories.enumerated()), id: \.element) { offset, category in
                    if offset > 0 {
                        RecipeFilterListDivider()
                    }
                    let chips = Self.facetChips(of: filters.categoryFilters[category], in: category)
                    RecipeFilterListButtonRow(
                        icon: RecipesConstants.icon(for: category),
                        title: RecipesConstants.displayName(for: category),
                        value: Self.summary(chips.map(\.title)),
                        isActive: !chips.isEmpty,
                        accent: RecipeAccent.accent(for: category)
                    ) { openPane = .category(category) }
                }
            }
        }
    }

    /// Zaznaczone opcje aspektów kategorii jako pigułki wiersza.
    static func facetChips(of filter: RecipeCategoryFilter?, in category: RecipesCategory) -> [RecipeFilterChipLine.Chip] {
        guard let chosen = filter else { return [] }
        return RecipeCategoryFacets.facets(for: category).flatMap { facet in
            facet.options
                .filter { chosen.contains($0.id, in: facet.kind) }
                .map { RecipeFilterChipLine.Chip(id: "\(facet.kind.rawValue):\($0.id)", title: $0.title) }
        }
    }

    /// Wartość wiersza z kilku wybranych: „Wege”, „Wege +2”.
    static func summary(_ titles: [String], none: String = "Dowolne") -> String {
        guard let first = titles.first else { return none }
        return titles.count > 1 ? "\(first) +\(titles.count - 1)" : first
    }

    // MARK: - Czas

    private static let timeChoices: [RecipeFilterChoice<Int?>] =
        [.init(value: nil, title: "Dowolny")]
        + RecipeFilterOptions.prepTimeChoices.map { minutes in
            RecipeFilterChoice<Int?>(value: minutes, title: "\(minutes) min")
        }

    /// Czas przygotowania — przełącznik w kolorze, wybór od ręki.
    private var timeSection: some View {
        RecipeFilterSection(title: "Czas przygotowania") {
            RecipeFilterSegment(
                choices: Self.timeChoices,
                selection: $filters.maxPrepTimeMinutes,
                accent: SCPalette.terracotta
            )
        }
    }

    // MARK: - Lista

    private static let difficultyChoices: [RecipeFilterChoice<Difficulty?>] = [
        .init(value: nil, title: "Dowolna"),
        .init(value: .easy, title: "Łatwa"),
        .init(value: .medium, title: "Średnia"),
        .init(value: .hard, title: "Trudna")
    ]

    /// Progi kalorii w menu. Limit ustawiony inaczej (stary wykres, inny
    /// próg) dochodzi do listy, żeby menu pokazało, co działa.
    private var calorieChoices: [RecipeFilterChoice<Int?>] {
        var limits = [300, 400, 500, 600, 700, 800]
        if let current = filters.maxCaloriesPerServing, !limits.contains(current) {
            limits.append(current)
            limits.sort()
        }
        return [.init(value: nil, title: "Dowolne")]
            + limits.map { RecipeFilterChoice<Int?>(value: $0, title: "do \($0) kcal") }
    }

    /// Reszta filtrów jako JEDNA lista jak Ustawienia iOS: kolorowy kafelek
    /// ikony, wartość po prawej (wybrana w kapsułce). Trudność i kalorie =
    /// systemowe menu; mięso / pora kategorii, dieta, składniki i „Więcej
    /// filtrów” = podstrona.
    private func listSection(_ category: RecipesCategory?) -> some View {
        // „Pora w planie” (przekąski) znika w wyborze do planu — pora jest
        // tam już wybrana, a lista ma tylko jej przepisy.
        let hidesSlot = slot != nil
        let otherFacets = category.map { cat in
            Self.inlineFacets(for: cat).filter {
                $0.kind != .dish && $0.kind != .taste && !(hidesSlot && $0.kind == .slot)
            }
        } ?? []
        let locked = lockedDiets
        let diets = RecipeDietFilter.allCases
            .filter { locked.contains($0) || filters.diets.contains($0) }
            .map(\.title)
        let excluded = profileChips.map(\.title)
            + filters.excludedIngredients
                .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
                .map(\.chipTitle)
        let more = filters.traits.count + filters.cuisines.count + filters.moments.count
        let traits = RecipeTraitFilter.allCases.filter { filters.traits.contains($0) }.map(\.title)
        let moments = RecipeMoment.allCases.filter { filters.moments.contains($0) }.map(\.title)

        // Bez etykiety nad kartą — „Więcej” dublowało wiersz „Więcej filtrów”,
        // a lista czyta się sama (jak w podglądzie uzgodnionym 6.10.2026).
        return RecipeFilterPickerGroup {
            if let category {
                ForEach(otherFacets) { facet in
                    let picked = facet.options
                        .filter { filters.categoryFilters[category]?.contains($0.id, in: facet.kind) ?? false }
                        .map(\.title)
                    RecipeFilterListButtonRow(
                        icon: Self.facetIcon(facet.kind, in: category),
                        title: facet.title,
                        value: Self.summary(picked),
                        isActive: !picked.isEmpty,
                        accent: RecipeAccent.accent(for: category)
                    ) { openPane = .facet(category, facet.kind) }
                    RecipeFilterListDivider()
                }
            }

            RecipeFilterListMenuRow(
                icon: "chart.bar.fill",
                title: "Trudność",
                choices: Self.difficultyChoices,
                selection: $filters.difficulty,
                accent: SCPalette.indigo
            )
            RecipeFilterListDivider()
            RecipeFilterListMenuRow(
                icon: "flame.fill",
                title: "Kalorie na porcję",
                choices: calorieChoices,
                selection: $filters.maxCaloriesPerServing,
                accent: SCPalette.terracotta
            )
            RecipeFilterListDivider()
            RecipeFilterListButtonRow(
                icon: "leaf.fill",
                title: "Dieta",
                value: Self.summary(diets),
                isActive: !diets.isEmpty,
                accent: SCPalette.sage
            ) { openPane = .diets }
            RecipeFilterListDivider()
            RecipeFilterListButtonRow(
                icon: "nosign",
                title: "Bez składników",
                value: Self.summary(excluded, none: "Żadnych"),
                isActive: !excluded.isEmpty,
                accent: SCPalette.rose
            ) { openPane = .exclude }
            RecipeFilterListDivider()
            if category != nil {
                RecipeFilterListButtonRow(
                    icon: "sparkles",
                    title: "Więcej filtrów",
                    value: more > 0 ? "Wybrane: \(more)" : "Cechy, kuchnia…",
                    isActive: more > 0,
                    accent: SCPalette.lavender
                ) { openPane = .more }
            } else {
                // Globalnie kuchnia stoi na górze, więc zostają dwie grupy —
                // bez pośredniego „Więcej filtrów”.
                RecipeFilterListButtonRow(
                    icon: "calendar",
                    title: "Okazje i sezon",
                    value: Self.summary(moments),
                    isActive: !moments.isEmpty,
                    accent: SCPalette.rose
                ) { openPane = .moments }
                RecipeFilterListDivider()
                RecipeFilterListButtonRow(
                    icon: "sparkles",
                    title: "Cechy",
                    value: Self.summary(traits),
                    isActive: !traits.isEmpty,
                    accent: SCPalette.indigo
                ) { openPane = .traits }
            }
        }
        .padding(.top, 24)
    }

    // MARK: - Podstrony

    /// Podstrony arkusza (push w jego stosie). Kafelki ze zdjęciami stoją
    /// TYLKO tu — na wierzchu arkusza są zdjęcia rodzaju dania, smak, czas
    /// i jedna lista (6.10.2026, Rafał: „prościej, ale nie smutno”).
    enum Pane: Hashable {
        case traits, cuisines, moments, exclude, diets, more
        /// Jeden aspekt kategorii z zakresu (mięso, pora).
        case facet(RecipesCategory, RecipeFacetKind)
        /// Wszystkie aspekty kategorii spoza zakresu („Filtry kategorii”).
        case category(RecipesCategory)
    }

    // MARK: - Stopka

    /// Liczba przepisów na żywo — dokładnie ta, którą pokazuje lista pod
    /// arkuszem — i „Gotowe”, które tylko zamyka (zmiany już działają).
    private var footer: some View {
        let count = resultCount

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(count)")
                        .font(.sc(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(count)))

                    Text(verbatim: "z \(index.total) \(totalContext)")
                        .font(.sc(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }

                if scope == nil {
                    RecipeFilterCategorySplit(
                        counts: index.countsByCategory(filters, fit: fit),
                        totals: index.totalsByCategory
                    )
                    .padding(.top, 7)
                } else {
                    RecipeFilterProgressBar(
                        count: count,
                        total: index.total,
                        accent: slot?.cozyAccent
                            ?? scope.map(RecipeScopeTabs.accent(for:))
                            ?? SCPalette.terracotta
                    )
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(footerAccessibilityLabel(count: count))

            RecipeFilterFooterButton(title: "Gotowe", trailingIcon: nil) { finish() }
        }
        .padding(.leading, 4)
    }

    private func footerAccessibilityLabel(count: Int) -> String {
        let head = "Zostaje \(PolishPlural.recipes(count)) z \(index.total) \(totalContext)."
        guard scope == nil else { return head }
        let byCategory = index.countsByCategory(filters, fit: fit)
        let split = RecipesCategory.catalogSections
            .filter { (index.totalsByCategory[$0] ?? 0) > 0 }
            .map { "\(RecipesConstants.displayName(for: $0)) \(byCategory[$0] ?? 0)" }
            .joined(separator: ", ")
        return "\(head) \(split)"
    }

    // MARK: - Akcje

    /// „Wyczyść” zdejmuje WSZYSTKO, co działa na listę w zakresie — filtry
    /// wszystkich przepisów i filtry kategorii — od razu.
    private func clearAll() {
        withAnimation(.smooth(duration: 0.25)) {
            filters.reset(in: scope)
        }
    }

    /// Pudełko na indeks — klasa, żeby zapamiętanie wyniku w trakcie `body`
    /// nie było zmianą stanu, która przerysowuje widok.
    private final class IndexBox {
        var index: RecipeFilterIndex?
        /// Przepisy, z których policzono indeks — w tej samej kolejności.
        var recipes: [Recipe] = []
        var covers: RecipeFilterCovers?
        var facetCovers: [RecipesCategory: RecipeFacetCovers] = [:]
    }
}

// MARK: - Podstrony

/// Podstrona arkusza „Filtry” wpchnięta w jego stos. Czyta filtry przez
/// wiązanie, więc liczby i kafelki zmieniają się na żywo także wtedy, gdy
/// strona stoi nad korzeniem arkusza. „Gotowe” zamyka cały arkusz — zmiany
/// już działają; „wstecz” wraca do Filtrów. Haptykę wyboru daje arkusz
/// (`sensoryFeedback` na jego stosie), nie strona — inaczej byłaby podwójna.
private struct RecipeFilterPane: View {
    let pane: RecipeFilterSheet.Pane
    @Binding var filters: RecipeFilterOptions
    let fit: Bool
    let index: RecipeFilterIndex
    let covers: RecipeFilterCovers
    let facetCovers: (RecipesCategory) -> RecipeFacetCovers
    let profileChips: [RecipeFilterChipLine.Chip]
    /// Diety z profilu — kafelki z kłódką.
    let lockedDiets: Set<RecipeDietFilter>
    let totalContext: String
    let onDone: () -> Void

    private var resultCount: Int { index.count(filters, fit: fit) }

    var body: some View {
        switch pane {
        case .traits:
            RecipeFilterPage(
                title: "Cechy",
                accent: SCPalette.indigo,
                hint: "Wszystkie zaznaczone naraz",
                selectedCount: filters.traits.count,
                resultCount: resultCount,
                totalCount: index.total,
                totalContext: totalContext,
                onClear: { filters.traits = [] },
                onDone: onDone
            ) {
                RecipeFilterTileGrid(items: RecipeTraitFilter.visibleCases) { trait in
                    RecipeFilterOptionTile(
                        title: trait.title,
                        count: index.count(adding: trait, to: filters, fit: fit),
                        mark: filters.traits.contains(trait) ? .on : .off,
                        accent: SCPalette.indigo,
                        cover: covers.traits[trait],
                        icon: trait.tileIcon,
                        accessibilityDetail: trait.accessibilityDetail
                    ) {
                        withAnimation(.smooth(duration: 0.18)) { filters.toggle(trait: trait) }
                    }
                }
            }
        case .cuisines:
            RecipeFilterPage(
                title: "Kuchnia",
                accent: SCPalette.sage,
                hint: "Dowolna z zaznaczonych",
                selectedCount: filters.cuisines.count,
                resultCount: resultCount,
                totalCount: index.total,
                totalContext: totalContext,
                onClear: { filters.cuisines = [] },
                onDone: onDone
            ) {
                RecipeFilterTileGrid(items: RecipeCuisine.allCases) { cuisine in
                    RecipeFilterOptionTile(
                        title: cuisine.title,
                        count: index.count(adding: cuisine, to: filters, fit: fit),
                        mark: filters.cuisines.contains(cuisine) ? .on : .off,
                        accent: SCPalette.sage,
                        cover: covers.cuisines[cuisine],
                        icon: cuisine.tileIcon,
                        accessibilityDetail: "kuchnia \(cuisine.summaryAdjective)"
                    ) {
                        withAnimation(.smooth(duration: 0.18)) { filters.toggle(cuisine: cuisine) }
                    }
                }
            }
        case .moments:
            RecipeFilterPage(
                title: "Okazje i sezon",
                accent: SCPalette.rose,
                hint: "Dowolna z zaznaczonych · pora roku to dania sezonowe",
                selectedCount: filters.moments.count,
                resultCount: resultCount,
                totalCount: index.total,
                totalContext: totalContext,
                onClear: { filters.moments = [] },
                onDone: onDone
            ) {
                RecipeFilterTileGrid(items: RecipeMoment.allCases) { moment in
                    RecipeFilterOptionTile(
                        title: moment.title,
                        count: index.count(adding: moment, to: filters, fit: fit),
                        mark: filters.moments.contains(moment) ? .on : .off,
                        accent: SCPalette.rose,
                        cover: covers.moments[moment],
                        icon: moment.tileIcon
                    ) {
                        withAnimation(.smooth(duration: 0.18)) { filters.toggle(moment: moment) }
                    }
                }
            }
        case .exclude:
            RecipeExcludePage(
                index: index,
                filters: $filters,
                fit: fit,
                profileChips: profileChips,
                onDone: onDone
            )
        case .diets:
            dietPage
        case .more:
            morePage
        case .facet(let category, let kind):
            facetPage(category, kind: kind)
        case .category(let category):
            categoryPage(category)
        }
    }

    /// „Więcej filtrów” — cechy, kuchnia, okazje i sezon jako wiersze; każdy
    /// wpycha swoje kafelki (`NavigationLink` w stosie arkusza).
    private var morePage: some View {
        let traits = RecipeTraitFilter.allCases.filter { filters.traits.contains($0) }.map(\.title)
        let cuisines = RecipeCuisine.allCases.filter { filters.cuisines.contains($0) }.map(\.title)
        let moments = RecipeMoment.allCases.filter { filters.moments.contains($0) }.map(\.title)

        return RecipeFilterPage(
            title: "Więcej filtrów",
            accent: SCPalette.lavender,
            selectedCount: traits.count + cuisines.count + moments.count,
            resultCount: resultCount,
            totalCount: index.total,
            totalContext: totalContext,
            onClear: {
                filters.traits = []
                filters.cuisines = []
                filters.moments = []
            },
            onDone: onDone
        ) {
            RecipeFilterPickerGroup {
                moreLink(.traits, icon: "sparkles", title: "Cechy", picked: traits, accent: SCPalette.indigo)
                RecipeFilterListDivider()
                moreLink(.cuisines, icon: "globe.europe.africa.fill", title: "Kuchnia", picked: cuisines, accent: SCPalette.sage)
                RecipeFilterListDivider()
                moreLink(.moments, icon: "calendar", title: "Okazje i sezon", picked: moments, accent: SCPalette.rose)
            }
        }
    }

    private func moreLink(
        _ pane: RecipeFilterSheet.Pane,
        icon: String,
        title: String,
        picked: [String],
        accent: Color
    ) -> some View {
        NavigationLink {
            RecipeFilterPane(
                pane: pane,
                filters: $filters,
                fit: fit,
                index: index,
                covers: covers,
                facetCovers: facetCovers,
                profileChips: profileChips,
                lockedDiets: lockedDiets,
                totalContext: totalContext,
                onDone: onDone
            )
        } label: {
            RecipeFilterListRowLabel(
                icon: icon,
                title: title,
                value: RecipeFilterSheet.summary(picked),
                isActive: !picked.isEmpty,
                accent: accent,
                trailingIcon: "chevron.right"
            )
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
    }

    /// Dieta — kafelki ze zdjęciem dania; diety z profilu z kłódką.
    private var dietPage: some View {
        RecipeFilterPage(
            title: "Dieta",
            accent: SCPalette.sage,
            hint: lockedDiets.isEmpty ? "" : "Z kłódką — z Twojego profilu, zmienisz w Ustawieniach",
            selectedCount: filters.diets.count,
            resultCount: resultCount,
            totalCount: index.total,
            totalContext: totalContext,
            onClear: { filters.diets = [] },
            onDone: onDone
        ) {
            RecipeFilterTileGrid(items: RecipeDietFilter.allCases) { diet in
                let isLocked = lockedDiets.contains(diet)
                RecipeFilterOptionTile(
                    title: diet.title,
                    count: isLocked ? nil : index.count(adding: diet, to: filters, fit: fit),
                    mark: isLocked ? .locked : (filters.diets.contains(diet) ? .on : .off),
                    accent: SCPalette.sage,
                    cover: covers.diets[diet],
                    icon: diet.tileIcon
                ) {
                    withAnimation(.smooth(duration: 0.18)) { filters.toggle(diet: diet) }
                }
            }
        }
    }

    /// Jeden aspekt kategorii z zakresu — kafelki ze zdjęciem dania.
    @ViewBuilder
    private func facetPage(_ category: RecipesCategory, kind: RecipeFacetKind) -> some View {
        if let facet = RecipeCategoryFacets.facets(for: category).first(where: { $0.kind == kind }) {
            let covers = facetCovers(category)
            let accent = RecipeAccent.accent(for: category)

            RecipeFilterPage(
                title: facet.title,
                accent: accent,
                hint: "Dowolna z zaznaczonych",
                selectedCount: filters.categoryFilters[category]?.picks[kind]?.count ?? 0,
                resultCount: resultCount,
                totalCount: index.total,
                totalContext: totalContext,
                onClear: { filters.select(nil, in: kind, for: category) },
                onDone: onDone
            ) {
                RecipeFilterTileGrid(items: facet.options) { option in
                    RecipeFilterOptionTile(
                        title: option.title,
                        count: index.count(adding: option.id, in: kind, for: category, to: filters, fit: fit),
                        mark: (filters.categoryFilters[category]?.contains(option.id, in: kind) ?? false) ? .on : .off,
                        accent: accent,
                        cover: covers.cover(for: option.id, in: kind),
                        icon: RecipeFilterSheet.facetIcon(kind, in: category)
                    ) {
                        withAnimation(.smooth(duration: 0.18)) { filters.toggle(option.id, in: kind, for: category) }
                    }
                }
            }
        }
    }

    /// Aspekty kategorii spoza zakresu listy (wiersz „Filtry kategorii”).
    private func categoryPage(_ category: RecipesCategory) -> some View {
        let covers = facetCovers(category)
        let accent = RecipeAccent.accent(for: category)
        let selected = filters.categoryFilters[category]?.activeCount ?? 0

        return RecipeFilterPage(
            title: RecipesConstants.displayName(for: category),
            accent: accent,
            hint: "Tylko w tej kategorii · w jednym rzędzie dowolna z zaznaczonych",
            selectedCount: selected,
            resultCount: resultCount,
            totalCount: index.total,
            totalContext: totalContext,
            onClear: { filters.categoryFilters[category] = nil },
            onDone: onDone
        ) {
            ForEach(RecipeFilterSheet.inlineFacets(for: category)) { facet in
                RecipeFacetTilesSection(
                    facet: facet,
                    title: facet.title,
                    top: 12,
                    accent: accent,
                    icon: RecipesConstants.icon(for: category),
                    isOn: { filters.categoryFilters[category]?.contains($0, in: facet.kind) ?? false },
                    count: { index.count(adding: $0, in: facet.kind, for: category, to: filters, fit: fit) },
                    cover: { covers.cover(for: $0, in: facet.kind) },
                    onToggle: { filters.toggle($0, in: facet.kind, for: category) }
                )
            }
        }
    }
}

// MARK: - Ile zostaje w każdej kategorii

/// Cztery paski pod liczbą w stopce — szerokość paska to wielkość kategorii
/// w katalogu, wypełnienie to ile w niej zostaje. Pod paskiem sama liczba,
/// w kolorze kategorii (ten sam, co sekcje na Przepisach).
private struct RecipeFilterCategorySplit: View {
    let counts: [RecipesCategory: Int]
    let totals: [RecipesCategory: Int]

    private static let spacing: CGFloat = 3

    private var categories: [RecipesCategory] {
        RecipesCategory.catalogSections.filter { (totals[$0] ?? 0) > 0 }
    }

    var body: some View {
        let visible = categories
        let sum = visible.reduce(0) { $0 + (totals[$1] ?? 0) }

        GeometryReader { proxy in
            let usable = max(0, proxy.size.width - Self.spacing * CGFloat(max(visible.count - 1, 0)))

            HStack(alignment: .top, spacing: Self.spacing) {
                ForEach(visible) { category in
                    let total = totals[category] ?? 0
                    let left = counts[category] ?? 0
                    let width = usable * CGFloat(total) / CGFloat(max(sum, 1))
                    let accent = RecipeAccent.accent(for: category)

                    VStack(alignment: .leading, spacing: 4) {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.2))
                            .frame(height: 5)
                            .overlay(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(accent)
                                    .frame(width: left == 0 ? 0 : max(5, width * CGFloat(left) / CGFloat(max(total, 1))))
                            }

                        Text(verbatim: "\(left)")
                            .font(.sc(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                            .contentTransition(.numericText(value: Double(left)))
                            .fixedSize()
                    }
                    .frame(width: width, alignment: .leading)
                }
            }
        }
        .frame(height: 22)
        .animation(.smooth(duration: 0.3), value: counts)
    }
}

// MARK: - Krawędź przewijania

/// Górna krawędź przewijanej treści Filtrów: w arkuszu wspólny „cień w dół”
/// pod przypiętym nagłówkiem (`scScrollEdgeFade`), na ekranie wepchniętym
/// w stos wyboru do planu — miękka krawędź systemowego paska, jak na
/// podstronach (`RecipeFilterPage`).
private struct RecipeFilterScrollEdge: ViewModifier {
    let isPushed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPushed {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content.scScrollEdgeFade()
        }
    }
}

// MARK: - Przełącznik

/// Mały switch-look bez `Toggle` — cały wiersz jest przyciskiem, więc
/// natywny toggle łapałby gest jako drugi target.
struct RecipeFilterToggleIndicator: View {
    let isOn: Bool
    var accent: Color = SCPalette.terracotta

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Capsule()
            .fill(isOn ? AnyShapeStyle(accent) : AnyShapeStyle(Color.scBarTrack(scheme)))
            .frame(width: 44, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .padding(.horizontal, 3)
            }
            .animation(.smooth(duration: 0.18), value: isOn)
    }
}

// MARK: - Glify kafelków

/// Glif na kafelku, gdy żaden przepis z tą cechą nie ma zdjęcia.
private extension RecipeDietFilter {
    var tileIcon: String {
        switch self {
        case .lactoseFree: return "cup.and.saucer.fill"
        case .vegetarian:  return "leaf.fill"
        case .vegan:       return "carrot.fill"
        case .withFish:    return "fish.fill"
        case .glutenFree:  return "laurel.leading"
        case .keto:        return "flame.fill"
        }
    }
}

private extension RecipeTraitFilter {
    var tileIcon: String {
        switch self {
        case .highProtein: return "dumbbell.fill"
        case .lowFat:      return "drop.fill"
        case .highFiber:   return "leaf"
        case .lowSalt:     return "aqi.low"
        case .airfryer:    return "fan.fill"
        case .lunchbox:    return "takeoutbag.and.cup.and.straw.fill"
        case .favourites:  return "heart.fill"
        case .thermomix:   return "cooktop.fill"
        }
    }
}
