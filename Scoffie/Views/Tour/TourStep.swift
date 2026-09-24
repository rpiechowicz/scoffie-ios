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
    /// Dwa zdania pod tytułem: o co w tym chodzi, zwykłym językiem, zanim
    /// padną konkrety. Sam tytuł i lista funkcji czytały się jak specyfikacja
    /// (Rafał 24.09.2026: „więcej opisu pod title… bardziej friendly”).
    let lead: String
    /// Konkrety pod tytułem, każdy z własną ikoną w karcie (`TourPointsCard`,
    /// wiersze jak `SCStepFeatureCard` na powitaniu i ekranie końcowym).
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

/// Jeden punkt kroku: ikona w kafelku (tint koloru kroku) i jedno zdanie.
struct TourPoint: Identifiable {
    let icon: String
    let text: String

    var id: String { text }
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
            lead: "Rozkładasz posiłki na dni tygodnia jak w kalendarzu — i nikt już nie musi pytać, co dziś na obiad.",
            points: [
                TourPoint(icon: "fork.knife", text: "Od śniadania po przekąski — tyle pór, ile jecie"),
                TourPoint(icon: "flame.fill", text: "Kalorie i makro na każdy dzień i każdą osobę"),
                TourPoint(icon: "person.2.fill", text: "Zmiany widzi od razu cały dom"),
                TourPoint(icon: "bell.fill", text: "Przypomnienie, kiedy zacząć gotować"),
            ],
            imageName: "TourPlan",
            isArtwork: true
        ),
        TourStep(
            id: "recipes",
            eyebrow: "Zakładka Przepisy",
            accent: SCPalette.sage,
            title: "Przepisy dopasowane do Was",
            lead: "Kilkaset dań z kaloriami, makro i czasem gotowania. Te z Twoimi alergenami chowamy same, a filtry odsieją resztę tego, czego nie jecie.",
            points: [
                TourPoint(icon: "slider.horizontal.3", text: "Filtry: czas, kalorie, trudność, dieta i składniki"),
                TourPoint(icon: "plusminus", text: "Porcje przeliczają składniki i makro"),
                TourPoint(icon: "list.bullet.rectangle.fill", text: "Składniki po działach i kroki na jednym ekranie"),
                TourPoint(icon: "heart.fill", text: "Ulubione pod sercem — i pod ręką w planie"),
            ],
            imageName: "TourRecipes",
            isArtwork: true
        ),
        TourStep(
            id: "shopping",
            eyebrow: "Plan · pod koszykiem",
            accent: SCPalette.indigo,
            title: "Lista zakupów robi się sama",
            lead: "Nie musisz niczego przepisywać. Składniki ze wszystkich dań w planie zbierają się w jedną listę, ułożoną po działach sklepu.",
            points: [
                TourPoint(icon: "square.grid.2x2.fill", text: "Produkty po działach sklepu"),
                TourPoint(icon: "sun.max.fill", text: "„Na dziś” — braki na dzisiejsze dania"),
                TourPoint(icon: "checkmark.circle.fill", text: "Odhaczanie widoczne u drugiej osoby od razu"),
                TourPoint(icon: "clock.arrow.circlepath", text: "Zamknięte listy zostają w historii"),
            ],
            imageName: "TourShopping"
        ),
        TourStep(
            id: "assistant",
            eyebrow: "Zakładka Asystent",
            accent: SCPalette.butter,
            title: "Zapytaj, gdy brakuje pomysłu",
            lead: "Napisz zwyczajnie, czego potrzebujesz — „lekki obiad na jutro” albo „tydzień bez mięsa”. Asystent zaproponuje dania, a Ty decydujesz, co trafi do planu.",
            points: [
                TourPoint(icon: "calendar", text: "Dzień albo tydzień z katalogu przepisów"),
                TourPoint(icon: "arrow.triangle.2.circlepath", text: "Podmiana dania z różnicą kalorii i czasu"),
                TourPoint(icon: "checkmark.shield.fill", text: "Pilnuje alergenów i celu kalorii"),
                TourPoint(icon: "hand.thumbsup.fill", text: "Nic nie trafia do planu bez Twojej zgody"),
            ],
            imageName: "TourAssistant"
        ),
        TourStep(
            id: "settings",
            eyebrow: "Ustawienia",
            accent: SCPalette.terracottaDeep,
            title: "Ustaw wszystko pod siebie",
            lead: "Wszystko, o co zaraz zapytamy, zmienisz tu później jednym stuknięciem — cel, dietę, godziny posiłków i domowników.",
            points: [
                TourPoint(icon: "target", text: "Cel, makroskładniki, dieta i alergeny"),
                TourPoint(icon: "clock.fill", text: "Posiłki w planie i godziny, o których jecie"),
                TourPoint(icon: "person.badge.plus", text: "Zaproszenie domowników do gospodarstwa"),
                TourPoint(icon: "bell.badge.fill", text: "Poranny przegląd i przypomnienia o porach"),
            ],
            imageName: "TourSettings"
        ),
    ]
}
