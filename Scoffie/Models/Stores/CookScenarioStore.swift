import Foundation
import Observation
import SwiftUI

/// Scenariusze trybu Gotuj w pamięci telefonu (§7.7).
///
/// Przycisk „Gotuj” stoi tylko przy przepisie, którego scenariusz jest JUŻ
/// tutaj (§4.1) — dlatego paczki pobieramy z wyprzedzeniem: dania dziś
/// i jutro z planu (`prefetch`) oraz przy otwarciu szczegółów (`prepare`).
/// Po pobraniu tryb działa w całości offline: scenariusz, składniki przepisu
/// i duże zdjęcie leżą na dysku.
///
/// Telefon trzyma najwyżej jedną wersję na przepis (sesja ma własną kopię).
/// Nowsza wersja w katalogu (`Recipe.cookScenarioVersion`) = paczka do
/// wymiany; `nil` w katalogu = przycisku nie ma, nawet gdy paczka leży.
///
/// Błędy są ciche: brak scenariusza to brak przycisku, bez wyszarzonych
/// obietnic i bez toastu — ekran przepisu działa jak dotąd.
@Observable
final class CookScenarioStore {
    private let repository: RecipeRepository
    /// Konto i dom — paczki przepisów domu nie przechodzą do innego domu.
    private let ownerKey: String
    private(set) var packages: [UUID: CookPackage] = [:]
    private var inFlight: [UUID: Task<CookPackage?, Never>] = [:]
    private var isInvalidated = false

    init(repository: RecipeRepository, ownerKey: String) {
        self.repository = repository
        self.ownerKey = ownerKey
        Self.removeOtherOwners(keeping: ownerKey)
        self.packages = Self.loadAll(from: Self.directory(for: ownerKey))
    }

    /// Ocena gotowania na serwer. Błąd zostaje tutaj — ocena to sygnał dla
    /// panelu, a ekran zakończenia nie ma nic do poprawienia.
    @MainActor
    func sendFeedback(_ feedback: CookFeedback) async {
        guard !isInvalidated else { return }
        _ = try? await repository.sendCookFeedback(feedback)
    }

    /// Koniec sesji (wylogowanie, inny dom) — spóźnione odpowiedzi nic już
    /// nie zapisują.
    func invalidate() {
        isInvalidated = true
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
    }

    /// Paczka gotowa do gotowania albo `nil`. Paczka STARSZA niż wersja
    /// w katalogu się nie liczy (przepis zmienił się po napisaniu), nowsza —
    /// tak: serwer bywa o krok przed deltą katalogu.
    func package(for recipe: Recipe) -> CookPackage? {
        guard Self.isEligible(recipe),
              let version = recipe.cookScenarioVersion,
              let package = packages[recipe.id],
              package.version >= version else { return nil }
        return package
    }

    /// Czy pokazać „Gotuj”.
    func canCook(_ recipe: Recipe) -> Bool {
        package(for: recipe) != nil
    }

    /// Przepis, który w ogóle może mieć tryb Gotuj: z opublikowanym
    /// scenariuszem i nie z Cookidoo — tam gotuje Thermomix (D8, §13.6).
    static func isEligible(_ recipe: Recipe) -> Bool {
        recipe.cookScenarioVersion != nil && !recipe.isThermomix
    }

    /// Pobiera paczkę, jeśli jej nie ma albo jest nieaktualna. Kilka wywołań
    /// naraz dla tego samego przepisu czeka na jedno zapytanie.
    @MainActor
    @discardableResult
    func prepare(_ recipe: Recipe) async -> CookPackage? {
        guard !isInvalidated, Self.isEligible(recipe) else { return nil }
        if let ready = package(for: recipe) { return ready }
        if let running = inFlight[recipe.id] { return await running.value }

        let task = Task { @MainActor [weak self] () -> CookPackage? in
            guard let self else { return nil }
            return await self.download(recipe)
        }
        inFlight[recipe.id] = task
        let result = await task.value
        inFlight[recipe.id] = nil
        return result
    }

    /// Paczki dań, które za chwilę mogą trafić na patelnię (dziś i jutro
    /// z planu) — po kolei, żeby start aplikacji nie wysłał kilkunastu
    /// zapytań naraz.
    @MainActor
    func prefetch(_ recipes: [Recipe]) async {
        var seen = Set<UUID>()
        for recipe in recipes where seen.insert(recipe.id).inserted {
            guard !isInvalidated, !Task.isCancelled else { return }
            if package(for: recipe) == nil {
                await prepare(recipe)
            }
        }
    }

    @MainActor
    private func download(_ recipe: Recipe) async -> CookPackage? {
        do {
            guard let envelope = try await repository.fetchCookScenario(recipe.id) else {
                guard !isInvalidated else { return nil }
                drop(recipe.id)
                return nil
            }
            // Składniki ze SZCZEGÓŁU: tylko on niesie `ingredientId`, po którym
            // scenariusz wskazuje składniki kroków.
            let detail = try await repository.fetchRecipeById(recipe.id)
            guard !isInvalidated else { return nil }
            let package = CookPackage(
                recipeId: recipe.id,
                version: envelope.version,
                rulesVersion: envelope.rulesVersion,
                scenario: envelope.content,
                ingredients: detail.ingredients.compactMap(Self.info),
                savedAt: Date()
            )
            packages[recipe.id] = package
            save(package)
            // Duże zdjęcie do nagłówka trybu — w kuchni bywa bez sieci.
            if let url = detail.imageURL ?? recipe.imageURL {
                ImagePrefetcher.prefetch([url], variant: .large)
            }
            return package
        } catch {
            // Bez sieci zostaje to, co już leży (jeśli leży) — `package(for:)`
            // i tak sprawdza wersję.
            return package(for: recipe)
        }
    }

    private static func info(_ ingredient: Ingredient) -> CookIngredientInfo? {
        guard let ingredientId = ingredient.ingredientId, !ingredientId.isEmpty else { return nil }
        return CookIngredientInfo(
            ingredientId: ingredientId,
            name: ingredient.name,
            amount: ingredient.amount,
            unit: ingredient.unit == .other ? (ingredient.rawUnit ?? ingredient.unit.rawValue) : ingredient.unit.rawValue,
            department: ingredient.department,
            kitchenMeasure: ingredient.kitchenMeasure
        )
    }

    private func drop(_ recipeId: UUID) {
        packages[recipeId] = nil
        try? FileManager.default.removeItem(at: fileURL(recipeId))
    }

    // MARK: - Dysk

    /// Przepisy domu są prywatne, więc katalog paczek znika z wylogowaniem
    /// i wyjściem z domu (`SessionStore.clearRuntimeStores`).
    static func clearCache() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static var directory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cook-scenarios-v1", isDirectory: true)
    }

    /// Katalog paczek jednego konta i domu (klucz bez znaków spoza nazwy pliku).
    private static func directory(for ownerKey: String) -> URL {
        let safe = ownerKey.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
        return directory.appendingPathComponent(safe, isDirectory: true)
    }

    /// Paczki innego konta albo domu (zmiana domu bez wylogowania) znikają.
    private static func removeOtherOwners(keeping ownerKey: String) {
        let keep = directory(for: ownerKey).lastPathComponent
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent != keep {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func fileURL(_ recipeId: UUID) -> URL {
        Self.directory(for: ownerKey).appendingPathComponent("\(recipeId.uuidString.lowercased()).json")
    }

    private func save(_ package: CookPackage) {
        do {
            try FileManager.default.createDirectory(at: Self.directory(for: ownerKey), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(package)
            try data.write(to: fileURL(package.recipeId), options: .atomic)
        } catch {
            // Brak zapisu = paczka żyje do końca procesu; następne otwarcie
            // szczegółów pobierze ją jeszcze raz.
        }
    }

    private static func loadAll(from directory: URL) -> [UUID: CookPackage] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [:] }
        var result: [UUID: CookPackage] = [:]
        let decoder = JSONDecoder()
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let package = try? decoder.decode(CookPackage.self, from: data),
                  package.format == CookPackage.currentFormat else { continue }
            result[package.recipeId] = package
        }
        return result
    }
}
