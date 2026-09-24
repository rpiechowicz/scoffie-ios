import SwiftUI

// Klocki arkusza „Co potrafi Asystent” (menu ⋯) i kilku arkuszy planów:
// akcenty, kafelek ikony, karta na żetonach aplikacji, stopka i dane
// umiejętności. Od wprowadzenia v2 (24.09.2026) bez podglądów rozmowy
// i miniatur kart — pokazywały je tylko dawne karty „Poznaj”, zastąpione
// żywymi scenkami w `AssistantIntroPages.swift`.

// MARK: - Ton i kolory

enum AssistantAccent {
    case terracotta, sage, indigo, butter

    var color: Color {
        switch self {
        case .terracotta: return SCPalette.terracotta
        case .sage: return SCPalette.sage
        case .indigo: return SCPalette.indigo
        case .butter: return SCPalette.butter
        }
    }

    func tint(_ scheme: ColorScheme) -> Color {
        switch self {
        case .terracotta: return Color.scAccentTint(scheme)
        case .sage: return Color.scSageTint(scheme)
        case .indigo: return Color.scIndigoTint(scheme)
        case .butter: return Color.scButterTint(scheme)
        }
    }
}

/// Kafelek z ikoną w tinacie akcentu — jak w Ustawieniach.
struct AssistantIconTile: View {
    let icon: String
    let accent: AssistantAccent
    var size: CGFloat = 32
    var radius: CGFloat = 10

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(accent.tint(scheme))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(accent.color)
            )
    }
}

/// Karta w stylu asystenta: tło kafla, cienki obrys, 20 pt.
struct AssistantSurfaceCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.scTileBg(scheme)))
            // Tła wierszy (podświetlony wiersz zgody, rozwinięty wiersz
            // akordeonu) to prostokąty — bez przycięcia wystawały z rogów.
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))
    }
}

/// Stopka przyklejona do dołu: treść chowa się pod miękkim gradientem tła,
/// jak w kreatorze „Poznajmy się". Wewnątrz przyciski w stylu `SCSoftButton`.
struct AssistantStickyFooter<Content: View>: View {
    /// Kolor tła ekranu pod stopką. Musi być DOKŁADNIE ten sam, co tło
    /// arkusza — inaczej nad przyciskiem wraca twarda linia. Domyślnie
    /// `scPageBase`; szczegóły posiłku mają własne, cieplejsze tło.
    var base: Color? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Wzór, z którego wyrosła wspólna stopka arkuszy — teraz jest nią.
        SCSheetFooter(base: base, content: content)
    }
}

/// Drugorzędny przycisk stopki — tekst bez wypełnienia, obok `SCSoftButton`.
struct AssistantTextButton: View {
    let title: String
    var role: ButtonRole? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(role == .destructive ? SCPalette.terracotta : Color.scMuted(scheme))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Możliwości (dane)

/// Jedna umiejętność Asystenta z przykładem, który arkusz „Co potrafi”
/// wysyła jednym stuknięciem.
///
/// Od wprowadzenia v2 (24.09.2026) bez opisów, odpowiedzi i miniatur kart:
/// pokazywały je tylko dawne karty „Poznaj” i rozwijane wiersze, a opisy
/// zdążyły się zestarzeć (wykluczenia i limit czasu gotowania zniknęły
/// z aplikacji, podmiana nie niesie powodu, zapis cofa się w oknie
/// z serwera, a nie „w ciągu doby”). Każdy przykład odpowiada narzędziu
/// Asystenta w backendzie (`src/agent/tools/agent-tools.ts`).
struct AssistantCapability: Identifiable {
    let id: String
    let icon: String
    let accent: AssistantAccent
    let title: String
    /// Wiadomość wysyłana po stuknięciu.
    let example: String
}

enum AssistantCapabilities {
    static let all: [AssistantCapability] = [
        // `propose_week_plan`
        .init(id: "week", icon: "sparkles", accent: .terracotta, title: "Plan całego tygodnia", example: "Zaplanuj cały tydzień, w tygodniu szybkie obiady"),
        // `propose_day_plan`
        .init(id: "day", icon: "calendar", accent: .terracotta, title: "Plan jednego dnia", example: "Ułóż mi czwartek pod 1800 kcal"),
        // `propose_swap` — karta pokazuje różnicę czasu i kalorii
        .init(id: "swap", icon: "arrow.triangle.2.circlepath", accent: .indigo, title: "Podmiana dania", example: "Podmień wtorkową kolację na coś bez laktozy do 30 minut"),
        // `offer_options`
        .init(id: "options", icon: "square.grid.2x2.fill", accent: .butter, title: "Kilka dań do wyboru", example: "Daj mi trzy szybkie kolacje do wyboru"),
        // `propose_remove_meal`
        .init(id: "remove", icon: "trash", accent: .indigo, title: "Zdjęcie dania z planu", example: "W czwartek jemy u teściów, zdejmij kolację"),
        // `show_macro_gap`
        .init(id: "macro", icon: "chart.bar.fill", accent: .indigo, title: "Domknięcie makro", example: "Czego brakuje w planie, żeby wyrobić się z białkiem?"),
        // `get_week_balance` z osobą
        .init(id: "scope", icon: "person.crop.circle.badge.checkmark", accent: .sage, title: "Dla kogo liczyć", example: "Policz bilans tylko dla mnie"),
        // `show_shopping_list`
        .init(id: "shopping", icon: "cart.fill", accent: .sage, title: "Lista zakupów z planu", example: "Co wyjdzie na liście zakupów z tego tygodnia?"),
        // `check_shopping_items` / `mark_meal_eaten`
        .init(id: "checkoff", icon: "checkmark.circle.fill", accent: .sage, title: "Odhaczanie zjedzonego i zakupów", example: "Kupiłem mleko i jajka"),
        // `get_recipe_details`
        .init(id: "cook", icon: "text.book.closed.fill", accent: .butter, title: "Skład i sposób przygotowania", example: "Jak ugotować ten czwartkowy obiad?"),
        // `search_recipes_by_ingredient`
        .init(id: "byingredient", icon: "magnifyingglass", accent: .butter, title: "Dania z tego, co masz", example: "Co mogę zrobić z bakłażanem?"),
        // `create_recipe` / `update_recipe`
        .init(id: "recipes", icon: "book.closed.fill", accent: .butter, title: "Własne przepisy", example: "Zapisz mój przepis na chili: 400 g indyka mielonego, puszka fasoli, passata, papryka…"),
        // `propose_swap` dla wybranych osób — reszta domu zostaje przy swoim
        .init(id: "split", icon: "person.2.fill", accent: .sage, title: "Osobne danie dla kogoś", example: "Ania nie je ryb, zrób jej coś innego w piątek"),
        // `remember_note`
        .init(id: "memory", icon: "brain.head.profile", accent: .indigo, title: "Pamięć domu", example: "Zapamiętaj, że w piątki jemy rybę"),
    ]

    static func by(_ id: String) -> AssistantCapability {
        all.first { $0.id == id } ?? all[0]
    }

    struct Group: Identifiable {
        let id: String
        let label: String
        let accent: AssistantAccent
        let lead: String
        let items: [String]
    }

    /// Pięć grup po tym, co użytkownik ROBI: planuje → liczy → kupuje →
    /// gotuje → dzieli na dom.
    static let groups: [Group] = [
        .init(id: "plan", label: "Plan i posiłki", accent: .terracotta, lead: "Najczęściej", items: ["week", "day", "options", "swap", "remove"]),
        .init(id: "goal", label: "Cel i makro", accent: .indigo, lead: "Pod Twoje zapotrzebowanie", items: ["macro", "scope"]),
        .init(id: "shopping", label: "Zakupy", accent: .sage, lead: "Z planu do sklepu", items: ["shopping", "checkoff"]),
        .init(id: "recipes", label: "Przepisy", accent: .butter, lead: "Katalog i Wasze dania", items: ["cook", "byingredient", "recipes"]),
        .init(id: "home", label: "Domownicy", accent: .sage, lead: "Różne osoby, jeden plan", items: ["split", "memory"]),
    ]
}
