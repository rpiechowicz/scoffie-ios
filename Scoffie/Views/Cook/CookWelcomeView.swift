import SwiftUI

/// Powitanie (WL1) — treść pod zdjęciem na wspólnym ekranie trybu
/// (`CookScreen`): co gotujesz i dla ilu porcji. Szuflady i „Zaczynamy” są
/// w stopce (`CookWelcomeFooter`). Porcje zmieniają się tylko w tej sesji —
/// plan zostaje (D11). Sprzętu nie pokazujemy (§13.1).
///
/// Ruch: sekcje wjeżdżają kaskadą (jak szczegóły posiłku), liczby w meta
/// liczą się od zera, a zmiana porcji roluje liczby w karcie, stepperze
/// i skrócie składników.
struct CookWelcomeContent: View {
    let session: CookSession
    let recipe: CookRecipeFacts
    let onPortions: (Int) -> Void

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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .cookReveal(hasAppeared, order: 0)

            meta
                .padding(.top, 12)
                .cookReveal(hasAppeared, order: 1)

            servingsCard
                .padding(.top, 20)
                .cookReveal(hasAppeared, order: 2)

            Color.clear.frame(height: 24)
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
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.scMuted(scheme))
        // Wąski ekran: rząd maleje, zamiast ucinać słowa.
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func metaItem(icon: String, text: String, counts: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            if counts {
                SCCountingText(text, loadAnimation: .easeOut(duration: 0.9).delay(0.2))
            } else {
                Text(text)
            }
        }
    }

    private var servingsCard: some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gotujesz \(PolishPlural.servingsAccusative(session.portions))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(session.portions)))
                Text(servingsCaption)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CookPortionStepper(value: session.portions, onChange: onPortions)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: SCCook.Height.servingsCard)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }

    private var servingsCaption: String {
        if session.portionsChanged { return "tylko na teraz — plan bez zmian" }
        return session.planDateKey != nil ? "tyle, ile w planie" : "tyle, ile w przepisie"
    }
}

/// Szuflada powitania — co otwiera jej arkusz.
enum CookWelcomeDrawer {
    case ingredients
    case tips
}

/// Stopka powitania: szuflady Składniki i Rady kucharza, „Zaczynamy” — na
/// płycie stopki aplikacji (`SCSheetFooter`), w wspólnej stopce ekranu
/// trybu (`CookScreen`).
struct CookWelcomeFooter: View {
    let session: CookSession
    let onOpen: (CookSheet) -> Void
    let onStart: () -> Void

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        SCSheetFooter(horizontalPadding: SCCook.Spacing.page, reservesShade: true) {
            VStack(spacing: 12) {
                drawerButton(.ingredients)
                    .cookReveal(hasAppeared, order: 3)
                if !session.scenario.tips.isEmpty {
                    drawerButton(.tips)
                        .cookReveal(hasAppeared, order: 4)
                }
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

    private func drawerButton(_ kind: CookWelcomeDrawer) -> some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous)
        return Button {
            onOpen(kind == .tips ? .tips : .recipeIngredients)
        } label: {
            HStack(spacing: 14) {
                switch kind {
                case .ingredients:
                    ingredientStack
                case .tips:
                    Image(systemName: "lightbulb")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SCPalette.butter)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.scButterTint(scheme)))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(drawerTitle(kind))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.scLabel(scheme))
                    Text(drawerSummary(kind))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        // Ilości w skrócie idą za porcjami — rolują.
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .padding(.leading, 14)
            .padding(.trailing, 18)
            .frame(height: SCCook.Height.drawer)
            .background(shape.fill(SCCook.Palette.dockSurface(scheme)))
            .overlay(shape.strokeBorder(SCCook.Palette.dockStroke(scheme), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func drawerTitle(_ kind: CookWelcomeDrawer) -> String {
        switch kind {
        case .ingredients: "Składniki · \(session.package.ingredients.count)"
        case .tips: "Rady kucharza · \(session.scenario.tips.count)"
        }
    }

    private func drawerSummary(_ kind: CookWelcomeDrawer) -> String {
        switch kind {
        case .ingredients:
            session.package.allLines(portions: session.portions)
                .prefix(4)
                .map { "\($0.name.lowercased(with: Locale(identifier: "pl_PL"))) \($0.amountText)" }
                .joined(separator: " · ")
        case .tips:
            session.scenario.tips.first ?? ""
        }
    }

    /// Stos czterech ikon działów — kolor działu na pierścieniu tła strony
    /// (makieta: krążki 30 z obwódką `pageBase`, nachodzące o 8).
    private var ingredientStack: some View {
        let lines = Array(session.package.allLines(portions: session.portions).prefix(4))
        return HStack(spacing: -8) {
            ForEach(lines) { line in
                let tint = CookIngredientLook.color(line.department)
                Image(systemName: CookIngredientLook.icon(line.department))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(SCCook.Palette.dockSurface(scheme)))
                    .background(Circle().fill(tint.opacity(0.18)).padding(-0.5))
                    .overlay(Circle().strokeBorder(Color.scPageBase(scheme), lineWidth: 2).padding(-2))
            }
        }
        .accessibilityHidden(true)
    }
}

/// To, co powitanie mówi o przepisie, a czego scenariusz nie niesie.
struct CookRecipeFacts {
    /// Nazwa do „ z ” — „Kotlet de volaille”.
    let headline: String
    /// Dopisek po „ z ” — „z ziemniakami i mizerią”.
    let subtitle: String?
    let difficultyText: String
    let kcalPerServing: Int?

    init(headline: String, subtitle: String?, difficultyText: String, kcalPerServing: Int?) {
        self.headline = headline
        self.subtitle = subtitle
        self.difficultyText = difficultyText
        self.kcalPerServing = kcalPerServing
    }
}

/// Stepper porcji z powitania — wygląd steppera ze szczegółów przepisu
/// (przyciski 40 × 36, liczba 16 heavy) na żetonach aplikacji.
struct CookPortionStepper: View {
    let value: Int
    let onChange: (Int) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", enabled: value > 1, label: "Mniej porcji") { onChange(value - 1) }
            Text("\(value)")
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
                .frame(minWidth: 28)
                .contentTransition(.numericText(value: Double(value)))
            stepButton("plus", enabled: value < CookSession.maxPortions, label: "Więcej porcji") { onChange(value + 1) }
        }
        .background(Capsule().fill(Color.scChipBg(scheme)))
        .overlay(Capsule().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Liczba porcji")
        .accessibilityValue(PolishPlural.servings(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < CookSession.maxPortions { onChange(value + 1) }
            case .decrement: if value > 1 { onChange(value - 1) }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ systemName: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
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
                        .font(.system(size: 16, weight: .bold))
                }
                Text(title)
                    .cookText(style)
                    .lineLimit(1)
                if let trailingIcon {
                    Image(systemName: trailingIcon)
                        .font(.system(size: 16, weight: .bold))
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

/// Arkusz szuflady powitania: cały przepis w ilościach sesji albo rady
/// kucharza (makieta pokazuje szuflady tylko zwinięte — docs/GOTUJ.md, ustalenie 6).
struct CookWelcomeDrawerSheet: View {
    let session: CookSession
    let drawer: CookWelcomeDrawer

    @State private var hasAppeared = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetHeader(
                eyebrow: drawer == .ingredients ? "NA \(PolishPlural.servingsAccusative(session.portions).uppercased(with: Locale(identifier: "pl_PL")))" : "OD KUCHARZA",
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
                        ForEach(Array(lines.enumerated()), id: \.element.id) { offset, line in
                            VStack(spacing: 0) {
                                ingredientRow(line)
                                if offset < lines.count - 1 {
                                    Rectangle().fill(Color.scChipBg(scheme)).frame(height: 1)
                                }
                            }
                            // Wiersze wchodzą kaskadą — pierwsze osiem po
                            // kolei, reszta razem z ósmym.
                            .cookReveal(hasAppeared, order: min(offset, 8))
                        }
                    case .tips:
                        ForEach(Array(session.scenario.tips.enumerated()), id: \.offset) { offset, tip in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "lightbulb")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(SCPalette.butter)
                                Text(tip)
                                    .font(.system(size: 16))
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

    private var lines: [CookIngredientLine] {
        session.package.allLines(portions: session.portions)
    }

    private func ingredientRow(_ line: CookIngredientLine) -> some View {
        let tint = CookIngredientLook.color(line.department)
        return HStack(spacing: 12) {
            Image(systemName: CookIngredientLook.icon(line.department))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: SCCook.Size.ingredientIcon, height: SCCook.Size.ingredientIcon)
                .background(Circle().fill(tint.opacity(0.12)))
            Text(line.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(line.amountText)
                .font(.system(size: 16, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.scLabel(scheme))
        }
        .frame(minHeight: SCCook.Height.ingredientRow)
        .accessibilityElement(children: .combine)
    }
}
