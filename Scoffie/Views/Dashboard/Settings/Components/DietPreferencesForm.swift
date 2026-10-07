import SwiftUI

// Treść „Diety i alergenów” — JEDNA dla arkusza Ustawień (`SettingsView.dietSheet`)
// i kroku „Dieta” kreatora (`WelcomeDietStep`).
//
// Od liczby do skutku (6.10.2026, artefakt „Arkusze Ustawień”, sekcja 3):
// kalorie, zaraz pod nimi makro, które się z nich liczy, potem cel (jego
// „Ustaw” siedzi w karcie kalorii), dieta i alergeny, które odsiewają przepisy.
//
// 7.10.2026 (Rafał: „zrób na onboarding user te nowe widoki z ustawień…
// uspójnij to”): kreator pytał o to samo w dwóch krokach własnymi kartami
// (cel z długimi podpisami, kalorie z suwakiem nad liczbą, makro jako paski).
// Teraz to te same sekcje, a różnice to tryby:
// - `macroOverrides` — Ustawienia nadpisują makro stepperami; kreator (`nil`)
//   pokazuje sam wynik, bo zapis z kreatora nie wysyła nadpisań;
// - `onEditAllergens` — Ustawienia wpychają wybór alergenów w stos arkusza;
//   kreator (`nil`) otwiera go jako arkusz (`AllergenSelectionField`);
// - `onOpenProfile` — odsyłacz „Twoje dane ›”, gdy sylwetki brakuje; kreator
//   ma ją zawsze (krok 1), więc go nie podaje.

/// Ręczne nadpisania makro (−1 = „licz za mnie”) — tylko w Ustawieniach.
struct DietMacroOverrides {
    var protein: Binding<Int>
    var carbs: Binding<Int>
    var fat: Binding<Int>

    var isActive: Bool {
        protein.wrappedValue >= 0 || carbs.wrappedValue >= 0 || fat.wrappedValue >= 0
    }

    func reset() {
        protein.wrappedValue = -1
        fat.wrappedValue = -1
        carbs.wrappedValue = -1
    }
}

struct DietPreferencesForm: View {
    @Binding var calorieGoal: Int
    @Binding var goal: UserGoal
    @Binding var diet: DietPreference
    /// Sylwetka z „Twoich danych” — podpowiedź kaloryczna celu i makro.
    /// `nil`, gdy brakuje którejś danej.
    let metrics: BodyMetrics?
    let allergens: Set<Allergen>
    /// Ile przepisów ukrywają same alergeny — `nil`, dopóki nie ma katalogu.
    let allergenHiddenRecipes: Int?
    let onToggleAllergen: (Allergen) -> Void
    let onClearAllergens: () -> Void
    var onEditAllergens: (() -> Void)?
    var macroOverrides: DietMacroOverrides?
    var onOpenProfile: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    init(
        calorieGoal: Binding<Int>,
        goal: Binding<UserGoal>,
        diet: Binding<DietPreference>,
        metrics: BodyMetrics?,
        allergens: Set<Allergen>,
        allergenHiddenRecipes: Int?,
        onToggleAllergen: @escaping (Allergen) -> Void,
        onClearAllergens: @escaping () -> Void,
        onEditAllergens: (() -> Void)? = nil,
        macroOverrides: DietMacroOverrides? = nil,
        onOpenProfile: (() -> Void)? = nil
    ) {
        _calorieGoal = calorieGoal
        _goal = goal
        _diet = diet
        self.metrics = metrics
        self.allergens = allergens
        self.allergenHiddenRecipes = allergenHiddenRecipes
        self.onToggleAllergen = onToggleAllergen
        self.onClearAllergens = onClearAllergens
        self.onEditAllergens = onEditAllergens
        self.macroOverrides = macroOverrides
        self.onOpenProfile = onOpenProfile
    }

    // Calorie goal range — 1200 kcal is the lower medical safety bound for
    // adults; 3500 covers heavy training. 50 kcal step keeps the slider
    // tactile without snapping to silly precision.
    static let calorieGoalMin: Int = 1200
    static let calorieGoalMax: Int = 3500
    static let calorieGoalStep: Int = 50
    static let calorieGoalDefault: Int = 2000

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            calorieGoalSection
            macroSection
            goalPickerSection
            dietPickerSection
            allergensSection
        }
    }

    // MARK: - Kalorie

    private var suggestedCalories: Int {
        goal.suggestedCalories(for: metrics)
    }

    /// Karta „Kalorie”: wiersz „Dzienny cel” z dużą liczbą po prawej, suwak
    /// co 50 kcal z podpisami skrajnych wartości (`CalorieGoalEditor`), a na
    /// dole podpowiedź celu z „Ustaw” (6.10.2026 — dawniej pod listą celów).
    private var calorieGoalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Kalorie")

            VStack(spacing: 0) {
                CalorieGoalEditor(
                    calorieGoal: $calorieGoal,
                    range: Self.calorieGoalMin...Self.calorieGoalMax,
                    step: Self.calorieGoalStep
                )
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)

                if showsCalorieSuggestion {
                    calorieSuggestionRow
                        .transition(.opacity)
                }
            }
            .background(cardShape.fill(Color.scTileBg(scheme)))
            .overlay(cardShape.stroke(Color.scTileStroke(scheme), lineWidth: 1))
            .clipShape(cardShape)
        }
    }

    /// Cel niesie ze sobą sugerowaną kaloryczność, ale ustawiony suwak jest
    /// decyzją użytkownika — więc podpowiadamy przyciskiem zamiast nadpisywać.
    /// Kreator idzie za celem sam, dopóki nikt nie ruszył suwaka, więc u niego
    /// podpowiedź pokazuje się dopiero po ręcznej zmianie.
    private var showsCalorieSuggestion: Bool {
        goal != .plan && calorieGoal != suggestedCalories
    }

    /// Dwa warianty: policzony z sylwetki (wtedy mówimy skąd) i awaryjny,
    /// gdy w profilu brakuje danych. Drugi zachęca do ich uzupełnienia,
    /// zamiast udawać, że liczba jest szyta na miarę.
    private var calorieSuggestionText: String {
        guard metrics != nil else {
            return "Dla tego celu zwykle wychodzi \(suggestedCalories) kcal"
        }
        return "Dla celu „\(goal.title)” wychodzi \(suggestedCalories) kcal"
    }

    /// Podpowiedź na dole karty kalorii: żarówka, zdanie i „Ustaw”. Bez
    /// sylwetki pod zdaniem odsyłacz „Twoje dane ›”.
    private var calorieSuggestionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.sc(size: 15, weight: .semibold))
                .foregroundStyle(SCPalette.butter)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(calorieSuggestionText)
                    .font(.sc(size: 13, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)

                // Odsyłacz do sylwetki prowadzi TAM, w tym samym arkuszu —
                // zamiast kazać zamknąć dietę i szukać karty profilu.
                if metrics == nil {
                    openProfileLink
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.smooth(duration: 0.22)) {
                    calorieGoal = snappedCalorieGoal(from: Double(suggestedCalories))
                }
            } label: {
                Text("Ustaw")
                    .font(.sc(size: 12, weight: .bold))
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    // Wariant „soft” = szkło w tincie terakoty.
                    .scSoftCapsule()
            }
            .buttonStyle(PlanPressStyle(scale: 0.94))
            .accessibilityLabel("Ustaw \(suggestedCalories) kcal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(SCPalette.butter.opacity(scheme == .dark ? 0.10 : 0.07))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)
        }
    }

    /// Round an arbitrary slider value to the nearest 50-kcal step and
    /// clamp it to the [min, max] range. Defensive against the rare
    /// off-end value the UISlider can emit at the extremes.
    private func snappedCalorieGoal(from raw: Double) -> Int {
        let stepped = (raw / Double(Self.calorieGoalStep)).rounded() * Double(Self.calorieGoalStep)
        return min(max(Int(stepped), Self.calorieGoalMin), Self.calorieGoalMax)
    }

    /// „Twoje dane ›” — odsyłacz do sylwetki. Ustawienia wpychają ekran
    /// „Twoje dane” w arkusz diety; „wstecz” wraca do diety z policzonymi
    /// już kaloriami i makro. Bez `onOpenProfile` (kreator) — nic.
    @ViewBuilder
    private var openProfileLink: some View {
        if let onOpenProfile {
            Button(action: onOpenProfile) {
                HStack(spacing: 3) {
                    Text("Twoje dane")
                        .font(.sc(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.sc(size: 11, weight: .bold))
                }
                .foregroundStyle(SCPalette.terracotta)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.96))
            .accessibilityHint("Otwiera wzrost, wagę i rok urodzenia")
        }
    }

    // MARK: - Makroskładniki
    //
    // Domyślnie liczone z celu, sylwetki i liczby treningów — użytkownik nie
    // musi nic robić i wartości same podążają, gdy zmieni cel albo dołoży
    // treningów. W Ustawieniach każde makro da się jednak nadpisać: „max
    // 2200 kcal, ale 160 g białka" to normalny sposób prowadzenia redukcji
    // i aplikacja nie ma prawa go blokować.

    /// To, co realnie obowiązuje: ręczne nadpisanie, a w jego braku wyliczenie
    /// z celu kalorycznego, sylwetki i liczby treningów (`DailyNutritionTargets`
    /// — ta sama reguła co pigułka i „Cel dnia” w Planie). `nil`, gdy w profilu
    /// brakuje danych.
    private var effectiveMacros: MacroTargets? {
        DailyNutritionTargets.resolve(
            calorieGoal: calorieGoal,
            goal: goal,
            metrics: metrics,
            proteinOverride: macroOverrides?.protein.wrappedValue ?? -1,
            fatOverride: macroOverrides?.fat.wrappedValue ?? -1,
            carbsOverride: macroOverrides?.carbs.wrappedValue ?? -1
        ).macros
    }

    private var hasMacroOverride: Bool {
        macroOverrides?.isActive ?? false
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Makroskładniki")

            VStack(alignment: .leading, spacing: 0) {
                if let macros = effectiveMacros {
                    macroRow(.protein, value: macros.proteinG, override: macroOverrides?.protein)
                    macroDivider
                    macroRow(.carbs, value: macros.carbsG, override: macroOverrides?.carbs)
                    macroDivider
                    macroRow(.fat, value: macros.fatG, override: macroOverrides?.fat)
                    // Kreska nad stopką idzie na pełną szerokość, bo stopka
                    // ma własne tło rozciągnięte od krawędzi do krawędzi —
                    // wcięta kreska kończyła się w innym miejscu niż kolor
                    // pod nią i wyglądało to na niedoróbkę.
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                    macroFooter(macros)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Uzupełnij sylwetkę w „Twoje dane”, a rozbijemy dzienny cel na białko, węglowodany i tłuszcze.")
                            .font(.sc(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        openProfileLink
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .background(cardShape.fill(Color.scTileBg(scheme)))
            .overlay(cardShape.stroke(Color.scTileStroke(scheme), lineWidth: 1))
            .clipShape(cardShape)
        }
    }

    private var macroDivider: some View {
        Rectangle()
            .fill(Color.scRule(scheme))
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private enum Macro {
        case protein, carbs, fat

        var title: String {
            switch self {
            case .protein: return "Białko"
            case .carbs:   return "Węglowodany"
            case .fat:     return "Tłuszcze"
            }
        }

        var accent: Color {
            switch self {
            case .protein: return SCPalette.indigo
            case .carbs:   return SCPalette.sage
            case .fat:     return SCPalette.butter
            }
        }

        /// Ten sam krok, do którego zaokrąglane są wyliczenia — inaczej
        /// stepper wyprowadzałby wartość z siatki („193 g") i pół karty
        /// pokazywałoby okrągłe liczby, a pół nie.
        var step: Int { MacroTargets.gramStep }

        var upperBound: Int {
            switch self {
            case .protein: return 400
            case .carbs:   return 800
            case .fat:     return 300
            }
        }
    }

    /// Wiersz makro. Bez `override` (kreator) — sama liczba, bez steppera.
    private func macroRow(_ macro: Macro, value: Int, override: Binding<Int>?) -> some View {
        let isOverridden = (override?.wrappedValue ?? -1) >= 0

        return HStack(spacing: 12) {
            Circle()
                .fill(macro.accent)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(macro.title)
                    .font(.sc(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))

                Text(isOverridden ? "Twoja wartość" : "Wyliczone")
                    .font(.sc(size: 11, weight: .medium))
                    .foregroundStyle(isOverridden ? macro.accent : Color.scFaint(scheme))
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.sc(size: 17, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(value)))

                Text("g")
                    .font(.sc(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .frame(minWidth: 58, alignment: .trailing)

            if let override {
                macroStepper(macro, value: value, override: override)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.smooth(duration: 0.18), value: value)
    }

    /// Minus / plus zamiast pola tekstowego. Makra reguluje się o kilka
    /// gramów w jedną albo drugą stronę, a nie wpisuje od zera — a przy okazji
    /// nie ma tu żadnego stanu pośredniego do zepsucia.
    private func macroStepper(_ macro: Macro, value: Int, override: Binding<Int>) -> some View {
        HStack(spacing: 0) {
            macroStepButton(systemName: "minus", accent: macro.accent) {
                override.wrappedValue = MacroTargets.snappedGrams(Double(value - macro.step))
            }

            Rectangle()
                .fill(Color.scTileStroke(scheme))
                .frame(width: 1, height: 18)

            macroStepButton(systemName: "plus", accent: macro.accent) {
                let next = MacroTargets.snappedGrams(Double(value + macro.step))
                override.wrappedValue = min(next, macro.upperBound)
            }
        }
        .background(Capsule().fill(Color.scChipBg(scheme)))
        .overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
        .accessibilityLabel(macro.title)
        .accessibilityValue("\(value) gramów")
    }

    private func macroStepButton(
        systemName: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.18)) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.sc(size: 12, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Suma makr rzadko trafia w cel co do kilokalorii — i nie musi. Pokazujemy
    /// ją wprost, żeby po ręcznym podkręceniu białka było widać, że dzienna
    /// pula przestała się spinać, zamiast zostawiać użytkownika z trzema
    /// liczbami bez kontekstu.
    private func macroFooter(_ macros: MacroTargets) -> some View {
        let diff = macros.totalKcal - calorieGoal

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Z makr: \(macros.totalKcal) kcal")
                    .font(.sc(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))

                Text(macroFooterNote(diff: diff))
                    .font(.sc(size: 11.5, weight: .medium))
                    .foregroundStyle(abs(diff) > 60 ? SCPalette.terracotta : Color.scMuted(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasMacroOverride, let macroOverrides {
                Button {
                    withAnimation(.smooth(duration: 0.22)) { macroOverrides.reset() }
                } label: {
                    Text("Policz od nowa")
                        .font(.sc(size: 12, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .scSoftCapsule()
                }
                .buttonStyle(PlanPressStyle(scale: 0.94))
                .accessibilityLabel("Policz makra od nowa")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.scChipBg(scheme).opacity(scheme == .dark ? 0.5 : 0.7))
    }

    private func macroFooterNote(diff: Int) -> String {
        if abs(diff) <= 20 { return "Spina się z dziennym celem" }
        if diff > 0 { return "\(diff) kcal ponad cel" }
        return "\(abs(diff)) kcal poniżej celu"
    }

    // MARK: - Twój cel
    //
    // Cel nie odsiewa przepisów; przestawia kolejność listy (patrz
    // `RecipePersonalization.goalScore`). Jego podpowiedź kaloryczna („Ustaw”)
    // siedzi w karcie kalorii wyżej.

    private var goalPickerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Twój cel")

            VStack(spacing: 0) {
                ForEach(Array(UserGoal.allCases.enumerated()), id: \.element.id) { idx, candidate in
                    goalRow(candidate, isLast: idx == UserGoal.allCases.count - 1)
                }
            }
            .background(cardShape.fill(Color.scTileBg(scheme)))
            .overlay(cardShape.stroke(Color.scTileStroke(scheme), lineWidth: 1))
            .clipShape(cardShape)
        }
    }

    private func goalRow(_ candidate: UserGoal, isLast: Bool) -> some View {
        let isSelected = candidate == goal

        return Button {
            withAnimation(.smooth(duration: 0.20)) {
                goal = candidate
            }
        } label: {
            choiceRowLabel(
                icon: candidate.icon,
                accent: candidate.accent,
                title: candidate.title,
                subtitle: Self.goalShortSubtitle(candidate),
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast { choiceRowRule }
        }
        .accessibilityLabel(candidate.title)
        .accessibilityValue(isSelected ? "Wybrane" : "")
    }

    /// Podpisy celów w jednej linii — krótsze niż `UserGoal.subtitle`.
    private static func goalShortSubtitle(_ goal: UserGoal) -> String {
        switch goal {
        case .healthy:  return "Zbilansowane, mniej przetworzonych"
        case .lose:     return "Lekki deficyt kaloryczny"
        case .gain:     return "Nadwyżka kaloryczna z białkiem"
        case .maintain: return "Kalorie na utrzymanie"
        case .plan:     return "Bez celu kalorycznego"
        }
    }

    // MARK: - Sposób odżywiania

    private var dietPickerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Sposób odżywiania")

            VStack(spacing: 0) {
                ForEach(Array(DietPreference.allCases.enumerated()), id: \.element.id) { idx, candidate in
                    dietRow(candidate, isLast: idx == DietPreference.allCases.count - 1)
                }
            }
            .background(cardShape.fill(Color.scTileBg(scheme)))
            .overlay(cardShape.stroke(Color.scTileStroke(scheme), lineWidth: 1))
            .clipShape(cardShape)
        }
    }

    private func dietRow(_ candidate: DietPreference, isLast: Bool) -> some View {
        let isSelected = candidate == diet

        return Button {
            withAnimation(.smooth(duration: 0.20)) {
                diet = candidate
            }
        } label: {
            // Dokładnie ta sama geometria co `goalRow` — obie sekcje to ta
            // sama lista wyboru i mają wyglądać identycznie.
            choiceRowLabel(
                icon: candidate.icon,
                accent: candidate.accent,
                title: candidate.title,
                subtitle: Self.dietShortSubtitle(candidate),
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !isLast { choiceRowRule }
        }
        .accessibilityLabel(candidate.title)
        .accessibilityValue(isSelected ? "Wybrane" : "")
    }

    /// Podpisy diet w jednej linii — krótsze niż `DietPreference.subtitle`.
    private static func dietShortSubtitle(_ diet: DietPreference) -> String {
        switch diet {
        case .none:        return "Wszystkie przepisy"
        case .vegetarian:  return "Bez mięsa i ryb"
        case .vegan:       return "Bez produktów odzwierzęcych"
        case .pescatarian: return "Bez mięsa, z rybami"
        case .keto:        return "Bardzo mało węglowodanów"
        case .paleo:       return "Bez zbóż, nabiału i przetworzonych"
        case .highProtein: return "Min. 20 % kalorii z białka"
        }
    }

    /// Wiersz wyboru celu i diety — wymiary wiersza Ustawień
    /// (`EditorialSettingsRow`: kafelek 30, tytuł 15, wiersz 52, kreska od
    /// tytułu), podpis w JEDNEJ linii, kółko wyboru po prawej.
    private func choiceRowLabel(
        icon: String,
        accent: Color,
        title: String,
        subtitle: String,
        isSelected: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            EditorialSettingsTileIcon(icon: icon, color: accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.sc(size: 12.5, weight: .regular))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SCRadioMark(isOn: isSelected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    private var choiceRowRule: some View {
        Rectangle()
            .fill(Color.scRule(scheme))
            .frame(height: 1)
            .padding(.leading, 12 + 30 + 12)
    }

    // MARK: - Alergeny

    /// Alergeny to sam wynik — co jest wykluczone i ile przepisów przez to
    /// znika. Wybór: w Ustawieniach wepchnięty ekran (`onEditAllergens`),
    /// w kreatorze arkusz (`AllergenSelectionField` sam go prezentuje).
    private var allergensSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Alergeny i nietolerancje")

            AllergenSelectionField(
                selected: allergens,
                hiddenRecipes: allergenHiddenRecipes,
                onToggle: onToggleAllergen,
                onClear: onClearAllergens,
                onEdit: onEditAllergens
            )

            Text("Dieta i alergeny odsiewają przepisy, cel ustawia je na liście.")
                .font(.sc(size: 12.5))
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.top, 8)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }
}

/// Wiersz „Dzienny cel” z dużą liczbą po prawej i suwak pod nim
/// (6.10.2026 — dawniej liczba 44 pt NAD suwakiem). Liczba stoi w tym samym
/// widoku co suwak, bo pod palcem pokazuje wartość z `draft`.
///
/// W trakcie przeciągania wartość żyje TYLKO tutaj, a do `@AppStorage`
/// trafia po puszczeniu. Wcześniej każdy krok suwaka (co 50 kcal, kilkanaście
/// razy na sekundę) zapisywał `UserDefaults` — a na ten klucz patrzy cały
/// arkusz diety (makro, podpowiedź celu, liczenie ukrytych przepisów), całe
/// Ustawienia i zakładki pod arkuszem (ranking Przepisów, cel dnia w Planie
/// i Kalendarzu). Każdy krok przebudowywał je wszystkie, a liczba dodatkowo
/// rolowała się animacją, której następny krok nie dawał dojechać — suwak
/// szedł za palcem z opóźnieniem. Zapis na serwer i tak czekał na koniec
/// (`dietPreferencesSyncToken`), więc nic się nie traci.
private struct CalorieGoalEditor: View {
    @Binding var calorieGoal: Int
    let range: ClosedRange<Int>
    let step: Int

    @Environment(\.colorScheme) private var scheme
    /// Wartość pod palcem; `nil`, gdy nikt nie przeciąga.
    @State private var draft: Int?
    @State private var isEditing = false

    private var shown: Int { draft ?? calorieGoal }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                EditorialSettingsTileIcon(icon: "flame.fill", color: SettingsAccent.coral)

                Text("Dzienny cel")
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(shown, format: .number.grouping(.never))
                        .font(.sc(size: 28, weight: .heavy))
                        .tracking(-0.8)
                        .foregroundStyle(SCPalette.terracotta)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown)))
                        // Roluje też pod palcem. Animacja siedzi na SAMEJ liczbie
                        // i jest krótka, więc kolejny krok przejmuje ją w locie
                        // zamiast czekać na koniec; zapis do @AppStorage i tak idzie
                        // dopiero po puszczeniu (to on dławił suwak, nie rolowanie).
                        .animation(
                            isEditing ? .snappy(duration: 0.14) : .smooth(duration: 0.22),
                            value: shown
                        )

                    Text("kcal")
                        .font(.sc(size: 13, weight: .bold))
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
            .frame(minHeight: 40)

            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(shown) },
                        set: { raw in
                            let value = snapped(raw)
                            if isEditing {
                                if value != draft { draft = value }
                            } else if value != calorieGoal {
                                // VoiceOver (przesunięcie w górę / w dół) nie
                                // przeciąga — zapisuje od razu.
                                calorieGoal = value
                            }
                        }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step),
                    onEditingChanged: { editing in
                        isEditing = editing
                        guard !editing else { return }
                        if let draft, draft != calorieGoal {
                            calorieGoal = draft
                        }
                        draft = nil
                    }
                )
                .tint(SCPalette.terracotta)
                .accessibilityLabel("Dzienny cel w kcal")

                HStack {
                    Text("\(range.lowerBound)")
                    Spacer()
                    Text("\(range.upperBound)")
                }
                .font(.sc(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
                .accessibilityHidden(true)
            }
        }
    }

    /// Najbliższy krok co 50 kcal, w granicach skali — UISlider potrafi
    /// oddać wartość tuż za końcem.
    private func snapped(_ raw: Double) -> Int {
        let stepped = (raw / Double(step)).rounded() * Double(step)
        return min(max(Int(stepped), range.lowerBound), range.upperBound)
    }
}
