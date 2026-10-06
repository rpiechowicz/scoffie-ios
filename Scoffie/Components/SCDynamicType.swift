import SwiftUI
import UIKit

// MARK: - Dynamic Type dla rozmiarów z makiet

extension Font {
    /// Krój systemowy o rozmiarze z makiety, który rośnie z Dynamic Type.
    ///
    /// Zastępuje `.system(size:weight:design:)` w całej aplikacji: przy
    /// domyślnym rozmiarze tekstu (`.large`) oddaje DOKŁADNIE rozmiar
    /// z makiety, przy większym — rośnie tak, jak rósłby najbliższy styl
    /// systemowy (`SCDynamicType.style(for:)`): drobne podpisy mocniej,
    /// duże tytuły słabiej, jak w aplikacjach Apple. Górny limit to
    /// `SCDynamicType.cap` — powyżej niego układy liczone na 844 pt
    /// (dok Gotuj, kapsuły, talerze) przestałyby się mieścić.
    ///
    /// Wartość jest liczona przy budowaniu widoku, nie przy rysowaniu,
    /// więc typ zostaje `Font` (działa w `Text + Text`, w `-> Text`,
    /// w wyrażeniach warunkowych). Zmianę rozmiaru w trakcie działania
    /// aplikacji łapie `scRefreshesOnDynamicType()` na korzeniu pulpitu.
    static func sc(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: SCDynamicType.scaled(size), weight: weight, design: design)
    }
}

enum SCDynamicType {
    /// Najwyższy rozmiar, do którego rośnie tekst z makiet. Rozmiary
    /// dostępności (AX1–AX5) zatrzymują się tutaj.
    static let cap: UIContentSizeCategory = .extraExtraLarge
    /// To samo dla stylów systemowych i `@ScaledMetric` (środowisko SwiftUI).
    static let swiftUICap: DynamicTypeSize = .xxLarge

    private static var cachedCategory: UIContentSizeCategory = .large
    private static var cachedTraits = UITraitCollection(preferredContentSizeCategory: .large)
    private static var metricsByStyle: [UIFont.TextStyle: UIFontMetrics] = [:]

    /// Rozmiar z makiety przeliczony na bieżące ustawienie tekstu.
    static func scaled(_ size: CGFloat) -> CGFloat {
        let category = currentCategory
        // Domyślny rozmiar: dokładnie makieta, bez liczenia.
        guard category != .large else { return size }
        if category != cachedCategory {
            cachedCategory = category
            cachedTraits = UITraitCollection(preferredContentSizeCategory: category)
        }
        return metrics(for: style(for: size)).scaledValue(for: size, compatibleWith: cachedTraits)
    }

    /// Ustawienie tekstu z iOS przycięte do `cap`.
    static var currentCategory: UIContentSizeCategory {
        let current = UIApplication.shared.preferredContentSizeCategory
        if current == .unspecified { return .large }
        return current > cap ? cap : current
    }

    /// Styl systemowy, którego krzywą rośnie dany rozmiar: najbliższy
    /// rozmiarem przy `.large` (caption2 11 · caption1 12 · footnote 13 ·
    /// subheadline 15 · callout 16 · body 17 · title3 20 · title2 22 ·
    /// title1 28 · largeTitle 34).
    static func style(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case ..<11.5: .caption2
        case ..<12.5: .caption1
        case ..<14: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<18.5: .body
        case ..<21: .title3
        case ..<25: .title2
        case ..<31: .title1
        default: .largeTitle
        }
    }

    private static func metrics(for style: UIFont.TextStyle) -> UIFontMetrics {
        if let cached = metricsByStyle[style] { return cached }
        let metrics = UIFontMetrics(forTextStyle: style)
        metricsByStyle[style] = metrics
        return metrics
    }
}

extension View {
    /// Przebudowuje widok, gdy użytkownik zmieni rozmiar tekstu w trakcie
    /// działania aplikacji. `Font.sc` liczy rozmiar przy budowaniu widoku,
    /// więc bez tego nowe ustawienie weszłoby dopiero przy następnym
    /// przerysowaniu. Kładzione RAZ, na korzeniu pulpitu — przebudowa
    /// zamyka otwarte arkusze, ale zmiana rozmiaru tekstu w trakcie to
    /// rzadkość, a stan (plan, sesja Gotuj, rozmowa) żyje w sklepach.
    func scRefreshesOnDynamicType() -> some View {
        modifier(SCDynamicTypeRefresh())
    }
}

private struct SCDynamicTypeRefresh: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.id(dynamicTypeSize)
    }
}
