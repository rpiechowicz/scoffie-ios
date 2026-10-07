import SwiftUI

// Klocki arkusza „Co potrafi Asystent” (menu ⋯) i kilku arkuszy planów:
// akcenty, karta na żetonach aplikacji i dane umiejętności. Od wprowadzenia
// v2 (24.09.2026) bez podglądów rozmowy i miniatur kart — pokazywały je tylko
// dawne karty „Poznaj”, zastąpione żywymi scenkami w `AssistantIntroPages.swift`.
// 7.10.2026: bez kafelka w tincie (`AssistantIconTile`), stopki
// (`AssistantStickyFooter`) i przycisku tekstowego (`AssistantTextButton`) —
// nikt ich już nie używał; wiersz „Co potrafi” stoi na `EditorialSettingsRow`.

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
        // `check_shopping_items` / `mark_meal_eaten`
        .init(id: "checkoff", icon: "checkmark.circle.fill", accent: .sage, title: "Odhaczanie zjedzonego i zakupów", example: "Kupiłem mleko i jajka"),
        // `get_recipe_details`
        // Nie „jak ugotować” — kroki i skład są w szczegółach posiłku.
        .init(id: "cook", icon: "arrow.left.arrow.right", accent: .butter, title: "Zamienniki składników", example: "Czym zastąpić śmietanę w czwartkowym obiedzie?"),
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
        // Bez „Lista zakupów z planu” (27.09.2026) — lista jest w Planie →
        // Zakupy, a pytanie o nią telefon przechwytuje (`AssistantAppShortcut`).
        .init(id: "shopping", label: "Zakupy", accent: .sage, lead: "Z planu do sklepu", items: ["checkoff"]),
        .init(id: "recipes", label: "Przepisy", accent: .butter, lead: "Katalog i Wasze dania", items: ["cook", "byingredient", "recipes"]),
        .init(id: "home", label: "Domownicy", accent: .sage, lead: "Różne osoby, jeden plan", items: ["split", "memory"]),
    ]
}
