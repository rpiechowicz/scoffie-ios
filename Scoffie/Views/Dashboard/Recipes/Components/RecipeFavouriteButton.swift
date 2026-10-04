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
/// Przy dodaniu serce podskakuje i wokół rozbiegają się kropki (`ThumbCheer`,
/// ten sam „like” co w Gotuj i u Asystenta) — oba stoją w drzewie przez cały
/// czas i ruszają na podbicie licznika, bez wstawiania widoków i uśpień
/// (dawny `BurstHeart` ze wstawianym sercem przycinał pierwszą fazę).
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
            // Dodane do ulubionych: serce podskakuje, a wokół rozbiegają się
            // kropki w terakocie — ten sam „like” co kciuk na zakończeniu
            // Gotuj i pod odpowiedzią Asystenta (`ThumbCheer`, Rafał
            // 4.10.2026: „like na feature Gotuj jest super, zrób podobnie”).
            // Dawniej małe serce wyskakiwało w górę (`BurstHeart`).
            .symbolEffect(.bounce.up.byLayer, value: burstCount)
            .overlay { ThumbCheer(trigger: burstCount, tint: SCPalette.terracotta) }
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
                    .scPhotoGlass(in: Circle())
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
