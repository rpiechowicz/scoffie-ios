import SwiftUI

/// Błąd pod polem albo przyciskiem — terakota, 13 pt, bez czerwieni.
///
/// Aplikacja nie mówi błędów czerwienią (porażka tury Asystenta też jej nie
/// ma), a mimo to pod formularzami stały trzy odcienie systemowego czerwonego
/// — obok arkuszy, które ten sam błąd pisały terakotą (eksport danych,
/// zgłoszenie odpowiedzi). Teraz jeden krój i jeden kolor. Treść dalej
/// przychodzi z `UserFacingErrorMapper.inlineMessage(from:)` albo z ekranu —
/// ten widok tylko ją rysuje.
struct SCInlineErrorText: View {
    let message: String

    /// Kolor błędu — także obwódki pola, które błąd dotyczy.
    static let tint = SCPalette.terracotta

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Self.tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// „Spróbuj ponownie” pod `SCInlineErrorText` — mała kapsuła „soft”.
/// Goły napis w terakocie czytał się jak dalszy ciąg błędu nad nim,
/// a nie jak coś, w co można stuknąć.
struct SCRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Spróbuj ponownie", systemImage: "arrow.clockwise")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .scSoftCapsule()
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
    }
}
