import SwiftUI

/// Szukanie na Przepisach jak w Poczcie na iOS 26 (Rafał 4.10.2026: „na dole
/// wyszukiwarka, po lewej button od filtrów”): pływający pasek NAD dolnym
/// menu — szklany krążek filtrów z plakietką liczby filtrów i szklana kapsuła
/// pola. Przy fokusie z prawej dochodzi krążek z krzyżykiem (koniec szukania:
/// czyści frazę i chowa klawiaturę), a cały pasek jedzie nad klawiaturą
/// (`safeAreaBar` w `recipesSearchDock`).
///
/// Drugi — obok pola Asystenta — pływający wyjątek od `SCSearchField`:
/// stoi na treści, nie w niej, więc ma wysokość krążków paska (50 pt).
struct RecipesSearchBar: View {
    @Binding var text: String
    /// Podpowiedź w polu — w kategorii „Szukaj w obiadach”
    /// (`RecipesConstants.searchPrompt(for:)`), bo tam szuka się w niej.
    var prompt: String = "Szukaj przepisów"
    /// Grupy filtrów z arkusza „Filtry” — plakietka i tint krążka.
    let activeFilterCount: Int
    var onSubmit: () -> Void = {}
    let onOpenFilters: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var scheme

    static let height: CGFloat = 50

    private var hasFilters: Bool { activeFilterCount > 0 }

    var body: some View {
        // Bez `GlassEffectContainer` (6.10.2026): w grupie szkła krążek filtrów
        // przestał przyjmować stuknięcia pod systemowym `TabView` („zero
        // reakcji”), a plakietka musiała wisieć w osobnej nakładce, bo grupa ją
        // przycinała. Każde szkło osobno, plakietka wprost na krążku.
        HStack(spacing: 10) {
            filterButton
                // Plakietka wystaje poza krążek — nad polem, nie pod nim.
                .zIndex(1)
            field
            if isFocused {
                closeButton
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isFocused)
    }

    // MARK: Filtry

    private var filterButton: some View {
        Button(action: onOpenFilters) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.sc(size: 17, weight: .semibold))
                .foregroundStyle(hasFilters ? SCPalette.terracotta : Color.scLabel(scheme))
                .frame(width: Self.height, height: Self.height)
                .scChromeGlass(
                    in: Circle(),
                    tint: hasFilters ? SCPalette.terracotta.opacity(scheme == .dark ? 0.3 : 0.22) : nil
                )
                .contentShape(Circle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.92))
        .scCountBadge(activeFilterCount, offset: CGSize(width: 2, height: -2))
        .accessibilityLabel(hasFilters ? "Filtry, aktywne: \(activeFilterCount)" : "Filtry")
    }

    // MARK: Pole

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.sc(size: 16, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))

            TextField(prompt, text: $text)
                .font(.sc(size: 16.5))
                .foregroundStyle(Color.scLabel(scheme))
                .tint(SCPalette.terracotta)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
            // Bez krzyżyka w polu — czyści krążek obok (Rafał 4.10.2026: „nie
            // musi być X, bo jest obok jako osobny button”).
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .scChromeGlass(in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
        // Stuknięcie gdziekolwiek w kapsułę — nie tylko w sam tekst.
        .onTapGesture { isFocused = true }
    }

    // MARK: Koniec szukania

    private var closeButton: some View {
        Button {
            text = ""
            isFocused = false
        } label: {
            Image(systemName: "xmark")
                .font(.sc(size: 15, weight: .bold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: Self.height, height: Self.height)
                .scChromeGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.92))
        .accessibilityLabel("Zakończ szukanie")
    }
}

// MARK: - Przyczepienie

extension View {
    /// Pływający pasek szukania Przepisów przyczepiony nad systemowym paskiem
    /// zakładek — JEDNA droga dla korzenia i ekranu kategorii (zmieniać razem).
    /// Pasek bezpiecznego obszaru: lista przejeżdża pod szkłem i kończy się nad
    /// nim, przy klawiaturze jedzie nad nią, a pod paskiem leży natywny, miękki
    /// efekt krawędzi przewijania (jak w Poczcie na iOS 26).
    func recipesSearchDock(_ bar: RecipesSearchBar, horizontalPadding: CGFloat) -> some View {
        safeAreaBar(edge: .bottom, spacing: 0) {
            bar
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 8)
        }
        // Miękki, jawnie — `.automatic` z Xcode Cloud wychodził jako `.hard`
        // (kreska i kryjące tło, patrz `scSheetFooterEdge`).
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}
