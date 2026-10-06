import SwiftUI

/// Powitanie (WL1) — treść pod zdjęciem na wspólnym ekranie trybu
/// (`CookScreen`): co gotujesz, liczby (czas, trudność, kroki) i opis
/// przepisu. Porcje, szuflady i „Zaczynamy” są w stopce
/// (`CookWelcomeFooter`) — runda 6: „gotujesz porcje nad składnikami, a pod
/// czasem / trudnością daj opis przepisu”. Sprzętu nie pokazujemy (§13.1).
///
/// Runda 7: całe powitanie mieści się na ekranie BEZ przewijania (iPhone
/// 16e: 844 pt) — tytuł 32, opis najwyżej trzy linie, w stopce porcje 52 pt
/// i obie szuflady w jednym rzędzie. Na mniejszym ekranie treść przewija się
/// pod stopką jak wcześniej.
///
/// Ruch: sekcje wjeżdżają kaskadą (jak szczegóły posiłku), liczby w meta
/// liczą się od zera.
struct CookWelcomeContent: View {
    let session: CookSession
    let recipe: CookRecipeFacts

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SCCook.Spacing.titleTop)

            VStack(alignment: .leading, spacing: 0) {
                Text(eyebrow)
                    .cookText(SCCook.Typography.stage)
                    .foregroundStyle(SCPalette.sage)

                Text(recipe.headline)
                    .cookText(SCCook.Typography.welcomeTitle)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle = recipe.subtitle {
                    Text(subtitle)
                        .font(.sc(size: 16, weight: .semibold))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .cookReveal(hasAppeared, order: 0)

            meta
                .padding(.top, 10)
                .cookReveal(hasAppeared, order: 1)

            if let description = recipe.description {
                // Opisy katalogu mają ~180 znaków (4 linie) — trzy linie
                // i wielokropek, żeby powitanie nie wymagało przewijania.
                Text(description)
                    .cookText(SCCook.Typography.note)
                    .lineSpacing(3)
                    .lineLimit(3)
                    .foregroundStyle(SCCook.Palette.body(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .cookReveal(hasAppeared, order: 2)
            }

            Color.clear.frame(height: 8)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
    }

    private var eyebrow: String {
        guard let raw = session.mealSlotRaw, let slot = MealSlot(rawValue: raw) else { return "GOTUJEMY" }
        return "GOTUJEMY · \(slot.title.uppercased(with: Locale(identifier: "pl_PL")))"
    }

    /// Liczby liczą się od zera przy wejściu (`SCCountingText`) — razem
    /// z kaskadą, a nie zanim rząd się pokaże.
    private var meta: some View {
        let count = session.stepCount
        return HStack(spacing: 16) {
            metaItem(icon: "clock", text: "ok. \(session.scenario.totalMinutes) min", counts: true)
            metaItem(icon: "chart.bar.fill", text: recipe.difficultyText, counts: false)
            metaItem(icon: "list.bullet", text: "\(count) \(PolishPlural.form(count, one: "krok", few: "kroki", many: "kroków"))", counts: true)
        }
        .font(.sc(size: 14, weight: .semibold))
        .foregroundStyle(Color.scMuted(scheme))
        // Wąski ekran: rząd maleje, zamiast ucinać słowa.
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func metaItem(icon: String, text: String, counts: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.sc(size: 13, weight: .semibold))
            if counts {
                SCCountingText(text, loadAnimation: .easeOut(duration: 0.9).delay(0.2))
            } else {
                Text(text)
            }
        }
    }
}

/// Szuflada powitania — co otwiera jej arkusz.
enum CookWelcomeDrawer {
    case ingredients
    case tips
}

/// Stopka powitania: porcje, szuflady Składniki i Rady kucharza,
/// „Zaczynamy” — na płycie stopki aplikacji (`SCSheetFooter`), we wspólnej
/// stopce ekranu trybu (`CookScreen`). Porcje stoją NAD składnikami (runda
/// 6), bo to od nich zależą ilości w szufladzie; zmieniają się tylko w tej
/// sesji — plan zostaje (D11). Zmiana porcji roluje liczby w karcie,
/// stepperze i podpisie szuflady. Szuflady to dwa kafle OBOK SIEBIE (runda 7
/// — jedna pod drugą nie mieściły się z resztą powitania bez przewijania).
struct CookWelcomeFooter: View {
    let session: CookSession
    let onPortions: (Double) -> Void
    let onOpen: (CookSheet) -> Void
    let onStart: () -> Void

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SCSheetFooter(horizontalPadding: SCCook.Spacing.page, reservesShade: true) {
            // 12 między kaflami (było 8 — Rafał 4.10.2026: „większy space
            // pomiędzy kaflami”).
            VStack(spacing: 12) {
                servingsCard
                    .cookReveal(hasAppeared, order: 3)
                HStack(spacing: 12) {
                    drawerButton(.ingredients)
                    if !session.scenario.tips.isEmpty {
                        drawerButton(.tips)
                    }
                }
                .cookReveal(hasAppeared, order: 4)
                CookPrimaryButton(title: "Zaczynamy", trailingIcon: "arrow.right", action: onStart)
                    .cookReveal(hasAppeared, order: 5)
            }
        }
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
    }

    /// Kafel szuflady na pół szerokości: ikona, nazwa, podpis z liczbą.
    private func drawerButton(_ kind: CookWelcomeDrawer) -> some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous)
        let summary = drawerSummary(kind)
        return Button {
            onOpen(kind == .tips ? .tips : .recipeIngredients)
        } label: {
            HStack(spacing: 10) {
                // Jedna ikona na szufladę — Składniki tak samo jak Rady
                // kucharza (runda 6).
                drawerIcon(kind)
                VStack(alignment: .leading, spacing: 1) {
                    Text(drawerTitle(kind))
                        .font(.sc(size: 14, weight: .bold))
                        .foregroundStyle(Color.scLabel(scheme))
                    Text(summary)
                        .font(.sc(size: 12))
                        .foregroundStyle(Color.scMuted(scheme))
                        // Porcje w podpisie Składników rolują.
                        .contentTransition(.numericText())
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: SCCook.Height.drawer)
            // Karta aplikacji — jak karta porcji nad nią (runda 6).
            .background(shape.fill(Color.scTileBg(scheme)))
            .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(drawerTitle(kind)), \(summary)")
        .accessibilityAddTraits(.isButton)
    }

    private func drawerTitle(_ kind: CookWelcomeDrawer) -> String {
        switch kind {
        case .ingredients: "Składniki"
        case .tips: "Rady kucharza"
        }
    }

    /// „14 · na 2 porcje” — ilości w arkuszu idą za porcjami z karty nad
    /// kaflem; „3 rady”.
    private func drawerSummary(_ kind: CookWelcomeDrawer) -> String {
        switch kind {
        case .ingredients:
            "\(session.package.ingredients.count) · na \(CookPortionsText.accusative(session.portions))"
        case .tips:
            "\(session.scenario.tips.count) \(PolishPlural.form(session.scenario.tips.count, one: "rada", few: "rady", many: "rad"))"
        }
    }

    /// Krążek 32 z glifem w tincie akcentu — koszyk w terakocie (jak nagłówek
    /// arkusza Składniki), żarówka w maśle.
    private func drawerIcon(_ kind: CookWelcomeDrawer) -> some View {
        let accent = kind == .ingredients ? SCPalette.terracotta : SCPalette.butter
        return Image(systemName: kind == .ingredients ? "basket" : "lightbulb")
            .font(.sc(size: 14, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 32, height: 32)
            .background(Circle().fill(accent.opacity(scheme == .dark ? 0.16 : 0.12)))
            .accessibilityHidden(true)
    }

    private var servingsCard: some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gotujesz \(CookPortionsText.accusative(session.portions))")
                    .font(.sc(size: 16, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: session.portions))
                Text(servingsCaption)
                    .font(.sc(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)

            CookPortionStepper(value: session.portions, onChange: onPortions)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: SCCook.Height.servingsCard)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }

    private var servingsCaption: String {
        if session.portionsChanged { return "tylko na teraz — plan bez zmian" }
        return session.planDateKey != nil ? "tyle, ile w planie" : "tyle, ile w przepisie"
    }
}

/// To, co powitanie mówi o przepisie, a czego scenariusz nie niesie.
struct CookRecipeFacts {
    /// Nazwa do „ z ” — „Kotlet de volaille”.
    let headline: String
    /// Dopisek po „ z ” — „z ziemniakami i mizerią”.
    let subtitle: String?
    /// Opis przepisu pod liczbami powitania.
    let description: String?
    let difficultyText: String
    let kcalPerServing: Int?

    init(headline: String, subtitle: String?, description: String?, difficultyText: String, kcalPerServing: Int?) {
        self.headline = headline
        self.subtitle = subtitle
        self.description = description
        self.difficultyText = difficultyText
        self.kcalPerServing = kcalPerServing
    }
}

/// Stepper porcji z powitania — co pół porcji (4.10.2026), od 0,5 do 12,
/// na szklanej pigułce jak `SCStepper`.
struct CookPortionStepper: View {
    let value: Double
    let onChange: (Double) -> Void

    @Environment(\.colorScheme) private var scheme

    private var canDecrement: Bool { value > CookSession.portionStep }
    private var canIncrement: Bool { value < Double(CookSession.maxPortions) }

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: canDecrement, label: "Mniej porcji") { onChange(value - CookSession.portionStep) }
            Text(CookPortionsText.number(value))
                .font(.sc(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
                .frame(minWidth: 34)
                .contentTransition(.numericText(value: value))
            stepButton("plus", enabled: canIncrement, label: "Więcej porcji") { onChange(value + CookSession.portionStep) }
        }
        // Szklana pigułka jak `SCStepper` (Liquid Glass runda 3).
        .scChromeGlass(in: Capsule())
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Liczba porcji")
        .accessibilityValue(CookPortionsText.spoken(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrement { onChange(value + CookSession.portionStep) }
            case .decrement: if canDecrement { onChange(value - CookSession.portionStep) }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ systemName: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.sc(size: 13, weight: .bold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }
}

/// Porcje sesji słowami — „2 porcje”, „1,5 porcji” (ułamek z dopełniaczem),
/// w bierniku „na 2 porcje” / „na 1,5 porcji”. Przez jednostki porcji
/// planu (`PlanPortions`), żeby Gotuj mówił tak samo jak Plan.
enum CookPortionsText {
    static func number(_ portions: Double) -> String {
        PlanPortions.label(units: PlanPortions.units(fromServings: portions))
    }

    static func spoken(_ portions: Double) -> String {
        PlanPortions.spokenServings(units: PlanPortions.units(fromServings: portions), plural: PolishPlural.servings)
    }

    static func accusative(_ portions: Double) -> String {
        PlanPortions.spokenServings(units: PlanPortions.units(fromServings: portions), plural: PolishPlural.servingsAccusative)
    }
}

/// Przycisk pełnej szerokości trybu: miękka kapsuła 56 pt (`SCSoftButton`)
/// z wagą z tokenu — terakota 800, szałwia i neutralny 700.
struct CookPrimaryButton: View {
    let title: String
    var leadingIcon: String? = nil
    var trailingIcon: String? = nil
    var accent: Color = SCPalette.terracotta
    var style: SCCookTextStyle = SCCook.Typography.button
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.sc(size: 16, weight: .bold))
                }
                Text(title)
                    .cookText(style)
                    .lineLimit(1)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.sc(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: SCCook.Height.button)
            .scSoftCapsule(accent)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Arkusz szuflady powitania: cały przepis w ilościach sesji, w działach
/// sklepu, albo rady kucharza (makieta pokazuje szuflady tylko zwinięte —
/// docs/GOTUJ.md, ustalenie 6).
struct CookWelcomeDrawerSheet: View {
    let session: CookSession
    let drawer: CookWelcomeDrawer

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetHeader(
                eyebrow: drawer == .ingredients ? "NA \(CookPortionsText.accusative(session.portions).uppercased(with: Locale(identifier: "pl_PL")))" : "OD KUCHARZA",
                title: drawer == .ingredients ? "Składniki" : "Rady kucharza",
                icon: drawer == .ingredients ? "basket" : "lightbulb",
                accent: drawer == .ingredients ? SCPalette.terracotta : SCPalette.butter,
                onClose: { dismiss() }
            )
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.top, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch drawer {
                    case .ingredients:
                        // Działy sklepu jak w Zakupach i szczegółach przepisu
                        // (runda 4: „poukładaj składniki względem kategorii”);
                        // działy wchodzą kaskadą, po kolei.
                        ForEach(Array(aisles.enumerated()), id: \.element.id) { group, aisle in
                            VStack(alignment: .leading, spacing: 0) {
                                CookSectionHeader(
                                    title: aisle.title,
                                    color: CookIngredientLook.color(aisle.department),
                                    count: aisle.lines.count,
                                    icon: CookIngredientLook.icon(aisle.department)
                                )
                                ForEach(Array(aisle.lines.enumerated()), id: \.element.id) { offset, line in
                                    ingredientRow(line)
                                    if offset < aisle.lines.count - 1 {
                                        Rectangle().fill(Color.scChipBg(scheme)).frame(height: 1)
                                    }
                                }
                            }
                            .cookReveal(hasAppeared, order: min(group, 8))
                        }
                    case .tips:
                        ForEach(Array(session.scenario.tips.enumerated()), id: \.offset) { offset, tip in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "lightbulb")
                                    .font(.sc(size: 14, weight: .semibold))
                                    .foregroundStyle(SCPalette.butter)
                                Text(tip)
                                    .font(.sc(size: 16))
                                    .lineSpacing(4)
                                    .foregroundStyle(SCCook.Palette.body(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 12)
                            .cookReveal(hasAppeared, order: min(offset, 8))
                        }
                    }
                }
                .padding(.horizontal, SCCook.Spacing.page)
                .padding(.vertical, 16)
            }
            .scScrollEdgeFade()
        }
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
    }

    private var aisles: [CookIngredientAisle] {
        CookIngredientAisle.make(session.package.allLines(portions: session.portions))
    }

    /// Wiersz bez ikony — dział mówi nagłówek sekcji (runda 7).
    private func ingredientRow(_ line: CookIngredientLine) -> some View {
        HStack(spacing: 12) {
            Text(line.name)
                .font(.sc(size: 16, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(line.amountText)
                .font(.sc(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
        }
        .frame(minHeight: SCCook.Height.ingredientRow)
        .accessibilityElement(children: .combine)
    }
}
