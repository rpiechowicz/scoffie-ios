import SwiftUI

/// Główna akcja w wariancie „soft" — akcent na własnym tincie, obwódka
/// w tym samym kolorze, zero gradientu.
///
/// Wzorzec przyszedł ze szczegółów przepisu („Dodaj do planu" / „Gotuj
/// w TM"), gdzie sprawdził się na tyle, że zastąpił pomarańczowy gradient
/// także w kreatorze i w przewodniku. Dotąd żył wpisany w miejscu użycia
/// w trzech kopiach, które zdążyły się rozjechać na wysokości i wadze
/// fontu — stąd jeden komponent.
///
/// Wysokość 56 pt (a nie 14 pt paddingu jak w pasku przepisu), bo tutaj
/// przycisk jest jedyną akcją na ekranie i musi utrzymać dolną strefę.
struct WMSoftButton: View {
    let title: String
    /// Glif po lewej — domyślnie brak, bo strzałka po prawej wystarcza.
    var leadingIcon: String?
    /// Glif po prawej. `nil` gasi strzałkę na akcjach, które nie prowadzą dalej.
    var trailingIcon: String? = "chevron.right"
    var accent: Color = WMPalette.terracotta
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(accent)
                } else {
                    if let leadingIcon {
                        Image(systemName: leadingIcon)
                            .font(.system(size: 15, weight: .bold))
                    }
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let trailingIcon {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 15, weight: .bold))
                    }
                }
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Capsule(style: .continuous)
                    .fill(accent.opacity(scheme == .dark ? 0.16 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(accent.opacity(0.45), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        // Wygaszamy tylko za brak danych. Spinner zostaje w pełnej mocy —
        // przygaszona kręciołka wygląda jak zawieszony ekran, a nie jak praca.
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.smooth(duration: 0.18), value: isEnabled)
    }
}

/// Okrągły towarzysz `WMSoftButton` na akcję poboczną („Wstecz").
///
/// Neutralny, nie akcentowy: dwa terakotowe przyciski obok siebie kłóciłyby
/// się o to, który jest tym głównym.
struct WMSoftIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.wmLabel(scheme))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.wmTileBg(scheme)))
                .overlay(Circle().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Dark") {
    ZStack {
        WMPalette.canvasDark.ignoresSafeArea()
        VStack(spacing: 14) {
            WMSoftButton(title: "Poznaj aplikację") {}
            HStack(spacing: 10) {
                WMSoftIconButton(systemName: "chevron.left", accessibilityLabel: "Wstecz") {}
                WMSoftButton(title: "Dalej") {}
            }
            WMSoftButton(title: "Utwórz gospodarstwo", isLoading: true) {}
            WMSoftButton(title: "Dalej", isEnabled: false) {}
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        WMPalette.canvasLight.ignoresSafeArea()
        VStack(spacing: 14) {
            WMSoftButton(title: "Poznaj aplikację") {}
            HStack(spacing: 10) {
                WMSoftIconButton(systemName: "chevron.left", accessibilityLabel: "Wstecz") {}
                WMSoftButton(title: "Dalej") {}
            }
        }
        .padding(24)
    }
    .preferredColorScheme(.light)
}
