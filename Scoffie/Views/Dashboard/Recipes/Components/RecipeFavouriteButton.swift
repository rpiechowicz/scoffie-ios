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
    @State private var bursts: [UUID] = []
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
            // i gaśnie. Nakładka nie łapie dotyku.
            .overlay {
                ZStack {
                    ForEach(bursts, id: \.self) { _ in
                        FloatingHeart()
                    }
                }
                .allowsHitTesting(false)
            }
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

        if next {
            let burst = UUID()
            bursts.append(burst)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                bursts.removeAll { $0 == burst }
            }
        }

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
/// Nad przyciskiem w szczegółach jest tylko 16 pt do krawędzi arkusza,
/// a arkusz przycina wszystko, co za nią wyjdzie. Środek przycisku stoi 34 pt
/// od krawędzi, więc serce wznosi się o 20 pt i gaśnie, zanim jej dotknie —
/// ta sama droga mieści się też na karcie karuzeli.
///
/// Każda cecha ma własną krzywą: skok sprężyną, wznoszenie z wyhamowaniem,
/// gaśnięcie dopiero po chwili. Ruch rusza klatkę PO wstawieniu widoku —
/// zmiana stanu w tej samej klatce, w której widok powstaje, nie ma czego
/// interpolować (patrz `PlanAssistantIntroSheet`: „Jedna klatka opóźnienia”).
private struct FloatingHeart: View {
    @State private var isFlying = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(SCPalette.terracotta)
            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
            .scaleEffect(isFlying ? 1.45 : 0.6)
            .animation(.spring(response: 0.34, dampingFraction: 0.62), value: isFlying)
            .offset(y: isFlying ? -20 : 0)
            .animation(.easeOut(duration: 0.6), value: isFlying)
            .opacity(isFlying ? 0 : 1)
            .animation(.easeIn(duration: 0.42).delay(0.18), value: isFlying)
            .task {
                try? await Task.sleep(for: .milliseconds(16))
                isFlying = true
            }
            .accessibilityHidden(true)
    }
}
