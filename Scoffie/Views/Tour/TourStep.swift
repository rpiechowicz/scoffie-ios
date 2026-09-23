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
    /// Trzy konkrety pod tytułem — zamiast akapitu opisu (od 23.09.2026:
    /// „tylko najważniejsze”; opis mówił to samo co punkty, dłużej). Trzy,
    /// nie dwa jak w designie — przy dwóch zostawała pusta strefa, a czwarty
    /// punkt spycha stopkę pod krawędź na mniejszych ekranach.
    let points: [String]
    let imageName: String
}

extension TourStep {
    /// Kolejność jak w aplikacji od lewej: Przepisy zaczynają, Ustawienia
    /// domykają — ostatni krok prowadzi wprost do kreatora, który te
    /// ustawienia wypełnia.
    static let all: [TourStep] = [
        TourStep(
            id: "plan",
            place: "Zakładce Plan",
            placeIcon: MenuConstans.Plan.icon,
            accent: SCPalette.terracotta,
            title: "Zaplanuj tydzień w pięć minut",
            points: [
                "Śniadanie, obiad, kolacja i przekąski",
                "Kalorie i makro liczone na każdy dzień",
                "Zmiany widzi od razu cały dom",
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
                "Filtry: czas, dieta, kalorie, trudność",
                "Składniki i kroki na jednym ekranie",
                "Własne przepisy domu obok katalogu",
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
                "Warzywa, nabiał, pieczywo — po działach",
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
                "Plan tygodnia albo dnia z Waszych przepisów",
                "Podmiana dania z powodem i różnicą kalorii",
                "Propozycję dodajesz Ty — nic nie zapisuje się samo",
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
            ],
            imageName: "TourSettings"
        ),
    ]
}
