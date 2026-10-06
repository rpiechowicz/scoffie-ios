import SwiftUI

// Porcje osób — JEDEN zestaw w aplikacji: arkusz porcji w szczegółach posiłku
// i „Dodaj do planu” (4.10.2026, trzecia runda tego dnia: „bardziej w stylu
// iOS”). Linia „Razem” nad listą (`SCPortionSummary`) i grupa wierszy jak
// w Ustawieniach (`SCPortionList` + `SCPortionRow` z systemowym `Stepper`).

// MARK: - Razem

/// Jedna linia nad listą, jak nagłówek sekcji w Ustawieniach iOS: „Razem”
/// z lewej, liczba porcji i kcal z prawej, ostrzeżenie pod spodem w terakocie
/// (Rafał 4.10.2026: „bardziej w stylu iOS, nieczytelne to jest”). Bez karty
/// i bez paska podziału — wcześniej tego dnia karta „DO UGOTOWANIA” z paskiem
/// w kolorach osób, a jeszcze wcześniej pierścień.
struct SCPortionSummary: View {
    struct Segment: Identifiable {
        let id: String
        let units: Int
        let color: Color
    }

    let segments: [Segment]
    /// Kalorie całego garnka; `nil` = bez kalorii.
    var kcal: Int? = nil
    /// Ostrzeżenie (w terakocie) — np. zapis nie zmieści się w limicie osoba
    /// po osobie. Suma ponad 12 ma własne zdanie.
    var note: String? = nil

    @Environment(\.colorScheme) private var scheme

    private var totalUnits: Int { segments.reduce(0) { $0 + $1.units } }
    private var isOverLimit: Bool { totalUnits > PlanPortions.maxTotalUnits }

    private var warning: String? {
        if isOverLimit {
            return "Najwyżej \(PlanPortions.label(units: PlanPortions.maxTotalUnits)) porcji — zmniejsz którąś"
        }
        return note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Razem")
                    .font(.sc(size: 15, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))

                Spacer(minLength: 8)

                Text(PlanPortions.spokenServings(units: totalUnits, plural: PolishPlural.servings))
                    .font(.sc(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? SCPalette.terracotta : Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(totalUnits)))

                if let kcal {
                    Text(verbatim: "· \(kcal) kcal")
                        .font(.sc(size: 15))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText(value: Double(kcal)))
                }
            }

            if let warning {
                Text(warning)
                    .font(.sc(size: 13, weight: .medium))
                    .foregroundStyle(SCPalette.terracotta)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .animation(SCMotion.textRoll, value: totalUnits)
        .animation(SCMotion.textRoll, value: kcal)
        .animation(.smooth(duration: 0.2), value: warning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Razem \(PlanPortions.spokenServings(units: totalUnits, plural: PolishPlural.servings))"
                + (kcal.map { ", \($0) kilokalorii" } ?? "")
                + (warning.map { ", \($0)" } ?? "")
        )
    }
}

// MARK: - Lista osób

/// Karta z wierszami osób (`SCPortionRow`) — jak grupa w Ustawieniach iOS:
/// strój kafla, wiersze dzielą włosowate kreski od tekstu.
struct SCPortionList<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 0, content: content)
            .background(shape.fill(Color.scTileBg(scheme)))
            .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }
}

/// Wiersz osoby jak w Ustawieniach iOS: awatar, imię (z dopiskiem „Ty”)
/// i kcal porcji, z prawej liczba porcji i SYSTEMOWY `Stepper` — ten, który
/// każdy zna z iOS. Zmieniona, a niezapisana porcja = liczba w terakocie.
/// Bez edycji (porcje do odczytu) — sama liczba.
struct SCPortionRow: View {
    let name: String
    var avatarUrl: String? = nil
    var avatarColor: Int? = nil
    /// Ziarno koloru awatara dla kont bez `avatarColor`.
    var seed: String = ""
    /// Kolor osoby — zostaje w API (dawny pasek podziału), wiersz go nie
    /// potrzebuje: awatar ma własny.
    let color: Color
    let units: Int
    var kcal: Int? = nil
    var isViewer: Bool = false
    var isChanged: Bool = false
    var isEditable: Bool = true
    var canDecrement: Bool = true
    var canIncrement: Bool = true
    /// Kreska nad wierszem — każdy poza pierwszym.
    var showsDivider: Bool = false
    /// Krok porcji: −1 / +1.
    var onStep: (Int) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme

    private static let avatarSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(
                avatarUrl: avatarUrl,
                displayName: name,
                size: Self.avatarSize,
                colorIndex: avatarColor,
                seed: seed
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.sc(size: 16, weight: .medium))
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)
                    if isViewer {
                        Text("· Ty")
                            .font(.sc(size: 16))
                            .foregroundStyle(Color.scMuted(scheme))
                            .fixedSize()
                    }
                }
                if let kcal {
                    Text(verbatim: "\(kcal) kcal")
                        .font(.sc(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText(value: Double(kcal)))
                        .animation(SCMotion.textRoll, value: kcal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(PlanPortions.label(units: units))
                .font(.sc(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isChanged ? SCPalette.terracotta : Color.scLabel(scheme))
                .contentTransition(.numericText(value: Double(units)))
                .animation(SCMotion.textRoll, value: units)
                .frame(minWidth: 28, alignment: .trailing)

            if isEditable {
                Stepper(
                    "Porcje: \(name)",
                    onIncrement: canIncrement ? { onStep(1) } : nil,
                    onDecrement: canDecrement ? { onStep(-1) } : nil
                )
                .labelsHidden()
                .fixedSize()
                .accessibilityHidden(true)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(Color.scTileStroke(scheme))
                    .frame(height: 1)
                    .padding(.leading, 14 + Self.avatarSize + 12)
            }
        }
        .animation(SCMotion.textRoll, value: isChanged)
        .sensoryFeedback(.selection, trigger: units)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(name)\(isViewer ? ", Ty" : ""), \(PlanPortions.spokenServings(units: units, plural: PolishPlural.servings))"
                + (kcal.map { ", \($0) kilokalorii" } ?? "")
        )
        .accessibilityAdjustableAction { direction in
            guard isEditable else { return }
            switch direction {
            case .increment: if canIncrement { onStep(1) }
            case .decrement: if canDecrement { onStep(-1) }
            @unknown default: break
            }
        }
    }
}
