import SwiftUI

// Arkusze asystenta — szkielet z `LSheet` z makiety v4 („05 · Arkusze
// i stany ekranu”): przypięty nagłówek, przewijana treść, stopka przypięta
// do dołu. Nagłówek i stopka są wspólne z resztą aplikacji
// (`EditorialSheetHeader`, `SCSheetFooter`) — arkusz asystenta otwarty
// z Ustawień („Asystent i plan”, „Wybierz plan”) nie może mieć innego
// krzyżyka i innego tytułu niż arkusz obok.
//
// Od 7.10.2026 także TREŚĆ list stoi na klockach Ustawień: etykieta
// `EditorialSheetSectionLabel`, karta `EditorialSettingsCardGroup`, wiersz
// `EditorialSettingsRow` (z podpisem `subtitle:` i `wrapsText:`). Dawne
// `AssistantGroup` (`LGroup`), `AssistantRow` (`LRow`), `AssistantTile`
// (`LTile`) i nieużywana `AssistantSheetFooter` USUNIĘTE — były drugą
// wersją tej samej listy (karta 20 pt, tytuł 15,5, kafelek w tincie).

// MARK: - Szkielet arkusza

struct AssistantSheetScaffold<Content: View, Action: View, Footer: View>: View {
    var eyebrow: String = "Asystent"
    let title: String
    var subtitle: String? = nil
    /// Kafelek przed tytułem (`SCHeaderIconWell`) — jak w każdym arkuszu
    /// aplikacji: glif tej samej sprawy, co pozycja menu ⋯, która go otwiera.
    var icon: String? = nil
    var accent: Color = SCPalette.terracotta
    /// Półarkusz: mniejszy nagłówek (`EditorialSheetHeader(compact:)`).
    var compact: Bool = false
    var onClose: () -> Void
    @ViewBuilder var action: () -> Action
    @ViewBuilder var footer: () -> Footer
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            SCPageBackground(scheme: scheme).ignoresSafeArea()

            // Nagłówek przypięty NAD listą, jak w pozostałych arkuszach:
            // przewijał się razem z treścią i w długich arkuszach (plany,
            // zgoda) krzyżyk uciekał z ekranu.
            VStack(spacing: 0) {
                AssistantSheetHeader(
                    eyebrow: eyebrow,
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    accent: accent,
                    compact: compact,
                    onClose: onClose,
                    action: action
                )
                .padding(.bottom, compact ? 4 : 8)

                // Stopka przez `safeAreaInset` (`scSheetFooter`), nie nad listą
                // w `ZStack` — treść kończy się nad nią sama, bez 140 pt zapasu.
                // Arkusz bez stopki nie dostaje nawet pustej płyty na dole.
                if Footer.self == EmptyView.self {
                    list
                } else {
                    list.scSheetFooter(horizontalPadding: 16) { footer() }
                }
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
                    .padding(.horizontal, 16)
            }
            // Stopka rezerwuje miejsce na swój cień sama (`scSheetFooter`),
            // więc przy stopce wystarczy krótki oddech.
            .padding(.bottom, Footer.self == EmptyView.self ? 24 : 8)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // Treść gaśnie pod przypiętym nagłówkiem zamiast kreski.
        .scScrollEdgeFade()
    }
}

extension AssistantSheetScaffold where Action == EmptyView {
    init(
        eyebrow: String = "Asystent",
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        accent: Color = SCPalette.terracotta,
        compact: Bool = false,
        onClose: @escaping () -> Void,
        @ViewBuilder footer: @escaping () -> Footer,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            icon: icon,
            accent: accent,
            compact: compact,
            onClose: onClose,
            action: { EmptyView() },
            footer: footer,
            content: content
        )
    }
}

extension AssistantSheetScaffold where Action == EmptyView, Footer == EmptyView {
    init(
        eyebrow: String = "Asystent",
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        accent: Color = SCPalette.terracotta,
        compact: Bool = false,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            icon: icon,
            accent: accent,
            compact: compact,
            onClose: onClose,
            action: { EmptyView() },
            footer: { EmptyView() },
            content: content
        )
    }
}

/// Nagłówek arkusza — TEN SAM dla każdego arkusza asystenta, także tych,
/// które nie przewijają listy (onboarding z kartami): kafelek · eyebrow ·
/// tytuł · podtytuł po lewej, opcjonalna akcja i X po prawej.
///
/// Rysuje go `EditorialSheetHeader`, domyślny nagłówek arkusza w aplikacji.
/// Wcześniej asystent miał własny krój (eyebrow 11 pt, tytuł 26 bold)
/// i własny krzyżyk 34 pt — obok arkuszy Ustawień wyglądało to jak druga
/// aplikacja.
struct AssistantSheetHeader<Action: View>: View {
    var eyebrow: String = "Asystent"
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var accent: Color = SCPalette.terracotta
    var compact: Bool = false
    var onClose: () -> Void
    @ViewBuilder var action: () -> Action

    var body: some View {
        EditorialSheetHeader(
            eyebrow: eyebrow,
            title: title,
            icon: icon,
            accent: accent,
            subtitle: subtitle,
            compact: compact,
            onClose: onClose,
            accessory: action
        )
        .padding(.horizontal, 20)
        .padding(.top, compact ? 16 : 18)
    }
}

extension AssistantSheetHeader where Action == EmptyView {
    init(
        eyebrow: String = "Asystent",
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        accent: Color = SCPalette.terracotta,
        compact: Bool = false,
        onClose: @escaping () -> Void
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            icon: icon,
            accent: accent,
            compact: compact,
            onClose: onClose,
            action: { EmptyView() }
        )
    }
}
