import SwiftUI

// Porcje osób — JEDEN zestaw w aplikacji: arkusz porcji w szczegółach posiłku
// i „Dodaj do planu” (4.10.2026). Na górze karta z garnkiem i liczbą porcji do
// ugotowania (`SCPortionSummary`), pod nią lista osób (`SCPortionList` +
// `SCPortionRow`). Wcześniej tego samego dnia: duży pierścień i kafle po dwa
// w rzędzie — Rafał: „popraw, aby były bardziej czytelne, ale też ładnie UX”.
// Pełne wiersze czyta się od lewej do prawej jak każdą listę w aplikacji,
// a liczba porcji stoi zawsze w tym samym miejscu, przy swoim stepperze.

// MARK: - Garnek

/// Karta podsumowania: mały garnek (pierścień z łukami osób w ich kolorach,
/// łączna liczba w środku) i obok „Do ugotowania · 3,5 porcji · 1840 kcal”.
struct SCPortionSummary: View {
    struct Segment: Identifiable {
        let id: String
        let units: Int
        let color: Color
    }

    let segments: [Segment]
    /// Kalorie całego garnka; `nil` = bez linii kalorii.
    var kcal: Int? = nil
    /// Ostrzeżenie zamiast kalorii (w terakocie) — np. zapis nie zmieści się
    /// w limicie osoba po osobie. Suma ponad 12 ma własne zdanie.
    var note: String? = nil

    @Environment(\.colorScheme) private var scheme

    private static let diameter: CGFloat = 64
    private static let lineWidth: CGFloat = 7

    private var totalUnits: Int { segments.reduce(0) { $0 + $1.units } }
    private var isOverLimit: Bool { totalUnits > PlanPortions.maxTotalUnits }
    private var spokenTotal: String {
        PlanPortions.spokenServings(units: totalUnits, plural: PolishPlural.servings)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        HStack(spacing: 16) {
            pot
            details
        }
        .padding(16)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .animation(.smooth(duration: 0.35), value: segments.map(\.units))
        .animation(SCMotion.textRoll, value: totalUnits)
        .animation(SCMotion.textRoll, value: kcal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // Kolumna i zdanie dla VoiceOver poza `body` — w jednym wyrażeniu
    // kompilator nie mieścił się w czasie („unable to type-check”).
    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Do ugotowania")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))
            Text(spokenTotal)
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(isOverLimit ? SCPalette.terracotta : Color.scLabel(scheme))
                .contentTransition(.numericText(value: Double(totalUnits)))
            if isOverLimit {
                // Suma pozycji ≤ 12 — serwer odrzuca więcej; zapis czeka,
                // aż ktoś zejdzie z porcją.
                Text("Najwyżej \(PlanPortions.label(units: PlanPortions.maxTotalUnits)) porcji — zmniejsz którąś")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if let note {
                Text(note)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if let kcal {
                Text(verbatim: "\(kcal) kcal")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText(value: Double(kcal)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityText: String {
        let lead = "Do ugotowania \(spokenTotal)"
        if isOverLimit { return lead + ", za dużo, najwyżej 12 porcji" }
        if let note { return lead + ", \(note)" }
        if let kcal { return lead + ", \(kcal) kilokalorii" }
        return lead
    }

    private var pot: some View {
        let total = max(1, totalUnits)
        // Przerwa między łukami w ułamku obwodu — przy jednej osobie pełne koło.
        let gap: CGFloat = segments.count > 1 ? 0.03 : 0

        return ZStack {
            Circle()
                .stroke(Color.scLabel(scheme).opacity(0.07), lineWidth: Self.lineWidth)

            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                let start = CGFloat(segments.prefix(index).reduce(0) { $0 + $1.units }) / CGFloat(total)
                let end = start + CGFloat(segment.units) / CGFloat(total)
                Circle()
                    .trim(from: min(start + gap / 2, end), to: max(end - gap / 2, start))
                    .stroke(segment.color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            Image(systemName: "frying.pan.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))
        }
        .frame(width: Self.diameter, height: Self.diameter)
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

/// Wiersz osoby: awatar w obwódce JEJ koloru (tym samym, co jej łuk garnka),
/// imię z „TY” i kcal porcji, z prawej szklany stepper „− 1,5 +” z dużą
/// liczbą. Zmieniona, a niezapisana porcja = liczba w kolorze osoby i kropka
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
    /// Kreska zaczyna się przy tekście: wcięcie wiersza + awatar z obwódką + odstęp.
    private static let dividerInset: CGFloat = 14 + avatarSize + 5 + 12

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
                    .padding(.leading, Self.dividerInset)
            }
        }
        .animation(.smooth(duration: 0.2), value: isChanged)
        .sensoryFeedback(.selection, trigger: units)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAdjustableAction { direction in
            guard isEditable else { return }
            switch direction {
            case .increment: if canIncrement { onStep(1) }
            case .decrement: if canDecrement { onStep(-1) }
            @unknown default: break
            }
        }
    }

    private var accessibilityText: String {
        let spoken = "\(name), \(PlanPortions.spokenServings(units: units, plural: PolishPlural.servings))"
        guard let kcal else { return spoken }
        return spoken + ", \(kcal) kilokalorii"
    }

    @ViewBuilder
    private var stepper: some View {
        let value = Text(PlanPortions.label(units: units))
            .font(.system(size: 20, weight: .heavy))
            .tracking(-0.4)
            .monospacedDigit()
            .foregroundStyle(isChanged ? color : Color.scLabel(scheme))
            .contentTransition(.numericText(value: Double(units)))
            .animation(SCMotion.textRoll, value: units)
            .frame(minWidth: 40)

        if isEditable {
            HStack(spacing: 0) {
                stepButton("minus", enabled: canDecrement) { onStep(-1) }
                value
                stepButton("plus", enabled: canIncrement) { onStep(1) }
            }
            .padding(3)
            .scChromeGlass(in: Capsule(), interactive: true)
        } else {
            value
                .padding(.horizontal, 8)
        }
    }

    private func stepButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(systemName == "plus" ? SCPalette.terracotta : Color.scLabel(scheme))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.85))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityHidden(true)
    }
}
