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

struct BackendHouseholdMembersChangedDTO: Codable {
    let householdId: String
    let action: String?
    let changedByUserId: String?
    let changedByDisplayName: String?
}

struct BackendInvitationPreviewDTO: Codable {
    struct HouseholdDTO: Codable {
        let id: String
        let name: String
    }

    let token: String
    let status: String
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
    let onboardingCompletedAt: String?
}

struct BackendHouseholdMemberDTO: Decodable {
    struct UserDTO: Decodable {
        let id: String
        let displayName: String
        let email: String?
        let avatarUrl: String?
    }

    let id: String
    let userId: String
    let householdId: String
    let role: String
    let user: UserDTO
}

struct HouseholdMembersCachePayload: Codable {
    let householdId: String
    let members: [HouseholdMemberSnapshot]
    let savedAt: Date
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
}

/// Odpowiedź na `users:delete` — samo potwierdzenie, że konto o tym id
/// zniknęło. Klient nie ma już czego z niego czytać.
struct BackendDeletedUserDTO: Decodable {
    let id: String
}
