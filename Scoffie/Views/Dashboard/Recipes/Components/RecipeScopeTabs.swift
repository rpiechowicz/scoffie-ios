import SwiftUI

/// Szybki zakres na Przepisach — szklane zakładki „Wszystkie · Śniadania ·
/// Obiady · Kolacje · Przekąski · Ulubione” pod tytułem (Rafał 4.10.2026:
/// „główne szybko dostępne filtry jako tab liquid… jak już mamy wyszukane,
/// np. kuskus, móc wybrać obiady od razu”). Świadomy wyjątek od „zawężanie
/// tylko w arkuszu filtrów”: to nie cecha przepisu, tylko pora — ta sama
/// oś, co sekcje widoku.
///
/// Wybór = stan wyników (płaska lista tej kategorii). Przy frazie albo
/// filtrach każda zakładka mówi, ile trafień w niej leży (`counts`), więc
/// widać, gdzie szukać, zanim się stuknie. Ponowne stuknięcie wybranej
/// wraca do „Wszystkie”.
struct RecipeScopeTabs: View {
    @Binding var selection: RecipesCategory?
    /// Trafienia na zakładkę — tylko przy frazie / filtrach; `nil` = bez liczb.
    var counts: [RecipesCategory: Int]? = nil
    var total: Int? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Soczewka zaznaczenia przejeżdża między zakładkami.
    @Namespace private var lens

    static let scopes: [RecipesCategory] = RecipesCategory.catalogSections + [.favourite]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        tab(
                            id: "all",
                            title: "Wszystkie",
                            icon: RecipesConstants.icon(for: .all),
                            accent: SCPalette.terracotta,
                            count: total,
                            isOn: selection == nil
                        ) {
                            select(nil)
                        }

                        ForEach(Self.scopes, id: \.self) { scope in
                            tab(
                                id: "\(scope)",
                                title: Self.title(for: scope),
                                icon: RecipesConstants.icon(for: scope),
                                accent: Self.accent(for: scope),
                                count: counts.map { $0[scope] ?? 0 },
                                isOn: selection == scope
                            ) {
                                select(selection == scope ? nil : scope)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.hidden)
            // Cień szkła i plakietki nie urywają się na brzegu przewijania.
            .scrollClipDisabled()
            .sensoryFeedback(.selection, trigger: selection)
            .onChange(of: selection) { _, value in
                withAnimation(.smooth(duration: 0.3)) {
                    proxy.scrollTo(value.map { "\($0)" } ?? "all", anchor: .center)
                }
            }
        }
    }

    /// Sprężyna soczewki — krótka, z lekkim dobiciem, jak przełączniki iOS 26.
    private var lensMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.78)
    }

    private func select(_ scope: RecipesCategory?) {
        withAnimation(lensMotion) { selection = scope }
    }

    private func tab(
        id: String,
        title: String,
        icon: String,
        accent: Color,
        count: Int?,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(accent)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(isOn ? accent : Color.scLabel(scheme))
                    .lineLimit(1)

                if let count {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 12.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? accent : Color.scMuted(scheme))
                        .contentTransition(.numericText(value: Double(count)))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            // Zaznaczenie to JEDNA soczewka w kolorze kategorii, która
            // przejeżdża sprężyną do stukniętej zakładki i po drodze zmienia
            // barwę (Rafał 4.10.2026: „animacja zmiany stanu buttonu tab”).
            // Dawniej tint przeskakiwał z kapsuły na kapsułę w jednej klatce.
            .background {
                if isOn {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(scheme == .dark ? 0.3 : 0.2))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(accent.opacity(scheme == .dark ? 0.45 : 0.3), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "scope-lens", in: lens)
                }
            }
            .scChromeGlass(in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .opacity(count == 0 && !isOn ? 0.55 : 1)
            // Stuknięta zakładka lekko „przyjmuje” soczewkę.
            .scaleEffect(isOn ? 1 : 0.97)
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .id(id)
        .animation(SCMotion.textRoll, value: count)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    static func title(for scope: RecipesCategory) -> String {
        scope == .favourite ? "Ulubione" : RecipesConstants.shortDisplayName(for: scope)
    }

    static func accent(for scope: RecipesCategory) -> Color {
        scope == .favourite ? SCPalette.terracotta : RecipeAccent.accent(for: scope)
    }

    /// Czy przepis leży w zakresie — ulubione po sercu, reszta po kategorii.
    static func contains(_ recipe: Recipe, in scope: RecipesCategory) -> Bool {
        scope == .favourite ? recipe.favourite : recipe.category == scope
    }
}
