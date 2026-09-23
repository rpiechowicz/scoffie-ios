import SwiftUI

// Arkusze asystenta — układ z `LSheet`, `LGroup`, `LRow` z makiety v4
// („05 · Arkusze i stany ekranu”): zgrupowane listy jak iOS inset grouped,
// stopka przypięta do dołu. Nagłówek i stopka są już wspólne z resztą
// aplikacji (`EditorialSheetHeader`, `SCSheetFooter`) — arkusz asystenta
// otwarty z Ustawień („Asystent i plan”, „Wybierz plan”) nie może mieć
// innego krzyżyka i innego tytułu niż arkusz obok.

// MARK: - Szkielet arkusza

struct AssistantSheetScaffold<Content: View, Action: View, Footer: View>: View {
    var eyebrow: String = "Asystent"
    let title: String
    var subtitle: String? = nil
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
                AssistantSheetHeader(eyebrow: eyebrow, title: title, subtitle: subtitle, onClose: onClose, action: action)
                    .padding(.bottom, 8)

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
        onClose: @escaping () -> Void,
        @ViewBuilder footer: @escaping () -> Footer,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, onClose: onClose, action: { EmptyView() }, footer: footer, content: content)
    }
}

extension AssistantSheetScaffold where Action == EmptyView, Footer == EmptyView {
    init(
        eyebrow: String = "Asystent",
        title: String,
        subtitle: String? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, onClose: onClose, action: { EmptyView() }, footer: { EmptyView() }, content: content)
    }
}

/// Nagłówek arkusza — TEN SAM dla każdego arkusza asystenta, także tych,
/// które nie przewijają listy (onboarding z kartami): eyebrow · tytuł ·
/// podtytuł po lewej, opcjonalna akcja i X po prawej.
///
/// Rysuje go `EditorialSheetHeader`, domyślny nagłówek arkusza w aplikacji.
/// Wcześniej asystent miał własny krój (eyebrow 11 pt, tytuł 26 bold)
/// i własny krzyżyk 34 pt — obok arkuszy Ustawień wyglądało to jak druga
/// aplikacja.
struct AssistantSheetHeader<Action: View>: View {
    var eyebrow: String = "Asystent"
    let title: String
    var subtitle: String? = nil
    var onClose: () -> Void
    @ViewBuilder var action: () -> Action

    var body: some View {
        EditorialSheetHeader(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            onClose: onClose,
            accessory: action
        )
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }
}

extension AssistantSheetHeader where Action == EmptyView {
    init(eyebrow: String = "Asystent", title: String, subtitle: String? = nil, onClose: @escaping () -> Void) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle, onClose: onClose, action: { EmptyView() })
    }
}

/// Stopka arkusza asystenta — wspólna stopka aplikacji (`SCSheetFooter`)
/// z wcięciem list asystenta (16 pt).
struct AssistantSheetFooter<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        SCSheetFooter(horizontalPadding: 16, content: content)
    }
}

// MARK: - Zgrupowana lista

/// `LGroup`: tytuł wersalikami (+ dopisek po prawej) nad kartą o promieniu
/// 20. Tytuł ma krój etykiet sekcji aplikacji (`EditorialSheetSectionLabel`:
/// 10,5 pt, tracking 1,4), a nie 12/700 z makiety.
struct AssistantGroup<Content: View, Aside: View>: View {
    var title: String? = nil
    var titleColor: Color? = nil
    @ViewBuilder var aside: () -> Aside
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let title {
                        Text(title)
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(titleColor ?? Color.scFaint(scheme))
                    }
                    Spacer(minLength: 0)
                    aside()
                        .font(.system(size: 12))
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
            }

            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(shape.fill(AssistantLook.card(scheme)))
                .clipShape(shape)
                .overlay(shape.stroke(AssistantLook.cardStroke(scheme), lineWidth: 1))
        }
        .padding(.top, 14)
    }
}

extension AssistantGroup where Aside == EmptyView {
    init(title: String? = nil, titleColor: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, titleColor: titleColor, aside: { EmptyView() }, content: content)
    }
}

extension AssistantGroup where Aside == Text {
    init(title: String?, aside: String, titleColor: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, titleColor: titleColor, aside: { Text(aside) }, content: content)
    }
}

/// `LRow`: element po lewej · tytuł 15,5/600 + podtytuł 13 · element po
/// prawej · chevron. Włoskowata kreska nad każdym wierszem poza pierwszym.
struct AssistantRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var chevron: Bool = false
    var first: Bool = false
    var titleSize: CGFloat = 15.5
    var titleWeight: Font.Weight = .semibold
    var titleColor: Color? = nil
    var subtitleColor: Color? = nil
    var subtitleWeight: Font.Weight = .regular
    var subtitleWraps: Bool = false
    var verticalPadding: CGFloat = 11
    var leadingInset: CGFloat = 14
    var trailingInset: CGFloat = 14
    var alignment: VerticalAlignment = .center
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            leading()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: titleSize, weight: titleWeight))
                    .tracking(-0.3)
                    .lineSpacing(2)
                    .foregroundStyle(titleColor ?? AssistantLook.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: subtitleWeight))
                        .lineSpacing(2)
                        .foregroundStyle(subtitleColor ?? AssistantLook.muted(scheme))
                        .lineLimit(subtitleWraps ? nil : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: subtitleWraps)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()

            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AssistantLook.ink(scheme).opacity(0.35))
            }
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.vertical, verticalPadding)
        .overlay(alignment: .top) {
            if !first { AssistantCardRule() }
        }
    }
}

extension AssistantRow where Leading == EmptyView, Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        chevron: Bool = false,
        first: Bool = false,
        titleSize: CGFloat = 15.5,
        titleWeight: Font.Weight = .semibold,
        subtitleWraps: Bool = false
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            chevron: chevron,
            first: first,
            titleSize: titleSize,
            titleWeight: titleWeight,
            subtitleWraps: subtitleWraps,
            leading: { EmptyView() },
            trailing: { EmptyView() }
        )
    }
}

extension AssistantRow where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        chevron: Bool = false,
        first: Bool = false,
        titleSize: CGFloat = 15.5,
        titleWeight: Font.Weight = .semibold,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            chevron: chevron,
            first: first,
            titleSize: titleSize,
            titleWeight: titleWeight,
            leading: leading,
            trailing: { EmptyView() }
        )
    }
}

/// `LTile`: kafelek ikony 36 w tincie akcentu.
struct AssistantTile: View {
    let icon: String
    var tint: Color? = nil
    var color: Color? = nil
    var size: CGFloat = 36

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(tint ?? AssistantLook.terraTint(scheme))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(color ?? AssistantLook.terra(scheme))
            )
            .accessibilityHidden(true)
    }
}
