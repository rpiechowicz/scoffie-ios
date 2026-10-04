import SwiftUI

/// Pusty stan Zakupów: szklany koszyk na środku, wokół niego działy sklepu
/// w swoich kolorach (te same ikony i barwy co alejki listy), które lekko się
/// unoszą — pod spodem tytuł, jedno zdanie i (gdy jest co zrobić) akcja.
/// „Życie” przez kolor i ikony, nie przez tekst (Rafał: „tylko najważniejsze,
/// ale nie pusto”). Przy Reduce Motion działy stoją.
struct ShoppingEmptyHero: View {
    let title: String
    let message: String
    var primaryTitle: String? = nil
    var primaryIcon: String = "arrow.right"
    var onPrimary: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floats = false

    /// Działy wokół koszyka: kąt (stopnie od góry, zgodnie ze wskazówkami),
    /// odległość od środka i opóźnienie unoszenia.
    private static let orbit: [(department: String, angle: Double, radius: CGFloat)] = [
        (ProductConstants.Department.vegetables, -60, 96),
        (ProductConstants.Department.fruits, 0, 88),
        (ProductConstants.Department.dairy, 60, 96),
        (ProductConstants.Department.bakery, 125, 92),
        (ProductConstants.Department.fish, 235, 92),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(Array(Self.orbit.enumerated()), id: \.offset) { index, entry in
                    let color = ProductConstants.departmentColor(for: entry.department)
                    let radians = entry.angle * .pi / 180
                    Image(systemName: ProductConstants.departmentIcon(for: entry.department))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(color.opacity(scheme == .dark ? 0.18 : 0.14)))
                        .offset(
                            x: CGFloat(sin(radians)) * entry.radius,
                            y: -CGFloat(cos(radians)) * entry.radius * 0.62
                                + (floats ? (index.isMultiple(of: 2) ? -5 : 5) : 0)
                        )
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 2.4 + Double(index) * 0.3).repeatForever(autoreverses: true),
                            value: floats
                        )
                }

                Image(systemName: "basket.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .frame(width: 92, height: 92)
                    .scChromeGlass(in: Circle(), tint: SCPalette.terracotta.opacity(scheme == .dark ? 0.26 : 0.18))
            }
            .frame(height: 170)
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text(message)
                .font(.system(size: 14.5))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if let primaryTitle, let onPrimary {
                EditorialPrimaryActionButton(title: primaryTitle, icon: primaryIcon, action: onPrimary)
                    .padding(.top, 22)
            }

            if let secondaryTitle, let onSecondary {
                Button(action: onSecondary) {
                    Text(secondaryTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.scMuted(scheme))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlanPressStyle(scale: 0.97))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { floats = true }
    }
}
