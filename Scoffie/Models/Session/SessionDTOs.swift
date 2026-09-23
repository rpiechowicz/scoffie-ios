import Foundation

// MARK: - Auth DTOs

/// Matches backend POST /auth/apple payload exactly.
struct AppleSignInRequest: Codable {
    let identityToken: String
    let rawNonce: String
    let givenName: String?
    let familyName: String?
    let email: String?
}

/// Matches backend response envelope for both /auth/apple and /auth/dev
/// (both funnel through AuthService.buildAuthResult → same shape).
struct SessionResponse: Codable {
    struct UserDTO: Codable {
        let id: String
        let displayName: String
        let email: String?
        let avatarUrl: String?
        /// Indeks gradientu awatara przydzielony przez backend. Jedzie już
        /// w odpowiedzi logowania — bez niego klient do czasu pierwszego
        /// `users:me` kolorował własny awatar fallbackiem z hasza, czyli
        /// innym odcieniem niż listy domowników. `nil` na starszym backendzie
        /// i dla kont sprzed onboardingu.
        let avatarColor: Int?
        let provider: String?
        /// ISO 8601 timestamp; `nil` means the user hasn't finished the
        /// welcome flow yet and should be routed to it.
        let onboardingCompletedAt: String?
    }

    struct HouseholdDTO: Codable {
        let id: String
        let name: String
    }

    let accessToken: String
    let refreshToken: String
    let user: UserDTO
    let household: HouseholdDTO?
}

// MARK: - Household / invitation DTOs

struct HouseholdLeaveAckDTO: Codable {
    let success: Bool
}

struct PushDeviceRegisterAckDTO: Codable {
    let success: Bool
    /// Czy serwer w ogóle umie wysłać pusha (APNs skonfigurowany).
    ///
    /// Samo „zarejestrowałem token" tego nie rozstrzyga — token zapisuje się
    /// także wtedy, gdy APNs jest wyłączony w środowisku. Klient potrzebuje tej
    /// odpowiedzi, żeby wiedzieć, czy może zamilknąć ze swoimi lokalnymi
    /// powiadomieniami, czy zostaje jedynym kanałem. Starszy backend tego pola
    /// nie przysyła — `nil` czytamy wtedy jako „nie wiadomo", czyli ostrożnie.
    let pushEnabled: Bool?
}

struct BackendInvitationDTO: Codable {
    let id: String
    let token: String
    let householdId: String
}

struct BackendMembershipDTO: Codable {
    let id: String
    let userId: String
    let householdId: String
    let role: String
}

struct BackendHouseholdMembersChangedDTO: Decodable {
    let householdId: String
    let action: String?
    let changedByUserId: String?
    let changedByDisplayName: String?
    /// Nowy skład gospodarstwa, jeśli serwer go dołożył.
    ///
    /// Bez tej listy zdarzenie było samym sygnałem „coś się zmieniło" i klient
    /// musiał po skład wrócić osobnym `households:listMembers`. Ten round-trip
    /// bywał ostatnim brakującym ogniwem: gdy nie przechodził, nowy domownik
    /// nie pojawiał się na liście i nikt się o tym nie dowiadywał. Wzorzec jest
    /// ten sam co w `households:mealTypesChanged`, które listę wozi od zawsze.
    let members: [BackendHouseholdMemberDTO]?
}

/// Zmiana zestawu posiłków planowanych przez gospodarstwo
/// (`households:mealTypesChanged`). Nowa lista jedzie w ładunku, więc
/// odbiorca nie musi po nią wracać osobnym zapytaniem.
struct BackendHouseholdMealTimesChangedDTO: Codable {
    let householdId: String
    let mealSlotTimes: [String: Int]?
    let changedByUserId: String?
    let changedByDisplayName: String?
}

struct BackendHouseholdMealTypesChangedDTO: Codable {
    let householdId: String
    let mealTypes: [String]
    let changedByUserId: String?
    let changedByDisplayName: String?
}

struct BackendInvitationPreviewDTO: Codable {
    struct HouseholdDTO: Codable {
        let id: String
        let name: String
    }

    let token: String
    /// `PENDING` | `REQUIRES_LEAVE` | `ALREADY_MEMBER` | `EXPIRED`
    /// | `REDEEMED` | `DECLINED` | `NOT_FOUND`.
    let status: String
    let household: HouseholdDTO?
    let invitedByDisplayName: String?
    let expiresAt: String?
    /// Gospodarstwo, które użytkownik straci, przyjmując zaproszenie.
    /// `nil` na starszym backendzie i wtedy, gdy do żadnego nie należy.
    let currentHousehold: HouseholdDTO?
    /// Czy tamten dom zniknie razem z jego odejściem, bo nikt w nim nie
    /// zostanie. `nil` (starszy backend) czytamy jak `false` — ostrożniej jest
    /// nie straszyć usunięciem, którego może nie być.
    let willDeleteCurrentHousehold: Bool?
}

/// Potwierdzenie prostej mutacji, która nie ma nic do odesłania poza
/// „zrobione" (np. `households:declineInvitation`).
struct BackendMutationAckDTO: Codable {
    let success: Bool?
}

/// Zaproszenie czekające w skrzynce użytkownika (`households:listPendingInvitations`).
struct BackendPendingInvitationDTO: Codable {
    struct HouseholdDTO: Codable {
        let id: String
        let name: String
    }

    let token: String
    let household: HouseholdDTO?
    let invitedByDisplayName: String?
    let expiresAt: String?
}

struct BackendCurrentUserDTO: Codable {
    struct MembershipDTO: Codable {
        struct HouseholdDTO: Codable {
            let id: String
            let name: String
        }

        let householdId: String
        let household: HouseholdDTO?
    }

    let id: String
    let displayName: String
    let email: String?
    let avatarUrl: String?
    let yearOfBirth: Int?
    let heightCm: Int?
    let weightKg: Double?
    let sex: String?
    let avatarColor: Int?
    let onboardingCompletedAt: String?
    let memberships: [MembershipDTO]
}

/// Backend payload for `users:profile:update` and `users:onboarding:complete`.
/// Mirrors `UserProfilePayload` server-side.
struct BackendUserProfileDTO: Codable {
    let id: String
    let displayName: String
    let email: String?
    let avatarUrl: String?
    let yearOfBirth: Int?
    let heightCm: Int?
    let weightKg: Double?
    let sex: String?
    let avatarColor: Int?
    let onboardingCompletedAt: String?
}

struct BackendHouseholdMemberDTO: Decodable {
    struct UserDTO: Decodable {
        let id: String
        let displayName: String
        let email: String?
        let avatarUrl: String?
        /// Indeks gradientu przydzielony przez backend — patrz
        /// `ProfileAvatar.colorIndex`. `nil` dla kont sprzed tej zmiany.
        let avatarColor: Int?
    }

    let id: String
    let userId: String
    let householdId: String
    let role: String
    let user: UserDTO
}

/// Jeden wiersz `households:memberPreferences` — tylko pola, których używa
/// arkusz gospodarstwa. Reszta kontekstu (cele, ograniczenia) jest dla
/// asystenta i tu się jej nie dekoduje.
struct BackendMemberContextDTO: Decodable {
    let userId: String
    let dietPreference: String?
    let allergens: [String]?
}

struct HouseholdMembersCachePayload: Codable {
    let householdId: String
    let members: [HouseholdMemberSnapshot]
    let savedAt: Date
}

/// Jeden wynik `ingredients:search`.
///
/// Serwer oddaje więcej pól (alergeny, jednostki, makra); klient bierze to,
/// czego potrzebuje lista wyboru — resztę pomija, bo `Decodable` ignoruje
/// nieznane klucze.
struct BackendIngredientHitDTO: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
}

// MARK: - User preferences DTO

/// Backend payload for `users:preferences:get` and the response of
/// `users:preferences:update`. The backend uses uppercase enum values
/// (`VEGETARIAN`, `NONE`, `HEALTHY`); iOS stores them lowercased in AppStorage
/// so we normalise on the boundary.
struct BackendUserPreferencesDTO: Decodable {
    let dietPreference: String
    let calorieGoal: Int
    let allergens: [String]
    let goal: String
    let activityLevel: Int
    /// `nil` = użytkownik nie nadpisał makra i klient ma je policzyć sam.
    let proteinG: Int?
    let fatG: Int?
    let carbsG: Int?
    /// Czego ten domownik nie je, choć nie jest to alergia. `nil` = backend
    /// sprzed tej zmiany; wtedy nie ruszamy lokalnej listy.
    let excludedIngredientIds: [String]?
    /// Ile minut najwyżej ma zajmować gotowanie; `nil` = bez ograniczenia.
    let maxPrepTimeMinutes: Int?
    /// Kanały powiadomień push. `nil` = backend sprzed tej zmiany; wtedy
    /// zostawiamy lokalne ustawienia w spokoju i wyślemy je przy najbliższym
    /// zapisie.
    let pushPlanChanges: Bool?
    let pushShoppingList: Bool?
    let pushHousehold: Bool?
    let pushQuietHours: Bool?
}

/// Odpowiedź na `users:delete` — samo potwierdzenie, że konto o tym id
/// zniknęło. Klient nie ma już czego z niego czytać.
struct BackendDeletedUserDTO: Decodable {
    let id: String
}

/// Odpowiedź `notifications:unregisterDevice`.
struct PushDeviceUnregisterAckDTO: Decodable {
    let success: Bool
    let removed: Int?
}
