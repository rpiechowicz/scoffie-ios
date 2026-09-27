import Foundation

/// Przykład w polu wiadomości W ROZMOWIE (27.09.2026, Rafał: „zmieniaj
/// placeholder zależnie od stanu, jaki asystent proponuje — niech to idzie
/// w parze, nie powielaj odpowiedzi, daj wiele różnych wariantów”).
///
/// Zależy od OSTATNIEJ odpowiedzi asystenta: propozycja do zatwierdzenia
/// podsuwa zmianę (z nazwą prawdziwego dania z karty), zapisany plan —
/// następny krok, dania do wyboru — własne życzenie, lista zakupów —
/// odhaczenie, pytanie — odpowiedź własnymi słowami. Nie powtarza tego, co
/// już jest przyciskiem pod kartą („Inny zestaw”, „Zapisz…”, „Otwórz plan”) —
/// pole ma podsunąć to, czego przyciski nie robią.
///
/// Wariant wybiera ziarno z id wiadomości: ta sama odpowiedź ma zawsze ten sam
/// przykład (pole nie miga przy przerysowaniu), kolejne odpowiedzi — różne.
/// Powitanie na pustym ekranie ma własny przykład (`briefing.placeholder`).
enum AssistantComposerHint {
    static func text(after message: AgentChatMessage?, isSending: Bool) -> String {
        if isSending {
            return pick(["Chwila, kończę odpowiedź…", "Już piszę — zaraz będzie gotowe…", "Pracuję nad tym…"], seed: message?.id ?? "")
        }
        guard let message, message.author == .assistant else {
            return "Napisz do asystenta…"
        }
        let seed = message.id
        let status = message.card?.state.map(AssistantCardStatus.init)

        switch message.card {
        case let .planDay(card):
            if status == .applied { return pick(afterSave, seed: seed) }
            if status == .stale || status == .expired { return pick(afterStale, seed: seed) }
            return pick(changeHints(titles: card.slots.map(\.title), extra: dayHints), seed: seed)
        case let .planWeek(card):
            if status == .applied { return pick(afterSave, seed: seed) }
            if status == .stale || status == .expired { return pick(afterStale, seed: seed) }
            let titles = card.days.flatMap { $0.slots.map(\.title) }
            return pick(changeHints(titles: titles, extra: weekHints), seed: seed)
        case let .swap(card):
            if status == .applied { return pick(afterSave, seed: seed) }
            return pick([
                "Np. coś szybszego niż „\(card.to.title)”",
                "Np. zamiennik bez mięsa",
                "Np. coś lżejszego na tę porę",
                "Napisz, czego szukasz zamiast tego…",
            ], seed: seed)
        case .removeMeal, .householdSplit:
            if status == .applied { return pick(afterSave, seed: seed) }
            return pick(["Np. zostaw, ale zmień porcje", "Napisz, co zrobić inaczej…", "Np. usuń też kolację w piątek"], seed: seed)
        case let .options(card):
            let first = card.options.first?.title
            return pick([
                "Np. coś bez glutenu",
                "Np. pokaż dania z kurczakiem",
                "Np. coś, co zrobię w 15 minut",
                "Albo napisz, na co masz ochotę…",
                first.map { "Np. coś podobnego do „\($0)”, ale lżejszego" } ?? "Np. coś lżejszego",
                "Np. coś na ciepło i sycącego",
            ], seed: seed)
        case .shoppingList:
            return pick([
                "Np. odhacz mleko i jajka",
                "Np. co mam kupić na weekend?",
                "Np. mam już pomidory — odhacz",
                "Napisz, co już kupiłeś…",
            ], seed: seed)
        case .macroGap:
            return pick([
                "Np. dorzuć białko do jutrzejszego śniadania",
                "Np. ułóż mi lżejszy dzień",
                "Np. co zjeść, żeby domknąć cel?",
            ], seed: seed)
        case .clarify:
            return pick([
                "Albo odpowiedz własnymi słowami…",
                "Możesz też dopisać szczegóły…",
                "Np. dla dwóch osób, bez ryby",
            ], seed: seed)
        case .applied:
            return pick(afterSave, seed: seed)
        case .unknown, .none:
            return pick([
                "Zapytaj o coś jeszcze…",
                "Np. a co na jutro?",
                "Np. ułóż mi przyszły tydzień",
                "Np. mam kurczaka i paprykę — co z tego zrobić?",
                "Np. ile białka mam w tym tygodniu?",
                "Np. zrób listę zakupów na weekend",
            ], seed: seed)
        }
    }

    // MARK: - Warianty

    /// Po zapisie: następny krok, nie powtórka „Otwórz plan”.
    private static let afterSave = [
        "Np. zrób listę zakupów na ten tydzień",
        "Np. ułóż jeszcze przyszły tydzień",
        "Co jeszcze zaplanować?",
        "Np. a co na jutro na kolację?",
        "Np. ile białka wychodzi w tym tygodniu?",
    ]

    /// Propozycja się zestarzała: przyciski mówią „Odśwież”, pole — co zmienić.
    private static let afterStale = [
        "Np. przelicz to jeszcze raz, ale lżej",
        "Napisz, co ma się zmienić w nowej wersji…",
        "Np. ułóż od nowa, bez ryby",
    ]

    private static let dayHints = [
        "Np. lżejsza kolacja tego dnia",
        "Np. śniadanie na słodko",
        "Np. obiad do 30 minut",
    ]

    private static let weekHints = [
        "Np. mniej mięsa w tym tygodniu",
        "Np. szybsze kolacje, do 20 minut",
        "Np. w piątek coś z rybą",
        "Np. więcej zup w tym tygodniu",
    ]

    /// Zmiana propozycji — z nazwą PRAWDZIWEGO dania z karty, żeby przykład
    /// był o tej odpowiedzi, a nie ogólnikiem.
    private static func changeHints(titles: [String], extra: [String]) -> [String] {
        var hints = extra + ["Napisz, co zmienić w propozycji…"]
        if let first = titles.first {
            hints.append("Np. zamień „\(first)” na coś innego")
        }
        if titles.count > 2 {
            hints.append("Np. zamiast „\(titles[titles.count / 2])” coś lżejszego")
        }
        if let last = titles.last, titles.count > 1 {
            hints.append("Np. „\(last)” bez mięsa")
        }
        return hints
    }

    /// Wariant z ziarna — deterministycznie (bez `hashValue`, który zmienia
    /// się między uruchomieniami).
    private static func pick(_ options: [String], seed: String) -> String {
        guard !options.isEmpty else { return "Napisz do asystenta…" }
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return options[Int(hash % UInt64(options.count))]
    }
}
