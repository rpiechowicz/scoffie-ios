import SwiftUI

// Kalendarz v2 — wiersz posiłku.
//
// Źródło: canvas claude.ai → „Weekly Meals - Kalendarz v2 D6.html”,
// `CalDRow` z `components/cal-v2-variants.jsx`. Kafla nie ma: checkbox po
// lewej, zdjęcie 48 pt, treść, hairline pod spodem. Karty z obwódką odeszły
// razem z blokiem makra — dzień to teraz jedna lista, a nie stos pudełek,
// i to lista czyta się jednym spojrzeniem od góry do dołu.
//
// Checkbox NIE jest ozdobą: to ten sam znak, który stoi na osi nad listą,
// i to on niesie stan posiłku. Stąd wspólny `CalendarMealStatus` — oś i wiersz
// nie mogą się różnić w tym, który posiłek jest „następny”.

/// Stan posiłku względem „teraz”. Liczy go ekran (`CalendarView.statusMap`),
/// bo „następny” zależy od całego dnia, a nie od pojedynczego wiersza.
enum CalendarMealStatus {
    /// Odhaczony przez zalogowanego użytkownika.
    case eaten
    /// Pierwszy nieodhaczony posiłek z godziną — tylko dzisiaj.
    case next
    /// Dzisiaj, ale już za „następnym”.
    case later
    /// Slot bez stałej pory (domyślnie przekąska).
    case anytime
    /// Dzień miniony albo przyszły — nic nie nadchodzi i nic nie minęło.
    case planned

    var isEaten: Bool { self == .eaten }
}

/// „za 4 h 19 min” — ile zostało do posiłku.
enum CalendarRelativeTime {
    static func text(to minutes: Int, from nowMinutes: Int) -> String {
        let delta = minutes - nowMinutes
        guard delta > 0 else { return "teraz" }

        let hours = delta / 60
        let rest = delta % 60
        if hours > 0 && rest > 0 { return "za \(hours) h \(rest) min" }
        if hours > 0 { return "za \(hours) h" }
        return "za \(rest) min"
    }
}

// MARK: - Checkbox

/// Kółko stanu: puste (później / inny dzień) · kreskowane (bez pory) ·
/// w kolorze pory z kropką (następne) · sage'owe z ptaszkiem (zjedzone).
///
/// Ten sam rysunek co węzeł osi, tylko bez zdjęcia — dlatego mieszka obok
/// wiersza, a nie w nim: oś sięga po `CalendarMealStatus` do tego samego
/// źródła.
struct CalendarMealCheck: View {
    let status: CalendarMealStatus
    let color: Color
    var size: CGFloat = 26

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if status.isEaten {
                Circle().fill(SCPalette.sage)

                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(Color.scPageBase(scheme))
            } else {
                Circle()
                    .strokeBorder(
                        borderColor,
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            dash: status == .anytime ? [3, 2.5] : []
                        )
                    )

                if status == .next {
                    Circle()
                        .fill(color)
                        .frame(width: size * 0.36, height: size * 0.36)
                }
            }
        }
        .frame(width: size, height: size)
        // Poświata tylko pod „następnym": to jedyny posiłek, w który
        // użytkownik ma teraz stuknąć, więc jako jedyny woła o uwagę.
        .background(
            Circle()
                .fill(color.opacity(status == .next ? 0.16 : 0))
                .padding(-3)
        )
        .animation(.smooth(duration: 0.22), value: status)
    }

    private var borderColor: Color {
        status == .next ? color : Color.scRule(scheme)
    }
}

// MARK: - Wiersz posiłku

struct CalendarMealRow: View {
    let slot: MealSlot
    let recipe: Recipe
    let status: CalendarMealStatus
    /// Godzina slotu z rozkładu gospodarstwa; `nil` = pora dowolna.
    let time: String?
    /// „za 4 h 19 min" — wyłącznie dla `.next`.
    let relative: String?
    /// „12 min · 510 kcal · 2 porcje".
    let meta: String
    let isFavourite: Bool
    /// Dzień z przyszłości nie ma czego odhaczać — kółko zostaje, ale gaśnie.
    let canToggleEaten: Bool
    /// Ostatni wiersz listy nie rysuje kreski pod sobą.
    let isLast: Bool
    let onTap: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleEaten: () -> Void

    @Environment(\.colorScheme) private var scheme
    /// Wiersz zajmuje całą szerokość strony dnia, a strona jeździ palcem
    /// w bok — bez furtki machnięcie kończące się na wierszu otwierało
    /// posiłek zamiast przestawić dzień.
    @Environment(\.dayPagerGate) private var pagerGate

    private var eaten: Bool { status.isEaten }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                pagerGate.ifNotSwiping(onToggleEaten)
            } label: {
                CalendarMealCheck(status: status, color: slot.cozyAccent)
                    .scTapTarget(44, drawn: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canToggleEaten)
            .opacity(canToggleEaten ? 1 : 0.5)
            .accessibilityLabel(eaten ? "Cofnij oznaczenie zjedzenia" : "Oznacz jako zjedzone")

            CalendarMealThumbnail(recipe: recipe, slot: slot, isEaten: eaten)

            VStack(alignment: .leading, spacing: 3) {
                eyebrow

                Text(recipe.name)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(eaten ? Color.scMuted(scheme) : Color.scLabel(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(meta)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pagerGate.ifNotSwiping(onTap) }
        .contextMenu { contextActions }
        .animation(.smooth(duration: 0.22), value: eaten)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Pora dnia i status w jednym wierszu — „ŚNIADANIE · zjedzone",
    /// „OBIAD · 14:00 · za 4 h 19 min".
    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(slot.title.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(eyebrowColor)

            Text("· \(statusText)")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(eaten ? SCPalette.sage : Color.scFaint(scheme))
        }
        .lineLimit(1)
    }

    /// Wyblakła pora dnia przy tym, co już zjedzone albo dopiero późno —
    /// akcent zostaje dla posiłku, który jest teraz na tapecie.
    private var eyebrowColor: Color {
        switch status {
        case .eaten, .later: return Color.scFaint(scheme)
        default:             return slot.cozyAccent
        }
    }

    private var statusText: String {
        switch status {
        case .eaten:
            return "zjedzone"
        case .next:
            guard let time else { return relative ?? "" }
            guard let relative else { return time }
            return "\(time) · \(relative)"
        case .anytime:
            return "dowolna pora"
        case .later, .planned:
            return time ?? "dowolna pora"
        }
    }

    /// Długie przytrzymanie: ulubione (zeszło z wiersza) i drugie wejście
    /// w odhaczanie — jeden mechanizm może być niewidoczny, drugi musi być
    /// widoczny, i to ten drugi uczy pierwszego.
    @ViewBuilder
    private var contextActions: some View {
        if canToggleEaten {
            Button(action: onToggleEaten) {
                Label(
                    eaten ? "Cofnij oznaczenie" : "Oznacz jako zjedzone",
                    systemImage: eaten ? "arrow.uturn.backward" : "checkmark.circle"
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

    private var accessibilityLabel: String {
        var parts = ["\(slot.title): \(recipe.name)", statusText, meta]
        if isFavourite { parts.append("ulubione") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Pusta pora

/// Pusty slot jest INFORMACJĄ, nie przyciskiem.
///
/// Kalendarz nie planuje — odpowiada na „co dziś jem i czy już zjadłem".
/// Podpis mówi, dokąd iść, zamiast udawać, że tu się nic nie da zrobić.
struct CalendarEmptySlotRow: View {
    let slot: MealSlot
    let time: String?
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .strokeBorder(
                    Color.scRule(scheme),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])
                )
                .frame(width: 26, height: 26)
                .scTapTarget(44, drawn: 26)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scChipBg(scheme))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: slot.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.scFaint(scheme))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(slot.title.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.scFaint(scheme))

                    if let time {
                        Text("· \(time)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                }
                .lineLimit(1)

                Text("Nic nie zaplanowano")
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)

                Text("Zaplanujesz w zakładce Plan")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.title): nic nie zaplanowano. Posiłki planuje się w zakładce Plan.")
    }
}

// MARK: - Miniatura

struct CalendarMealThumbnail: View {
    let recipe: Recipe
    let slot: MealSlot
    let isEaten: Bool
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        gradientFallback
                    }
                }
            } else {
                gradientFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Zjedzony posiłek przygasa — zostaje czytelny, ale przestaje
        // konkurować o uwagę z tym, co dopiero przed użytkownikiem.
        .saturation(isEaten ? 0.45 : 1)
        .opacity(isEaten ? 0.75 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }
}

// MARK: - Paleta pór dnia

extension MealSlot {
    /// Akcent „Cozy Kitchen" — zastępuje domyślne kolory systemowe.
    ///
    /// Posiłek dodatkowy dziedziczy akcent po sąsiednim posiłku głównym
    /// (II śniadanie ← śniadanie, podwieczorek ← obiad, przekąska ← kolacja).
    /// Paleta ma cztery akcenty i dokładanie do niej dwóch nowych dla slotów,
    /// które są z definicji mniej ważne od głównych, rozbiłoby hierarchię
    /// ekranu zamiast ją doprecyzować.
    var cozyAccent: Color {
        switch self {
        case .breakfast, .secondBreakfast: return SCPalette.butter
        case .lunch, .afternoonSnack:      return SCPalette.sage
        case .dinner, .snack:              return SCPalette.indigo
        }
    }

    /// Tło miniatury, gdy przepis nie ma zdjęcia.
    var cozyTint: Color { cozyAccent }
}
