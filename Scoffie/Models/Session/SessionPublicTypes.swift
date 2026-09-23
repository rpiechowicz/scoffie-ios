import Foundation

/// Alert pokazywany po otwarciu linku z zaproszeniem.
/// Trzymany w `SessionStore.invitationPrompt`.
struct InvitationPromptState: Identifiable {
    let id = UUID()
    let token: String
    let householdName: String
    let invitedByDisplayName: String?
    let expiresAtText: String?
    /// Nazwa gospodarstwa, które trzeba opuścić, żeby przyjąć to zaproszenie.
    ///
    /// Konto obsługuje jeden dom naraz, więc dla kogoś, kto już gdzieś należy,
    /// „dołącz" znaczy w istocie „przenieś się". Wcześniej ta ścieżka po prostu
    /// nie działała: backend dopisywał drugie członkostwo, którego aplikacja
    /// nigdzie nie pokazywała, a po ponownym zalogowaniu użytkownik wracał do
    /// starego domu — z zewnątrz wyglądało to jak zaproszenie, które „nie
    /// zadziałało".
    let currentHouseholdName: String?
    /// Czy tamten dom zniknie razem z jego odejściem, bo zostałby pusty.
    let willDeleteCurrentHousehold: Bool

    var requiresLeave: Bool { currentHouseholdName != nil }

    var title: String {
        requiresLeave ? "Przenieść się do innego gospodarstwa?" : "Dołączyć do gospodarstwa?"
    }

    var confirmLabel: String {
        requiresLeave ? "Przenieś się" : "Dołącz"
    }

    var message: String {
        var parts: [String] = []
        if let invitedByDisplayName, !invitedByDisplayName.isEmpty {
            parts.append("\(invitedByDisplayName) zaprasza Cię do gospodarstwa „\(householdName)”.")
        } else {
            parts.append("Otrzymano zaproszenie do gospodarstwa „\(householdName)”.")
        }
        if let currentHouseholdName {
            parts.append("Opuścisz przy tym „\(currentHouseholdName)” i stracisz dostęp do jego planu oraz listy zakupów.")
            if willDeleteCurrentHousehold {
                // Mówimy wprost, bo to jedyny moment, w którym można się
                // wycofać — po przeniesieniu nie ma czego przywracać.
                parts.append("Nikt w nim nie zostanie, więc zostanie usunięte razem z planami i listami.")
            }
        }
        if let expiresAtText, !expiresAtText.isEmpty {
            parts.append("Ważne do: \(expiresAtText).")
        }
        return parts.joined(separator: " ")
    }
}

/// Zaproszenie czekające w skrzynce — kafel w Ustawieniach → Gospodarstwo.
struct HouseholdInvitationSnapshot: Identifiable, Hashable {
    var id: String { token }
    let token: String
    let householdName: String
    let invitedByDisplayName: String?
    let expiresAtText: String?

    var subtitle: String {
        if let invitedByDisplayName, !invitedByDisplayName.isEmpty {
            return "Zaprasza: \(invitedByDisplayName)"
        }
        return "Zaproszenie do gospodarstwa"
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

/// Czego domownik nie je — dieta i alergeny z `households:memberPreferences`.
///
/// Tylko to, co pokazuje arkusz gospodarstwa. Serwer oddaje więcej (cel,
/// makro, poziom aktywności), ale wzrostu i wagi celowo nie wysyła nikomu
/// poza samym właścicielem konta — patrz `MemberContext` w backendzie.
struct HouseholdMemberPreferences: Equatable {
    let diet: DietPreference
    /// Tylko alergeny znane tej wersji aplikacji, w kolejności `Allergen.allCases`.
    let allergens: [Allergen]
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

extension HouseholdMemberSnapshot {
    /// Ten sam kształt, co składany ręcznie w `refreshHouseholdMembers` —
    /// wyciągnięty tutaj, bo skład gospodarstwa przychodzi teraz dwiema
    /// drogami: z odpowiedzi na `households:listMembers` i z ładunku zdarzenia
    /// `households:membersChanged`. Dwie kopie mapowania rozjechałyby się
    /// przy pierwszym nowym polu.
    init(backend dto: BackendHouseholdMemberDTO) {
        self.init(
            id: dto.user.id,
            displayName: dto.user.displayName,
            email: dto.user.email,
            avatarUrl: dto.user.avatarUrl,
            avatarColor: dto.user.avatarColor,
            role: dto.role
        )
    }
}
