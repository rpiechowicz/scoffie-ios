import SwiftUI

// Arkusz „Filtry” otwierany z przycisku obok wyszukiwarki na Przepisach.
// Źródło: Claude Design, „Scoffie - Przepisy v3 - Filtry.html”, sekcja
// „Filtry · wersja finalna” (`FFSheet` w `components/filtry-final.jsx`).
//
// Nagłówek stoi przypięty nad przewijaną treścią (jak w każdym arkuszu,
// `scScrollEdgeFade`). Pod nim: zasięg („Wszystkie przepisy — działają
// w każdej kategorii”), dopasowanie do profilu, czas i trudność, kalorie
// (wykres rozkładu, który sam jest suwakiem), dieta i cechy (kafelki 2 × 3
// ze zdjęciem dania i liczbą przepisów), wykluczanie składników (osobny
// arkusz). Na dole wspólna stopka: ile zostaje łącznie i w każdej kategorii,
// i „Pokaż”.
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
    @State private var isExcludePresented = false

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

    /// Zdjęcia kafelków Diety i Cech — tak samo leniwie i raz na otwarcie.
    /// Dania ukryte przez profil (np. z alergenem z Ustawień) biorą się
    /// dopiero, gdy nic innego nie pasuje — niezależnie od przełącznika
    /// „Dopasowane do Ciebie”, żeby zdjęcie nie zmieniało się z nim.
    private var covers: RecipeFilterCovers {
        if let covers = indexBox.covers { return covers }
        let entries = index.entries
        let covers = RecipeFilterCovers(recipes: recipes) { entries[$0].hiddenByProfile }
        indexBox.covers = covers
        return covers
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
                        fitRow
                            .padding(.top, 6)
                        timeAndDifficultySection
                        caloriesSection
                        dietSection
                        traitsSection
                        excludeSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .containerRelativeFrame(.horizontal)
                }
                .scrollIndicators(.hidden)
                // Treść gaśnie, gdy wjeżdża pod nagłówek — wspólny „cień w dół”.
                .scScrollEdgeFade()
                // Wspólna stopka arkuszy (`scSheetFooter`): kryjąca płyta pod
                // liczbami i „Pokaż”, przewijane sekcje giną w przejściu nad nią.
                .scSheetFooter { footer }
            }
        }
        .animation(.smooth(duration: 0.22), value: draft.activeCount > 0)
        .sensoryFeedback(.selection, trigger: draft.diets)
        .sensoryFeedback(.selection, trigger: draft.traits)
        .sensoryFeedback(.impact(weight: .light), trigger: fitDraft)
        .sheet(isPresented: $isExcludePresented) {
            RecipeExcludeSheet(
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
        RecipeFilterHeader(
            icon: "slider.horizontal.3",
            eyebrow: "Przepisy",
            title: "Filtry",
            scope: "Działają we wszystkich kategoriach",
            activeSummary: activeSummary,
            canClear: draft.activeCount > 0,
            onClear: { clearAll() },
            onClose: { dismiss() }
        )
    }

    /// Co z tego arkusza zawęża teraz listę — „Aktywne: czas, kalorie, dieta”.
    private var activeSummary: String? {
        var parts: [String] = []
        if draft.maxPrepTimeMinutes != nil { parts.append("czas") }
        if draft.difficulty != nil { parts.append("trudność") }
        if draft.maxCaloriesPerServing != nil { parts.append("kalorie") }
        if !draft.diets.isEmpty { parts.append("dieta") }
        if !draft.traits.isEmpty { parts.append("cechy") }
        if !draft.excludedIngredients.isEmpty { parts.append("wykluczenia") }
        return parts.isEmpty ? nil : "Aktywne: " + parts.joined(separator: ", ")
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

    private var fitRow: some View {
        let canFit = personalization.hasAnyPreference
        let isOn = fitDraft && canFit
        let hidden = index.profileHiddenCount

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
                    Text(canFit ? profileSummary : "Ustaw dietę i cel w Ustawieniach")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if isOn, hidden > 0 {
                        (Text("ukrywa ")
                            + Text(verbatim: "\(hidden)").fontWeight(.semibold)
                            + Text(verbatim: " \(PolishPlural.recipesNoun(hidden))"))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(SCPalette.sage)
                            .transition(.opacity)
                    }
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
        .accessibilityValue(isOn ? "włączone, \(profileSummary)" : "wyłączone")
        .accessibilityAddTraits(.isButton)
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
                    selection: $draft.maxPrepTimeMinutes
                )
                RecipeFilterMenuTile(
                    title: "Trudność",
                    icon: "chart.bar",
                    items: Self.difficultyItems,
                    selection: $draft.difficulty
                )
            }
        }
    }

    /// Limit stoi dużą liczbą na górze karty wykresu — etykieta sekcji go
    /// nie powtarza.
    private var caloriesSection: some View {
        RecipeFilterSection(title: "Kalorie na porcję") {
            RecipeFilterKcalChart(
                value: $draft.maxCaloriesPerServing,
                histogram: index.kcalHistogram(draft, fit: fitDraft),
                goalZone: goalZone
            )
        }
    }

    // MARK: - Dieta i cechy

    private var dietSection: some View {
        let locked = lockedDiets
        return RecipeFilterSection(title: "Dieta") {
            VStack(alignment: .leading, spacing: 10) {
                RecipeFilterTileGrid(items: RecipeDietFilter.allCases) { diet in
                    let isLocked = locked.contains(diet)
                    RecipeFilterOptionTile(
                        title: diet.title,
                        count: isLocked ? nil : index.count(adding: diet, to: draft, fit: fitDraft),
                        mark: isLocked ? .locked : (draft.diets.contains(diet) ? .on : .off),
                        cover: covers.diets[diet],
                        icon: diet.tileIcon
                    ) {
                        withAnimation(.smooth(duration: 0.18)) { draft.toggle(diet: diet) }
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
            RecipeFilterTileGrid(items: RecipeTraitFilter.allCases) { trait in
                RecipeFilterOptionTile(
                    title: trait.title,
                    count: index.count(adding: trait, to: draft, fit: fitDraft),
                    mark: draft.traits.contains(trait) ? .on : .off,
                    cover: covers.traits[trait],
                    icon: trait.tileIcon,
                    accessibilityDetail: trait.accessibilityDetail
                ) {
                    withAnimation(.smooth(duration: 0.18)) { draft.toggle(trait: trait) }
                }
            }
        }
    }

    // MARK: - Wykluczanie

    /// Jeden kafelek zamiast pola szukania i całej listy działów — ta lista
    /// rozciągała arkusz na kilka ekranów przewijania. Szukanie, działy
    /// i „Cofnij” żyją w osobnym arkuszu (`RecipeExcludeSheet`).
    private var excludeSection: some View {
        let hidden = index.hiddenCount(by: draft.excludedIngredients, fit: fitDraft)
        let own = draft.excludedIngredients
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        let chips = profileChips + own.map { RecipeFilterChipLine.Chip(id: $0.id, title: $0.chipTitle) }

        return RecipeFilterSection(title: "Wyklucz składniki") {
            if hidden > 0 {
                hiddenLabel(hidden)
                    .transition(.opacity)
            }
        } content: {
            Button {
                isExcludePresented = true
            } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "nosign")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(SCPalette.terracotta)
                        )

                    VStack(alignment: .leading, spacing: 0) {
                        Text(excludeTitle(own: own.count, profile: profileChips.count))
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                            .contentTransition(.interpolate)

                        if chips.isEmpty {
                            Text("Np. papryka, grzyby, kolendra")
                                .font(.system(size: 12.5))
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
                        .font(.system(size: 12, weight: .bold))
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

    private var footer: some View {
        let count = resultCount
        let byCategory = index.countsByCategory(draft, fit: fitDraft)

        return HStack(spacing: 12) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.smooth(duration: 0.3), value: count)
            .animation(.smooth(duration: 0.3), value: byCategory)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(footerAccessibilityLabel(count: count, byCategory: byCategory))

            RecipeFilterFooterButton(title: "Pokaż", isEnabled: count > 0, action: apply)
        }
        .padding(.leading, 4)
    }

    private func footerAccessibilityLabel(count: Int, byCategory: [RecipesCategory: Int]) -> String {
        let split = RecipesCategory.catalogSections
            .filter { (index.totalsByCategory[$0] ?? 0) > 0 }
            .map { "\(RecipesConstants.displayName(for: $0)) \(byCategory[$0] ?? 0)" }
            .joined(separator: ", ")
        return "Zostaje \(PolishPlural.recipes(count)) z \(index.total). \(split)"
    }

    // MARK: - Akcje

    /// „Wyczyść” działa od razu — lista pod arkuszem jest czysta bez
    /// stuknięcia „Pokaż”. Czyści filtry wszystkich przepisów (to piętro);
    /// filtry kategorii zostają, mają własne „Wyczyść”.
    private func clearAll() {
        withAnimation(.smooth(duration: 0.25)) {
            draft.resetGlobal()
            filters = draft
        }
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
        var covers: RecipeFilterCovers?
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
        case .favourites:  return "heart.fill"
        case .thermomix:   return "cooktop.fill"
        }
    }
}
