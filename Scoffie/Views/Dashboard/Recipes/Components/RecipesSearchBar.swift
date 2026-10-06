import SwiftUI

/// Szukanie na Przepisach jak w Poczcie na iOS 26 (Rafał 4.10.2026: „na dole
/// wyszukiwarka, po lewej button od filtrów”): pływający pasek NAD dolnym
/// menu — szklany krążek filtrów z plakietką liczby filtrów i szklana kapsuła
/// pola. Przy fokusie z prawej dochodzi krążek z krzyżykiem (koniec szukania:
/// czyści frazę i chowa klawiaturę), a cały pasek jedzie nad klawiaturą
/// (`safeAreaBar` w `recipesSearchDock`).
///
/// Gdy systemowy pasek zakładek zwinie się przy przewijaniu do jednej ikony
/// po lewej, pasek szukania ZJEŻDŻA w jego wiersz, na prawo od tej ikony —
/// jak akcesorium w Muzyce (Rafał 6.10.2026: „nav się scala do 1 ikony po
/// lewej, a filter zostaje i to się nie skleja”). Przy fokusie zostaje nad
/// klawiaturą.
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
    /// Systemowy pasek zakładek jest zwinięty (`recipesTracksTabBarMinimize`).
    var besideMinimizedTabBar: Bool = false

    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var scheme

    static let height: CGFloat = 50

    /// O ile pasek zjeżdża w wiersz zwiniętego paska zakładek. Liczone na
    /// iOS 26: wiersz paska zakładek ma 62 pt i zaczyna się tam, gdzie kończy
    /// się bezpieczny obszar treści; pasek szukania stoi 8 pt nad nim, a po
    /// zjeździe ma stać na środku tego wiersza (62 / 2 + 50 / 2 + 8).
    /// DO DOSTROJENIA na urządzeniu, jeśli wiersze się rozjadą.
    static let besideTabBarDrop: CGFloat = 64
    /// Ile miejsca po lewej zostawić zwiniętej ikonie zakładek — krążek ~56 pt
    /// przy ~21 pt marginesu systemu, 10 pt przerwy, minus 20 pt marginesu,
    /// który pasek ma i tak. Też do dostrojenia na urządzeniu.
    static let besideTabBarLeading: CGFloat = 67
    /// Ruch zjazdu — sprężyna o czasie zwijania systemowego paska.
    static let dockMotion: Animation = .spring(response: 0.42, dampingFraction: 0.8)

    private var hasFilters: Bool { activeFilterCount > 0 }

    var body: some View {
        // Przy pisaniu pasek stoi nad klawiaturą, nigdy w wierszu zakładek.
        let docked = besideMinimizedTabBar && !isFocused

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
        .padding(.leading, docked ? Self.besideTabBarLeading : 0)
        .offset(y: docked ? Self.besideTabBarDrop : 0)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isFocused)
        .animation(Self.dockMotion, value: docked)
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

// MARK: - Zwinięty pasek zakładek

/// Czy systemowy pasek zakładek jest teraz zwinięty do jednej ikony
/// (`tabBarMinimizeBehavior(.onScrollDown)` w `NavigationMenu`).
///
/// iOS 26 nie mówi tego publicznie poza akcesorium paska
/// (`tabViewBottomAccessoryPlacement`), a akcesorium z polem tekstowym
/// zostawałoby przy pisaniu pod klawiaturą. Liczymy więc to samo, co system —
/// z kierunku przewijania: w dół zwija, w górę i przy samej górze rozwija.
/// Ostrożnie w jedną stronę: zwija dopiero po 24 pt w dół (pasek szukania
/// zjechany na ROZWINIĘTY pasek zakładek nachodziłby na niego), rozwija już
/// po 4 pt w górę.
private struct RecipesTabBarMinimizeTracker: ViewModifier {
    @Binding var isMinimized: Bool
    /// Droga w bieżącym kierunku — dodatnia w dół, ujemna w górę.
    @State private var travel: CGFloat = 0

    private static let topZone: CGFloat = 12
    private static let collapseTravel: CGFloat = 24
    private static let expandTravel: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { old, new in
                track(from: old, to: new)
            }
    }

    private func track(from old: CGFloat, to new: CGFloat) {
        if new <= Self.topZone {
            travel = 0
            set(false)
            return
        }
        let delta = new - old
        guard delta != 0 else { return }
        travel = delta > 0 ? max(travel, 0) + delta : min(travel, 0) + delta
        if travel >= Self.collapseTravel {
            set(true)
        } else if travel <= -Self.expandTravel {
            set(false)
        }
    }

    private func set(_ minimized: Bool) {
        guard isMinimized != minimized else { return }
        isMinimized = minimized
    }
}

extension View {
    /// Na `ScrollView` listy Przepisów (korzeń i kategoria): melduje, czy
    /// systemowy pasek zakładek jest zwinięty — patrz `RecipesTabBarMinimizeTracker`.
    func recipesTracksTabBarMinimize(_ isMinimized: Binding<Bool>) -> some View {
        modifier(RecipesTabBarMinimizeTracker(isMinimized: isMinimized))
    }

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
