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
    /// Od bezpiecznego obszaru, jak strona przewodnika (`TourLayout.top`) —
    /// przejście przewodnik → kreator nie przesuwa nagłówka. Dawne 132 pt
    /// liczone od krawędzi ekranu robiło miejsce pod „Wyloguj” w pasku
    /// nawigacji; przycisk stoi teraz w nagłówku (`WelcomeHeader`).
    static let topInset: CGFloat = TourLayout.top
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
/// 10,5 pt, tracking 1,4, `scFaint`) nad treścią i — opcjonalnie — jedno
/// zdanie pod etykietą, PO CO o to pytamy.
///
/// Zastąpiła `WelcomeFieldCaption` — kopię tej samej etykiety, która żyła
/// w kreatorze osobno i dostawała odstępy od każdego kroku po swojemu.
/// Podpowiedź doszła 24.09.2026 (Rafał: „więcej opisu… takie bardziej
/// friendly”): sama etykieta mówiła CO podać, a nie po co.
struct WelcomeSection<Content: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EditorialSheetSectionLabel(title: title)
            if let hint {
                // Etykieta ma własne 6 pt pod spodem — podpowiedź dosuwa się
                // do niej, a od treści odsuwa, żeby czytała się jako podpis
                // etykiety, nie pierwsza linijka karty.
                Text(hint)
                    .font(.system(size: 13))
                    .lineSpacing(1.5)
                    .foregroundStyle(Color.scMuted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.top, -4)
                    .padding(.bottom, 8)
            }
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

/// Nagłówek kroku kreatora: wspólny `SCStepHeader` i „Wyloguj” w rzędzie
/// z kafelkiem ikony.
///
/// Do 24.09.2026 „Wyloguj” wisiał w pasku nawigacji jako pływająca
/// pigułka, a treść zaczynała się 132 pt od krawędzi ekranu, żeby się pod
/// nim nie schować — nad każdym krokiem stała pusta ćwiartka ekranu, której
/// przewodnik (`TourPage`) nie ma. Teraz przycisk przewija się razem
/// z nagłówkiem, a krok zaczyna się tam, gdzie strona przewodnika.
struct WelcomeHeader: View {
    let icon: String
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        SCStepHeader(icon: icon, eyebrow: eyebrow, title: title, subtitle: subtitle)
            // Kafelek ikony ma 48 pt, przycisk 34 — 7 pt z góry stawia oba
            // na jednej osi.
            .overlay(alignment: .topTrailing) {
                WelcomeSignOutButton()
                    .padding(.top, 7)
            }
    }
}

/// „Wyloguj” w kreatorze — cicha kapsuła na karcie aplikacji
/// (`scTileBg` + `scTileStroke`), nie akcja niszcząca: nic tu nie ginie,
/// kreator wraca po ponownym zalogowaniu.
struct WelcomeSignOutButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sessionStore) private var sessionStore

    var body: some View {
        Button {
            Task { await sessionStore.signOut() }
        } label: {
            Text("Wyloguj")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.scMuted(colorScheme))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Capsule(style: .continuous).fill(Color.scTileBg(colorScheme)))
                .overlay(Capsule(style: .continuous).stroke(Color.scTileStroke(colorScheme), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Powrót do ekranu logowania")
    }
}
