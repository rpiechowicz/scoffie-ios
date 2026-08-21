import Foundation

/// One-shot alert state shown when the user taps an invitation deep link
/// before a household context exists. Held by `SessionStore.invitationPrompt`.
struct InvitationPromptState: Identifiable {
    let id = UUID()
    let token: String
    let householdName: String
    let invitedByDisplayName: String?
    let expiresAtText: String?

    var message: String {
        var parts: [String] = []
        if let invitedByDisplayName, !invitedByDisplayName.isEmpty {
            parts.append("\(invitedByDisplayName) zaprasza Cię do gospodarstwa „\(householdName)”.")
        } else {
            parts.append("Otrzymano zaproszenie do gospodarstwa „\(householdName)”.")
        }
        if let expiresAtText, !expiresAtText.isEmpty {
            parts.append("Ważne do: \(expiresAtText).")
        }
        return parts.joined(separator: " ")
    }
}

/// Kontrolowane fazy startu po logowaniu / restore sesji.
/// UI gatuje przejście do dashboardu na `.ready`, żeby użytkownik nie zobaczył
/// niedoładowanych ekranów z placeholderami.
enum StartupPhase: Equatable {
    case idle
    case warmingUp
    case ready
}

/// Snapshot domownika trzymany w SessionStore (preload pod Settings / Household).
struct HouseholdMemberSnapshot: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let email: String?
    let avatarUrl: String?
    /// Kolor awatara z backendu. Opcjonalny, bo starsze wpisy w cache'u
    /// gospodarstwa go nie mają — wtedy `MemberAvatar` liczy kolor z id,
    /// tak samo jak `ProfileAvatar` dla kont bez przydziału.
    var avatarColor: Int?
    let role: String
}
