import SwiftUI

/// Jeden krok przewodnika „Poznaj aplikację".
///
/// Treść siedzi w danych, a nie w widoku, bo kroków jest pięć i każdy ma
/// identyczny układ — różni je wyłącznie zdjęcie, akcent i tekst.
struct TourStep: Identifiable {
    let id: String
    /// Gdzie w aplikacji szukać tej funkcji. Chip pod statusbarem zastępuje
    /// mini pasek zakładek z designu: nazwa miejsca niesie tę informację
    /// wprost, a rysunek paska w skali 1:3 i tak byłby nieczytelny.
    let place: String
    let placeIcon: String
    let accent: Color
    let title: String
    /// Konkrety pod tytułem, każdy z ptaszkiem w karcie (`TourPointsCard`).
    /// Od 24.09.2026 cztery, nie trzy: każdy punkt to funkcja, która JEST
    /// w aplikacji (źródła przy `TourStep.all`), a nie obietnica. Czwarty
    /// punkt mieści się dzięki ciaśniejszej karcie; na iPhonie SE zdjęcie
    /// kroku przycina się do wysokości (`TourMedia`), a stopka stoi osobno.
    let points: [String]
    let imageName: String
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
            place: "Zakładce Plan",
            placeIcon: MenuConstans.Plan.icon,
            accent: SCPalette.terracotta,
            title: "Zaplanuj tydzień w pięć minut",
            points: [
                "Od śniadania po przekąski — tyle pór, ile jecie",
                "Kalorie i makro na każdy dzień i każdą osobę",
                "Zmiany widzi od razu cały dom",
                "Przypomnienie, kiedy zacząć gotować",
            ],
            imageName: "TourPlan"
        ),
        TourStep(
            id: "recipes",
            place: "Zakładce Przepisy",
            placeIcon: MenuConstans.Recipes.icon,
            accent: SCPalette.sage,
            title: "Przepisy dopasowane do Was",
            points: [
                "Filtry: czas, kalorie, trudność, dieta i składniki",
                "Porcje przeliczają składniki i makro",
                "Składniki po działach i kroki na jednym ekranie",
                "Ulubione pod sercem — i pod ręką w planie",
            ],
            imageName: "TourRecipes"
        ),
        TourStep(
            id: "shopping",
            place: "Planie, pod koszykiem",
            placeIcon: MenuConstans.Products.icon,
            accent: SCPalette.indigo,
            title: "Lista zakupów robi się sama",
            points: [
                "Produkty po działach sklepu",
                "„Na dziś” — braki na dzisiejsze dania",
                "Odhaczanie widoczne u drugiej osoby od razu",
                "Zamknięte listy zostają w historii",
            ],
            imageName: "TourShopping"
        ),
        TourStep(
            id: "assistant",
            place: "Zakładce Asystent",
            placeIcon: MenuConstans.Assistant.icon,
            accent: SCPalette.butter,
            title: "Zapytaj, gdy brakuje pomysłu",
            points: [
                "Dzień albo tydzień z katalogu przepisów",
                "Podmiana dania z różnicą kalorii i czasu",
                "Pilnuje alergenów i celu kalorii",
                "Nic nie trafia do planu bez Twojej zgody",
            ],
            imageName: "TourAssistant"
        ),
        TourStep(
            id: "settings",
            place: "Ustawieniach",
            placeIcon: MenuConstans.Settings.icon,
            accent: SCPalette.terracottaDeep,
            title: "Ustaw wszystko pod siebie",
            points: [
                "Cel, makroskładniki, dieta i alergeny",
                "Posiłki w planie i godziny, o których jecie",
                "Zaproszenie domowników do gospodarstwa",
                "Poranny przegląd i przypomnienia o porach",
            ],
            imageName: "TourSettings"
        ),
    ]
}
