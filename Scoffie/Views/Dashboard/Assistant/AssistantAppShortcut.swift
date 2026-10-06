import SwiftUI

/// Pytanie, na które odpowiedź JUŻ jest w aplikacji — telefon go nie wysyła
/// (27.09.2026, Rafał: „w asystencie nie ma sensu robić mechanizmów »pokaż
/// listę zakupów« / »jak się robi dany przepis«. User może sam szybko
/// sprawdzić, a to bez sensu wywoływanie agenta — szkoda kasy i rozmów”).
///
/// Zamiast tury (koszt + wiadomość z puli) nad polem staje karta z przejściem
/// do właściwego ekranu i „Zapytaj mimo to”. Serwer ma tę samą regułę
/// w prompcie (`show_shopping_list` wycofane z modelu), więc pytanie wysłane
/// „mimo to” dostaje jedno zdanie odsyłające.
///
/// Rozpoznanie jest OSTROŻNE — lepiej przepuścić pytanie do Asystenta niż
/// zablokować coś, co tylko on umie: „kupiłem mleko” (odhaczenie), „zapisz
/// mój przepis na…” (nowy przepis), „co zrobić z bakłażanem” (dobór dań),
/// „czym zastąpić…” (zamiennik) przechodzą normalnie.
enum AssistantAppShortcut: Equatable {
    case shopping
    case recipe

    static func match(_ raw: String) -> AssistantAppShortcut? {
        let text = raw.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL"))
        func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

        // Zapis, zmiana, zamiennik albo odhaczenie — to robi Asystent.
        if has(["kupil", "mam juz", "odhacz", "zapisz", "dodaj", "zapamietaj", "zamien", "zastap",
                "bez ", "zamiast", "uloz", "zaplanuj", "zaproponuj"]) {
            return nil
        }
        if has(["lista zakupow", "liste zakupow", "listy zakupow", "co musze kupic", "co trzeba kupic",
                "co mam kupic", "zakupy na ten tydzien", "pokaz zakupy"]) {
            return .shopping
        }
        if has(["jak ugotowac", "jak zrobic", "jak przygotowac", "jak sie robi", "rozpisz kroki",
                "podaj przepis", "daj przepis", "pokaz przepis", "krok po kroku"]) {
            return .recipe
        }
        return nil
    }

    var icon: String {
        switch self {
        case .shopping: return "cart"
        case .recipe: return "book.closed"
        }
    }

    var title: String {
        switch self {
        case .shopping: return "Listę zakupów masz w Planie"
        case .recipe: return "Przepis krok po kroku masz w aplikacji"
        }
    }

    var detail: String {
        switch self {
        case .shopping: return "Liczy się sama z planu tygodnia — bez wiadomości do Asystenta."
        case .recipe: return "Stuknij danie w Planie albo w Przepisach — skład i kroki są w szczegółach."
        }
    }

    var openTitle: String {
        switch self {
        case .shopping: return "Otwórz listę"
        case .recipe: return "Otwórz Przepisy"
        }
    }
}

/// Karta nad polem wiadomości: skąd wziąć odpowiedź w aplikacji, „Zapytaj
/// mimo to” (wysyła pytanie jak zwykle) i krzyżyk.
struct AssistantAppShortcutCard: View {
    let shortcut: AssistantAppShortcut
    let onOpen: () -> Void
    let onAskAnyway: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SCHeaderIconWell(icon: shortcut.icon, accent: AssistantLook.sage(scheme), size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(shortcut.title)
                        .font(.sc(size: 15, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(AssistantLook.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(shortcut.detail)
                        .font(.sc(size: 13))
                        .foregroundStyle(AssistantLook.muted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.sc(size: 11, weight: .bold))
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .frame(width: 28, height: 28)
                        .scTapTarget(drawn: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zamknij")
            }

            AssistantActionPair(spacing: 8) {
                AssistantGhostButton(
                    action: AssistantCardAction(title: "Zapytaj mimo to", action: onAskAnyway),
                    size: .compact
                )
                AssistantPrimaryButton(
                    action: AssistantCardAction(title: shortcut.openTitle, icon: "arrow.right", action: onOpen),
                    size: .compact,
                    tint: AssistantLook.sage(scheme)
                )
            }
        }
        .padding(14)
        // Pływa nad rozmową razem z polem — szkło jak pole, nie strój kafla
        // (Liquid Glass runda 2). `AssistantView.composer` daje mu tożsamość
        // w grupie szkła, więc karta wyrasta z pola i w nie wsiąka.
        .scChromeGlass(in: shape)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}
