import SwiftUI

/// Jeden krok przewodnika „Poznaj aplikację".
///
/// Treść siedzi w danych, a nie w widoku, bo kroków jest pięć i każdy ma
/// identyczny układ — różni je wyłącznie zdjęcie, akcent i tekst.
struct TourStep: Identifiable {
    let id: String
    /// Gdzie w aplikacji szukać tej funkcji — eyebrow nad tytułem w kolorze
    /// kroku („Zakładka Plan”), jak w nagłówkach arkuszy. Do 24.09.2026
    /// stała tu kapsułka „Znajdziesz w…” nad zdjęciem: trzeci styl nagłówka
    /// w jednym przepływie, obok logo powitania i kafelka kreatora.
    let eyebrow: String
    let accent: Color
    let title: String
    /// Najwyżej dwie linie pod tytułem: o co w tym chodzi, zwykłym językiem, zanim
    /// padną konkrety. Sam tytuł i lista funkcji czytały się jak specyfikacja
    /// (Rafał 24.09.2026: „więcej opisu pod title… bardziej friendly”).
    let lead: String
    /// Konkrety pod tytułem: ikona, tytuł i podpis w `SCStepFeatureCard` —
    /// tej samej karcie, co na powitaniu i ekranie końcowym.
    /// Od 24.09.2026 cztery, nie trzy: każdy punkt to funkcja, która JEST
    /// w aplikacji (źródła przy `TourStep.all`), a nie obietnica. Czwarty
    /// punkt mieści się dzięki ciaśniejszej karcie; na iPhonie SE zdjęcie
    /// kroku przycina się do wysokości (`TourMedia`), a stopka stoi osobno.
    let points: [TourPoint]
    let imageName: String
    /// Ilustracja z kartami aplikacji skomponowana do brzegu (Plan,
    /// Przepisy) — pokazywana w całości, w swoich proporcjach. `false` =
    /// render telefonów z marginesem, kadrowany 16:13 (`TourMedia`).
    var isArtwork: Bool = false
}

/// Jeden punkt kroku: ikona w kafelku (tint koloru kroku), tytuł i krótki
/// podpis — ten sam wiersz, co na powitaniu i ekranie „Teraz my poznajmy
/// Ciebie” (`SCStepFeatureCard`). Do 24.09.2026 jedno zdanie bez podpisu —
/// trzy różne listy w jednym przepływie (Rafał: „dopracuj te wszystkie
/// listy, aby były podobne”).
struct TourPoint: Identifiable {
    let icon: String
    let title: String
    let subtitle: String

    var id: String { title }
}

extension TourStep {
    /// Kolejność jak w aplikacji od lewej: Przepisy zaczynają, Ustawienia
    /// domykają — ostatni krok prowadzi wprost do kreatora, który te
    /// ustawienia wypełnia.
    ///
    /// Każdy punkt sprawdzony w kodzie 24.09.2026 (zmieniasz funkcję —
    /// zajrzyj tutaj):
    /// - Plan: pory — `MealSlot` (6 pór) i „Posiłki w planie” w Ustawieniach;
    ///   kcal i makro na osobę — `PlanDayGoalSheet` (przełącznik osób);
    ///   „widzi cały dom” — `WeeklyPlanStore` na gnieździe (`PlanChangeNotificationService`);
    ///   przypomnienia — `MealReminderService` (gotowanie / pora posiłku).
    /// - Przepisy: filtry — `RecipeFilterState` (`maxPrepTimeMinutes`,
    ///   `maxCaloriesPerServing`, `difficulty`, `diets`, `excludedIngredients`);
    ///   porcje — stepper w nagłówku „Wartości odżywcze” (`RecipeDetail`);
    ///   składniki po działach i „Przygotowanie” — `RecipeDetail`; ulubione —
    ///   `RecipeFavouriteButton` + „Ulubione” w `PlanSlotPickerSheet`.
    ///   (Zdjęte: „Własne przepisy domu obok katalogu” — w aplikacji nie ma
    ///   tworzenia przepisów, gniazdo zna tylko `recipes:findAll/findById/setFavorite`.)
    /// - Zakupy: działy — `ShoppingAisleSection`; „Na dziś” — `ShoppingTodaySheet`;
    ///   odhaczanie na żywo — `WebSocketShoppingListTransportClient`; historia —
    ///   `ShoppingHistorySheet`.
    /// - Asystent: dzień / tydzień — karty propozycji (`AssistantCards`), z
    ///   katalogu, nie z „Waszych przepisów”; podmiana — `SwapCardDTO.deltas`
    ///   („−230 kcal”, „−18 min”; osobnego powodu karta nie ma); alergeny —
    ///   walidator planu w backendzie (FAQ „Jakie alergeny zna aplikacja?”);
    ///   zgoda — `ProposalAcceptButton` (nic nie zapisuje się samo).
    /// - Ustawienia: `SettingsView` — „Dieta i alergeny” z `macroSection`,
    ///   „Posiłki w planie” (`MealDayTimesCard`), „Gospodarstwo” (zaproszenia),
    ///   „Powiadomienia” (poranny przegląd, pory posiłków).
    static let all: [TourStep] = [
        TourStep(
            id: "plan",
            eyebrow: "Zakładka Plan",
            accent: SCPalette.terracotta,
            title: "Zaplanuj tydzień w pięć minut",
            lead: "Rozkładasz posiłki na dni tygodnia — i nikt już nie musi pytać, co dziś na obiad.",
            points: [
                TourPoint(icon: "fork.knife", title: "Tyle posiłków, ile jecie", subtitle: "Od śniadania po przekąski"),
                TourPoint(icon: "flame.fill", title: "Kalorie i makro", subtitle: "Na każdy dzień i każdą osobę"),
                TourPoint(icon: "person.2.fill", title: "Wspólny plan", subtitle: "Zmiany widzi od razu cały dom"),
                TourPoint(icon: "bell.fill", title: "Przypomnienia", subtitle: "Kiedy zacząć gotować"),
            ],
            imageName: "TourPlan",
            isArtwork: true
        ),
        TourStep(
            id: "recipes",
            eyebrow: "Zakładka Przepisy",
            accent: SCPalette.sage,
            title: "Przepisy dopasowane do Was",
            lead: "Kilkaset dań z kaloriami i czasem gotowania. Te z Twoimi alergenami chowamy same.",
            points: [
                TourPoint(icon: "slider.horizontal.3", title: "Filtry", subtitle: "Czas, kalorie, trudność, dieta, składniki"),
                TourPoint(icon: "plusminus", title: "Porcje", subtitle: "Przeliczają składniki i makro"),
                TourPoint(icon: "list.bullet.rectangle.fill", title: "Składniki i kroki", subtitle: "Po działach, na jednym ekranie"),
                TourPoint(icon: "heart.fill", title: "Ulubione", subtitle: "Pod sercem — i pod ręką w planie"),
            ],
            imageName: "TourRecipes",
            isArtwork: true
        ),
        TourStep(
            id: "shopping",
            eyebrow: "Plan · pod koszykiem",
            accent: SCPalette.indigo,
            title: "Lista zakupów robi się sama",
            lead: "Nie musisz niczego przepisywać — składniki z całego planu zbierają się w jedną listę.",
            points: [
                TourPoint(icon: "square.grid.2x2.fill", title: "Po działach sklepu", subtitle: "Alejka po alejce"),
                TourPoint(icon: "sun.max.fill", title: "„Na dziś”", subtitle: "Braki na dzisiejsze dania"),
                TourPoint(icon: "checkmark.circle.fill", title: "Wspólne odhaczanie", subtitle: "Druga osoba widzi je od razu"),
                TourPoint(icon: "clock.arrow.circlepath", title: "Historia", subtitle: "Zamknięte listy zostają pod ręką"),
            ],
            imageName: "TourShopping"
        ),
        TourStep(
            id: "assistant",
            eyebrow: "Zakładka Asystent",
            accent: SCPalette.butter,
            title: "Zapytaj, gdy brakuje pomysłu",
            lead: "Napisz, czego potrzebujesz. Asystent zaproponuje dania, a Ty wybierzesz.",
            points: [
                TourPoint(icon: "calendar", title: "Dzień albo tydzień", subtitle: "Z katalogu przepisów"),
                TourPoint(icon: "arrow.triangle.2.circlepath", title: "Podmiana dania", subtitle: "Z różnicą kalorii i czasu"),
                TourPoint(icon: "checkmark.shield.fill", title: "Alergeny i cel", subtitle: "Pilnuje ich w każdej propozycji"),
                TourPoint(icon: "hand.thumbsup.fill", title: "Ty decydujesz", subtitle: "Nic nie trafia do planu bez zgody"),
            ],
            imageName: "TourAssistant"
        ),
        TourStep(
            id: "settings",
            eyebrow: "Ustawienia",
            accent: SCPalette.terracottaDeep,
            title: "Ustaw wszystko pod siebie",
            lead: "Wszystko, o co zaraz zapytamy, zmienisz tu później jednym stuknięciem.",
            points: [
                TourPoint(icon: "target", title: "Cel i makro", subtitle: "Dieta i alergeny w jednym miejscu"),
                TourPoint(icon: "clock.fill", title: "Posiłki w planie", subtitle: "I godziny, o których jecie"),
                TourPoint(icon: "person.badge.plus", title: "Domownicy", subtitle: "Zaproś ich do gospodarstwa"),
                TourPoint(icon: "bell.badge.fill", title: "Powiadomienia", subtitle: "Poranny przegląd i pory posiłków"),
            ],
            imageName: "TourSettings"
        ),
    ]
}

/// Klucz „przewodnik obejrzany".
///
/// Trzymany w `UserDefaults`, a nie na serwerze, bo dotyczy urządzenia, nie
/// konta — i celowo kasowany w `SessionStore.clearPersistedSession()`.
/// Bez tego kasowania wylogowanie i ponowne zalogowanie (także na cudze
/// konto) omijałoby przewodnik, bo flaga przeżywa w `UserDefaults` sesję,
/// po której została ustawiona.
enum TourCompletion {
    static let storageKey = "onboarding.tourCompleted"
}
