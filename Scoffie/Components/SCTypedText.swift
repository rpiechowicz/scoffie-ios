import SwiftUI

/// Tekst, który dopisuje się na oczach — tak, jak asystent pisze odpowiedź
/// (`AssistantRevealedAnswer`), ale dla zdań, które aplikacja zna od razu:
/// powitanie pustej rozmowy, otwarcie sytuacji.
///
/// Układ nie skacze: cały tekst jest złożony od pierwszej klatki, a jeszcze
/// nienapisana końcówka ma przezroczysty kolor. Linie łamią się więc tak
/// samo na początku i na końcu, a blok przyklejony do dołu nie rośnie
/// w trakcie pisania.
///
/// `playKey` mówi, KIEDY pisać: nowa wartość = tekst pisze się od zera,
/// `nil` = tekst stoi w całości. Zmiana samego `text` przy tym samym kluczu
/// nie pisze od nowa, tylko roluje zmienione znaki (`numericText`) — „Za 40
/// minut obiad” przechodzi w „Za 39 minut obiad” jak zegar, nie jak nowe
/// zdanie. Przy „Ogranicz ruch” tekst stoi od razu.
struct SCTypedText: View {
    let text: String
    var playKey: Int?
    /// Znaków na sekundę.
    var rate: Double = 45
    /// Opóźnienie startu po zmianie `playKey`.
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var isTyping = false

    init(_ text: String, playKey: Int?, rate: Double = 45, delay: Double = 0) {
        self.text = text
        self.playKey = playKey
        self.rate = rate
        self.delay = delay
        // Od pierwszej klatki ukryty, gdy ma się pisać — bez błysku całości
        // przed startem zadania.
        _isTyping = State(initialValue: playKey != nil)
    }

    /// Ile trwa napisanie `text` w tempie `rate` — do układania kaskady.
    static func duration(_ text: String, rate: Double = 45) -> Double {
        Double(text.count) / max(rate, 1)
    }

    var body: some View {
        Group {
            if isTyping {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: startedAt == nil)) { context in
                    Text(partial(shown: shownCount(at: context.date)))
                }
            } else {
                Text(text)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: text)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
        .task(id: playKey) { await play() }
    }

    private func play() async {
        guard playKey != nil, !reduceMotion else {
            isTyping = false
            return
        }
        startedAt = nil
        isTyping = true
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        if Task.isCancelled { return }
        startedAt = Date()
        try? await Task.sleep(for: .seconds(Self.duration(text, rate: rate) + 0.05))
        if Task.isCancelled { return }
        isTyping = false
    }

    private func shownCount(at date: Date) -> Int {
        guard let startedAt else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        return min(text.count, Int(elapsed * rate))
    }

    /// Cały tekst, z nienapisaną końcówką w przezroczystym kolorze.
    private func partial(shown: Int) -> AttributedString {
        var attributed = AttributedString(text)
        guard shown < text.count else { return attributed }
        let start = attributed.characters.index(attributed.startIndex, offsetBy: shown)
        attributed[start..<attributed.endIndex].foregroundColor = Color.clear
        return attributed
    }
}
