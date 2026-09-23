import SwiftUI

// Nagłówek arkusza: eyebrow wersalikami w terakocie, ciężki tytuł, krzyżyk
// po prawej. Używa go dwadzieścia arkuszy — Ustawienia, Przepisy, Asystent,
// cel dnia w Planie — więc to jest DOMYŚLNY nagłówek arkusza w aplikacji.
//
// Zakupy prowadzą własny (`ShoppingSheetHeader`): ich arkusze są ciągiem
// dalszym ekranu Zakupów i mają czytać się jak on — dużym tytułem, z eyebrow
// w osobnym wierszu pod spodem. Krzyżyk jest ten sam (`SCSheetCloseButton`),
// bo zamykanie arkusza nie ma prawa zależeć od tego, skąd się przyszło.
//
// Opcjonalna akcja (`accessory`) stoi obok krzyżyka — np. ołówek do nazwy
// gospodarstwa. Bez niej wywołanie zostaje takie jak było:
// `EditorialSheetHeader(eyebrow:title:) { zamknij }`.
struct EditorialSheetHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    var onClose: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(SCPalette.terracotta)
                    .lineLimit(1)

                Text(title)
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                accessory()
                SCSheetCloseButton(action: onClose)
            }
        }
    }
}

extension EditorialSheetHeader where Accessory == EmptyView {
    init(eyebrow: String, title: String, onClose: @escaping () -> Void) {
        self.init(eyebrow: eyebrow, title: title, onClose: onClose, accessory: { EmptyView() })
    }
}

// Small editorial label above a single card — same look as the
// `EditorialSettingsSectionHeader` used on the main settings list, kept
// as a separate component so the sheet content can tune padding without
// inheriting the list's `marginTop: 20` baseline.
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
