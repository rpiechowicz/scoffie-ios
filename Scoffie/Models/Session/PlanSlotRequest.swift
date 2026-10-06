import Foundation

/// Prośba zakładki „Dziś” do Planu: pokaż ten dzień i — gdy jest pora —
/// otwórz wybór przepisu na nią (pusta pora → „Zaplanuj”).
///
/// Planowanie ma JEDNO miejsce, Plan; „Dziś” tylko tam prowadzi. Prośba idzie
/// przez `SessionStore.planSlotRequest`, a nie przez menu zakładek: Plan
/// odbiera ją w `onChange(initial: true)` (także wtedy, gdy dopiero się
/// buduje) i sam ją zdejmuje — ta sama droga co `opensShoppingList`.
struct PlanSlotRequest: Equatable {
    /// Każda prośba jest nowa — dwa stuknięcia w tę samą porę to dwie prośby.
    let id = UUID()
    /// Dzień do pokazania w Planie.
    let date: Date
    /// Pora do zaplanowania. `nil` = sam dzień, bez wyboru przepisu (pusty
    /// dzień w „Dziś” nie wskazuje żadnej pory).
    let slot: MealSlot?
    /// „Dla kogo” na starcie wyboru: `[]` = cały dom (pora jest pusta dla
    /// wszystkich), `[ja]` = pora pusta tylko dla mnie, a ktoś już ma w niej
    /// swoje danie — dokładamy moje obok, zamiast proponować zamianę jego.
    let participantIds: [String]
}
