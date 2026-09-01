import Foundation

/// Tłumaczy błędy na kopię dla użytkownika.
///
/// Od plastra C backend oddaje każdy błąd z KODEM (`code`) — po sockecie
/// w kopercie ack, po REST w body `{code, message, details?, requestId}`.
/// Decyzja „co pokazać" zapada więc najpierw po kodzie (tabela niżej), a
/// dopiero potem — dla błędów transportu i starszego backendu — po dawnych
/// dopasowaniach angielskich podciągów. Podciągi zostają na jedno wydanie:
/// przez ten czas telefon może rozmawiać ze starym serwerem, który kodów
/// dla tych sytuacji jeszcze nie miał.
enum UserFacingErrorMapper {
    /// Kod z odpowiedzi serwera, jeśli błąd go niesie.
    static func code(from error: Error) -> String? {
        if case let RecipeDataError.server(code, _, _, _) = error {
            return code
        }
        if case let BackendAPIError.backend(code, _, _) = error {
            return code
        }
        return nil
    }

    /// Czy to błąd ŁĄCZNOŚCI (martwy socket, brak ACK, offline), a nie
    /// odpowiedź serwera. Te pierwsze bywają chwilowe — zaraz po wybudzeniu
    /// aplikacji socket jeszcze wstaje — i `ConnectivityErrorGate` pokazuje je
    /// dopiero, gdy się utrzymają.
    ///
    /// Odpowiedź serwera z kodem NIGDY nie jest błędem łączności — dawne
    /// dopasowanie gołego „socket" w treści opóźniałoby o 2 s prawdziwe
    /// odmowy, gdyby tylko komunikat zawierał to słowo.
    static func isConnectivityIssue(_ error: Error) -> Bool {
        switch error {
        case RecipeDataError.server:
            return false
        case RecipeDataError.transportNotConfigured:
            return true
        case let RecipeDataError.serverError(message):
            return matchesConnectivity(message)
        case BackendAPIError.network:
            return true
        case is URLError:
            return true
        default:
            return matchesConnectivity(extractMessage(from: error))
        }
    }

    /// Kopia dla kodu, który NIE przyszedł jako błąd HTTP.
    ///
    /// Tura asystenta kończy się polem `errorCode` w odpowiedzi `200` — jest
    /// sam kod, nie ma czego mapować przez `message(from:)`. `nil` znaczy
    /// „nie znam tego kodu": wołający pokaże własne zdanie zamiast wyciągać
    /// użytkownikowi surowy identyfikator.
    static func copy(forCode code: String) -> String? {
        copyByCode[code]
    }

    static func message(from error: Error) -> String {
        if let code = code(from: error), let copy = copyByCode[code] {
            return copy
        }

        // Błędy transportu NIE mają kodu, a `BackendAPIError` nie jest
        // `LocalizedError` — bez tych dwóch przypadków użytkownik dostawał
        // „The operation couldn't be completed. (weekly_meals.BackendAPIError
        // error 2.)". Cookidoo miało własny switch i dlatego to nie wyszło
        // wcześniej; asystent jest pierwszym ekranem, który idzie tędy wprost.
        switch error {
        case BackendAPIError.network:
            return "Brak połączenia z serwerem. Sprawdź internet i spróbuj ponownie."
        case BackendAPIError.notAuthenticated:
            return copyByCode["UNAUTHORIZED"]!
        default:
            break
        }

        let baseMessage = extractMessage(from: error).trimmingCharacters(in: .whitespacesAndNewlines)
        if baseMessage.isEmpty {
            return "Wystąpił nieoczekiwany błąd. Spróbuj ponownie."
        }

        let lower = baseMessage.lowercased()

        if lower.contains("cancelled") || lower.contains("cancellationerror") {
            return "Operacja została przerwana."
        }
        if lower.contains("cannot post /auth/apple") || lower.contains("cannot post /auth/dev")
            || (lower.contains("not found") && (lower.contains("/auth/apple") || lower.contains("/auth/dev"))) {
            return "Nie udało się zalogować. Sprawdź, czy backend działa."
        }
        // ─── Dopasowania po treści: tylko dla starszego backendu bez kodów ───
        if lower.contains("invalid apple identity token") || lower.contains("apple nonce does not match") {
            return copyByCode["APPLE_IDENTITY_INVALID"]!
        }
        if lower.contains("only owners can") || lower.contains("only owners") {
            return copyByCode["OWNER_REQUIRED"]!
        }
        if lower.contains("user is not a member of this household") {
            return copyByCode["NOT_HOUSEHOLD_MEMBER"]!
        }
        if lower.contains("invitation already redeemed") {
            return copyByCode["INVITATION_ALREADY_REDEEMED"]!
        }
        if lower.contains("invitation expired") {
            return copyByCode["INVITATION_EXPIRED"]!
        }
        if lower.contains("invitation was declined") {
            return copyByCode["INVITATION_DECLINED"]!
        }
        if lower.contains("already belongs to another household") {
            return copyByCode["INVITATION_REQUIRES_LEAVE"]!
        }
        if lower.contains("invitation not found") || lower.contains("nie znaleziono zaproszenia") {
            return copyByCode["INVITATION_NOT_FOUND"]!
        }
        if matchesConnectivity(lower) {
            return "Problem z połączeniem na żywo. Spróbuj ponownie."
        }
        if lower.contains("already assigned to that day and meal slot") {
            return copyByCode["PLAN_SLOT_DUPLICATE"]!
        }
        if lower.contains("internal_error") || lower.contains("internal server error") {
            return copyByCode["INTERNAL_ERROR"]!
        }

        return baseMessage
    }

    // MARK: - Tabela kodów

    /// Jedna kopia na kod — parytet z `AppErrorCode` w `src/common/app-error-code.ts`.
    /// Nieznany (nowszy) kod spada niżej, na komunikat z serwera.
    private static let copyByCode: [String: String] = [
        // generyczne
        "UNAUTHORIZED": "Sesja wygasła. Zaloguj się ponownie.",
        "FORBIDDEN": "Nie masz uprawnień do tej akcji.",
        "NOT_FOUND": "Nie znaleziono danych. Odśwież i spróbuj ponownie.",
        "BAD_REQUEST": "Serwer odrzucił te dane. Sprawdź je i spróbuj ponownie.",
        "VALIDATION_ERROR": "Serwer odrzucił te dane. Sprawdź je i spróbuj ponownie.",
        "CONFLICT": "Te dane już istnieją. Odśwież i spróbuj ponownie.",
        "TOO_MANY_REQUESTS": "Za dużo prób. Odczekaj chwilę i spróbuj ponownie.",
        "SERVICE_UNAVAILABLE": "Serwer jest chwilowo niedostępny. Spróbuj ponownie za chwilę.",
        "INTERNAL_ERROR": "Wystąpił błąd serwera. Spróbuj ponownie za chwilę.",
        // auth
        "APPLE_IDENTITY_INVALID": "Nie udało się zweryfikować logowania Apple. Spróbuj ponownie.",
        "DEV_LOGIN_DISABLED": "Logowanie deweloperskie jest wyłączone.",
        // gospodarstwo
        "HOUSEHOLD_NOT_FOUND": "Nie znaleziono gospodarstwa.",
        "NOT_HOUSEHOLD_MEMBER": "Nie należysz do tego gospodarstwa.",
        "OWNER_REQUIRED": "Tylko właściciel gospodarstwa może wykonać tę akcję.",
        "MEMBER_NOT_FOUND": "Tej osoby nie ma już w gospodarstwie.",
        "LAST_OWNER": "Gospodarstwo musi mieć przynajmniej jednego właściciela.",
        "HOUSEHOLD_ALREADY_MEMBER": "Należysz już do gospodarstwa. Najpierw je opuść.",
        // zaproszenia
        "INVITATION_NOT_FOUND": "Nie znaleziono zaproszenia. Sprawdź link.",
        "INVITATION_EXPIRED": "To zaproszenie wygasło.",
        "INVITATION_ALREADY_REDEEMED": "Ten link zaproszenia jest jednorazowy. Poproś o nowy link.",
        "INVITATION_DECLINED": "To zaproszenie zostało odrzucone. Poproś o nowe.",
        "INVITATION_REQUIRES_LEAVE": "Należysz już do innego gospodarstwa. Otwórz zaproszenie ponownie, aby się przenieść.",
        // plan
        "RECIPE_NOT_FOUND": "Nie znaleziono przepisu.",
        "INGREDIENT_NOT_FOUND": "Nie znaleziono składnika w katalogu.",
        "PLAN_ITEM_NOT_FOUND": "Tego posiłku nie ma już w planie.",
        "PLAN_SLOT_LIMIT_REACHED": "Ten typ posiłku ma już komplet dań w tym tygodniu.",
        "PLAN_SLOT_VARIANT_LIMIT_REACHED": "W tym slocie nie zmieści się więcej dań.",
        "PLAN_PARTICIPANT_NOT_IN_HOUSEHOLD": "Wybrana osoba nie należy do gospodarstwa.",
        "PLAN_TOTAL_LIMIT_REACHED": "Plan tygodnia jest pełny.",
        "PLAN_SLOT_DUPLICATE": "Ten przepis jest już w tym slocie.",
        "RECIPE_NOT_SUITABLE_FOR_SLOT": "Ten przepis nie pasuje do tego posiłku.",
        "RECIPE_ALLERGEN_CONFLICT": "Ten przepis ma składnik, na który ktoś z jedzących jest uczulony.",
        "RECIPE_NOT_EDITABLE": "Przepisów z katalogu nie da się zmieniać. Zapisz własną wersję.",
        "RECIPE_IN_USE": "Ten przepis jest w planie tygodnia. Najpierw usuń go z planu.",
        // lista zakupów
        "SHOPPING_LIST_EMPTY": "Lista zakupów jest pusta.",
        "SHOPPING_LIST_NOT_COMPLETED": "Odhacz wszystkie produkty, zanim zamkniesz listę.",
        "SHOPPING_LIST_ARCHIVE_NOT_FOUND": "Tej listy zakupów już nie ma. Odśwież widok.",
        "SHOPPING_ITEM_NOT_FOUND": "Tej pozycji nie ma już na liście. Odśwież widok.",
        // asystent AI
        // `AI_PLAN_QUOTA_EXCEEDED` NIE ma tu kopii świadomie: ten kod wraca do
        // MODELU jako wynik narzędzia, a użytkownik dostaje o tym zdanie
        // w odpowiedzi asystenta, nie alert.
        "AI_DISABLED": "Asystent jest teraz niedostępny.",
        "AI_QUOTA_EXCEEDED": "Limit rozmów z asystentem na ten miesiąc został wyczerpany.",
        "AI_BUDGET_PAUSED": "Asystent jest dziś niedostępny. Spróbuj jutro.",
        "AI_UPSTREAM_PAUSED": "Asystent ma chwilową przerwę. Spróbuj za minutę.",
        "AI_TURN_IN_PROGRESS": "Poprzednia wiadomość jest jeszcze przetwarzana.",
        "AI_CONVERSATION_NOT_FOUND": "Tej rozmowy już nie ma.",
        "AI_TURN_NOT_FOUND": "Tej odpowiedzi już nie ma.",
        "AI_MESSAGE_NOT_FOUND": "Tej wiadomości już nie ma — odśwież rozmowę.",
        "AI_TIMEOUT": "Asystent nie zdążył odpowiedzieć. Spróbuj jeszcze raz.",
        "AI_PROVIDER_ERROR": "Asystent nie mógł dokończyć zadania. Spróbuj ponownie za chwilę.",
        // Propozycje: użytkownik klika przycisk W KARCIE, więc kopia mówi
        // o karcie, a nie o „żądaniu". Każda z tych trzech kończy się tak
        // samo — poproś asystenta o nową propozycję — ale POWÓD jest inny
        // i tylko on pozwala zrozumieć, czemu przycisk nagle nie działa.
        "AI_PROPOSAL_NOT_FOUND": "Tej propozycji już nie ma.",
        "AI_PROPOSAL_STALE": "Plan tygodnia zmienił się od czasu tej propozycji. Poproś asystenta o nową.",
        "AI_PROPOSAL_EXPIRED": "Ta propozycja jest już nieaktualna. Poproś asystenta o nową.",
        // Cookidoo
        "COOKIDOO_NOT_CONNECTED": "Gospodarstwo nie ma połączonego konta Cookidoo. Połącz je w Ustawieniach.",
        "COOKIDOO_AUTH_FAILED": "Połączenie z Cookidoo wygasło. Zaloguj się ponownie w Ustawieniach.",
        "COOKIDOO_RECIPE_NOT_LINKED": "Ten przepis nie ma wersji na Thermomixa.",
        "COOKIDOO_RECIPE_NOT_FOUND": "Ten przepis nie ma wersji na Thermomixa.",
        "COOKIDOO_SERVICE_UNAVAILABLE": "Usługa Cookidoo jest chwilowo niedostępna. Spróbuj ponownie za kilka minut.",
        "COOKIDOO_UPSTREAM_ERROR": "Cookidoo odpowiedziało błędem. Spróbuj ponownie za chwilę.",
        "COOKIDOO_SUBSCRIPTION_INACTIVE": "Subskrypcja Cookidoo jest nieaktywna.",
    ]

    // MARK: - Pomocnicze

    private static func matchesConnectivity(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("brak ack")
            || lower.contains("brak połączenia websocket")
            || lower.contains("socket")
    }

    private static func extractMessage(from error: Error) -> String {
        let message = error.localizedDescription
        if let parsed = parseJsonMessage(message), !parsed.isEmpty {
            return parsed
        }
        return message
    }

    private static func parseJsonMessage(_ raw: String) -> String? {
        guard raw.first == "{", let data = raw.data(using: .utf8) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        if let messageArray = json["message"] as? [String], !messageArray.isEmpty {
            return messageArray.joined(separator: ", ")
        }
        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }
        return nil
    }
}
