import Foundation

/// „Pobierz moje dane" — `GET /me/export` (backend `data-export.controller.ts`).
///
/// Serwer oddaje jeden plik JSON z profilem, preferencjami, przepisami,
/// posiłkami, krokami i rozmowami z asystentem (bez danych innych
/// domowników). Nie dekodujemy go — trafia jak jest do arkusza
/// udostępniania, żeby użytkownik zapisał go w Plikach albo wysłał sobie.
final class DataExportAPIClient {
    private let core: BackendRESTCore

    init(core: BackendRESTCore) {
        self.core = core
    }

    /// Zapisuje eksport do pliku tymczasowego i oddaje jego adres.
    func downloadExport() async throws -> URL {
        let data = try await core.raw(path: "me/export")
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("weekly-meals-dane-\(stamp).json")
        try data.write(to: url, options: [.atomic])
        return url
    }
}
