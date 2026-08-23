import Foundation

struct WeekPlanSlot {
    /// Backend `PlanItem.id` — a slot can hold several of these, one per
    /// household split, so the id is what identifies a single variant.
    let itemId: String
    let dateKey: String
    let mealSlot: MealSlot
    let recipe: Recipe
    /// Household member ids this variant is for. Empty = shared („Wspólne").
    let participantIds: [String]
    /// Members who marked this meal as eaten. Per-user, because a shared meal
    /// is eaten by each person on their own schedule.
    let eatenByUserIds: [String]
    /// Ile porcji przepisu gotujemy w tym slocie — łącznie, nie na osobę.
    ///
    /// `nil` przenosi dalej „serwer nie podał", a nie „jedna porcja": backend
    /// sprzed tej zmiany nie zna tego pola, a podstawiona tu jedynka
    /// połowiłaby w dwuosobowym domu i listę zakupów, i licznik kalorii.
    /// Liczbę wylicza dopiero `PlanMeal.effectiveServings(householdMemberCount:)`.
    let plannedServings: Int?
}

protocol WeeklyPlanRepository {
    func fetchWeekPlan(weekStart: String) async throws -> [WeekPlanSlot]
    /// `plannedServings == nil` zostawia wyliczenie liczby porcji serwerowi.
    func upsertWeekSlot(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID, participantIds: [String], plannedServings: Int?) async throws
    /// `recipeId == nil` clears every variant in the slot.
    func removeWeekSlot(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID?) async throws
    func clearWeekPlan(weekStart: String) async throws
    /// Marks one planned meal as eaten by the signed-in user, or clears it.
    func setMealEaten(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID, isEaten: Bool) async throws
    func observeWeekPlanChanges(_ onChange: @escaping (_ event: BackendWeekChangedDTO) -> Void)
    func fetchSavedPlan(weekStart: String) async throws -> BackendSharedMealPlanDTO
    func saveSavedPlan(weekStart: String, recipeIdsByMealType: [String: [String]]) async throws -> BackendSharedMealPlanDTO
    func observeSavedPlanChanges(_ onChange: @escaping (_ event: BackendSavedPlanChangedDTO) -> Void)
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void)
}

protocol WeeklyPlanTransportClient {
    func fetchWeekPlan(weekStart: String) async throws -> [BackendWeeklyPlanItemDTO]
    /// `plannedServings == nil` zostawia wyliczenie liczby porcji serwerowi.
    func upsertWeekSlot(weekStart: String, dayOfWeek: String, mealType: String, recipeId: String, participantIds: [String], plannedServings: Int?) async throws
    func removeWeekSlot(weekStart: String, dayOfWeek: String, mealType: String, recipeId: String?) async throws
    func clearWeekPlan(weekStart: String) async throws
    func setMealEaten(weekStart: String, dayOfWeek: String, mealType: String, recipeId: String, isEaten: Bool) async throws
    func observeWeekPlanChanges(_ onChange: @escaping (_ event: BackendWeekChangedDTO) -> Void)
    func fetchSavedPlan(weekStart: String) async throws -> BackendSharedMealPlanDTO
    func saveSavedPlan(weekStart: String, recipeIdsByMealType: [String: [String]]) async throws -> BackendSharedMealPlanDTO
    func observeSavedPlanChanges(_ onChange: @escaping (_ event: BackendSavedPlanChangedDTO) -> Void)
    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void)
}

struct BackendWeeklyPlanDTO: Codable {
    let id: String
    let weekStart: String
    let items: [BackendWeeklyPlanItemDTO]
}

struct BackendWeeklyPlanItemDTO: Codable {
    let id: String
    let dayOfWeek: String
    let mealType: String
    let recipe: BackendRecipeDTO
    /// Absent on responses from a backend that predates splits — treated as
    /// „Wspólne", which is what those rows have always meant.
    let participantIds: [String]?
    /// Absent on a backend that predates eaten-marks — treated as „nobody ate
    /// it yet", which is the only safe reading of missing data.
    let eatenByUserIds: [String]?
    /// Nieobecne na backendzie sprzed porcji — i tak właśnie zostaje, jako
    /// `nil`. To znaczy „policz z audytorium", więc taki tydzień pokazuje
    /// dzisiejsze liczby zamiast twardej jednej porcji.
    let plannedServings: Int?
}

struct BackendSharedMealPlanDTO: Codable {
    let weekStart: String
    let items: [BackendSharedMealPlanItemDTO]
}

struct BackendSharedMealPlanItemDTO: Codable {
    let mealType: String
    let quantity: Int
    let recipe: BackendRecipeDTO
}

private struct BackendPlanItemAckDTO: Codable {
    let id: String
}

/// `weeklyPlans:removeWeekSlot` answers with the ids it deleted — a slot can
/// hold several variants, and clearing it removes them all.
private struct BackendRemoveWeekSlotAckDTO: Codable {
    let removedItemIds: [String]?
    let count: Int?
}

private struct BackendClearWeekPlanAckDTO: Codable {
    let success: Bool
}

struct BackendWeekChangedDTO: Codable {
    let householdId: String
    let weekStart: String
    let action: String?
    let changedByUserId: String?
    let changedByDisplayName: String?
    let dayOfWeek: String?
    let mealType: String?
    let changeVersion: Int64?
}

struct BackendSavedPlanChangedDTO: Codable {
    let householdId: String
    let weekStart: String
    let changedByUserId: String?
    let changedByDisplayName: String?
    let action: String?
    let changeVersion: Int64?
}

private final class WeekDateMapper {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayOffsets: [String: Int] = [
        "MON": 0,
        "TUE": 1,
        "WED": 2,
        "THU": 3,
        "FRI": 4,
        "SAT": 5,
        "SUN": 6
    ]

    static func dateKey(weekStart: String, dayOfWeek: String) -> String? {
        guard let monday = formatter.date(from: weekStart),
              let offset = dayOffsets[dayOfWeek.uppercased()],
              let date = Calendar.current.date(byAdding: .day, value: offset, to: monday) else {
            return nil
        }
        return formatter.string(from: date)
    }

    static func dayOfWeek(from date: Date, weekStart: String) -> String? {
        guard let monday = formatter.date(from: weekStart) else { return nil }
        let startOfMonday = Calendar.current.startOfDay(for: monday)
        let startOfDate = Calendar.current.startOfDay(for: date)
        let diff = Calendar.current.dateComponents([.day], from: startOfMonday, to: startOfDate).day ?? 0
        switch diff {
        case 0: return "MON"
        case 1: return "TUE"
        case 2: return "WED"
        case 3: return "THU"
        case 4: return "FRI"
        case 5: return "SAT"
        case 6: return "SUN"
        default: return nil
        }
    }
}

// Mapowanie slot ↔ `MealType` mieszka teraz przy samym `MealSlot`
// (`Models/Components/MealSlot.swift`) — trzymanie go tutaj oznaczało, że
// każdy nowy posiłek trzeba dopisać w dwóch miejscach, a ominięcie jednego
// z nich nie było błędem kompilacji, tylko cicho gubionym posiłkiem.
private extension BackendWeeklyPlanItemDTO {
    var appMealSlot: MealSlot? {
        MealSlot(backendMealType: mealType)
    }
}

final class WebSocketWeeklyPlanTransportClient: WeeklyPlanTransportClient {
    private let socket: RecipeSocketClient
    private let userId: String
    private let householdId: String?
    private let preferredHouseholdName: String?
    private var resolvedHouseholdId: String?

    init(
        socket: RecipeSocketClient,
        userId: String,
        householdId: String? = nil,
        preferredHouseholdName: String? = "Home"
    ) {
        self.socket = socket
        self.userId = userId
        self.householdId = householdId
        self.preferredHouseholdName = preferredHouseholdName
    }

    private func resolveHouseholdId() async throws -> String {
        if let resolvedHouseholdId {
            return resolvedHouseholdId
        }
        if let householdId, !householdId.isEmpty {
            resolvedHouseholdId = householdId
            return householdId
        }

        let envelope: WsEnvelope<[BackendHouseholdDTO]> = try await socket.emitWithAck(
            event: "households:findAll",
            payload: ["userId": userId],
            as: WsEnvelope<[BackendHouseholdDTO]>.self
        )

        guard envelope.ok, let households = envelope.data else {
            throw RecipeDataError.serverError(message: envelope.error ?? "Nie udało się pobrać gospodarstw.")
        }

        if let preferredHouseholdName,
           let matched = households.first(where: { $0.name.lowercased() == preferredHouseholdName.lowercased() }) {
            resolvedHouseholdId = matched.id
            return matched.id
        }

        guard let first = households.first else {
            throw RecipeDataError.serverError(message: "Brak gospodarstwa dla użytkownika.")
        }
        resolvedHouseholdId = first.id
        return first.id
    }

    func fetchWeekPlan(weekStart: String) async throws -> [BackendWeeklyPlanItemDTO] {
        let householdId = try await resolveHouseholdId()
        let envelope: WsEnvelope<BackendWeeklyPlanDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:getByWeek",
            payload: [
                "userId": userId,
                "householdId": householdId,
                "weekStart": weekStart
            ],
            as: WsEnvelope<BackendWeeklyPlanDTO>.self
        )

        if envelope.ok, let data = envelope.data {
            return data.items
        }

        if envelope.code == "NOT_FOUND" || envelope.error?.localizedCaseInsensitiveContains("not found") == true {
            return []
        }

        throw RecipeDataError.serverError(message: envelope.error ?? "Nieznany błąd weeklyPlans:getByWeek.")
    }

    func upsertWeekSlot(weekStart: String, dayOfWeek: String, mealType: String, recipeId: String, participantIds: [String], plannedServings: Int?) async throws {
        let householdId = try await resolveHouseholdId()
        var data: [String: Any] = [
            "dayOfWeek": dayOfWeek,
            "mealType": mealType,
            "recipeId": recipeId,
            "participantIds": participantIds
        ]
        // Pole leci tylko wtedy, gdy użytkownik sam ustawił liczbę porcji.
        // Brak klucza znaczy dla serwera „policz sam z audytorium" — gdybyśmy
        // wysłali tu domyślne 1, każdy posiłek dodany bez ruszania steppera
        // wchodziłby do listy zakupów jako pojedyncza porcja zamiast tylu,
        // ilu jest jedzących.
        if let plannedServings {
            data["plannedServings"] = plannedServings
        }
        let envelope: WsEnvelope<BackendPlanItemAckDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:upsertWeekSlot",
            payload: [
                "userId": userId,
                "householdId": householdId,
                "weekStart": weekStart,
                "data": data
            ],
            as: WsEnvelope<BackendPlanItemAckDTO>.self
        )

        if envelope.ok {
            return
        }

        throw RecipeDataError.serverError(message: envelope.error ?? "Nieznany błąd weeklyPlans:upsertWeekSlot.")
    }

    func removeWeekSlot(weekStart: String, dayOfWeek: String, mealType: String, recipeId: String?) async throws {
        let householdId = try await resolveHouseholdId()
        var data: [String: Any] = [
            "dayOfWeek": dayOfWeek,
            "mealType": mealType
        ]
        if let recipeId {
            data["recipeId"] = recipeId
        }
        let envelope: WsEnvelope<BackendRemoveWeekSlotAckDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:removeWeekSlot",
            payload: [
                "userId": userId,
                "householdId": householdId,
                "weekStart": weekStart,
                "data": data
            ],
            as: WsEnvelope<BackendRemoveWeekSlotAckDTO>.self
        )

        if envelope.ok {
            return
        }
        throw RecipeDataError.serverError(message: envelope.error ?? "Nieznany błąd weeklyPlans:removeWeekSlot.")
    }

    func setMealEaten(weekStart: String, dayOfWeek: String, mealType: String, recipeId: String, isEaten: Bool) async throws {
        let householdId = try await resolveHouseholdId()
        let envelope: WsEnvelope<BackendPlanItemAckDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:setMealEaten",
            payload: [
                "userId": userId,
                "householdId": householdId,
                "weekStart": weekStart,
                "data": [
                    "dayOfWeek": dayOfWeek,
                    "mealType": mealType,
                    "recipeId": recipeId,
                    "isEaten": isEaten
                ]
            ],
            as: WsEnvelope<BackendPlanItemAckDTO>.self
        )

        if envelope.ok {
            return
        }

        throw RecipeDataError.serverError(message: envelope.error ?? "Nieznany błąd weeklyPlans:setMealEaten.")
    }

    func clearWeekPlan(weekStart: String) async throws {
        let householdId = try await resolveHouseholdId()
        let envelope: WsEnvelope<BackendClearWeekPlanAckDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:clearWeekPlan",
            payload: [
                "userId": userId,
                "householdId": householdId,
                "weekStart": weekStart
            ],
            as: WsEnvelope<BackendClearWeekPlanAckDTO>.self
        )
        if envelope.ok {
            return
        }
        throw RecipeDataError.serverError(message: envelope.error ?? "Nieznany błąd weeklyPlans:clearWeekPlan.")
    }

    func observeWeekPlanChanges(_ onChange: @escaping (_ event: BackendWeekChangedDTO) -> Void) {
        socket.off(event: "weeklyPlans:weekChanged")
        socket.on(event: "weeklyPlans:weekChanged") { [weak self] items in
            guard let self else { return }
            guard let first = items.first,
                  JSONSerialization.isValidJSONObject(first),
                  let data = try? JSONSerialization.data(withJSONObject: first),
                  let event = try? JSONDecoder().decode(BackendWeekChangedDTO.self, from: data)
            else { return }

            let expectedHouseholdId = self.resolvedHouseholdId ?? self.householdId
            if let expectedHouseholdId, event.householdId != expectedHouseholdId {
                return
            }

            onChange(event)
        }
    }

    func fetchSavedPlan(weekStart: String) async throws -> BackendSharedMealPlanDTO {
        let householdId = try await resolveHouseholdId()
        let envelope: WsEnvelope<BackendSharedMealPlanDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:getSavedPlan",
            payload: [
                "userId": userId,
                "householdId": householdId,
                "weekStart": weekStart
            ],
            as: WsEnvelope<BackendSharedMealPlanDTO>.self
        )

        if envelope.ok, let data = envelope.data {
            return data
        }
        throw RecipeDataError.serverError(message: envelope.error ?? "Nieznany błąd weeklyPlans:getSavedPlan.")
    }

    /// Zapis puli na tydzień.
    ///
    /// Ładunek jedzie jako mapa `MealType → id przepisów` (`recipeIdsByMealType`)
    /// zamiast trzech pól `breakfast/lunch/dinnerRecipeIds`. Backend nadal
    /// przyjmuje stare pola, ale wysyłanie ich obok mapy nic nie wnosi — dla
    /// slotów wymienionych w mapie i tak wygrywa mapa.
    func saveSavedPlan(weekStart: String, recipeIdsByMealType: [String: [String]]) async throws -> BackendSharedMealPlanDTO {
        let householdId = try await resolveHouseholdId()
        let envelope: WsEnvelope<BackendSharedMealPlanDTO> = try await socket.emitWithAck(
            event: "weeklyPlans:saveSavedPlan",
            payload: [
                "userId": userId,
                "householdId": householdId,
                "weekStart": weekStart,
                "data": [
                    "recipeIdsByMealType": recipeIdsByMealType
                ]
            ],
            as: WsEnvelope<BackendSharedMealPlanDTO>.self
        )

        if envelope.ok, let data = envelope.data {
            return data
        }
        throw RecipeDataError.serverError(message: envelope.error ?? "Nieznany błąd weeklyPlans:saveSavedPlan.")
    }

    func observeSavedPlanChanges(_ onChange: @escaping (_ event: BackendSavedPlanChangedDTO) -> Void) {
        socket.off(event: "weeklyPlans:savedPlanChanged")
        socket.on(event: "weeklyPlans:savedPlanChanged") { [weak self] items in
            guard let self else { return }
            guard let first = items.first,
                  JSONSerialization.isValidJSONObject(first),
                  let data = try? JSONSerialization.data(withJSONObject: first),
                  let event = try? JSONDecoder().decode(BackendSavedPlanChangedDTO.self, from: data)
            else { return }

            let expectedHouseholdId = self.resolvedHouseholdId ?? self.householdId
            if let expectedHouseholdId, event.householdId != expectedHouseholdId {
                return
            }

            onChange(event)
        }
    }

    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {
        socket.observeConnection { isConnected in
            guard isConnected else { return }
            onReconnect()
        }
    }
}

final class ApiWeeklyPlanRepository: WeeklyPlanRepository {
    private let client: WeeklyPlanTransportClient

    init(client: WeeklyPlanTransportClient) {
        self.client = client
    }

    func fetchWeekPlan(weekStart: String) async throws -> [WeekPlanSlot] {
        let items = try await client.fetchWeekPlan(weekStart: weekStart)
        return items.compactMap { item in
            guard let dateKey = WeekDateMapper.dateKey(weekStart: weekStart, dayOfWeek: item.dayOfWeek),
                  let mealSlot = item.appMealSlot,
                  let recipe = item.recipe.toAppRecipe() else {
                return nil
            }
            return WeekPlanSlot(
                itemId: item.id,
                dateKey: dateKey,
                mealSlot: mealSlot,
                recipe: recipe,
                participantIds: item.participantIds ?? [],
                eatenByUserIds: item.eatenByUserIds ?? [],
                // Bez `?? 1`: brak pola ma dojechać do modelu jako „nie wiem",
                // żeby licznik zdążył policzyć porcje z audytorium.
                plannedServings: item.plannedServings
            )
        }
    }

    func upsertWeekSlot(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID, participantIds: [String], plannedServings: Int?) async throws {
        guard let dayOfWeek = WeekDateMapper.dayOfWeek(from: date, weekStart: weekStart) else {
            throw RecipeDataError.serverError(message: "Nie można wyznaczyć dnia tygodnia dla slotu.")
        }
        try await client.upsertWeekSlot(
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            mealType: mealSlot.backendMealType,
            recipeId: recipeId.uuidString,
            participantIds: participantIds,
            plannedServings: plannedServings
        )
    }

    func removeWeekSlot(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID?) async throws {
        guard let dayOfWeek = WeekDateMapper.dayOfWeek(from: date, weekStart: weekStart) else {
            throw RecipeDataError.serverError(message: "Nie można wyznaczyć dnia tygodnia dla slotu.")
        }
        try await client.removeWeekSlot(
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            mealType: mealSlot.backendMealType,
            recipeId: recipeId?.uuidString
        )
    }

    func clearWeekPlan(weekStart: String) async throws {
        try await client.clearWeekPlan(weekStart: weekStart)
    }

    func setMealEaten(weekStart: String, date: Date, mealSlot: MealSlot, recipeId: UUID, isEaten: Bool) async throws {
        guard let dayOfWeek = WeekDateMapper.dayOfWeek(from: date, weekStart: weekStart) else {
            throw RecipeDataError.serverError(message: "Nie można wyznaczyć dnia tygodnia dla slotu.")
        }
        try await client.setMealEaten(
            weekStart: weekStart,
            dayOfWeek: dayOfWeek,
            mealType: mealSlot.backendMealType,
            recipeId: recipeId.uuidString,
            isEaten: isEaten
        )
    }

    func observeWeekPlanChanges(_ onChange: @escaping (_ event: BackendWeekChangedDTO) -> Void) {
        client.observeWeekPlanChanges(onChange)
    }

    func fetchSavedPlan(weekStart: String) async throws -> BackendSharedMealPlanDTO {
        try await client.fetchSavedPlan(weekStart: weekStart)
    }

    func saveSavedPlan(weekStart: String, recipeIdsByMealType: [String: [String]]) async throws -> BackendSharedMealPlanDTO {
        try await client.saveSavedPlan(
            weekStart: weekStart,
            recipeIdsByMealType: recipeIdsByMealType
        )
    }

    func observeSavedPlanChanges(_ onChange: @escaping (_ event: BackendSavedPlanChangedDTO) -> Void) {
        client.observeSavedPlanChanges(onChange)
    }

    func observeRealtimeReconnect(_ onReconnect: @escaping () -> Void) {
        client.observeRealtimeReconnect(onReconnect)
    }
}
