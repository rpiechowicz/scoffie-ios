import Foundation

enum UserFacingErrorMapper {
    static func message(from error: Error) -> String {
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
        if lower.contains("invalid apple identity token") || lower.contains("apple nonce does not match") {
            return "Nie udało się zweryfikować logowania Apple. Spróbuj ponownie."
        }
        if lower.contains("only owners can") || lower.contains("only owners") {
            return "Tylko właściciel gospodarstwa może wykonać tę akcję."
        }
        if lower.contains("user is not a member of this household") {
            return "Nie należysz do tego gospodarstwa."
        }
        if lower.contains("invitation already redeemed") {
            return "Ten link zaproszenia jest jednorazowy. Poproś o nowy link."
        }
        if lower.contains("invitation expired") {
            return "To zaproszenie wygasło."
        }
        if lower.contains("invitation was declined") {
            return "To zaproszenie zostało odrzucone. Poproś o nowe."
        }
        // Ten stan nie jest błędem, tylko pytaniem, na które klient nie
        // odpowiedział: przyjęcie zaproszenia wymaga wyjścia z obecnego
        // gospodarstwa. Normalnie widok pyta o to wcześniej (podgląd zwraca
        // `REQUIRES_LEAVE`), więc tu ląduje tylko wyścig — ktoś dołączył gdzieś
        // między podglądem a przyjęciem.
        if lower.contains("already belongs to another household") {
            return "Należysz już do innego gospodarstwa. Otwórz zaproszenie ponownie, aby się przenieść."
        }
        if lower.contains("invitation not found") || lower.contains("nie znaleziono zaproszenia") {
            return "Nie znaleziono zaproszenia. Sprawdź link."
        }
        if lower.contains("brak ack") || lower.contains("brak połączenia websocket") || lower.contains("socket") {
            return "Problem z połączeniem na żywo. Spróbuj ponownie."
        }
        if lower.contains("internal_error") || lower.contains("internal server error") {
            return "Wystąpił błąd serwera. Spróbuj ponownie za chwilę."
        }

        return baseMessage
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
