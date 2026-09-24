import SwiftUI

// Nagłówek arkusza: eyebrow wersalikami w akcencie, ciężki tytuł, krzyżyk
// po prawej. Używa go kilkadziesiąt arkuszy — Ustawienia, Przepisy, Asystent,
// cel dnia w Planie — więc to jest DOMYŚLNY nagłówek arkusza w aplikacji.
//
// Zakupy prowadzą własny (`ShoppingSheetHeader`): ich arkusze są ciągiem
// dalszym ekranu Zakupów i mają czytać się jak on — dużym tytułem, z eyebrow
// w osobnym wierszu pod spodem. Krzyżyk jest ten sam (`SCSheetCloseButton`),
// bo zamykanie arkusza nie ma prawa zależeć od tego, skąd się przyszło.
//
// Opcjonalnie:
// - `accessory` — akcja obok krzyżyka (ołówek do nazwy gospodarstwa, filtry
//   listy, „Wyczyść”);
// - `icon` — kafelek z glifem w tincie akcentu przed tekstem. Tak stoją
//   arkusze, które mają własny kolor: filtry, lista kategorii, wybór
//   przepisu do planu, gospodarstwo, dział składników. Każdy z nich miał
//   wcześniej prywatną kopię tego układu — kolorowy pion z poświatą w liście
//   kategorii, eyebrow 10 pt z trackingiem 2 w wyborze przepisu, pełny kafel
//   z gradientem w gospodarstwie — czyli ten sam nagłówek w kilku krojach;
// - `subtitle` — jedno zdanie pod spodem (data i pora posiłku, liczba
//   przepisów, zasięg filtrów).
//
// Bez tych dodatków wywołanie zostaje takie jak było:
// `EditorialSheetHeader(eyebrow:title:) { zamknij }`.
struct EditorialSheetHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let icon: String?
    let accent: Color
    let subtitle: String?
    /// Jak podtytuł zmienia treść. Domyślnie rolują cyfry („3 z 4”);
    /// podtytuł z imieniem woli przenikanie, bo rolowanie przetacza litery.
    let subtitleTransition: ContentTransition
    let onClose: () -> Void
    let accessory: () -> Accessory

    init(
        eyebrow: String,
        title: String,
        icon: String? = nil,
        accent: Color = SCPalette.terracotta,
        subtitle: String? = nil,
        subtitleTransition: ContentTransition = .numericText(),
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.icon = icon
        self.accent = accent
        self.subtitle = subtitle
        self.subtitleTransition = subtitleTransition
        self.onClose = onClose
        self.accessory = accessory
    }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Z kafelkiem wszystko stoi na jego środku; bez — przy górnej
            // krawędzi, bo tytuł bywa dwuwierszową nazwą dania.
            HStack(alignment: icon == nil ? .top : .center, spacing: 12) {
                HStack(spacing: 11) {
                    if let icon {
                        SCHeaderIconWell(icon: icon, accent: accent)
                    }

                    VStack(alignment: .leading, spacing: icon == nil ? 4 : 2) {
                        Text(eyebrow.uppercased())
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(accent)
                            .lineLimit(1)

                        Text(title)
                            .font(.system(size: 24, weight: .heavy))
                            .tracking(-0.4)
                            .foregroundStyle(Color.scLabel(scheme))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                HStack(spacing: 8) {
                    accessory()
                    SCSheetCloseButton(action: onClose)
                }
            }

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(subtitleTransition)
                    .padding(.top, 10)
            }
        }
    }
}

extension EditorialSheetHeader where Accessory == EmptyView {
    init(
        eyebrow: String,
        title: String,
        icon: String? = nil,
        accent: Color = SCPalette.terracotta,
        subtitle: String? = nil,
        subtitleTransition: ContentTransition = .numericText(),
        onClose: @escaping () -> Void
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            icon: icon,
            accent: accent,
            subtitle: subtitle,
            subtitleTransition: subtitleTransition,
            onClose: onClose,
            accessory: { EmptyView() }
        )
    }
}

/// Kafelek z glifem w tincie akcentu — lewa strona nagłówka arkusza.
/// Tint, a nie pełny kolor z gradientem: pełne kafle (`EditorialSettingsTileIcon`)
/// zostają wierszom listy Ustawień, gdzie czytają się jak ikony systemowe.
struct SCHeaderIconWell: View {
    let icon: String
    var accent: Color = SCPalette.terracotta
    var size: CGFloat = 44

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(accent.opacity(scheme == .dark ? 0.16 : 0.12))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.41, weight: .semibold))
                    .foregroundStyle(accent)
            )
            .accessibilityHidden(true)
    }
}

// Etykieta sekcji w arkuszu — ten sam krój, co etykiety grup na liście
// Ustawień (`EditorialSettingsCardGroup`); osobny komponent, żeby treść
// arkusza mogła stroić odstępy bez dziedziczenia `marginTop: 20` z listy.
struct EditorialSheetSectionLabel: View {
    let title: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Color.scFaint(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
    }
}
