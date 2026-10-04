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
    func scChromeGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
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
/// strony — zamiast przejeżdżać ostro pod paskiem stanu, dolnym menu albo
/// polem asystenta. Wzór: Telegram na iOS 26 (górny i dolny brzeg rozmowy).
///
/// Własny, a nie systemowy `scrollEdgeEffectStyle` + `safeAreaBar`: zakładki
/// mają przewijanie pod górnym bezpiecznym obszarem (`ignoresSafeArea`,
/// tytuł mierzony od krawędzi ekranu — `SCPageMetrics`), a własne paski
/// stoją w `overlay`, więc systemowa krawędź nie miałaby się do czego
/// przyczepić.
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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.scPageBase(scheme).opacity(scheme == .dark ? 0.5 : 0.45)
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
/// Sięga dokładnie do dołu górnego bezpiecznego obszaru: niżej stoją już
/// nagłówki zakładek (tytuł 78 pt od krawędzi) i przyciski „wstecz”
/// wepchniętych ekranów, których pas nie może przymglić.
struct SCStatusBarBlur: View {
    var body: some View {
        GeometryReader { proxy in
            SCScrollEdgeBlur(edge: .top, solidFraction: 0.6)
                .frame(height: proxy.safeAreaInsets.top)
                .offset(y: -proxy.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
