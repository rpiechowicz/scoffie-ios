import Foundation
import Observation
import SwiftUI

/// Trwająca sesja gotowania i jej zapis na dysk (§8.6).
///
/// Jedna sesja naraz (§4.7). Każda zmiana stanu idzie przez `update`, który
/// od razu zapisuje plik — po zabiciu aplikacji przez system talerz
/// i szczegóły pokazują „Wróć do gotowania” w tym samym kroku, z tymi samymi
/// timerami (liczonymi od dat końca, więc bez doganiania).
///
/// Widok trybu (`CookModeView`) stoi w `fullScreenCover` nad pulpitem;
/// `isPresented` to jego przełącznik. „Wstrzymaj” chowa widok, sesja zostaje;
/// „Zakończ” i „Zjedzone” sesję kończą.
@Observable
final class CookSessionStore {
    private(set) var session: CookSession?
    /// Pełny ekran trybu Gotuj nad pulpitem.
    var isPresented = false
    /// Konto i dom (`userId_householdId`) — sesja z pliku innego właściciela
    /// nie wraca.
    let ownerKey: String

    init(ownerKey: String) {
        self.ownerKey = ownerKey
        session = Self.load(ownerKey: ownerKey)
    }

    /// Nowa sesja. Poprzednia (inny przepis) znika — pytanie „zakończyć
    /// tamtą?” zadaje ekran, zanim tu przyjdzie (§4.7, jedna sesja naraz).
    func start(
        recipe: Recipe,
        package: CookPackage,
        portions: Int,
        mealSlot: MealSlot?,
        now: Date = Date()
    ) {
        let session = CookSession(
            recipeId: recipe.id,
            recipeTitle: recipe.name,
            imageURL: recipe.imageURL,
            mealSlotRaw: mealSlot?.rawValue,
            package: package,
            portions: portions,
            startedAt: now
        )
        self.session = session
        save()
        isPresented = true
    }

    /// Powrót do wstrzymanej sesji (talerz, szczegóły, Live Activity).
    func resume() {
        guard session != nil else { return }
        isPresented = true
    }

    /// Sesja dla tego przepisu — „Wróć do gotowania” zamiast „Gotuj”.
    func session(for recipeId: UUID) -> CookSession? {
        guard let session, session.recipeId == recipeId, session.stage != .finished else { return nil }
        return session
    }

    /// Jedyna droga zmiany stanu: zmiana + zapis.
    func update(_ change: (inout CookSession) -> Void) {
        guard var current = session else { return }
        change(&current)
        guard current != session else { return }
        session = current
        save()
    }

    /// „Wstrzymaj”: widok znika, sesja i timery zostają.
    func pause() {
        isPresented = false
    }

    /// „Zakończ gotowanie” / „Zjedzone”: koniec sesji.
    func end() {
        isPresented = false
        session = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    // MARK: - Dysk

    /// Sesja należy do konta — po wylogowaniu nie ma prawa wrócić u kogoś innego.
    static func clearCache() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var fileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cook-session-v1.json")
    }

    private func save() {
        guard let session else { return }
        do {
            let directory = Self.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(StoredSession(ownerKey: ownerKey, session: session))
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            // Bez zapisu sesja żyje do końca procesu — gotowanie trwa dalej.
        }
    }

    private static func load(ownerKey: String) -> CookSession? {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data),
              stored.ownerKey == ownerKey,
              stored.session.format == CookSession.currentFormat else { return nil }
        let session = stored.session
        // Stara sesja nie wraca — to już nie jest „to samo gotowanie”. Granica
        // to 36 h od startu, a nie doba czy północ, bo scenariusz bywa „na noc”
        // (D38: ciasto w lodówce do rana, następny krok zaczyna się od „Rano…”).
        guard Date().timeIntervalSince(session.startedAt) < 36 * 60 * 60 else { return nil }
        return session.stage == .finished ? nil : session
    }
}

/// Plik sesji: właściciel + stan.
private struct StoredSession: Codable {
    let ownerKey: String
    let session: CookSession
}

private struct CookSessionStoreKey: EnvironmentKey {
    @MainActor static let defaultValue: CookSessionStore? = nil
}

extension EnvironmentValues {
    var cookSessionStore: CookSessionStore? {
        get { self[CookSessionStoreKey.self] }
        set { self[CookSessionStoreKey.self] = newValue }
    }
}
