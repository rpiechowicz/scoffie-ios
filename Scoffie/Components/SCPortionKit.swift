import SwiftUI

// MARK: - Garnek

/// Garnek: pierścień podzielony na osoby — łuk = porcja, kolor = kolor
/// awatara — z łączną liczbą porcji w środku. JEDEN w aplikacji: arkusz
/// porcji w szczegółach posiłku i „Dodaj do planu” (4.10.2026). Łuki
/// przesuwają się razem ze stepperami (przycięcie koła animuje się
/// w sprężynie zmiany).
struct SCPortionPot: View {
    struct Segment: Identifiable {
        let id: String
        let units: Int
        let color: Color
    }

    let segments: [Segment]
    /// Podpis pod garnkiem — „1840 kcal w garnku”; `nil` = bez podpisu.
    var caption: String? = nil

    @Environment(\.colorScheme) private var scheme

    private static let diameter: CGFloat = 132
    private static let lineWidth: CGFloat = 12

    private var totalUnits: Int { segments.reduce(0) { $0 + $1.units } }

    /// „porcja / porcje / porcji” pod liczbą — ułamek łączy się z dopełniaczem.
    private var unitWord: String {
        let total = totalUnits
        guard total % PlanPortions.unitsPerServing == 0 else { return "porcji" }
        return PolishPlural.form(total / PlanPortions.unitsPerServing, one: "porcja", few: "porcje", many: "porcji")
    }

    var body: some View {
        let total = max(1, totalUnits)
        // Przerwa między łukami w ułamku obwodu — przy jednej osobie pełne koło.
        let gap: CGFloat = segments.count > 1 ? 0.018 : 0

        VStack(spacing: 10) {
            ZStack {
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

                VStack(spacing: 0) {
                    Text(PlanPortions.label(units: totalUnits))
                        .font(.system(size: 34, weight: .heavy))
                        .tracking(-1)
                        .monospacedDigit()
                        .foregroundStyle(Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(totalUnits)))
                    Text(unitWord)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.opacity)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)

            if let caption {
                Text(caption)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.smooth(duration: 0.35), value: segments.map(\.units))
        .animation(SCMotion.textRoll, value: totalUnits)
        .animation(SCMotion.textRoll, value: caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Razem \(PlanPortions.spokenServings(units: totalUnits, plural: PolishPlural.servings))"
                + (caption.map { ", \($0)" } ?? "")
        )
    }
}

// MARK: - Kafel osoby

/// Kafel porcji jednej osoby: awatar w obwódce JEJ koloru (tym samym, co jej
/// łuk garnka), imię z „TY”, duża porcja między szklanymi −/+ (co 0,5),
/// opcjonalnie kcal porcji. Zmieniona, a niezapisana porcja = obwódka kafla
/// w kolorze osoby. Bez edycji (porcje do odczytu) — sama liczba.
struct SCPortionTile: View {
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
    /// Krok porcji: −1 / +1.
    var onStep: (Int) -> Void = { _ in }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        VStack(spacing: 10) {
            ProfileAvatar(
                avatarUrl: avatarUrl,
                displayName: name,
                size: 44,
                colorIndex: avatarColor,
                seed: seed
            )
            .padding(3)
            .overlay(Circle().strokeBorder(color, lineWidth: 2))

            HStack(spacing: 5) {
                Text(name)
                    .font(.system(size: 14.5, weight: .semibold))
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
            }

            HStack(spacing: 6) {
                if isEditable {
                    stepButton("minus", enabled: canDecrement) { onStep(-1) }
                }
                Text(PlanPortions.label(units: units))
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .contentTransition(.numericText(value: Double(units)))
                    .animation(SCMotion.textRoll, value: units)
                    .frame(maxWidth: .infinity)
                if isEditable {
                    stepButton("plus", enabled: canIncrement) { onStep(1) }
                }
            }

            if let kcal {
                Text(verbatim: "\(kcal) kcal")
                    .font(.system(size: 12.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .contentTransition(.numericText(value: Double(kcal)))
                    .animation(SCMotion.textRoll, value: kcal)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(
            shape.strokeBorder(
                isChanged ? color.opacity(0.7) : Color.scTileStroke(scheme),
                lineWidth: isChanged ? 1.5 : 1
            )
        )
        .animation(.smooth(duration: 0.2), value: isChanged)
        // Jedno stuknięcie haptyki na kafel, nie na każdy z dwóch przycisków.
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

    /// Szklane −/+. Krok wychodzący poza widełki = przygaszony.
    private func stepButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: 34, height: 34)
                .scChromeGlass(in: Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.88))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityHidden(true)
    }
}

/// Siatka kafli: dwie kolumny, jedna osoba = pełna szerokość.
struct SCPortionTileGrid<Content: View>: View {
    let count: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        let columns = count > 1
            ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible())]
        LazyVGrid(columns: columns, spacing: 12, content: content)
    }
}
