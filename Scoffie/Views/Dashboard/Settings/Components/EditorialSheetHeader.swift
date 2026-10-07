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
//   przepisów, zasięg filtrów);
// - `compact` — mały arkusz (półarkusz): kafelek 36, tytuł 19 zamiast 24.
//   „Jak pracowałem” i „Co poprawić?” u Asystenta (27.09.2026 — „header
//   jest zbyt duży”); ten sam układ, tylko w skali połowy ekranu.
//
// - `leading` — własny widok w miejscu kafelka (zdjęcie dania w „Dodaj do
//   planu”, awatar w „Twoich danych”);
// - `detail` — krótka linijka POD tytułem, w kolumnie tekstu obok kafelka
//   (e-mail pod imieniem w „Twoich danych”); `subtitle` stoi niżej, pod
//   całym rzędem;
// - pusty `eyebrow` — bez wiersza nad tytułem (arkusze Zakupów mają eyebrow
//   własnym wierszem pod nagłówkiem).
//
// JEDEN nagłówek WSZYSTKICH arkuszy (Rafał 4.10.2026: „to powinno być 1:1
// wszędzie tak samo — globalny komponent ze slotami: icon, title, subtitle, X,
// right button actions”). `ShoppingSheetHeader` i `AssistantSheetHeader` to
// już tylko nakładki na niego, „Dodaj do planu” stoi na nim ze zdjęciem
// w `leading`. Nowy arkusz = ten nagłówek, nie własny.
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
    /// Linijka pod tytułem, obok kafelka (e-mail w „Twoich danych”).
    let detail: String?
    let compact: Bool
    /// Własny widok w miejscu kafelka z ikoną (zdjęcie dania).
    let leading: AnyView?
    let onClose: () -> Void
    let accessory: () -> Accessory

    init(
        eyebrow: String,
        title: String,
        icon: String? = nil,
        accent: Color = SCPalette.terracotta,
        subtitle: String? = nil,
        subtitleTransition: ContentTransition = .numericText(),
        detail: String? = nil,
        compact: Bool = false,
        leading: AnyView? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.icon = icon
        self.accent = accent
        self.subtitle = subtitle
        self.subtitleTransition = subtitleTransition
        self.detail = detail
        self.compact = compact
        self.leading = leading
        self.onClose = onClose
        self.accessory = accessory
    }

    private var hasLeading: Bool { icon != nil || leading != nil }

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Z kafelkiem wszystko stoi na jego środku; bez — przy górnej
            // krawędzi, bo tytuł bywa dwuwierszową nazwą dania.
            HStack(alignment: hasLeading ? .center : .top, spacing: 12) {
                HStack(spacing: compact ? 10 : 11) {
                    if let leading {
                        leading
                    } else if let icon {
                        SCHeaderIconWell(icon: icon, accent: accent, size: compact ? 36 : 44)
                    }

                    VStack(alignment: .leading, spacing: hasLeading ? 2 : 4) {
                        if !eyebrow.isEmpty {
                            Text(eyebrow.uppercased())
                                .font(.sc(size: 10.5, weight: .bold))
                                .tracking(1.4)
                                .foregroundStyle(accent)
                                .lineLimit(1)
                        }

                        Text(title)
                            .font(.sc(size: compact ? 19 : 24, weight: compact ? .bold : .heavy))
                            .tracking(compact ? -0.3 : -0.4)
                            .foregroundStyle(Color.scLabel(scheme))
                            // Kompaktowy (półarkusz) — zawsze jedna linia.
                            .lineLimit(compact ? 1 : 2)
                            .minimumScaleFactor(compact ? 0.8 : 0.85)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let detail {
                            Text(detail)
                                .font(.sc(size: 13))
                                .foregroundStyle(Color.scMuted(scheme))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
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
                    .font(.sc(size: 13))
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
        detail: String? = nil,
        compact: Bool = false,
        leading: AnyView? = nil,
        onClose: @escaping () -> Void
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            icon: icon,
            accent: accent,
            subtitle: subtitle,
            subtitleTransition: subtitleTransition,
            detail: detail,
            compact: compact,
            leading: leading,
            onClose: onClose,
            accessory: { EmptyView() }
        )
    }
}

/// Kafelek z glifem w tincie akcentu — lewa strona nagłówka arkusza.
/// Tint, a nie pełny kolor: pełne kafle (`EditorialSettingsTileIcon`) zostają
/// wierszom list (Ustawienia, Filtry), gdzie czytają się jak ikony systemowe.
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
                    .font(.sc(size: size * 0.41, weight: .semibold))
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
    /// `nil` = zwykła szarość (`scFaint`). Kreator barwi tu brakującą
    /// odpowiedź na terakotę (7.10.2026) — reszta bez zmian.
    var color: Color? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title.uppercased())
            .font(.sc(size: 10.5, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(color ?? Color.scFaint(scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
    }
}
