import SwiftUI

/// Wymiary wspólne dla wszystkich kroków kreatora.
///
/// Jedno miejsce, bo kroki jeżdżą na bok jeden po drugim i każda różnica
/// między nimi jest widoczna jako skok w trakcie przejścia: karta o innym
/// promieniu, treść zaczynająca się o parę punktów niżej, dłuższy ogon pod
/// ostatnią sekcją. Przed ujednoliceniem krok 1 miał promień 14, krok 2 —
/// 16, krok 3 — 18, a dolny margines wahał się między 170 a 200.
enum WelcomeLayout {
    static let horizontal: CGFloat = 24
    /// Pod paskiem statusu i „Wyloguj" — treść ignoruje górny bezpieczny
    /// obszar (`WelcomeView`), więc odstęp jest liczony od krawędzi ekranu.
    static let topInset: CGFloat = 140
    /// Tyle zajmuje `WelcomeFooter` razem z bezpiecznym obszarem u dołu;
    /// ostatnia karta ma wyjechać spod stopki, a nie zostawić pustej strony.
    static let bottomInset: CGFloat = 176
    static let sectionSpacing: CGFloat = 18
    static let cardRadius: CGFloat = 16
}

/// Tło karty kreatora: kafelek z hairline'em, jeden promień na wszystkich
/// krokach. Zastępuje trzy prywatne kopie `welcomeCardBackground`, które
/// zdążyły się od siebie rozjechać.
struct WelcomeCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: WelcomeLayout.cardRadius, style: .continuous)
            .fill(Color.scTileBg(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: WelcomeLayout.cardRadius, style: .continuous)
                    .stroke(Color.scTileStroke(colorScheme), lineWidth: 1)
            )
    }
}

extension View {
    func welcomeCard() -> some View {
        background(WelcomeCardBackground())
    }
}

/// Kropka wyboru „jedno z wielu". Krok 2 i 3 miały własne, różniące się
/// o 2 pt średnicy — obok siebie na kolejnych ekranach widać to gołym okiem.
struct WelcomeRadioDot: View {
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(SCPalette.terracotta)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .stroke(Color.scFaint(colorScheme), lineWidth: 1.8)
                    .frame(width: 22, height: 22)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
    }
}

/// Wiersz opcji z ikoną w kafelku, tytułem, podpisem i kropką wyboru —
/// ten sam dla celu (krok 2) i sposobu odżywiania (krok 3). Wcześniej dwa
/// prywatne widoki o innych wymiarach: ikona 30 vs 32, odstęp 12 vs 14,
/// margines 14 vs 16, a separator pod nimi liczony osobno i w kroku 3
/// o 2 pt za krótko.
struct WelcomeOptionRow: View {
    let icon: String
    let accent: Color
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    static let iconSize: CGFloat = 32
    static let iconSpacing: CGFloat = 14
    static let horizontalPadding: CGFloat = 16
    /// Separator zaczyna się pod tekstem, nie pod ikoną.
    static var dividerInset: CGFloat { horizontalPadding + iconSize + iconSpacing }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Self.iconSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: Self.iconSize, height: Self.iconSize)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(colorScheme))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scMuted(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                WelcomeRadioDot(isSelected: isSelected)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Wybrane" : "Niewybrane")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Hairline między wierszami opcji, wcięty pod tekst.
struct WelcomeOptionDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color.scRule(colorScheme).opacity(0.5))
            .frame(height: 1)
            .padding(.leading, WelcomeOptionRow.dividerInset)
    }
}
