import SwiftUI

/// Wymiary wspólne dla wszystkich kroków kreatora.
///
/// Jedno miejsce, bo kroki jeżdżą na bok jeden po drugim i każda różnica
/// między nimi jest widoczna jako skok w trakcie przejścia: karta o innym
/// promieniu, treść zaczynająca się o parę punktów niżej, dłuższy ogon pod
/// ostatnią sekcją. Przed ujednoliceniem krok 1 miał promień 14, krok 2 —
/// 16, krok 3 — 18, a dolny margines wahał się między 170 a 200.
enum WelcomeLayout {
    /// Margines stron aplikacji (`SCPageMetrics`) — ten sam, co w stopce
    /// kroków (`SCSheetFooter`), więc karty i przycisk stoją w jednej linii.
    static let horizontal: CGFloat = SCPageMetrics.horizontal
    /// Pod paskiem statusu i „Wyloguj" — treść ignoruje górny bezpieczny
    /// obszar (`WelcomeView`), więc odstęp jest liczony od krawędzi ekranu.
    static let topInset: CGFloat = 132
    /// Tyle zajmuje stopka kroków (`SCStepFooter`: 12 + wiersz 36 + 14 +
    /// przycisk ~45 + 12) nad bezpiecznym obszarem, plus jej cień
    /// (`SCEdgeShade.bottomHeight`), który leży na treści. Ostatnia karta ma
    /// wyjechać spod cienia, a nie zostawić pustej strony.
    static let bottomInset: CGFloat = 120 + SCEdgeShade.bottomHeight
    static let sectionSpacing: CGFloat = 22
    /// Promień kart Ustawień („Dieta i alergeny”, „Twoje dane”) — kreator
    /// i Ustawienia pytają o te same rzeczy tymi samymi kartami.
    static let cardRadius: CGFloat = 18
}

/// Tło karty kreatora: kafelek z hairline'em, jeden promień na wszystkich
/// krokach, bez cienia — karta aplikacji (`scTileBg` + `scTileStroke`).
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

/// Sekcja kroku: etykieta sekcji aplikacji (`EditorialSheetSectionLabel`,
/// 10,5 pt, tracking 1,4, `scFaint`) nad treścią.
///
/// Zastąpiła `WelcomeFieldCaption` — kopię tej samej etykiety, która żyła
/// w kreatorze osobno i dostawała odstępy od każdego kroku po swojemu.
struct WelcomeSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EditorialSheetSectionLabel(title: title)
            content()
        }
    }
}

/// Wiersz opcji z ikoną w kafelku, tytułem, podpisem i kółkiem wyboru —
/// ten sam dla celu (krok 2) i sposobu odżywiania (krok 3).
///
/// Geometria i kafelek jak w wierszach celu i diety w Ustawieniach
/// (`EditorialSettingsTileIcon` 32 pt, odstęp 14, margines 16, pion 14,
/// `SCRadioMark`), bo kreator i Ustawienia pytają o te same rzeczy. Kreator
/// rysował dotąd kafelek sam, z innym gradientem i ciaśniej.
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
                EditorialSettingsTileIcon(icon: icon, color: accent, size: Self.iconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(colorScheme))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scMuted(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCRadioMark(isOn: isSelected)
            }
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Wybrane" : "Niewybrane")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Hairline między wierszami opcji, wcięty pod tekst — kolor i wcięcie jak
/// na listach Ustawień.
struct WelcomeOptionDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color.scRule(colorScheme))
            .frame(height: 1)
            .padding(.leading, WelcomeOptionRow.dividerInset)
    }
}
