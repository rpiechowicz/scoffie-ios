import SwiftUI

/// Wiersz w karcie listy — ten sam co lista w Filtrach (`RecipeFilterListRowLabel`,
/// 6.10.2026, artefakt „Ustawienia Scoffie”): płaski kafelek 30 pt
/// (`EditorialSettingsTileIcon`), tytuł 15 semibold, wartość 15 szara przed
/// strzałką / przełącznikiem, wiersz 52 pt, kreska od tytułu (12 + 30 + 12).
/// Dawny wiersz z makiety „settings.jsx” (`Row`: 14/16 pt, kafel 32 z gradientem,
/// tytuł 15,5, wartość 14) był o ~8 pt wyższy i inny niż reszta aplikacji.
struct EditorialSettingsRow<Trailing: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    /// Linijka pod tytułem (12,5 pt, szara) — wiersz z treścią, a nie samą
    /// nazwą: rozmowa z podglądem odpowiedzi, notatka pamięci ze źródłem,
    /// umiejętność Asystenta z przykładem (7.10.2026, arkusze Asystenta na
    /// klockach Ustawień). Bez niej wiersz jest dokładnie taki jak był.
    var subtitle: String? = nil
    var value: String? = nil
    var isLast: Bool = false
    /// Tytuł i podpis łamią się na kolejne linie zamiast ucinać — gdy TREŚĆ
    /// jest sprawą wiersza (notatka, cała wiadomość do wysłania, zdanie
    /// zgody). Domyślnie jedna linia, jak w Ustawieniach.
    var wrapsText: Bool = false
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowBody
                }
                .buttonStyle(.plain)
            } else {
                rowBody
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    // Kreska zaczyna się pod tytułem, nie pod kafelkiem.
                    .padding(.leading, 12 + 30 + 12)
            }
        }
    }

    private var hasSubtitle: Bool { !(subtitle ?? "").isEmpty }

    private var rowBody: some View {
        HStack(spacing: 12) {
            EditorialSettingsTileIcon(icon: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(wrapsText ? nil : 1)
                    .fixedSize(horizontal: false, vertical: wrapsText)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.sc(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(wrapsText ? nil : 1)
                        .fixedSize(horizontal: false, vertical: wrapsText)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.sc(size: 15))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
            }

            trailing()
        }
        .padding(.horizontal, 12)
        // Z podpisem dwie linie — oddech jak w wierszach wyboru diety.
        .padding(.vertical, hasSubtitle ? 8 : 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

// Convenience initialisers — chevron is the default trailing accessory,
// matching the design's `onRight: 'chevron'` default.
extension EditorialSettingsRow where Trailing == EditorialSettingsChevron {
    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        isLast: Bool = false,
        wrapsText: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.isLast = isLast
        self.wrapsText = wrapsText
        self.action = action
        self.trailing = { EditorialSettingsChevron() }
    }
}

/// Strzałka wiersza — ta sama co w liście Filtrów (11 pt bold, `scFaint`).
struct EditorialSettingsChevron: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.sc(size: 11, weight: .bold))
            .foregroundStyle(Color.scFaint(scheme))
    }
}
