import SwiftUI

// Arkusz „Filtry” otwierany z przycisku obok wyszukiwarki na Przepisach.
// Źródło: Claude Design, „Scoffie - Przepisy v3 - Filtry.html”, sekcja
// „Filtry · wersja finalna” (`FFSheet` w `components/filtry-final.jsx`).
//
// Od góry: zasięg („Wszystkie przepisy — działają w każdej kategorii”),
// dopasowanie do profilu, czas, kalorie (linijka z igłą), dieta i cechy
// (kafelki 2 × 3 z liczbą przepisów), trudność, wykluczanie składników
// (szukanie + działy sklepu). Na dole pływa szklana kapsuła: ile zostaje
// łącznie i w każdej kategorii, i „Pokaż”.
//
// Zmiany idą na kopię roboczą (`draft`, `fitDraft`) — dopiero „Pokaż”
// zapisuje je do Przepisów. Zamknięcie arkusza gestem nie zostawia listy
// w połowie przefiltrowanej, a liczby w kapsule pokazują na żywo, co
// zobaczy się po „Pokaż”. Arkusze kategorii i szukania piszą do tej samej
// kopii roboczej.
struct RecipeFilterSheet: View {
    @Binding var filters: RecipeFilterOptions
    /// Przełącznik „Dopasowane do Ciebie” — ten sam, co różdżka na Przepisach.
    @Binding var isPersonalizationEnabled: Bool

    /// Profil z Ustawień (dieta, alergeny, cel). `isEnabled` nie ma tu
    /// znaczenia — o nim decyduje `fitDraft`.
    let personalization: RecipePersonalization

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var draft: RecipeFilterOptions
    @State private var fitDraft: Bool
    @State private var indexBox: IndexBox
    @State private var isHeaderCompact = false
    @State private var openDepartment: IngredientDepartment?
    @State private var isSearchPresented = false

    /// Przepisy po wyszukiwarce Przepisów, ale PRZED dopasowaniem i filtrami.
    private let recipes: [Recipe]

    init(
        filters: Binding<RecipeFilterOptions>,
        isPersonalizationEnabled: Binding<Bool>,
        recipes: [Recipe],
        personalization: RecipePersonalization
    ) {
        self._filters = filters
        self._isPersonalizationEnabled = isPersonalizationEnabled
        self.recipes = recipes
        self.personalization = personalization
        self._draft = State(initialValue: filters.wrappedValue)
        self._fitDraft = State(initialValue: isPersonalizationEnabled.wrappedValue)
        self._indexBox = State(initialValue: IndexBox())
    }

    /// Indeks liczony leniwie, raz na otwarcie arkusza. Nie w `init`: ten
    /// odpala się przy KAŻDYM przerysowaniu Przepisów pod arkuszem, a
    /// `State(initialValue:)` i tak wyrzuca wszystko poza pierwszą wartością —
    /// pięćset przepisów liczyłoby się na darmo.
    private var index: RecipeFilterIndex {
        if let index = indexBox.index { return index }
        let index = RecipeFilterIndex(recipes: recipes, personalization: personalization)
        indexBox.index = index
        return index
    }

    // MARK: - Stan pochodny

    private var resultCount: Int { index.count(draft, fit: fitDraft) }

    private var lockedDiets: Set<RecipeDietFilter> {
        fitDraft ? RecipeDietFilter.lockedByProfile(personalization) : []
    }

    /// Pole celu na linijce kalorii: od śniadania (25 % dnia) do obiadu
    /// (40 %) — te same udziały, którymi cel porządkuje katalog.
    private var goalZone: ClosedRange<Int>? {
        guard fitDraft, personalization.hasAnyPreference else { return nil }
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
        guard fitDraft else { return [] }
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

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    scopeRow
                        .padding(.top, 20)
                    fitRow
                        .padding(.top, 14)
                    timeSection
                    caloriesSection
                    dietSection
                    traitsSection
                    difficultySection
                    excludeSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            // Bool, nie przesunięcie: stan zmienia się raz przy przekroczeniu
            // progu, a nie w każdej klatce przewijania.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 52
            } action: { _, isPast in
                withAnimation(.easeInOut(duration: 0.2)) { isHeaderCompact = isPast }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }

            compactHeader
        }
        .animation(.smooth(duration: 0.22), value: draft.isActive)
        .sensoryFeedback(.selection, trigger: draft.diets)
        .sensoryFeedback(.selection, trigger: draft.traits)
        .sensoryFeedback(.impact(weight: .light), trigger: fitDraft)
        .sheet(item: $openDepartment) { department in
            RecipeExcludeCategorySheet(
                department: department,
                index: index,
                filters: $draft,
                fit: fitDraft
            )
            .presentationDetents([.large])
            .dashboardLiquidSheet()
        }
        .sheet(isPresented: $isSearchPresented) {
            RecipeExcludeSearchSheet(
                index: index,
                filters: $draft,
                fit: fitDraft,
                profileChips: profileChips
            )
            .presentationDetents([.large])
            .dashboardLiquidSheet()
        }
    }

    // MARK: - Nagłówek

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PRZEPISY")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(SCPalette.terracotta)

                Text("Filtry")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.scLabel(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if draft.isActive {
                RecipeFilterClearButton(action: clearAll)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            SCSheetCloseButton { dismiss() }
        }
    }

    /// Po przewinięciu: sam tytuł na środku, „Wyczyść” i krzyżyk po prawej —
    /// żeby zamknąć albo wyczyścić, nie trzeba wracać na górę.
    private var compactHeader: some View {
        ZStack {
            Text("Filtry")
                .font(.system(size: 16, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if draft.isActive {
                    RecipeFilterClearButton(compact: true, action: clearAll)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                SCSheetCloseButton { dismiss() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            SCPageBackground(scheme: scheme)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        }
        .opacity(isHeaderCompact ? 1 : 0)
        .allowsHitTesting(isHeaderCompact)
        .accessibilityHidden(!isHeaderCompact)
    }

    // MARK: - Zasięg i dopasowanie

    private var scopeRow: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Wszystkie przepisy")
                    .font(.system(size: 16.5, weight: .bold))
                    .tracking(-0.35)
                    .foregroundStyle(Color.scLabel(scheme))
                Text("Działają w każdej kategorii")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var fitRow: some View {
        let canFit = personalization.hasAnyPreference
        let isOn = fitDraft && canFit

        return Button {
            withAnimation(.smooth(duration: 0.22)) { fitDraft.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SCPalette.sage)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Dopasowane do Ciebie")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                    Text(canFit ? "Na podstawie Twojego profilu" : "Ustaw dietę i cel w Ustawieniach")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RecipeFilterToggleIndicator(isOn: isOn, accent: SCPalette.sage)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? SCPalette.sage.opacity(scheme == .dark ? 0.10 : 0.08) : Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isOn ? SCPalette.sage.opacity(0.26) : Color.scTileStroke(scheme), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .disabled(!canFit)
        .opacity(canFit ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dopasowane do Ciebie")
        .accessibilityValue(isOn ? "włączone" : "wyłączone")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Czas, kalorie, trudność

    private static let timeItems: [RecipeFilterSegmented<Int?>.Item] =
        [.init(value: nil, title: "Dowolny")]
        + RecipeFilterOptions.prepTimeChoices.map { minutes in
            RecipeFilterSegmented<Int?>.Item(value: minutes, title: "\(minutes) min")
        }

    private static let difficultyItems: [RecipeFilterSegmented<Difficulty?>.Item] = [
        .init(value: nil, title: "Dowolna"),
        .init(value: .easy, title: "Łatwa"),
        .init(value: .medium, title: "Średnia"),
        .init(value: .hard, title: "Trudna")
    ]

    private var timeSection: some View {
        RecipeFilterSection(title: "Czas przygotowania") {
            if let minutes = draft.maxPrepTimeMinutes {
                accentValue("do \(minutes) min", number: minutes)
            }
        } content: {
            RecipeFilterSegmented(
                items: Self.timeItems,
                selection: $draft.maxPrepTimeMinutes,
                accessibilityLabel: "Czas przygotowania"
            )
        }
    }

    private var caloriesSection: some View {
        RecipeFilterSection(title: "Kalorie na porcję") {
            if let kcal = draft.maxCaloriesPerServing {
                accentValue("do \(kcal) kcal", number: kcal)
            } else {
                Text("bez limitu")
            }
        } content: {
            RecipeFilterKcalRuler(value: $draft.maxCaloriesPerServing, goalZone: goalZone)
                .padding(.top, 2)
        }
    }

    private var difficultySection: some View {
        RecipeFilterSection(title: "Trudność") {
            RecipeFilterSegmented(
                items: Self.difficultyItems,
                selection: $draft.difficulty,
                accessibilityLabel: "Trudność"
            )
        }
    }

    private func accentValue(_ text: String, number: Int) -> some View {
        Text(verbatim: text)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(SCPalette.terracotta)
            .contentTransition(.numericText(value: Double(number)))
            .animation(.easeOut(duration: 0.2), value: number)
    }

    // MARK: - Dieta i cechy

    private let gridColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private var dietSection: some View {
        let locked = lockedDiets
        return RecipeFilterSection(title: "Dieta") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: gridColumns, spacing: 8) {
                    ForEach(RecipeDietFilter.allCases) { diet in
                        let isLocked = locked.contains(diet)
                        RecipeFilterOptionTile(
                            title: diet.title,
                            count: isLocked ? nil : index.count(adding: diet, to: draft, fit: fitDraft),
                            mark: isLocked ? .locked : (draft.diets.contains(diet) ? .on : .off)
                        ) {
                            withAnimation(.smooth(duration: 0.18)) { draft.toggle(diet: diet) }
                        }
                    }
                }

                if !locked.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Z Twojego profilu · zmienisz w Ustawieniach")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.scFaint(scheme))
                    .padding(.horizontal, 6)
                    .transition(.opacity)
                }
            }
        }
    }

    private var traitsSection: some View {
        RecipeFilterSection(title: "Cechy") {
            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(RecipeTraitFilter.allCases) { trait in
                    RecipeFilterOptionTile(
                        title: trait.title,
                        count: index.count(adding: trait, to: draft, fit: fitDraft),
                        mark: draft.traits.contains(trait) ? .on : .off,
                        accessibilityDetail: trait.accessibilityDetail
                    ) {
                        withAnimation(.smooth(duration: 0.18)) { draft.toggle(trait: trait) }
                    }
                }
            }
        }
    }

    // MARK: - Wykluczanie

    private var excludeSection: some View {
        let hidden = index.hiddenCount(by: draft.excludedIngredients, fit: fitDraft)
        return RecipeFilterSection(title: "Wyklucz składniki") {
            if hidden > 0 {
                hiddenLabel(hidden)
                    .transition(.opacity)
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                RecipeFilterSearchField(prompt: "Szukaj składnika, np. papryka") {
                    isSearchPresented = true
                }

                Text("Przeglądaj kategorie")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .padding(.horizontal, 6)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                departmentsCard
            }
        }
        .animation(.smooth(duration: 0.2), value: hidden)
    }

    private func hiddenLabel(_ count: Int) -> some View {
        (Text("ukrywa ")
            + Text(verbatim: "\(count)").fontWeight(.semibold).foregroundStyle(Color.scLabel(scheme))
            + Text(verbatim: " \(PolishPlural.recipesNoun(count))"))
            .monospacedDigit()
    }

    private var departmentsCard: some View {
        let chips = profileChips
        let departments = index.departments

        return VStack(spacing: 0) {
            if !chips.isEmpty {
                profileRow(chips)
            }

            ForEach(Array(departments.enumerated()), id: \.element.id) { offset, department in
                departmentRow(department, showsRule: offset > 0 || !chips.isEmpty)
            }

            if departments.isEmpty {
                Text("Przepisy nie mają jeszcze listy składników.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Alergeny i dieta z profilu, które nie mają kafelka w Diecie. Nie da
    /// się ich tu zdjąć — robi to przełącznik „Dopasowane do Ciebie”.
    private func profileRow(_ chips: [RecipeFilterChipLine.Chip]) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Z Twojego profilu")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.25)
                    .foregroundStyle(Color.scLabel(scheme))
                RecipeFilterChipLine(chips: chips)
                    .padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RecipeFilterCountBadge(count: chips.count, locked: true)
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Z Twojego profilu: " + chips.map(\.title).joined(separator: ", "))
    }

    private func departmentRow(_ department: IngredientDepartment, showsRule: Bool) -> some View {
        let excluded = department.excluded(in: draft.excludedIngredients)
        let chips = excluded.map { RecipeFilterChipLine.Chip(id: $0.id, title: $0.chipTitle) }

        return Button {
            openDepartment = department
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(department.name)
                        .font(.system(size: 15, weight: .medium))
                        .tracking(-0.25)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    if chips.isEmpty {
                        Text(PolishPlural.ingredients(department.ingredientCount))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.scFaint(scheme))
                            .padding(.top, 3)
                            .transition(.opacity)
                    } else {
                        RecipeFilterChipLine(chips: chips)
                            .padding(.top, 7)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !chips.isEmpty {
                    RecipeFilterCountBadge(count: chips.count)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.vertical, 12)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .overlay(alignment: .top) {
            if showsRule {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
        .animation(.smooth(duration: 0.22), value: chips.map(\.id))
        .accessibilityLabel(department.name)
        .accessibilityValue(chips.isEmpty
            ? PolishPlural.ingredients(department.ingredientCount)
            : "wykluczone: " + chips.map(\.title).joined(separator: ", "))
    }

    // MARK: - Stopka

    private var footer: some View {
        let count = resultCount
        let byCategory = index.countsByCategory(draft, fit: fitDraft)

        return RecipeFilterFloatingBar {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(count)))

                    Text(verbatim: "z \(index.total) \(index.total == 1 ? "przepisu" : "przepisów")")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }

                RecipeFilterCategorySplit(counts: byCategory, totals: index.totalsByCategory)
                    .padding(.top, 7)
            }
            .animation(.smooth(duration: 0.3), value: count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(footerAccessibilityLabel(count: count, byCategory: byCategory))
        } trailing: {
            RecipeFilterFooterButton(title: "Pokaż", isEnabled: count > 0, action: apply)
        }
    }

    private func footerAccessibilityLabel(count: Int, byCategory: [RecipesCategory: Int]) -> String {
        let split = RecipesCategory.catalogSections
            .filter { (index.totalsByCategory[$0] ?? 0) > 0 }
            .map { "\(RecipesConstants.displayName(for: $0)) \(byCategory[$0] ?? 0)" }
            .joined(separator: ", ")
        return "Zostaje \(PolishPlural.recipes(count)) z \(index.total). \(split)"
    }

    // MARK: - Akcje

    private func clearAll() {
        withAnimation(.smooth(duration: 0.25)) { draft.reset() }
    }

    private func apply() {
        filters = draft
        isPersonalizationEnabled = fitDraft
        dismiss()
    }

    /// Pudełko na indeks — klasa, żeby zapamiętanie wyniku w trakcie `body`
    /// nie było zmianą stanu, która przerysowuje widok.
    private final class IndexBox {
        var index: RecipeFilterIndex?
    }
}

// MARK: - Ile zostaje w każdej kategorii

/// Cztery paski pod liczbą w kapsule — szerokość paska to wielkość kategorii
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
                            .font(.system(size: 11, weight: .bold))
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
    }
}

// MARK: - Wspólne z arkuszem dopasowania

/// Zawijający rząd chipów — ten sam `Layout` co chmura alergenów.
struct RecipeFilterChipFlow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        AllergenChipFlow(spacing: spacing) {
            content()
        }
    }
}

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
