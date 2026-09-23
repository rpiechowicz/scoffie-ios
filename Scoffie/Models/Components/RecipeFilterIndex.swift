import Foundation

/// Pula przepisów, na której pracuje arkusz „Filtry”, policzona raz przy
/// otwarciu: fakty o każdym przepisie i katalog składników pogrupowany po
/// działach sklepu.
///
/// Arkusz pokazuje kilkanaście liczb naraz — ile zostaje łącznie i w każdej
/// kategorii, ile zostanie po każdym kafelku, ile ukrywają wykluczenia, w ilu
/// przepisach jest każdy składnik — i przelicza je przy każdym stuknięciu.
/// Wszystkie idą przez `RecipeFilterOptions.matches(_:)`, więc liczba w stopce
/// jest dokładnie tą, którą pokaże lista po „Pokaż”.
struct RecipeFilterIndex {
    struct Entry {
        let facts: RecipeFilterFacts
        /// Czy przepis odpada przez dietę i alergeny z profilu — liczone raz,
        /// bo profil nie zmienia się, gdy arkusz jest otwarty (zmienia się
        /// tylko to, czy dopasowanie jest włączone).
        let hiddenByProfile: Bool
    }

    let entries: [Entry]
    let totalsByCategory: [RecipesCategory: Int]
    let departments: [IngredientDepartment]

    var total: Int { entries.count }

    /// Ile przepisów puli odpada przez dietę i alergeny z profilu — liczba
    /// pod przełącznikiem „Dopasowane do Ciebie”.
    var profileHiddenCount: Int { entries.reduce(into: 0) { if $1.hiddenByProfile { $0 += 1 } } }

    @MainActor
    init(recipes: [Recipe], personalization: RecipePersonalization) {
        var profile = personalization
        profile.isEnabled = true
        entries = recipes.map {
            Entry(facts: RecipeFilterFactsCache.facts(for: $0), hiddenByProfile: profile.excludes($0))
        }

        var totals: [RecipesCategory: Int] = [:]
        for entry in entries { totals[entry.facts.category, default: 0] += 1 }
        totalsByCategory = totals

        departments = IngredientDepartment.build(from: recipes)
    }

    // MARK: - Liczenie

    private func passes(_ entry: Entry, _ options: RecipeFilterOptions, fit: Bool) -> Bool {
        if fit && entry.hiddenByProfile { return false }
        return options.matches(entry.facts)
    }

    func count(_ options: RecipeFilterOptions, fit: Bool) -> Int {
        entries.reduce(into: 0) { total, entry in
            if passes(entry, options, fit: fit) { total += 1 }
        }
    }

    func countsByCategory(_ options: RecipeFilterOptions, fit: Bool) -> [RecipesCategory: Int] {
        entries.reduce(into: [:]) { counts, entry in
            if passes(entry, options, fit: fit) { counts[entry.facts.category, default: 0] += 1 }
        }
    }

    /// Ile zostanie po zaznaczeniu kafelka — liczba pod jego nazwą. Dla
    /// zaznaczonego to po prostu bieżący wynik.
    func count(adding diet: RecipeDietFilter, to options: RecipeFilterOptions, fit: Bool) -> Int {
        var next = options
        next.diets.insert(diet)
        return count(next, fit: fit)
    }

    func count(adding trait: RecipeTraitFilter, to options: RecipeFilterOptions, fit: Bool) -> Int {
        var next = options
        next.traits.insert(trait)
        return count(next, fit: fit)
    }

    /// Rozkład kalorii na porcję pod suwak: przedziały po 50 kcal od zera do
    /// `calorieScaleMax` i jeden ostatni na wszystko powyżej („1000+”).
    ///
    /// Liczony przy WSZYSTKICH pozostałych filtrach, ale bez samego limitu
    /// kalorii — słupki mówią, co zostanie po przesunięciu uchwytu, więc nie
    /// mogą znikać za nim. Przepisy bez policzonych makr nie mają słupka
    /// (i tak przechodzą przez limit, patrz `RecipeFilterOptions.matches`).
    func kcalHistogram(_ options: RecipeFilterOptions, fit: Bool) -> [Int] {
        var withoutLimit = options
        withoutLimit.maxCaloriesPerServing = nil
        let step = RecipeFilterOptions.calorieStep
        let overflow = RecipeFilterOptions.calorieScaleMax / step
        var buckets = Array(repeating: 0, count: overflow + 1)
        for entry in entries where entry.facts.kcalPerServing > 0 && passes(entry, withoutLimit, fit: fit) {
            // Przedział i obejmuje (i·50, (i+1)·50] — przepis za dokładnie
            // 500 kcal mieści się w limicie „do 500”, więc jest w słupku pod nim.
            let bucket = min((entry.facts.kcalPerServing - 1) / step, overflow)
            buckets[bucket] += 1
        }
        return buckets
    }

    /// Ile przepisów ukrywają same wykluczenia — niezależnie od reszty
    /// filtrów, żeby liczba przy „Wyklucz składniki” nie skakała, gdy ktoś
    /// przesuwa igłę kalorii.
    func hiddenCount(by exclusions: Set<IngredientExclusion>, fit: Bool) -> Int {
        guard !exclusions.isEmpty else { return 0 }
        return entries.reduce(into: 0) { total, entry in
            if fit && entry.hiddenByProfile { return }
            if !exclusions.isDisjoint(with: entry.facts.exclusionKeys) { total += 1 }
        }
    }

    // MARK: - Składniki

    /// Wszystkie wpisy (grupy i pojedyncze składniki) ze wszystkich działów.
    var allEntries: [IngredientEntry] { departments.flatMap(\.entries) }

    func department(named name: String) -> IngredientDepartment? {
        departments.first { $0.name == name }
    }

    /// Grupa, do której należy składnik (w jego dziale), jeśli ma rodzeństwo.
    func group(containing item: IngredientExclusion) -> IngredientGroup? {
        for department in departments {
            for entry in department.entries {
                if case .group(let group) = entry, group.members.contains(where: { $0.exclusion == item }) {
                    return group
                }
            }
        }
        return nil
    }
}

// MARK: - Katalog składników

struct IngredientItem: Identifiable, Hashable {
    let exclusion: IngredientExclusion
    let department: String
    /// W ilu przepisach puli występuje.
    let recipeCount: Int

    var id: String { exclusion.id }
    var title: String { exclusion.title }
}

struct IngredientGroup: Identifiable, Hashable {
    let exclusion: IngredientExclusion
    let department: String
    /// Rodzaje od najczęstszego.
    let members: [IngredientItem]
    /// W ilu przepisach jest którykolwiek z rodzajów.
    let recipeCount: Int

    var id: String { exclusion.id }
    var title: String { exclusion.title }
}

enum IngredientEntry: Identifiable, Hashable {
    case item(IngredientItem)
    case group(IngredientGroup)

    var id: String {
        switch self {
        case .item(let item):   return item.id
        case .group(let group): return group.id
        }
    }

    var exclusion: IngredientExclusion {
        switch self {
        case .item(let item):   return item.exclusion
        case .group(let group): return group.exclusion
        }
    }

    var recipeCount: Int {
        switch self {
        case .item(let item):   return item.recipeCount
        case .group(let group): return group.recipeCount
        }
    }

    var department: String {
        switch self {
        case .item(let item):   return item.department
        case .group(let group): return group.department
        }
    }
}

/// Dział sklepu z jego składnikami — wiersz „Przeglądaj kategorie”.
///
/// Działy są te same, co alejki listy zakupów (`RecipeIngredient.department`
/// z backendu) i stoją w tej samej kolejności obchodzenia sklepu. Telefon nie
/// klasyfikuje składników sam: przypisanie do działu przychodzi z serwera.
struct IngredientDepartment: Identifiable, Hashable {
    let name: String
    /// Grupy i pojedyncze składniki, od najczęściej występujących.
    let entries: [IngredientEntry]
    /// Liczba różnych składników (rodzaje w grupach liczą się osobno).
    let ingredientCount: Int

    var id: String { name }

    /// Wszystkie klucze, które da się w tym dziale wykluczyć.
    var exclusions: Set<IngredientExclusion> {
        var keys: Set<IngredientExclusion> = []
        for entry in entries {
            keys.insert(entry.exclusion)
            if case .group(let group) = entry {
                for member in group.members { keys.insert(member.exclusion) }
            }
        }
        return keys
    }

    /// Nazwa w miejscowniku do pola „Szukaj w …”. `nil` = dział bez sensownej
    /// odmiany („Inne”) — pole mówi wtedy po prostu „Szukaj składnika”.
    var searchPrompt: String {
        let locative: String? = switch name {
        case ProductConstants.Department.vegetables:   "warzywach"
        case ProductConstants.Department.fruits:       "owocach"
        case ProductConstants.Department.meat:         "mięsie"
        case ProductConstants.Department.fish:         "rybach"
        case ProductConstants.Department.dairy:        "nabiale"
        case ProductConstants.Department.bakery:       "pieczywie"
        case ProductConstants.Department.grains:       "zbożach i makaronach"
        case ProductConstants.Department.canned:       "konserwach"
        case ProductConstants.Department.beverages:    "napojach"
        case ProductConstants.Department.snacks:       "przekąskach i słodyczach"
        case ProductConstants.Department.frozen:       "mrożonkach"
        case ProductConstants.Department.spices:       "przyprawach i sosach"
        case ProductConstants.Department.oils:         "olejach i tłuszczach"
        case ProductConstants.Department.alcohols:     "alkoholach"
        case ProductConstants.Department.bakerySweets: "cukierni"
        default:                                       nil
        }
        return locative.map { "Szukaj w \($0)" } ?? "Szukaj składnika"
    }

    @MainActor
    static func build(from recipes: [Recipe]) -> [IngredientDepartment] {
        // nazwa → (dział, ile przepisów); przepis liczy się raz, nawet gdy
        // ma ten sam składnik w dwóch wierszach (np. sól do wody i do sosu).
        var itemCounts: [String: Int] = [:]
        var itemDepartment: [String: String] = [:]
        var groupCounts: [IngredientExclusion: Int] = [:]

        for recipe in recipes {
            var seenItems: Set<String> = []
            var seenGroups: Set<IngredientExclusion> = []
            for ingredient in recipe.ingredients {
                let name = IngredientExclusion.normalizedName(ingredient.name)
                guard !name.isEmpty else { continue }
                let department = IngredientExclusion.normalizedDepartment(ingredient.department)
                if seenItems.insert(name).inserted {
                    itemCounts[name, default: 0] += 1
                    if itemDepartment[name] == nil { itemDepartment[name] = department }
                }
                if let stem = IngredientExclusion.groupStem(ofNormalized: name) {
                    let group = IngredientExclusion.group(stem: stem, department: department)
                    if seenGroups.insert(group).inserted { groupCounts[group, default: 0] += 1 }
                }
            }
        }

        // Składniki per dział, z podziałem na rdzenie.
        var byDepartment: [String: [IngredientItem]] = [:]
        for (name, count) in itemCounts {
            let department = itemDepartment[name] ?? ProductConstants.Department.other
            byDepartment[department, default: []].append(
                IngredientItem(exclusion: .item(name), department: department, recipeCount: count)
            )
        }

        return byDepartment
            .map { pair -> IngredientDepartment in
                let name = pair.key
                let items = pair.value
                var stems: [String: [IngredientItem]] = [:]
                var singles: [IngredientItem] = []
                for item in items {
                    if let stem = IngredientExclusion.groupStem(ofNormalized: item.exclusion.name) {
                        stems[stem, default: []].append(item)
                    } else {
                        singles.append(item)
                    }
                }

                var entries: [IngredientEntry] = singles.map { IngredientEntry.item($0) }
                for (stem, members) in stems {
                    // Grupa ma sens dopiero przy dwóch rodzajach — samotna
                    // „cebula” to zwykły składnik, nie „wszystkie cebule”.
                    guard members.count >= 2 else {
                        entries.append(contentsOf: members.map { IngredientEntry.item($0) })
                        continue
                    }
                    let key = IngredientExclusion.group(stem: stem, department: name)
                    entries.append(.group(IngredientGroup(
                        exclusion: key,
                        department: name,
                        members: members.sorted(by: isMoreCommonItem),
                        recipeCount: groupCounts[key] ?? members.map(\.recipeCount).max() ?? 0
                    )))
                }

                return IngredientDepartment(
                    name: name,
                    entries: entries.sorted(by: isMoreCommonEntry),
                    ingredientCount: items.count
                )
            }
            .sorted { ProductConstants.isDepartment($0.name, orderedBefore: $1.name) }
    }

    private static func isMoreCommonItem(_ lhs: IngredientItem, _ rhs: IngredientItem) -> Bool {
        if lhs.recipeCount != rhs.recipeCount { return lhs.recipeCount > rhs.recipeCount }
        return lhs.title.localizedCompare(rhs.title) == .orderedAscending
    }

    private static func isMoreCommonEntry(_ lhs: IngredientEntry, _ rhs: IngredientEntry) -> Bool {
        if lhs.recipeCount != rhs.recipeCount { return lhs.recipeCount > rhs.recipeCount }
        return lhs.exclusion.title.localizedCompare(rhs.exclusion.title) == .orderedAscending
    }
}

// MARK: - Szukanie

enum IngredientSearch {
    /// Pole wyszukiwania i nazwy porównują się bez polskich znaków i wielkości
    /// liter — „losos” ma znaleźć łososia.
    static func fold(_ text: String) -> String {
        RecipeDietClassifier.normalize(text)
    }

    /// Trafienie: jak dobrze nazwa pasuje (0 = od początku, 1 = od początku
    /// wyrazu, 2 = w środku) i gdzie w nazwie (w znakach) zaczyna się
    /// dopasowanie — do pogrubienia.
    struct Match {
        let rank: Int
        let offset: Int
        let length: Int
    }

    static func match(_ name: String, query foldedQuery: String) -> Match? {
        guard !foldedQuery.isEmpty else { return nil }
        let folded = fold(name)
        guard let range = folded.range(of: foldedQuery) else { return nil }
        let offset = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let rank: Int
        if offset == 0 {
            rank = 0
        } else if folded[folded.index(before: range.lowerBound)] == " " {
            rank = 1
        } else {
            rank = 2
        }
        // `normalize` zamienia znak na znak (ą → a, interpunkcja → spacja),
        // więc przesunięcie w złożonej nazwie jest tym samym przesunięciem
        // w oryginale.
        return Match(rank: rank, offset: offset, length: foldedQuery.count)
    }
}

// MARK: - Wykluczenia w dziale

extension IngredientDepartment {
    /// Wykluczenia tego działu w kolejności działu (od najczęstszych): cała
    /// grupa jako jeden wpis, a pojedynczo wykluczone rodzaje — każdy osobno.
    func excluded(in set: Set<IngredientExclusion>) -> [IngredientExclusion] {
        guard !set.isEmpty else { return [] }
        var result: [IngredientExclusion] = []
        for entry in entries {
            switch entry {
            case .item(let item):
                if set.contains(item.exclusion) { result.append(item.exclusion) }
            case .group(let group):
                if set.contains(group.exclusion) {
                    result.append(group.exclusion)
                } else {
                    result.append(contentsOf: group.members.map(\.exclusion).filter { set.contains($0) })
                }
            }
        }
        return result
    }

    /// Składnik albo grupa po kluczu — do wiersza „Wykluczone”.
    func lookup(_ exclusion: IngredientExclusion) -> (item: IngredientItem?, group: IngredientGroup?, parent: IngredientGroup?) {
        for entry in entries {
            switch entry {
            case .item(let item):
                if item.exclusion == exclusion { return (item, nil, nil) }
            case .group(let group):
                if group.exclusion == exclusion { return (nil, group, nil) }
                if let member = group.members.first(where: { $0.exclusion == exclusion }) {
                    return (member, nil, group)
                }
            }
        }
        return (nil, nil, nil)
    }
}

// MARK: - Wyniki szukania

/// Wiersz wyników: składnik (z grupą, do której należy) albo grupa.
struct IngredientSearchResult: Identifiable {
    enum Kind {
        case item(IngredientItem, parent: IngredientGroup?)
        case group(IngredientGroup)
    }

    let kind: Kind
    let match: IngredientSearch.Match?

    var id: String {
        switch kind {
        case .item(let item, _): return item.id
        case .group(let group):  return group.id
        }
    }
}

extension IngredientSearch {
    /// Trafienia od najlepszego: najpierw nazwy zaczynające się od frazy,
    /// potem wyrazy od niej zaczynające się, na końcu środek nazwy; w każdej
    /// klasie od najczęstszych w przepisach. Grupa staje zaraz pod pierwszym
    /// trafionym rodzajem — „Papryka czerwona”, a pod nią „Papryka · grupa”.
    static func results(for query: String, in entries: [IngredientEntry], limit: Int = 40) -> [IngredientSearchResult] {
        let folded = fold(query).trimmingCharacters(in: .whitespaces)
        guard !folded.isEmpty else { return [] }

        var candidates: [(item: IngredientItem, parent: IngredientGroup?, match: Match)] = []
        for entry in entries {
            switch entry {
            case .item(let item):
                if let match = match(item.title, query: folded) { candidates.append((item, nil, match)) }
            case .group(let group):
                for member in group.members {
                    if let match = match(member.title, query: folded) { candidates.append((member, group, match)) }
                }
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.match.rank != rhs.match.rank { return lhs.match.rank < rhs.match.rank }
            if lhs.item.recipeCount != rhs.item.recipeCount { return lhs.item.recipeCount > rhs.item.recipeCount }
            return lhs.item.title.localizedCompare(rhs.item.title) == .orderedAscending
        }

        var results: [IngredientSearchResult] = []
        var shownGroups: Set<String> = []
        for candidate in candidates {
            results.append(IngredientSearchResult(kind: .item(candidate.item, parent: candidate.parent), match: candidate.match))
            if let parent = candidate.parent, shownGroups.insert(parent.id).inserted {
                results.append(IngredientSearchResult(kind: .group(parent), match: match(parent.title, query: folded)))
            }
            if results.count >= limit { break }
        }
        return results
    }
}
