import SwiftUI

// One meal on Kalendarz — compact row.
//
// Replaces the 260pt hero-photo card. Three of those filled more than two
// screens on an iPhone, so the day's actual shape — what you eat and whether
// you ate it — was never visible at once. This row is ~88pt, which puts all
// three meals plus the macro block above the fold.
//
// Layout: thumbnail · (eyebrow / title / meta) · eaten tick.
// The folio number (01/02/03) is gone with the hero — the slot eyebrow
// already says which meal this is, and three numbered circles cost 42pt of
// width to repeat it.
//
// Rząd urósł do ~128pt: przy trzech posiłkach dzień i tak mieści się nad
// zgięciem z zapasem, a większa miniatura sprawia, że jedzenie — nie
// typografia — jest tym, co widać pierwsze.
//
// Only one control sits on the row: the eaten tick. Favourite moved into the
// long-press context menu — it was costing a permanent 28pt slot on every
// meal for an action taken once in a while, and the row reads calmer with a
// single obvious target. Nothing is lost: the menu also carries the eaten
// toggle, so both actions have a discoverable home.
struct EditorialMealCard: View {
    let slot: MealSlot
    /// One variant of the slot — a slot can hold several when the household
    /// splits the meal, and Kalendarz stacks them.
    let meal: PlanMeal?
    /// Sourced from the recipe catalog — the meal store snapshots `favourite`
    /// at plan-save time and never re-syncs, so we read the live value here.
    let isFavourite: Bool
    /// Did the signed-in user mark this meal as eaten?
    let isEaten: Bool
    /// Future days have nothing to log yet, so the tick only appears from
    /// today backwards. Past days stay markable on purpose — logging
    /// yesterday's dinner in the evening is the normal case, and those days
    /// are read-only for *planning*, not for what already happened.
    let showsEatenToggle: Bool
    let isEditable: Bool
    let onTap: () -> Void
    let onAssign: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleEaten: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let meal {
                assignedRow(meal)
            } else {
                emptyRow
            }
        }
        .id(contentIdentity)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
                removal: .opacity
            )
        )
        .animation(.smooth(duration: 0.22), value: contentIdentity)
        .animation(.smooth(duration: 0.22), value: isEaten)
    }

    private var contentIdentity: String {
        if let meal {
            return "\(slot.id).meal.\(meal.id)"
        }
        return "\(slot.id).empty"
    }

    // MARK: - Assigned

    private func assignedRow(_ meal: PlanMeal) -> some View {
        HStack(alignment: .center, spacing: 16) {
            MealThumbnail(recipe: meal.recipe, slot: slot, isEaten: isEaten)

            VStack(alignment: .leading, spacing: 4) {
                EyebrowRow(slot: slot, isEaten: isEaten)

                Text(meal.recipe.name)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                metaRow(meal.recipe)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsEatenToggle {
                EatenToggle(isEaten: isEaten, action: onToggleEaten)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isEaten ? WMPalette.sage.opacity(scheme == .dark ? 0.14 : 0.09) : Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isEaten ? WMPalette.sage.opacity(0.38) : Color.wmTileStroke(scheme),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { onTap() }
        .contextMenu { contextActions }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(slot.title): \(meal.recipe.name), \(meal.recipe.prepTimeMinutes) minut, "
            + "\(Int(meal.recipe.nutritionPerServing.kcal)) kalorii"
            + (isEaten ? ", zjedzone" : "")
        )
    }

    /// Długie przytrzymanie. Trzyma ulubione, które zeszło z kafla, i dubluje
    /// odhaczanie — jeden mechanizm może być niewidoczny (menu), drugi musi
    /// być widoczny (ptaszek), i to ten drugi uczy pierwszego.
    @ViewBuilder
    private var contextActions: some View {
        if showsEatenToggle {
            Button(action: onToggleEaten) {
                Label(
                    isEaten ? "Cofnij oznaczenie" : "Oznacz jako zjedzone",
                    systemImage: isEaten ? "arrow.uturn.backward" : "checkmark.circle"
                )
            }
        }

        Button(action: onToggleFavorite) {
            Label(
                isFavourite ? "Usuń z ulubionych" : "Dodaj do ulubionych",
                systemImage: isFavourite ? "heart.slash" : "heart"
            )
        }
    }

    /// Czas · kcal, a po oznaczeniu — „Zjedzone · kcal". Kalorie liczą się
    /// wtedy do bloku makro na górze ekranu, a ten wiersz mówi, który posiłek
    /// je tam wniósł. Pieczątki „checkmark.seal.fill" tu nie ma — przeniosła się
    /// na prawą krawędź kafla, a dwie takie same w jednym wierszu to szum.
    private func metaRow(_ recipe: Recipe) -> some View {
        HStack(spacing: 6) {
            if isEaten {
                Text("Zjedzone · \(Int(recipe.nutritionPerServing.kcal)) kcal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WMPalette.sage)
                    .monospacedDigit()
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))

                Text("\(recipe.prepTimeMinutes) min · \(Int(recipe.nutritionPerServing.kcal)) kcal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
    }

    // MARK: - Empty

    private var emptyRow: some View {
        Button(action: { if isEditable { onAssign() } }) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: slot.icon)
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .frame(width: 96, height: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.wmChipBg(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.wmRule(scheme), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    EyebrowRow(slot: slot, isEaten: false)

                    Text(promptText)
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)

                    if isEditable {
                        HStack(spacing: 4) {
                            Text("Wybierz z biblioteki")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(WMPalette.terracotta)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Dzień nieedytowalny")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Color.wmMuted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.wmTileBg(scheme).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        Color.wmTileStroke(scheme),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isEditable
                    ? "\(promptText). Stuknij, aby wybrać przepis."
                    : "\(slot.title) — dzień nieedytowalny"
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }

    private var promptText: String {
        switch slot {
        case .breakfast: return "Co dziś na śniadanie?"
        case .lunch:     return "Co dziś na obiad?"
        case .dinner:    return "Co dziś na kolację?"
        }
    }
}

// MARK: - MealSlot palette mapping

extension MealSlot {
    /// Cozy Kitchen accent — overrides the default system colors for this design.
    var cozyAccent: Color {
        switch self {
        case .breakfast: return WMPalette.butter
        case .lunch:     return WMPalette.sage
        case .dinner:    return WMPalette.indigo
        }
    }

    /// Hero tint used when the recipe has no image.
    var cozyTint: Color {
        switch self {
        case .breakfast: return WMPalette.butter
        case .lunch:     return WMPalette.sage
        case .dinner:    return WMPalette.indigo
        }
    }
}

// MARK: - Eyebrow (slot label · time)

private struct EyebrowRow: View {
    let slot: MealSlot
    let isEaten: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(slot.title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(isEaten ? WMPalette.sage : slot.cozyAccent)

            Text(slot.time)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.wmMuted(scheme))
        }
        .lineLimit(1)
    }
}

// MARK: - Thumbnail

private struct MealThumbnail: View {
    let recipe: Recipe
    let slot: MealSlot
    let isEaten: Bool

    var body: some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        gradientFallback
                    @unknown default:
                        gradientFallback
                    }
                }
            } else {
                gradientFallback
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Zjedzony posiłek przygasa — zdjęcie zostaje czytelne, ale przestaje
        // konkurować o uwagę z tym, co dopiero przed użytkownikiem.
        .saturation(isEaten ? 0.45 : 1)
        .opacity(isEaten ? 0.75 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var gradientFallback: some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(with: .black, by: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: slot.icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }
}

// MARK: - Eaten tick

// Trzecie podejscie, tym razem odejmowaniem. Krazek — czy pelny z gradientem,
// czy plaski — byl osobnym obiektem na kaflu i ciagnal wzrok na prawa krawedz,
// a przeciez nie o niego tu chodzi. Zostaje wiec sam znak stanu:
//
//   niezjedzone — cienki pusty pierscien, na tyle cichy, ze nie konkuruje ze
//                 zdjeciem, ale widoczny na tyle, by bylo w co celowac
//   zjedzone    — sage'owa pieczatka 'checkmark.seal.fill', bez tla i cienia
//
// Pieczatka zamiast golego 'checkmark': ma wlasny ksztalt, wiec czyta sie jako
// znak stanu, a nie jako szewron czy przypadkowa kreska w typografii wiersza.
// Ten sam symbol stal wczesniej przy napisie 'Zjedzone' — wraca na kafel, ale
// juz tylko raz.
//
// Ptaszek moze byc taki dyskretny, bo nie niesie informacji sam: zjedzony
// posilek widac juz po sage'owym tle kafla, sage'owej ramce, przygaszonej
// miniaturze i podpisie „Zjedzone". On tylko potwierdza i daje w co stuknac.
private struct EatenToggle: View {
    let isEaten: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            ZStack {
                if isEaten {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(WMPalette.sage)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                } else {
                    Circle()
                        .strokeBorder(Color.wmRule(scheme), lineWidth: 1.25)
                        .frame(width: 20, height: 20)
                        .transition(.opacity)
                }
            }
            // Znak ma 15-20pt, wiec sam w sobie jest za maly na palec. Ramka
            // 44pt jest przezroczysta i sluzy wylacznie dotykowi — zejscie z
            // rozmiarem nie moze oznaczac gorszego celowania.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isEaten ? "Cofnij oznaczenie zjedzenia" : "Oznacz jako zjedzone")
        .accessibilityAddTraits(isEaten ? [.isSelected, .isButton] : .isButton)
    }
}

// `Color.mix(with:by:)` lives in
// Views/Dashboard/Products/Components/EditorialShoppingHero.swift
// (alongside the `mix(black:)` / `mix(white:)` helpers) — a single
// internal extension shared across editorial v2 surfaces.
