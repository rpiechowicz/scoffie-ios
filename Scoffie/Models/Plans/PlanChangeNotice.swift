import Foundation

/// Kapsuła o zmianie planu zrobionej przez domownika (16.10.2026).
///
/// Zgłoszenie z dwóch telefonów: „dodałem przepis, a user2 go nie widział
/// i nie dostał powiadomienia w planie”. Push z serwera wymaga klucza APNs
/// (na prod go nie było), a powiadomienie lokalne wychodziło po minucie,
/// po cichu, tylko dla oglądanego tygodnia i tylko ze zgodą na powiadomienia.
/// Kapsuła mówi to samo od razu, w aplikacji — jedna na serię zmian.
///
/// Treść bez rodzaju gramatycznego („Ania: nowe danie w planie”), bo imię
/// nie mówi, czy „dodał”, czy „dodała”.
enum PlanChangeNotice {
    /// Czy zdarzenie jest wiadomością dla domownika. Porcje, „dla kogo”
    /// i odhaczenie „zjedzone” — nie (tak samo milczy push).
    static func isWorthTelling(_ event: BackendWeekChangedDTO) -> Bool {
        switch event.action?.uppercased() {
        case "UPSERT_SLOT":
            switch event.changeKind?.uppercased() {
            // `nil` = backend sprzed 16.10.2026, który rodzaju zmiany nie podaje.
            case nil, "CREATED", "REPLACED": return true
            default: return false
            }
        case "REMOVE_SLOT", "CLEAR_PLAN", "APPLY_WEEK", "SAVE_PLAN":
            return true
        default:
            return false
        }
    }

    /// Jedna kapsuła na całą serię. `recipeTitle` szuka nazwy dania w planie
    /// po odświeżeniu (serwer podaje `recipeId`).
    static func toast(
        for events: [BackendWeekChangedDTO],
        recipeTitle: (BackendWeekChangedDTO) -> String?,
        now: Date = Date()
    ) -> SCToast? {
        guard let last = events.last else { return nil }
        let actor = NotificationActorFormatter.firstName(from: last.changedByDisplayName)

        // Paczka z kilku osób albo kilku tygodni: bez przypisywania operacji
        // ostatniemu autorowi — „Kasia: wyczyszczony plan”, gdy plan
        // wyczyścił Adam, byłoby nieprawdą (Codex, 16.10.2026).
        let authors = events.reduce(into: [String]()) { names, event in
            let name = NotificationActorFormatter.firstName(from: event.changedByDisplayName)
            if !names.contains(name) { names.append(name) }
        }
        let authorIds = Set(events.map { $0.changedByUserId ?? "" })
        if authorIds.count > 1 {
            return SCToast(style: .info, title: "Zmiany w planie", message: listed(authors))
        }
        if Set(events.map(\.weekStart)).count > 1 {
            return SCToast(style: .info, title: "\(actor): zmiany w planie", message: nil)
        }

        let actions = Set(events.compactMap { $0.action?.uppercased() })
        let week = weekLabel(last.weekStart, now: now)

        if actions.contains("CLEAR_PLAN") {
            return SCToast(style: .info, title: "\(actor): wyczyszczony plan", message: week)
        }
        // Zapis asystenta zmienia wiele kratek naraz i nie mówi których.
        if actions.contains("APPLY_WEEK") || actions.contains("SAVE_PLAN") {
            return SCToast(style: .info, title: "\(actor): zmiany w planie", message: week)
        }

        let slotEvents = events.filter { $0.dayOfWeek != nil && $0.mealType != nil }
        let slots = Set(slotEvents.map { "\($0.weekStart)|\($0.dayOfWeek ?? "")|\($0.mealType ?? "")" })
        guard slots.count == 1, let event = slotEvents.last else {
            let count = max(slots.count, events.count)
            let noun = PolishPlural.form(count, one: "zmiana", few: "zmiany", many: "zmian")
            return SCToast(style: .info, title: "\(actor): \(count) \(noun) w planie", message: week)
        }

        let when = slotLabel(event)
        if slotEvents.allSatisfy({ $0.action?.uppercased() == "REMOVE_SLOT" }) {
            return SCToast(style: .info, title: "\(actor): usunięte z planu", message: when)
        }
        let added = slotEvents.contains { $0.changeKind?.uppercased() == "CREATED" }
        var dish: String?
        for candidate in slotEvents.reversed() {
            if let title = recipeTitle(candidate) {
                dish = title
                break
            }
        }
        let message = [dish, when].compactMap { $0 }.joined(separator: " · ")
        return SCToast(
            style: .info,
            title: added ? "\(actor): nowe danie w planie" : "\(actor): zmiana w planie",
            message: message.isEmpty ? nil : message
        )
    }

    /// „Ania i Kasia”, „Ania, Kasia i Marek”.
    private static func listed(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " i " + last
    }

    /// Przesunięcie dnia od poniedziałku (`MON` = 0).
    static func dayOffset(_ dayOfWeek: String) -> Int? {
        ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"].firstIndex(of: dayOfWeek.uppercased())
    }

    /// „środa, obiad”.
    private static func slotLabel(_ event: BackendWeekChangedDTO) -> String? {
        let days = ["poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota", "niedziela"]
        guard let dayOfWeek = event.dayOfWeek, let offset = dayOffset(dayOfWeek) else { return nil }
        let meal = event.mealType.flatMap { MealSlot(backendMealType: $0) }?.title.lowercased()
        return [days[offset], meal].compactMap { $0 }.joined(separator: ", ")
    }

    /// „ten tydzień” / „przyszły tydzień” / „tydzień od 20.10”.
    private static func weekLabel(_ weekStart: String, now: Date) -> String {
        guard let monday = PlanWeek.date(fromKey: weekStart) else { return "ten tydzień" }
        let current = PlanWeek.monday(of: now)
        let days = PlanWeek.calendar.dateComponents([.day], from: current, to: monday).day ?? 0
        switch Int((Double(days) / 7).rounded()) {
        case 0: return "ten tydzień"
        case 1: return "przyszły tydzień"
        default:
            let parts = PlanWeek.calendar.dateComponents([.day, .month], from: monday)
            return String(format: "tydzień od %02d.%02d", parts.day ?? 0, parts.month ?? 0)
        }
    }
}
