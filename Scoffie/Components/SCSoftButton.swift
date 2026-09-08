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
struct SCSoftButton: View {
    let title: String
    /// Glif po lewej — domyślnie brak, bo strzałka po prawej wystarcza.
    var leadingIcon: String?
    /// Glif po prawej. `nil` gasi strzałkę na akcjach, które nie prowadzą dalej.
    var trailingIcon: String? = "chevron.right"
    var accent: Color = SCPalette.terracotta
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

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
                        // „Dalej" → „Utwórz gospodarstwo" i „Poznaj aplikację"
                        // → „Dalej" przenikają się zamiast podmieniać skokiem.
                        // Działa tylko w animowanej transakcji — stopki mają
                        // własne `.animation(value:)`.
                        .contentTransition(.opacity)
                    if let trailingIcon {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 15, weight: .bold))
                    }
                }
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .scSoftCapsule(accent)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        // Wygaszamy tylko za brak danych. Spinner zostaje w pełnej mocy —
        // przygaszona kręciołka wygląda jak zawieszony ekran, a nie jak praca.
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.smooth(duration: 0.18), value: isEnabled)
    }
}

/// Okrągły towarzysz `SCSoftButton` na akcję poboczną („Wstecz").
///
/// Neutralny, nie akcentowy: dwa terakotowe przyciski obok siebie kłóciłyby
/// się o to, który jest tym głównym.
struct SCSoftIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.scTileBg(scheme)))
                .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Powierzchnia „soft" do użycia poza gotowymi przyciskami

/// Tło i obwódka w wariancie „soft" na dowolnym kształcie — tint akcentu
/// pod spodem, obwódka w tym samym kolorze. Ten sam zestaw liczb, co w
/// `SCSoftButton`, wyjęty do modyfikatora, żeby przyciski o innych
/// rozmiarach (okrągły „Wyślij", 44-punktowe akcje kart, CTA arkuszy)
/// nie kopiowały go po swojemu i nie rozjeżdżały się w odcieniach.
struct SCSoftSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(shape.fill(accent.opacity(scheme == .dark ? 0.16 : 0.10)))
            .overlay(shape.strokeBorder(accent.opacity(0.45), lineWidth: 1.2))
    }
}

extension View {
    /// Kapsuła w wariancie „soft" — domyślny kształt każdej akcji głównej.
    func scSoftCapsule(_ accent: Color = SCPalette.terracotta) -> some View {
        modifier(SCSoftSurface(shape: Capsule(style: .continuous), accent: accent))
    }

    /// Ten sam wariant na innym kształcie (koło pod „Wyślij", zaokrąglony
    /// prostokąt pod kafle).
    func scSoftSurface<S: InsettableShape>(_ shape: S, accent: Color = SCPalette.terracotta) -> some View {
        modifier(SCSoftSurface(shape: shape, accent: accent))
    }
}

#Preview("Dark") {
    ZStack {
        SCPalette.canvasDark.ignoresSafeArea()
        VStack(spacing: 14) {
            SCSoftButton(title: "Poznaj aplikację") {}
            HStack(spacing: 10) {
                SCSoftIconButton(systemName: "chevron.left", accessibilityLabel: "Wstecz") {}
                SCSoftButton(title: "Dalej") {}
            }
            SCSoftButton(title: "Utwórz gospodarstwo", isLoading: true) {}
            SCSoftButton(title: "Dalej", isEnabled: false) {}
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        SCPalette.canvasLight.ignoresSafeArea()
        VStack(spacing: 14) {
            SCSoftButton(title: "Poznaj aplikację") {}
            HStack(spacing: 10) {
                SCSoftIconButton(systemName: "chevron.left", accessibilityLabel: "Wstecz") {}
                SCSoftButton(title: "Dalej") {}
            }
        }
        .padding(24)
    }
    .preferredColorScheme(.light)
}

// MARK: - Ściśnięcie pod palcem

/// Wciśnięcie: lekkie ściśnięcie i przygaszenie treści.
///
/// Przyszedł z osi dnia w Planie i tam mieszkał, choć używa go dziś połowa
/// aplikacji — Kalendarz, pigułka celu, arkusz wyboru posiłku i krzyżyk
/// zamykający arkusze. Styl przycisku nie jest częścią osi dnia i nie ma
/// powodu, żeby wspólny komponent w `Components/` sięgał po niego do widoku.
///
/// Sprężyna jest krótka, bo reakcja na dotyk ma wyprzedzać ruch palca,
/// a nie iść za nim. Na osi dnia jest to jedyny sygnał, że wiersz bez karty
/// i bez obwódki w ogóle da się kliknąć.
struct PlanPressStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
