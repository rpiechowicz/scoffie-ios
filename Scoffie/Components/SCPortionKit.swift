import SwiftUI

// Porcje osób — JEDEN zestaw w aplikacji: arkusz porcji w szczegółach posiłku
// i „Dodaj do planu” (4.10.2026). Na górze karta z liczbą porcji do ugotowania
// i paskiem podziału (`SCPortionSummary`), pod nią lista osób (`SCPortionList` +
// `SCPortionRow`). Wcześniej tego samego dnia: duży pierścień i kafle po dwa
// w rzędzie — Rafał: „popraw, aby były bardziej czytelne, ale też ładnie UX”.
// Pełne wiersze czyta się od lewej do prawej jak każdą listę w aplikacji,
// a liczba porcji stoi zawsze w tym samym miejscu, przy swoim stepperze.

// MARK: - Garnek

/// Karta podsumowania: „DO UGOTOWANIA” · duża liczba porcji · kcal garnka
/// z prawej, a pod spodem pasek podziału garnka — odcinek na osobę w jej
/// kolorze, szerokość = jej porcja. Czyta się jak pasek postępu Zakupów:
/// jedno spojrzenie mówi, ile ugotować i kto ile z tego zje. (Wcześniej tego
/// dnia: pierścień z ikoną patelni — Rafał: „dopracuj design tego progress”.)
struct SCPortionSummary: View {
    struct Segment: Identifiable {
        let id: String
        let units: Int
        let color: Color
    }

    let segments: [Segment]
    /// Kalorie całego garnka; `nil` = bez kalorii.
    var kcal: Int? = nil
    /// Ostrzeżenie pod paskiem (w terakocie) — np. zapis nie zmieści się
    /// w limicie osoba po osobie. Suma ponad 12 ma własne zdanie.
    var note: String? = nil

    @Environment(\.colorScheme) private var scheme

    private var totalUnits: Int { segments.reduce(0) { $0 + $1.units } }
    private var isOverLimit: Bool { totalUnits > PlanPortions.maxTotalUnits }

    private var warning: String? {
        if isOverLimit {
            // Suma pozycji ≤ 12 — serwer odrzuca więcej; zapis czeka, aż
            // ktoś zejdzie z porcją.
            return "Najwyżej \(PlanPortions.label(units: PlanPortions.maxTotalUnits)) porcji — zmniejsz którąś"
        }
        return note
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DO UGOTOWANIA")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.scFaint(scheme))
                    Text(PlanPortions.spokenServings(units: totalUnits, plural: PolishPlural.servings))
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.7)
                        .monospacedDigit()
                        .foregroundStyle(isOverLimit ? SCPalette.terracotta : Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(totalUnits)))
                }

                Spacer(minLength: 8)

                if let kcal {
                    Text(verbatim: "\(kcal) kcal")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText(value: Double(kcal)))
                }
            }

            splitBar

            if let warning {
                Text(warning)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .animation(.smooth(duration: 0.35), value: segments.map(\.units))
        .animation(SCMotion.textRoll, value: totalUnits)
        .animation(SCMotion.textRoll, value: kcal)
        .animation(.smooth(duration: 0.2), value: warning)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Do ugotowania \(PlanPortions.spokenServings(units: totalUnits, plural: PolishPlural.servings))"
                + (kcal.map { ", \($0) kilokalorii" } ?? "")
                + (warning.map { ", \($0)" } ?? "")
        )
    }

    /// Odcinek na osobę, szerokość = porcja, kolor = kolor awatara.
    private var splitBar: some View {
        GeometryReader { proxy in
            let total = max(1, totalUnits)
            let gap: CGFloat = 3
            let usable = max(0, proxy.size.width - gap * CGFloat(max(0, segments.count - 1)))
            HStack(spacing: gap) {
                ForEach(segments) { segment in
                    Capsule(style: .continuous)
                        .fill(segment.color)
                        .frame(width: max(6, usable * CGFloat(segment.units) / CGFloat(total)))
                }
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Lista osób

/// Karta z wierszami osób (`SCPortionRow`) — strój kafla, wiersze dzielą
/// włosowate kreski od tekstu.
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

/// Wiersz osoby: awatar w obwódce JEJ koloru (tym samym, co jej odcinek
/// paska podziału), imię z „TY” i kcal porcji, z prawej liczba porcji
/// i stepper jak `SCStepper`. Zmieniona, a niezapisana porcja = liczba w kolorze osoby i kropka
/// przy imieniu. Bez edycji (porcje do odczytu) — sama liczba.
struct SCPortionRow: View {
    let name: String
    var avatarUrl: String? = nil
    var avatarColor: Int? = nil
    /// Ziarno koloru awatara dla kont bez `avatarColor`.
    var seed: String = ""
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

    private static let avatarSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(
                avatarUrl: avatarUrl,
                displayName: name,
                size: Self.avatarSize,
                colorIndex: avatarColor,
                seed: seed
            )
            .padding(2.5)
            .overlay(Circle().strokeBorder(color, lineWidth: 2))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)
                    if isViewer {
                        Text("TY")
                            .font(.system(size: 9.5, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(SCPalette.terracotta)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12), in: Capsule())
                            .fixedSize()
                    }
                    if isChanged {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                if let kcal {
                    Text(verbatim: "\(kcal) kcal")
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText(value: Double(kcal)))
                        .animation(SCMotion.textRoll, value: kcal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stepper
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(Color.scTileStroke(scheme))
                    .frame(height: 1)
                    .padding(.leading, 14 + Self.avatarSize + 5 + 12)
            }
        }
        .animation(.smooth(duration: 0.2), value: isChanged)
        .sensoryFeedback(.selection, trigger: units)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(name), \(PlanPortions.spokenServings(units: units, plural: PolishPlural.servings))"
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

    /// Liczba porcji i stepper w stroju `SCStepper` (dwa przyciski 34 × 30
    /// rozdzielone kreską, na szklanej pigułce) — ten sam, „naturalny”, co
    /// w całej aplikacji. Dawniej większa pigułka z liczbą w środku (Rafał:
    /// „stepper daj mniejszy, taki naturalny, jaki jest wszędzie”).
    @ViewBuilder
    private var stepper: some View {
        HStack(spacing: 10) {
            Text(PlanPortions.label(units: units))
                .font(.system(size: 18, weight: .heavy))
                .tracking(-0.3)
                .monospacedDigit()
                .foregroundStyle(isChanged ? color : Color.scLabel(scheme))
                .contentTransition(.numericText(value: Double(units)))
                .animation(SCMotion.textRoll, value: units)
                .frame(minWidth: 30, alignment: .trailing)

            if isEditable {
                HStack(spacing: 0) {
                    stepButton("minus", enabled: canDecrement) { onStep(-1) }
                    Rectangle()
                        .fill(Color.scTileStroke(scheme))
                        .frame(width: 1, height: 18)
                    stepButton("plus", enabled: canIncrement) { onStep(1) }
                }
                .scChromeGlass(in: Capsule(), interactive: true)
            }
        }
    }

    private func stepButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityHidden(true)
    }
}
