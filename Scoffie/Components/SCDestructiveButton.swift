import SwiftUI

/// Akcja nieodwracalna — wylogowanie, usunięcie konta, wyjście z domu,
/// rozłączenie integracji, wyczyszczenie preferencji. JEDNA w całej
/// aplikacji: wariant „soft” (tint i obwódka, jak `EditorialPrimaryActionButton`)
/// w ciepłej czerwieni i tej samej wysokości co akcja główna.
///
/// Wcześniej trzy stroje: prostokąt 14 pt w koralowej czerwieni pod listą
/// Ustawień, systemowa czerwień na kapsule bez obwódki („Wyczyść preferencje”,
/// „Opuść gospodarstwo”, „Usuń konto”) i szara kapsuła z czerwoną obwódką
/// przy integracjach.
///
/// Przycisk NIGDY nie robi szkody sam: jego `action` tylko otwiera
/// potwierdzenie (alert z `role: .destructive`), które zostaje przy ekranie.
/// Ten strój obiecuje pytanie „na pewno?” — akcja bez niego nie ma prawa
/// tak wyglądać.
struct SCDestructiveButton: View {
    let title: String
    var icon: String? = nil
    /// Obrót glifu — „Rozłącz” rysuje ogniwo łańcucha przekręcone o 45°.
    var iconRotation: Angle = .zero
    var isLoading: Bool = false
    let action: () -> Void

    /// Ciepła czerwień z makiety Ustawień (`oklch(0.76 0.14 28)` w ciemnym,
    /// `oklch(0.58 0.18 28)` w jasnym) — z rodziny terakoty, ale wyraźnie
    /// czerwieńsza, żeby akcja nieodwracalna nie udawała głównej.
    static let tint = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 233 / 255, green: 145 / 255, blue: 117 / 255, alpha: 1)
            : UIColor(red: 184 / 255, green: 70 / 255, blue: 38 / 255, alpha: 1)
    })

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Self.tint)
                } else if let icon {
                    // VoiceOver czyta sam tytuł — nazwa glifu („link badge
                    // plus”) nic nie mówi.
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .heavy))
                        .rotationEffect(iconRotation)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Self.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .scSoftCapsule(Self.tint)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .disabled(isLoading)
    }
}

#Preview("SCDestructiveButton") {
    ZStack {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        VStack(spacing: 12) {
            SCDestructiveButton(title: "Wyloguj się", icon: "rectangle.portrait.and.arrow.right") {}
            SCDestructiveButton(title: "Rozłącz konto", icon: "link.badge.plus", iconRotation: .degrees(45)) {}
            SCDestructiveButton(title: "Usuwam konto…", isLoading: true) {}
        }
        .padding(.horizontal, 20)
    }
    .preferredColorScheme(.dark)
}
