import SwiftUI

// MARK: - Szkło warstwy nawigacji

extension View {
    /// Szkło elementu, który PŁYWA nad treścią: dolne menu, pole asystenta,
    /// pigułka „Cel dnia”, toast cofania. Samo systemowe Liquid Glass — jak
    /// dok trybu Gotuj (`cookDockGlass`) — bez kryjącej warstwy `scPageBase`
    /// pod spodem.
    ///
    /// Ta warstwa (0,72) siedziała dotąd pod każdym takim szkłem, bo przez
    /// czyste szkło litery przewijanej treści przebijały ostro i wyglądały
    /// jak artefakt. Zamieniała je jednak w matową kremową plamę (Gotuj,
    /// runda 6: „strasznie różniąca się od reszty”). Czytelność daje teraz
    /// `SCScrollEdgeBlur` POD szkłem: treść, zanim dojdzie do szkła, jest już
    /// rozmyta i przygaszona — tak robi Telegram i systemowe paski iOS 26.
    ///
    /// Szkło nie leży na treści w przewijaniu (karty, wiersze, pola w liście) —
    /// tam zostaje strój kafla (`scTileBg` + `scTileStroke`).
    ///
    /// `tint` — barwa akcji, która coś włącza (aktywne filtry, „Wróć do
    /// dziś”): szkło w kolorze akcentu zamiast dawnego wariantu „soft”.
    ///
    /// `interactive` TYLKO dla elementów z własnym gestem, nie w etykietach
    /// i kontenerach przycisków (dolne menu, pigułka „Cel dnia”). Interaktywne
    /// szkło w etykiecie przycisku `.plain` przechwytywało na iOS 26 stuknięcie
    /// — „Dalej” w arkuszu „Jak działa Asystent” nic nie robiło (4.10.2026).
    /// Reakcję na dotyk daje przyciskom `PlanPressStyle`.
    func scChromeGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glassEffect(glass, in: shape)
    }
}

// MARK: - Szkło na zdjęciu

extension View {
    /// Szkło elementu leżącego NA ZDJĘCIU dania (serce i pigułki czasu/kcal
    /// na karcie karuzeli). Przezroczysty wariant `.clear` z przyciemnieniem —
    /// tak Apple każe stawiać szkło na bogatym kadrze: zdjęcie prześwituje,
    /// a biały glif i tekst zostają czytelne na każdym talerzu. Zastępuje
    /// dawny ciemny materiał (`ultraThinMaterial` + czerń 0,36–0,40 + biała
    /// obwódka).
    func scPhotoGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        let glass = Glass.clear.tint(Color.black.opacity(0.32))
        return glassEffect(interactive ? glass.interactive() : glass, in: shape)
    }
}

// MARK: - Rozmyta krawędź przewijania

/// Pas, pod którym przewijana treść CHOWA SIĘ — rozmywa i gaśnie w tło
/// strony — zamiast przejeżdżać ostro pod paskiem stanu. Wzór: Telegram na
/// iOS 26 (górny brzeg rozmowy).
///
/// Własny, a nie systemowy `scrollEdgeEffectStyle`, tylko u GÓRY: zakładki
/// mają przewijanie pod górnym bezpiecznym obszarem (`ignoresSafeArea`,
/// tytuł mierzony od krawędzi ekranu — `SCPageMetrics`), więc systemowa
/// krawędź nie miałaby się do czego przyczepić. Dół od 6.10.2026 jest
/// systemowy: pasek zakładek (`TabView`) i wstawki nad nim (`safeAreaBar` —
/// pole Asystenta, pasek szukania Przepisów, pigułka „Cel dnia”) mają
/// natywny efekt krawędzi przewijania.
///
/// Budowa: materiał (rozmycie tego, co pod spodem) + tło strony na wierzchu,
/// oba pod maską, która gaśnie ku treści. W spoczynku pod pasem leży samo
/// tło strony, więc pasa nie widać — pojawia się dopiero, gdy wjedzie pod
/// niego treść. Bez dotyku i bez VoiceOver.
struct SCScrollEdgeBlur: View {
    /// Krawędź ekranu, przy której stoi pas — przy niej jest najgęstszy.
    let edge: VerticalEdge
    /// Jaka część pasa, licząc od krawędzi, jest w pełni gęsta.
    var solidFraction: Double = 0.5
    /// Tło, w które treść gaśnie. `nil` = `scPageBase` (dół `SCPageBackground`);
    /// szczegóły posiłku mają własne, cieplejsze.
    var base: Color? = nil
    /// Krycie tła nad rozmyciem. Wyższe tam, gdzie na pasie stoi tekst
    /// (stopka arkusza: zdanie nad przyciskiem, liczby obok niego).
    var baseOpacity: Double? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            (base ?? Color.scPageBase(scheme))
                .opacity(baseOpacity ?? (scheme == .dark ? 0.5 : 0.45))
        }
        .mask {
            LinearGradient(
                stops: edge == .top
                    ? [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: solidFraction),
                        .init(color: .black.opacity(0), location: 1),
                    ]
                    : [
                        .init(color: .black.opacity(0), location: 0),
                        .init(color: .black, location: 1 - solidFraction),
                        .init(color: .black, location: 1),
                    ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Rozmyty pas pod paskiem stanu — JEDEN na cały pulpit (`NavigationMenu`).
/// W spoczynku sięga dokładnie do dołu górnego bezpiecznego obszaru: niżej
/// stoją już nagłówki zakładek (tytuł 78 pt od krawędzi), których pas nie
/// może przymglić. Gdy duży tytuł zjedzie i pojawi się kapsuła z tytułem
/// (`SCCompactTitle`), pas schodzi o `extends` niżej — pod kapsułą treść
/// też się chowa, jak pod nagłówkiem rozmowy w Telegramie.
struct SCStatusBarBlur: View {
    var extends: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            SCScrollEdgeBlur(edge: .top, solidFraction: 0.6)
                .frame(height: proxy.safeAreaInsets.top + extends)
                .offset(y: -proxy.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Kompaktowy tytuł zakładki

/// Szklana kapsuła z tytułem zakładki pod paskiem stanu — pojawia się, gdy
/// duży tytuł (`EditorialPageHeader`) zjedzie pod górną krawędź, jak nazwa
/// czatu w Telegramie. Rysuje ją `NavigationMenu` (jedna na pulpit, nad
/// wszystkimi zakładkami), a zakładka tylko melduje przewinięcie
/// (`scReportsCompactTitle`). Bez dotyku: to podpis, nie przycisk.
struct SCCompactTitle: View {
    static let height: CGFloat = 36
    static let top: CGFloat = 6
    /// O ile pas pod paskiem stanu schodzi niżej, gdy kapsuła stoi.
    static let blurExtension: CGFloat = top + height + 16

    let title: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(Color.scLabel(scheme))
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(height: Self.height)
            .scChromeGlass(in: Capsule(style: .continuous))
            .padding(.top, Self.top)
            .allowsHitTesting(false)
            // Tytuł jest już nagłówkiem dla VoiceOver w treści zakładki.
            .accessibilityHidden(true)
    }
}

/// Melduje, czy duży tytuł zakładki zjechał już pod górną krawędź.
/// Bool, nie przesunięcie: stan zmienia się raz na przekroczenie progu.
private struct SCCompactTitleReporter: ViewModifier {
    let title: String
    let tab: DashboardTab

    @Environment(\.scTabBarChrome) private var chrome

    /// Tytuł stoi 78 pt od krawędzi ekranu (`SCPageMetrics.top`) i ma
    /// ~32 pt — po 56 pt przewinięcia jego dół wchodzi pod pasek stanu.
    private static let threshold: CGFloat = 56

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > Self.threshold
            } action: { _, isPast in
                chrome.compactTitles[tab] = isPast ? title : nil
            }
    }
}

extension View {
    /// Na głównym `ScrollView` zakładki z dużym tytułem w treści: po
    /// przewinięciu pod paskiem stanu pojawia się kapsuła z tytułem.
    func scReportsCompactTitle(_ title: String, for tab: DashboardTab) -> some View {
        modifier(SCCompactTitleReporter(title: title, tab: tab))
    }
}

#Preview("Krawędzie") {
    ZStack {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<40) { index in
                    Text("Wiersz \(index) — treść przewija się pod szkłem")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .padding(20)
        }
    }
    .overlay(alignment: .top) { SCStatusBarBlur() }
    .overlay(alignment: .bottom) {
        Capsule()
            .fill(.clear)
            .frame(height: 60)
            .scChromeGlass(in: .capsule, interactive: true)
            .padding(.horizontal, 20)
            .background(alignment: .top) {
                SCScrollEdgeBlur(edge: .bottom)
                    .padding(.top, -28)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
    }
}
