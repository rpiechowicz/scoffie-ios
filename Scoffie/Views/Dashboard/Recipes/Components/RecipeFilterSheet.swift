import SwiftUI

// Arkusz „Filtry” otwierany krążkiem filtrów w pływającym pasku szukania
// Przepisów (na korzeniu i w kategorii). Źródło: Claude Design, „Scoffie -
// Przepisy v3 - Filtry.html”, sekcja „Filtry · wersja finalna” (`FFSheet`
// w `components/filtry-final.jsx`).
//
// Nagłówek stoi przypięty nad przewijaną treścią (jak w każdym arkuszu,
// `scScrollEdgeFade`). Pod nim: sekcja KATEGORII, gdy lista stoi w kategorii
// (ekran kategorii albo jej zakładka w wynikach — rodzaj dania, smak, mięso;
// aspekty z `RecipeCategoryFacets`), czas i trudność, kalorie (wykres
// rozkładu, który sam jest suwakiem), dieta (kafelki ze zdjęciem dania
// i liczbą przepisów), karta „Więcej filtrów” (cechy, kuchnia, okazje
// i sezon) i wykluczanie składników. Bez kategorii w zakresie, a z filtrami
// którejś kategorii — karta „Filtry kategorii”, żeby widać było wszystko, co
// zawęża listę. Na dole liczba przepisów i „Gotowe”.
//
// Zmiany idą OD RAZU do Przepisów (6.10.2026 — wcześniej kopia robocza
// i „Pokaż”): lista pod arkuszem i liczba w stopce zmieniają się z każdym
// stuknięciem, więc zamknięcie gestem niczego nie gubi, a „Gotowe” tylko
// zamyka. Dalsze kroki — „Więcej filtrów”, „Wyklucz składniki” i jego działy —
// to PUSH w stosie arkusza (systemowy pasek z tytułem i „wstecz”), nie
// kolejne arkusze na arkuszu.
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
        personalization: RecipePersonalization
    ) {
        self._filters = filters
        self._isPersonalizationEnabled = isPersonalizationEnabled
        self.scope = scope
        self.recipes = recipes
        self.personalization = personalization
        self._indexBox = State(initialValue: IndexBox())
    }

    /// Indeks liczony leniwie, raz na otwarcie arkusza. Nie w `init`: ten
    /// odpala się przy KAŻDYM przerysowaniu Przepisów pod arkuszem (a teraz
    /// każde stuknięcie je przerysowuje), a `State(initialValue:)` i tak
    /// wyrzuca wszystko poza pierwszą wartością.
    private var index: RecipeFilterIndex {
        if let index = indexBox.index { return index }
        let index = RecipeFilterIndex(recipes: recipes, personalization: personalization)
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

    /// Pole celu na linijce kalorii: od śniadania (25 % dnia) do obiadu
    /// (40 %) — te same udziały, którymi cel porządkuje katalog.
    private var goalZone: ClosedRange<Int>? {
        guard fit, personalization.hasAnyPreference else { return nil }
        let daily = Double(personalization.dailyCalorieGoal)
        let lower = Self.roundedToStep(daily * personalization.calorieShare(for: .breakfast))
        let upper = Self.roundedToStep(daily * personalization.calorieShare(for: .lunch))
        guard upper > lower else { return nil }
        return lower...upper
    }

    private static func roundedToStep(_ kcal: Double) -> Int {
        let step = Double(RecipeFilterOptions.calorieStep)
        return Int((kcal / step).rounded() * step)
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

    /// „z 1072 przepisów” / „z 132 w tej kategorii” / „z 18 ulubionych”.
    private var totalContext: String {
        if scope == .favourite { return "ulubionych" }
        if sectionCategory != nil { return "w tej kategorii" }
        return index.total == 1 ? "przepisu" : "przepisów"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            root
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $openPane) { pane in
                    RecipeFilterPane(
                        pane: pane,
                        filters: $filters,
                        fit: fit,
                        index: index,
                        covers: covers,
                        facetCovers: { facetCovers(for: $0) },
                        profileChips: profileChips,
                        totalContext: totalContext,
                        onDone: { dismiss() }
                    )
                }
        }
        .tint(SCPalette.terracotta)
        .sensoryFeedback(.selection, trigger: filters.diets)
        .sensoryFeedback(.selection, trigger: filters.traits)
        .sensoryFeedback(.selection, trigger: filters.cuisines)
        .sensoryFeedback(.selection, trigger: filters.moments)
        .sensoryFeedback(.selection, trigger: filters.categoryFilters)
        .sensoryFeedback(.impact(weight: .light), trigger: isPersonalizationEnabled)
    }

    private var root: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Przypięty i taki sam przez cały czas. Był zwijany do samego
                // tytułu na środku — przy przewijaniu „Filtry” przeskakiwały
                // z lewej na środek, a Rafał chciał ich tam, gdzie zawsze.
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let category = sectionCategory {
                            categorySection(category)
                        }
                        timeAndDifficultySection
                        caloriesSection
                        dietSection
                        moreSection
                        excludeSection
                        if !otherFilteredCategories.isEmpty {
                            categoryFiltersSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                // Treść gaśnie, gdy wjeżdża pod nagłówek — wspólny „cień w dół”.
                .scScrollEdgeFade()
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

    /// Nad tytułem — gdzie stoi lista: „Przepisy”, „Obiady”, „Ulubione”.
    private var headerEyebrow: String {
        guard let scope else { return "Przepisy" }
        return RecipesConstants.displayName(for: scope)
    }

    /// Podtytuł mówi, co robi różdżka obok krzyżyka — dawna karta
    /// „Dopasowane do Ciebie” z przełącznikiem zajmowała górę arkusza.
    private var headerScope: String {
        guard personalization.hasAnyPreference, fit else { return "Działają od razu na listę przepisów" }
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

    /// Aspekty kategorii na wierzchu arkusza — rodzaj dania, smak, mięso,
    /// pora. Kuchnia i okazje kategorii zostają w „Więcej filtrów”, bo to te
    /// same osie, co filtry wszystkich przepisów (dwie „Kuchnie” w jednym
    /// arkuszu czytałyby się jak błąd).
    static func inlineFacets(for category: RecipesCategory) -> [RecipeFacet] {
        RecipeCategoryFacets.facets(for: category).filter { !$0.kind.hidesEmptyOptions }
    }

    @ViewBuilder
    private func categorySection(_ category: RecipesCategory) -> some View {
        let covers = facetCovers(for: category)
        let name = RecipesConstants.shortDisplayName(for: category)
        ForEach(Self.inlineFacets(for: category)) { facet in
            RecipeFacetTilesSection(
                facet: facet,
                title: "\(name) · \(facet.title)",
                accent: RecipeAccent.accent(for: category),
                icon: RecipesConstants.icon(for: category),
                isOn: { filters.categoryFilters[category]?.contains($0, in: facet.kind) ?? false },
                count: { index.count(adding: $0, in: facet.kind, for: category, to: filters, fit: fit) },
                cover: { covers.cover(for: $0, in: facet.kind) },
                onToggle: { filters.toggle($0, in: facet.kind, for: category) }
            )
        }
    }

    /// Filtry kategorii, które działają na listę, choć ich sekcji nie ma na
    /// wierzchu (Filtry z korzenia Przepisów) — wiersz na kategorię, push do
    /// jej aspektów. Bez tego „Wyczyść” zdejmowałby coś, czego nie widać.
    private var categoryFiltersSection: some View {
        let categories = otherFilteredCategories
        return RecipeFilterSection(title: "Filtry kategorii") {
            RecipeFilterPickerGroup {
                ForEach(Array(categories.enumerated()), id: \.element) { offset, category in
                    if offset > 0 {
                        RecipeFilterPickerDivider()
                    }
                    RecipeFilterPickerRow(
                        icon: RecipesConstants.icon(for: category),
                        title: RecipesConstants.displayName(for: category),
                        placeholder: "",
                        chips: Self.facetChips(of: filters.categoryFilters[category], in: category),
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

    // MARK: - Czas, trudność, kalorie

    private static let timeItems: [RecipeFilterMenuTile<Int?>.Item] =
        [.init(value: nil, title: "Dowolny")]
        + RecipeFilterOptions.prepTimeChoices.map { minutes in
            RecipeFilterMenuTile<Int?>.Item(value: minutes, title: "do \(minutes) min")
        }

    private static let difficultyItems: [RecipeFilterMenuTile<Difficulty?>.Item] = [
        .init(value: nil, title: "Dowolna"),
        .init(value: .easy, title: "Łatwa"),
        .init(value: .medium, title: "Średnia"),
        .init(value: .hard, title: "Trudna")
    ]

    /// Czas i trudność w jednym rzędzie — dwie krótkie decyzje, które
    /// osobno zajmowały dwie pełne sekcje arkusza.
    private var timeAndDifficultySection: some View {
        RecipeFilterSection(title: "Czas i trudność") {
            HStack(spacing: 8) {
                RecipeFilterMenuTile(
                    title: "Czas",
                    icon: "clock",
                    items: Self.timeItems,
                    selection: $filters.maxPrepTimeMinutes
                )
                RecipeFilterMenuTile(
                    title: "Trudność",
                    icon: "chart.bar",
                    items: Self.difficultyItems,
                    selection: $filters.difficulty
                )
            }
        }
    }

    /// Limit stoi dużą liczbą na górze karty wykresu — etykieta sekcji go
    /// nie powtarza.
    private var caloriesSection: some View {
        RecipeFilterSection(title: "Kalorie na porcję") {
            RecipeFilterKcalChart(
                value: $filters.maxCaloriesPerServing,
                histogram: index.kcalHistogram(filters, fit: fit),
                goalZone: goalZone
            )
        }
    }

    // MARK: - Dieta

    private var dietSection: some View {
        let locked = lockedDiets
        return RecipeFilterSection(title: "Dieta") {
            VStack(alignment: .leading, spacing: 10) {
                RecipeFilterTileGrid(items: RecipeDietFilter.allCases) { diet in
                    let isLocked = locked.contains(diet)
                    RecipeFilterOptionTile(
                        title: diet.title,
                        count: isLocked ? nil : index.count(adding: diet, to: filters, fit: fit),
                        mark: isLocked ? .locked : (filters.diets.contains(diet) ? .on : .off),
                        cover: covers.diets[diet],
                        icon: diet.tileIcon
                    ) {
                        withAnimation(.smooth(duration: 0.18)) { filters.toggle(diet: diet) }
                    }
                }

                if !locked.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.sc(size: 10, weight: .bold))
                        Text("Z Twojego profilu · zmienisz w Ustawieniach")
                            .font(.sc(size: 12))
                    }
                    .foregroundStyle(Color.scFaint(scheme))
                    .padding(.horizontal, 6)
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Więcej filtrów

    /// Podstrony arkusza (push w jego stosie): grupy „Więcej filtrów”,
    /// wykluczanie składników i filtry kategorii spoza zakresu. Trzy siatki
    /// kafelków jedna pod drugą — cechy, kuchnie, okazje i pory roku, ponad 25
    /// kafelków — robiły z arkusza nieczytelną ścianę (Rafał, 28.09.2026).
    enum Pane: Hashable {
        case traits, cuisines, moments, exclude
        case category(RecipesCategory)
    }

    private var moreSection: some View {
        let traits = RecipeTraitFilter.allCases.filter { filters.traits.contains($0) }
        let cuisines = RecipeCuisine.allCases.filter { filters.cuisines.contains($0) }
        let moments = RecipeMoment.allCases.filter { filters.moments.contains($0) }

        return RecipeFilterSection(title: "Więcej filtrów") {
            RecipeFilterPickerGroup {
                RecipeFilterPickerRow(
                    icon: "sparkles",
                    title: "Cechy",
                    placeholder: RecipeFilterPickerRow.placeholder(
                        from: RecipeFilterPickerRow.sentence(RecipeTraitFilter.visibleCases.map { $0.title.lowercased() })
                    ),
                    chips: traits.map { RecipeFilterChipLine.Chip(id: $0.rawValue, title: $0.title) },
                    accent: SCPalette.indigo
                ) { openPane = .traits }

                RecipeFilterPickerDivider()

                RecipeFilterPickerRow(
                    icon: "globe.europe.africa.fill",
                    title: "Kuchnia",
                    placeholder: RecipeFilterPickerRow.placeholder(
                        from: RecipeFilterPickerRow.sentence(RecipeCuisine.allCases.map { $0.title.lowercased() })
                    ),
                    chips: cuisines.map { RecipeFilterChipLine.Chip(id: $0.rawValue, title: $0.title) },
                    accent: SCPalette.sage
                ) { openPane = .cuisines }

                RecipeFilterPickerDivider()

                RecipeFilterPickerRow(
                    icon: "calendar",
                    title: "Okazje i sezon",
                    placeholder: RecipeFilterPickerRow.placeholder(
                        from: RecipeFilterPickerRow.sentence(RecipeMoment.allCases.map(\.summaryTitle))
                    ),
                    chips: moments.map { RecipeFilterChipLine.Chip(id: $0.rawValue, title: $0.title) },
                    accent: SCPalette.rose
                ) { openPane = .moments }
            }
        }
    }

    // MARK: - Wykluczanie

    /// Jeden kafelek zamiast pola szukania i całej listy działów — ta lista
    /// rozciągała arkusz na kilka ekranów przewijania. Szukanie, działy
    /// i „Cofnij” żyją na podstronie (`RecipeExcludePage`).
    private var excludeSection: some View {
        let hidden = index.hiddenCount(by: filters.excludedIngredients, fit: fit)
        let own = filters.excludedIngredients
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        let chips = profileChips + own.map { RecipeFilterChipLine.Chip(id: $0.id, title: $0.chipTitle) }

        return RecipeFilterSection(title: "Wyklucz składniki") {
            if hidden > 0 {
                hiddenLabel(hidden)
                    .transition(.opacity)
            }
        } content: {
            Button {
                openPane = .exclude
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "nosign")
                                .font(.sc(size: 14, weight: .bold))
                                .foregroundStyle(SCPalette.terracotta)
                        )

                    VStack(alignment: .leading, spacing: 0) {
                        Text(excludeTitle(own: own.count, profile: profileChips.count))
                            .font(.sc(size: 15, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                            .contentTransition(.interpolate)

                        if chips.isEmpty {
                            Text("Np. papryka, grzyby, kolendra")
                                .font(.sc(size: 12.5))
                                .foregroundStyle(Color.scMuted(scheme))
                                .padding(.top, 2)
                        } else {
                            RecipeFilterChipLine(chips: chips)
                                .padding(.top, 7)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !own.isEmpty {
                        RecipeFilterCountBadge(count: own.count)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }

                    Image(systemName: "chevron.right")
                        .font(.sc(size: 12, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.scTileBg(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PlanPressStyle(scale: 0.985))
            .accessibilityLabel("Wyklucz składniki")
            .accessibilityValue(chips.isEmpty ? "nic" : chips.map(\.title).joined(separator: ", "))
        }
        .animation(.smooth(duration: 0.22), value: own)
        .animation(.smooth(duration: 0.2), value: hidden)
    }

    private func excludeTitle(own: Int, profile: Int) -> String {
        // Liczba stoi w plakietce obok — tytuł jej nie powtarza.
        if own > 0 { return "Wykluczone składniki" }
        return profile > 0 ? "Z Twojego profilu" : "Nic nie wykluczasz"
    }

    private func hiddenLabel(_ count: Int) -> some View {
        (Text("ukrywa ")
            + Text(verbatim: "\(count)").fontWeight(.semibold).foregroundStyle(Color.scLabel(scheme))
            + Text(verbatim: " \(PolishPlural.recipesNoun(count))"))
            .monospacedDigit()
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
                        accent: scope.map(RecipeScopeTabs.accent(for:)) ?? SCPalette.terracotta
                    )
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(footerAccessibilityLabel(count: count))

            RecipeFilterFooterButton(title: "Gotowe", trailingIcon: nil) { dismiss() }
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
                        accessibilityDetail: "kuchnia \(cuisine.title.lowercased())"
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
        case .category(let category):
            categoryPage(category)
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
