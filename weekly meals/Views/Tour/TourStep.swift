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
    let summary: String
    /// Trzy konkrety pod opisem. Trzy, nie dwa jak w designie — przy dwóch
    /// pod tekstem zostawała pusta strefa, a czwarty punkt spycha stepper
    /// pod krawędź na mniejszych ekranach.
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
            accent: WMPalette.terracotta,
            title: "Zaplanuj tydzień w pięć minut",
            summary: "Wybierz przepis, wskaż dzień i porę. Zmiana pojawia się u wszystkich domowników od razu.",
            points: [
                "Śniadanie, obiad, kolacja i przekąski",
                "Kalorie i makro liczone na każdy dzień",
                "Każdy domownik może jeść po swojemu",
            ],
            imageName: "TourPlan"
        ),
        TourStep(
            id: "recipes",
            place: "Zakładce Przepisy",
            placeIcon: MenuConstans.Recipes.icon,
            accent: WMPalette.sage,
            title: "Przepisy dopasowane do Was",
            summary: "Filtruj po czasie, diecie i kaloriach. Ulubione zostają pod ręką w osobnej kolekcji.",
            points: [
                "Filtry: czas, dieta, kalorie, trudność",
                "Składniki i kroki na jednym ekranie",
                "Przepis wyślesz prosto na Thermomix",
            ],
            imageName: "TourRecipes"
        ),
        TourStep(
            id: "shopping",
            place: "Planie, pod koszykiem",
            placeIcon: MenuConstans.Products.icon,
            accent: WMPalette.indigo,
            title: "Lista zakupów robi się sama",
            summary: "Z planu tygodnia składamy jedną listę, pogrupowaną po działach sklepu. Odhaczacie ją razem, na żywo.",
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
            accent: WMPalette.butter,
            title: "Zapytaj, gdy brakuje pomysłu",
            summary: "Napisz, co macie w lodówce albo ile zostało czasu. Asystent zaproponuje posiłek i doda go do planu.",
            points: [
                "Propozycje z tego, co macie pod ręką",
                "Podmiana dania jednym tapnięciem",
                "Pamięta ustalenia — „w środy jemy u teściów”",
            ],
            imageName: "TourAssistant"
        ),
        TourStep(
            id: "settings",
            place: "Ustawieniach",
            placeIcon: MenuConstans.Settings.icon,
            accent: WMPalette.terracottaDeep,
            title: "Ustaw wszystko pod siebie",
            summary: "Cel kaloryczny, dieta, alergeny i pory posiłków — plan i przepisy dopasowują się do tych ustawień.",
            points: [
                "Cel, makroskładniki, dieta i alergeny",
                "Posiłki w planie i godziny, o których jecie",
                "Zaproszenie domowników do gospodarstwa",
            ],
            imageName: "TourSettings"
        ),
    ]
}
