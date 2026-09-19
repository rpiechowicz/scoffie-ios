import Foundation

#if DEBUG
// Wzorce kart do podglądów SwiftUI — DOSŁOWNE odpowiedzi builderów serwera,
// te same co w `Scripts/CardContract/main.swift` (skopiowane skryptem, nie
// ręcznie). Podglądy dekodują je tak, jak robi to aplikacja, więc pokazują
// karty w tym kształcie, w jakim przychodzą z serwera.
//
// Po zmianie kontraktu w backendzie: `scripts/dump-card-fixtures.ts` →
// `Scripts/CardContract/main.swift` → ten plik (patrz `CLAUDE.md`).
enum AssistantPreviewFixtures {
    static let planWeekJSON = #"{"kind": "PLAN_WEEK", "v": 1, "proposalId": "55555555-5555-4555-8555-555555555555", "weekStart": "2026-08-31", "eyebrow": "Propozycja planu", "eyebrowDetail": "31 sierpnia – 6 września", "title": "Obiad i kolacja na tydzień", "subtitle": "Nic się nie powtarza, a wtorek jest szybki.", "days": [{"dayOfWeek": "MON", "dayLabel": "Poniedziałek", "dayShort": "Pon", "date": "2026-08-31", "dateLabel": "31.08", "slots": [{"mealType": "LUNCH", "mealLabel": "Obiad", "recipeId": "r-1", "title": "Kurczak z ryżem", "kcalPerServing": 620, "prepTimeMinutes": 30, "imageUrl": "https://example.invalid/kurczak.png", "participantIds": [], "change": "NEW"}, {"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "r-2", "title": "Sałatka z tuńczykiem", "kcalPerServing": 380, "prepTimeMinutes": 12, "imageUrl": null, "participantIds": ["u1"], "change": "KEPT"}], "kcalTotal": 1000}, {"dayOfWeek": "TUE", "dayLabel": "Wtorek", "dayShort": "Wt", "date": "2026-09-01", "dateLabel": "1.09", "slots": [{"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "r-3", "title": "Placki ziemniaczane", "kcalPerServing": 540, "prepTimeMinutes": 40, "imageUrl": null, "participantIds": [], "change": "NEW"}], "kcalTotal": 540}], "removed": [{"dayLabel": "Środa", "mealLabel": "Kolacja", "title": "Zupa pomidorowa"}], "summary": {"meals": 3, "created": 2, "updated": 0, "removed": 1, "averageKcalPerDay": 770, "targetKcalPerDay": 2100, "goalNote": "1330 kcal poniżej celu"}, "actions": [{"type": "APPLY", "proposalId": "55555555-5555-4555-8555-555555555555", "label": "Dodaj do planu", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
    static let planDayJSON = #"{"kind": "PLAN_DAY", "v": 1, "proposalId": "66666666-6666-4666-8666-666666666666", "weekStart": "2026-08-31", "date": "2026-09-01", "eyebrow": "Propozycja dnia", "eyebrowDetail": "wtorek, 1 września", "title": "Cały dzień pod cel 2100 kcal", "subtitle": "Lekki wieczór po ciężkim obiedzie.", "slots": [{"mealType": "BREAKFAST", "mealLabel": "Śniadanie", "recipeId": "r-4", "title": "Owsianka z bananem", "kcalPerServing": 447, "prepTimeMinutes": 12, "imageUrl": null, "participantIds": [], "change": "NEW"}, {"mealType": "LUNCH", "mealLabel": "Obiad", "recipeId": "r-1", "title": "Kurczak w sosie curry z ryżem", "kcalPerServing": 620, "prepTimeMinutes": 35, "imageUrl": null, "participantIds": [], "change": "KEPT"}, {"mealType": "DINNER", "mealLabel": "Kolacja", "recipeId": "r-5", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 393, "prepTimeMinutes": 12, "imageUrl": null, "participantIds": [], "change": "NEW"}], "removed": [{"dayLabel": "Wtorek", "mealLabel": "Kolacja", "title": "Pizza mrożona"}], "summary": {"meals": 3, "kcalTotal": 1460, "targetKcalPerDay": 2100, "goalNote": "zostaje 640"}, "actions": [{"type": "APPLY", "proposalId": "66666666-6666-4666-8666-666666666666", "label": "Zapisz wtorek", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
    static let clarifyJSON = #"{"kind": "CLARIFY", "v": 1, "question": "Dla ilu osób mam planować ten tydzień?", "hint": "W profilu są cztery osoby, ale wspominałeś o weekendzie we dwoje.", "actions": [{"type": "ASK", "proposalId": null, "label": "Dla czterech", "style": "PRIMARY", "prompt": "Dla czterech"}, {"type": "ASK", "proposalId": null, "label": "Dla dwóch", "style": "SECONDARY", "prompt": "Dla dwóch"}, {"type": "ASK", "proposalId": null, "label": "Inaczej w weekend", "style": "SECONDARY", "prompt": "Inaczej w weekend"}]}"#
    static let optionsJSON = #"{"kind": "OPTIONS", "v": 1, "eyebrow": "Kolacja · wtorek", "title": "Trzy szybkie kolacje", "options": [{"recipeId": "r-5", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 393, "prepTimeMinutes": 12, "imageUrl": "https://example.invalid/omlet.jpg", "tag": "Najszybsze", "prompt": "Wybieram: Omlet ze szpinakiem i fetą"}, {"recipeId": "r-7", "title": "Sałatka z tuńczykiem", "kcalPerServing": 340, "prepTimeMinutes": 15, "imageUrl": null, "tag": null, "prompt": "Wybieram: Sałatka z tuńczykiem"}, {"recipeId": "r-8", "title": "Tost z awokado i jajkiem", "kcalPerServing": 420, "prepTimeMinutes": 10, "imageUrl": null, "tag": "Najwięcej białka", "prompt": "Wybieram: Tost z awokado i jajkiem"}], "actions": [{"type": "ASK", "proposalId": null, "label": "Coś innego", "style": "SECONDARY", "prompt": "Żadne z tych mi nie pasuje. Zaproponuj coś innego."}]}"#
    static let swapJSON = #"{"kind": "SWAP", "v": 1, "proposalId": "77777777-7777-4777-8777-777777777777", "weekStart": "2026-08-31", "date": "2026-09-01", "eyebrow": "Podmiana · wtorek, kolacja", "title": "Szybciej o 43 min", "from": {"recipeId": "r-1", "title": "Gulasz wołowy z kaszą", "kcalPerServing": 720, "prepTimeMinutes": 55}, "to": {"recipeId": "r-5", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 393, "prepTimeMinutes": 12}, "deltas": [{"value": "−43 min", "label": "szybciej", "good": true}, {"value": "−327 kcal", "label": "na porcję", "good": true}], "actions": [{"type": "APPLY", "proposalId": "77777777-7777-4777-8777-777777777777", "label": "Podmień", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
    static let removeMealJSON = #"{"kind": "REMOVE_MEAL", "v": 1, "proposalId": "99999999-9999-4999-8999-999999999999", "weekStart": "2026-08-31", "date": "2026-09-03", "eyebrow": "Usunięcie · czwartek, kolacja", "title": "Jemy u teściów", "removed": {"recipeId": "r-9", "title": "Zapiekanka z cukinią", "kcalPerServing": 640, "prepTimeMinutes": 55}, "note": null, "actions": [{"type": "APPLY", "proposalId": "99999999-9999-4999-8999-999999999999", "label": "Usuń z planu", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
    static let splitJSON = #"{"kind": "HOUSEHOLD_SPLIT", "v": 1, "proposalId": "88888888-8888-4888-8888-888888888888", "weekStart": "2026-08-31", "date": "2026-09-02", "eyebrow": "Jedna baza · trzy porcje", "title": "Gulasz wołowy z kaszą gryczaną", "prepTimeMinutes": 55, "portions": [{"userId": "u-1", "displayName": "Rafał", "goalLabel": "2100 kcal", "note": "Duża porcja + kasza 100 g", "kcal": 740}, {"userId": "u-2", "displayName": "Ania", "goalLabel": "1750 kcal · wegetariańska", "note": "Bez mięsa, więcej kaszy", "kcal": 590}, {"userId": "u-3", "displayName": "Zosia", "goalLabel": "1400 kcal · bez laktozy", "note": "Śmietana osobno", "kcal": 420}], "actions": [{"type": "APPLY", "proposalId": "88888888-8888-4888-8888-888888888888", "label": "Zapisz na środę", "style": "PRIMARY"}], "state": {"status": "PENDING", "canApply": true, "canUndo": false, "until": "2026-09-03T10:00:00.000Z"}}"#
    static let macroJSON = #"{"kind": "MACRO_GAP", "v": 1, "eyebrow": "Białko · ten tydzień", "title": "Brakuje średnio 44 g dziennie", "macro": "PROTEIN", "unit": "g", "current": 96, "target": 140, "boosters": [{"text": "Twarożek zamiast musli (śr.)", "amount": 24}, {"text": "Jogurt grecki do owsianki (pon., czw.)", "amount": 18}, {"text": "Kurczak zamiast makaronu na kolację (pt.)", "amount": 22}], "actions": [{"type": "ASK", "proposalId": null, "label": "Zastosuj wszystkie trzy", "style": "PRIMARY", "prompt": "Zastosuj te zmiany w planie i pokaż mi je jako propozycję."}]}"#
    static let shoppingJSON = #"{"kind": "SHOPPING_LIST", "v": 1, "weekStart": "2026-08-31", "eyebrow": "Lista zakupów · 31 sierpnia – 6 września", "title": "4 rzeczy do kupienia", "groups": [{"department": "Warzywa", "items": ["Cukinia 2 szt.", "Dynia 1 kg"]}, {"department": "Ryby", "items": ["Dorsz 600 g"]}, {"department": "Nabiał", "items": ["Feta 2 op."]}], "summary": {"remaining": 4, "checked": 1}, "checkedNote": "1 pozycja już odhaczona", "actions": [{"type": "OPEN_SHOPPING", "proposalId": null, "label": "Otwórz listę zakupów", "style": "PRIMARY"}]}"#
    static let appliedJSON = #"{"kind": "APPLIED", "v": 1, "proposalId": "55555555-5555-4555-8555-555555555555", "weekStart": "2026-08-31", "title": "Zapisano w planie", "subtitle": "2 nowe pozycje, 1 usunięta · 31 sierpnia – 6 września", "summary": {"created": 2, "updated": 0, "removed": 1}, "notes": ["Cofnięcie przywróci usunięte posiłki, ale nie odhaczenia „zjedzone”."], "actions": [{"type": "UNDO", "proposalId": "55555555-5555-4555-8555-555555555555", "label": "Cofnij", "style": "SECONDARY"}, {"type": "OPEN_PLAN", "proposalId": null, "label": "Otwórz Plan tygodnia", "style": "PRIMARY"}], "state": {"status": "APPLIED", "canApply": false, "canUndo": true, "until": "2026-08-31T11:00:00.000Z"}}"#

    private static let decoder = JSONDecoder()

    static func card(_ json: String) -> AgentCardDTO {
        // swiftlint:disable:next force_try
        try! decoder.decode(AgentCardDTO.self, from: Data(json.utf8))
    }

    static var planWeek: PlanWeekCardDTO {
        guard case .planWeek(let card) = card(planWeekJSON) else { fatalError("PLAN_WEEK") }
        return card
    }

    static var planDay: PlanDayCardDTO {
        guard case .planDay(let card) = card(planDayJSON) else { fatalError("PLAN_DAY") }
        return card
    }

    static var clarify: ClarifyCardDTO {
        guard case .clarify(let card) = card(clarifyJSON) else { fatalError("CLARIFY") }
        return card
    }

    static var options: OptionsCardDTO {
        guard case .options(let card) = card(optionsJSON) else { fatalError("OPTIONS") }
        return card
    }

    static var swap: SwapCardDTO {
        guard case .swap(let card) = card(swapJSON) else { fatalError("SWAP") }
        return card
    }

    static var removeMeal: RemoveMealCardDTO {
        guard case .removeMeal(let card) = card(removeMealJSON) else { fatalError("REMOVE_MEAL") }
        return card
    }

    static var householdSplit: HouseholdSplitCardDTO {
        guard case .householdSplit(let card) = card(splitJSON) else { fatalError("HOUSEHOLD_SPLIT") }
        return card
    }

    static var macroGap: MacroGapCardDTO {
        guard case .macroGap(let card) = card(macroJSON) else { fatalError("MACRO_GAP") }
        return card
    }

    static var shoppingList: ShoppingListCardDTO {
        guard case .shoppingList(let card) = card(shoppingJSON) else { fatalError("SHOPPING_LIST") }
        return card
    }

    static var applied: AppliedCardDTO {
        guard case .applied(let card) = card(appliedJSON) else { fatalError("APPLIED") }
        return card
    }

    /// Ten sam tydzień w innym stanie — do podglądu STALE / APPLIED / UNDONE.
    static func planWeek(status: String, canApply: Bool, canUndo: Bool) -> PlanWeekCardDTO {
        var card = planWeek
        card.state = AgentCardStateDTO(status: status, canApply: canApply, canUndo: canUndo, until: "2026-09-21T10:00:00.000Z")
        return card
    }

    // MARK: - Briefingi

    /// Dzień briefingu z podanymi porami; `filled` = które mają danie.
    static func day(_ date: Date, filled: [AssistantBriefingSlot] = [], enabled: [AssistantBriefingSlot] = [.breakfast, .lunch, .dinner]) -> AssistantBriefingDay {
        let titles: [AssistantBriefingSlot: String] = [
            .breakfast: "Szakszuka z papryką i cebulą",
            .secondBreakfast: "Owsianka z masłem orzechowym",
            .lunch: "Leczo z kiełbasą, cukinią i papryką",
            .afternoonSnack: "Pudding ryżowy z musem malinowym",
            .dinner: "Ryż smażony z jajkiem i warzywami",
            .snack: "Jogurt z jagodami",
        ]
        return AssistantBriefingDay(
            date: date,
            enabledSlots: enabled,
            meals: filled.map { AssistantBriefingDay.Meal(slot: $0, title: titles[$0] ?? "Danie", kcal: 480, imageURL: nil) }
        )
    }

    static func week(from monday: Date, plannedDays: Int, filled: [AssistantBriefingSlot] = [.breakfast, .lunch, .dinner]) -> [AssistantBriefingDay] {
        (0..<7).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: monday) ?? monday
            return day(date, filled: offset < plannedDays ? filled : [])
        }
    }

    static func context(kind: AssistantBriefing.Kind) -> AssistantBriefingContext {
        let cal = Calendar.current
        // Czwartek, 14:30 — środek tygodnia, przed kolacją.
        var parts = DateComponents(year: 2026, month: 9, day: 17, hour: 14, minute: 30)
        if kind == .tomorrowEmpty { parts.hour = 19 }
        if kind == .nextWeekEmpty || kind == .weekendInspiration { parts.day = 19 }
        let now = cal.date(from: parts) ?? Date()
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 14)) ?? now
        let nextMonday = cal.date(byAdding: .day, value: 7, to: monday) ?? monday
        var context = AssistantBriefingContext(
            now: now,
            calendar: cal,
            displayName: "Rafał Piechowicz",
            thisWeek: week(from: monday, plannedDays: 7),
            nextWeek: week(from: nextMonday, plannedDays: 7)
        )
        switch kind {
        case .trialExhausted: context.trialExhausted = true
        case .newUser:
            context.isNewUser = true
            context.thisWeek = week(from: monday, plannedDays: 0)
            context.nextWeek = week(from: nextMonday, plannedDays: 0)
        case .weekEmpty: context.thisWeek = week(from: monday, plannedDays: 0)
        case .todayEmpty: context.thisWeek = week(from: monday, plannedDays: 3)
        case .tomorrowEmpty: context.thisWeek = week(from: monday, plannedDays: 4)
        case .missingMeal: context.thisWeek = week(from: monday, plannedDays: 7, filled: [.breakfast, .lunch])
        case .nextWeekEmpty: context.nextWeek = week(from: nextMonday, plannedDays: 0)
        case .balanceIssue:
            context.balance = AssistantBriefingBalance(macroGenitive: "białka", macroAccusative: "białko", unit: "g", averagePerDay: 116, target: 140, daysCounted: 5)
        case .weekendInspiration: context.thisWeek = week(from: monday, plannedDays: 6)
        case .dayReady: context.thisWeek = week(from: monday, plannedDays: 5)
        case .weekReady: break
        }
        return context
    }

    static func briefing(_ kind: AssistantBriefing.Kind) -> AssistantBriefing {
        AssistantBriefingResolver.resolve(context(kind: kind))
    }
}
#endif
