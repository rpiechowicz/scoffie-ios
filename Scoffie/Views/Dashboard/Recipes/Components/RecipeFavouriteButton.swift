import SwiftUI

/// Serce „ulubione” — w szczegółach posiłku i na karcie karuzeli Przepisów.
///
/// Pokazywany stan jest LOKALNY: stuknięcie przestawia serce od razu, a do
/// katalogu idzie dopiero po animacji (`syncDelay`). Wcześniej zapis szedł
/// w tej samej chwili: katalog przeliczał pod arkuszem całą listę Przepisów
/// (ranking, sekcje, karuzelę), rodzic podmieniał przepis w arkuszu, a po
/// 300 ms katalog zapisywał się na dysk — wszystko w trakcie wyskoku serca,
/// które przez to przycinało się (Rafał widział to na Macu). Kilka stuknięć
/// pod rząd zapisuje jeden, ostatni stan — jako WARTOŚĆ, nie przełączenie
/// (`RecipeCatalogStore.setFavourite`), więc zapis nie zależy od tego, czy
/// ekran miał aktualną kopię przepisu.
///
/// Stan w osobnym widoku, a nie w ekranie szczegółów: stuknięcie przerysowuje
/// sam przycisk, a nie cały arkusz ze zdjęciem, makro i krokami.
///
/// Wyskok serca przy dodaniu (`BurstHeart`) stoi w drzewie przez cały czas
/// i odtwarzają go keyframe'y na podbicie licznika — bez wstawiania widoku
/// i bez uśpień. Dawniej każde dodanie wstawiało nowe serce do nakładki,
/// które ruszało dopiero po `Task.sleep`: przez pierwsze klatki drugie,
/// nieruchome serce stało w pełnym kryciu na glifie, a wyskok zaczynał się
/// z opóźnieniem. To było przycięcie w pierwszej fazie dodawania, którego
/// odejmowanie (sama zamiana glifu) nie miało (Rafał, 23.09.2026).
struct RecipeFavouriteButton: View {
    enum Style {
        /// Krążek jak krzyżyk arkusza — `SCSheetIconButton` w wariancie na zdjęciu.
        case sheet
        /// Szklane kółko na zdjęciu karty karuzeli.
        case photo
    }

    /// Stan z katalogu — źródło prawdy, gdy nic nie czeka na zapis.
    let isFavourite: Bool
    var style: Style = .sheet
    /// Stan docelowy po ostatnim stuknięciu — do zapisania w katalogu.
    let onCommit: (Bool) -> Void

    @State private var shown: Bool
    /// Licznik dodań — każde podbicie odtwarza wyskok serca od początku.
    @State private var burstCount = 0
    @State private var pendingSync: Task<Void, Never>?

    /// Po tylu ms od ostatniego stuknięcia stan idzie do katalogu — już po
    /// wyskoku serca (0,6 s), więc przeliczanie listy nie wpada w animację.
    private static let syncDelay: Duration = .milliseconds(650)

    init(isFavourite: Bool, style: Style = .sheet, onCommit: @escaping (Bool) -> Void) {
        self.isFavourite = isFavourite
        self.style = style
        self.onCommit = onCommit
        _shown = State(initialValue: isFavourite)
    }

    var body: some View {
        button
            // Dodane do ulubionych: małe serce wyskakuje nad przyciskiem
            // i gaśnie. W spoczynku niewidoczne i nie łapie dotyku.
            .overlay { BurstHeart(trigger: burstCount) }
            .sensoryFeedback(.impact(weight: .light), trigger: shown)
            .onChange(of: isFavourite) { _, value in
                // Zmiana z zewnątrz (inny ekran, cofnięty zapis) wyrównuje
                // serce — ale nie wtedy, gdy własne stuknięcie czeka na zapis.
                guard pendingSync == nil, value != shown else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { shown = value }
            }
    }

    @ViewBuilder
    private var button: some View {
        switch style {
        case .sheet:
            SCSheetIconButton(
                systemName: shown ? "heart.fill" : "heart",
                tint: shown ? SCPalette.terracotta : nil,
                accessibilityLabel: shown ? "Usuń z ulubionych" : "Dodaj do ulubionych",
                onImage: true,
                action: { toggle() }
            )
        case .photo:
            Button {
                toggle()
            } label: {
                Image(systemName: shown ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(shown ? SCPalette.terracotta : Color.white.opacity(0.95))
                    // W górę, jak w szczegółach: stary glif odjeżdża do góry,
                    // nowy wjeżdża od dołu.
                    .contentTransition(.symbolEffect(.replace.upUp))
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(Color.black.opacity(0.40)))
                    }
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    // Cel dotyku 44 pt przy 32-punktowym kółku.
                    .padding(6)
                    .contentShape(Circle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.88))
            .accessibilityLabel(shown ? "Usuń z ulubionych" : "Dodaj do ulubionych")
        }
    }

    private func toggle() {
        let next = !shown
        withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { shown = next }

        // Wyskok rusza w tej samej klatce co zamiana glifu — tylko przy
        // dodaniu; odjęcie to sama zamiana glifu.
        if next { burstCount += 1 }

        pendingSync?.cancel()
        pendingSync = Task { @MainActor in
            try? await Task.sleep(for: Self.syncDelay)
            guard !Task.isCancelled else { return }
            pendingSync = nil
            onCommit(shown)
        }
    }
}

// MARK: - Wyskakujące serce

/// Małe serce, które po dodaniu do ulubionych wyskakuje z przycisku w górę,
/// rośnie i gaśnie.
///
/// Stoi w drzewie przez cały czas, z kryciem zero, a każde podbicie
/// `trigger` odtwarza keyframe'y od początku (`keyframeAnimator`). Nic się
/// nie wstawia i na nic się nie czeka, więc ruch rusza w klatce stuknięcia,
/// razem z zamianą glifu. Krycie wchodzi od zera w 60 ms — w pierwszej
/// klatce nie stoją dwa serca jedno na drugim.
///
/// Nad przyciskiem w szczegółach jest tylko 16 pt do krawędzi arkusza,
/// a arkusz przycina wszystko, co za nią wyjdzie. Środek przycisku stoi 34 pt
/// od krawędzi, więc serce wznosi się o 20 pt i gaśnie, zanim jej dotknie —
/// ta sama droga mieści się też na karcie karuzeli.
///
/// Każda cecha ma własny tor: skok sprężyną, wznoszenie z wyhamowaniem,
/// gaśnięcie dopiero po chwili. Każdy tor zaczyna się od `MoveKeyframe` —
/// kolejne dodanie startuje od zera, a nie od końca poprzedniego wyskoku.
private struct BurstHeart: View {
    let trigger: Int

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(SCPalette.terracotta)
            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            .keyframeAnimator(initialValue: BurstFrame(), trigger: trigger) { heart, frame in
                heart
                    .scaleEffect(frame.scale)
                    .offset(y: frame.rise)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(0.6)
                    SpringKeyframe(1.45, duration: 0.34, spring: Spring(response: 0.34, dampingRatio: 0.62))
                }
                KeyframeTrack(\.rise) {
                    MoveKeyframe(0)
                    LinearKeyframe(-20, duration: 0.6, timingCurve: .easeOut)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.06)
                    LinearKeyframe(1, duration: 0.12)
                    LinearKeyframe(0, duration: 0.42, timingCurve: .easeIn)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Stan jednej klatki wyskoku. Wartości startowe to spoczynek — serce jest
/// w drzewie, ale go nie widać (krycie zero), dopóki nic go nie ruszy.
private struct BurstFrame {
    var scale: CGFloat = 0.6
    /// Przesunięcie w górę (ujemne) od środka przycisku.
    var rise: CGFloat = 0
    var opacity: Double = 0
}
