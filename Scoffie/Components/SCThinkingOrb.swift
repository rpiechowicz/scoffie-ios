import SwiftUI

/// Orb „asystent pracuje" — kropki krążące w kuli, rysowane na `Canvas`.
///
/// Po co, skoro kręciołek już był: kręciołek mówi „czekaj" i nic więcej.
/// Tura asystenta trwa 25–240 s i przechodzi przez etapy o zupełnie różnym
/// charakterze — czytanie planu, przekazanie planiście, zapis. Orb pokazuje
/// TEN etap: inne tempo, inne rozproszenie, inny kolor. Użytkownik po samym
/// ruchu poznaje, że coś się zmieniło, zanim przeczyta nową linijkę.
///
/// **Faza liczy się z ZEGARA, nie ze stanu.** To nie jest wybór stylu, tylko
/// warunek działania: każdy nowy krok postępu przebudowuje ten widok, a
/// animacja na `@State` + `repeatForever` zastyga wtedy w miejscu, bo
/// `value:` już się nie zmienia (dokładnie ten błąd miał `Spinner`
/// w `AssistantKit`, patrz komentarz przy nim). Czas nie ma stanu, który
/// dałoby się zgubić przy przebudowie.
///
/// `Canvas` zamiast kilkunastu `Circle()` w `ZStack`: rysowanie kropek to
/// jedna warstwa i jeden przebieg, a nie kilkanaście węzłów widoku
/// przeliczanych przy każdej klatce. Przy 20 pt w wierszu postępu to jest
/// różnica między niczym a zauważalnym kosztem, bo takich wierszy bywa kilka.
struct SCThinkingOrb: View {
    /// Co asystent właśnie robi. Wybiera tempo, rozrzut i kolor — nazwy idą
    /// za CZYNNOŚCIĄ, nie za narzędziem, bo narzędzi jest dwadzieścia,
    /// a charakterów ruchu cztery.
    ///
    /// NIE `State`: zagnieżdżony typ o tej nazwie przesłania `SwiftUI.State`
    /// w całym ciele tego widoku i pierwsze `@State` dodane tu w przyszłości
    /// przestałoby się kompilować z komunikatem o niczym.
    enum Activity {
        /// Nic jeszcze nie wiadomo — spokojny oddech.
        case idle
        /// Czyta, szuka, sprawdza: szybko i nerwowo.
        case searching
        /// Układa plan (przekazanie planiście): wolniej, gęściej, głębiej.
        case planning
        /// Zapisuje: kropki zbierają się w pierścień.
        case saving
    }

    var activity: Activity = .idle
    var size: CGFloat = 20
    /// Kolor wiodący; stan `planning` i `saving` mają własne, bo to są
    /// momenty, na które warto spojrzeć.
    var tint: Color = SCPalette.terracotta

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ile kropek. Więcej nie znaczy lepiej: przy 20 pt dwanaście kropek
    /// zlewa się w szary placek.
    private var dotCount: Int { size >= 40 ? 14 : 8 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            Canvas { canvas, canvasSize in
                draw(
                    in: &canvas,
                    size: canvasSize,
                    time: context.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(in canvas: inout GraphicsContext, size canvasSize: CGSize, time: TimeInterval) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = min(canvasSize.width, canvasSize.height) / 2
        let profile = Profile(activity: activity, tint: tint)
        // Przy wyłączonych animacjach zamrażamy czas zamiast zatrzymywać
        // rysowanie: orb ma dalej wyglądać jak orb, tylko bez ruchu.
        let t = reduceMotion ? 0 : time

        // Poświata pod kropkami — bez niej kula przy 20 pt czyta się jak
        // przypadkowy pył, a nie jak jeden obiekt.
        let glow = radius * (0.62 + 0.06 * sin(t * profile.breathSpeed))
        canvas.fill(
            Path(
                ellipseIn: CGRect(
                    x: center.x - glow,
                    y: center.y - glow,
                    width: glow * 2,
                    height: glow * 2
                )
            ),
            with: .color(profile.color.opacity(0.14))
        )

        for index in 0..<dotCount {
            let seed = Double(index) / Double(dotCount)
            // Każda kropka ma własne przesunięcie fazy, więc kula „żyje"
            // zamiast obracać się jak sztywne koło.
            let angle = seed * 2 * .pi + t * profile.spinSpeed
            // Oddech promienia: kropki wchodzą do środka i wracają. Przy
            // `saving` amplituda jest bliska zeru, więc zbierają się
            // w pierścień — to jest ten moment „zapisuję".
            let wobble = sin(t * profile.breathSpeed + seed * 6.28) * profile.spread
            let distance = radius * (profile.orbit + wobble)

            let point = CGPoint(
                x: center.x + cos(angle) * distance,
                y: center.y + sin(angle) * distance
            )
            let dot = radius * profile.dotScale * (0.75 + 0.25 * cos(t * profile.breathSpeed + seed * 3.14))
            canvas.fill(
                Path(
                    ellipseIn: CGRect(
                        x: point.x - dot,
                        y: point.y - dot,
                        width: dot * 2,
                        height: dot * 2
                    )
                ),
                with: .color(profile.color.opacity(0.55 + 0.45 * seed))
            )
        }
    }

    /// Liczby, które odróżniają stany. Trzymane razem, bo dobiera się je
    /// wzrokiem i porównując do siebie, a nie po jednej.
    private struct Profile {
        let spinSpeed: Double
        let breathSpeed: Double
        /// Promień orbity jako ułamek połowy rozmiaru.
        let orbit: Double
        /// O ile kropki wędrują w głąb i na zewnątrz.
        let spread: Double
        let dotScale: Double
        let color: Color

        init(activity: Activity, tint: Color) {
            switch activity {
            case .idle:
                spinSpeed = 0.6
                breathSpeed = 1.5
                orbit = 0.5
                spread = 0.10
                dotScale = 0.11
                color = tint
            case .searching:
                // Szybko i z rozrzutem: „szukam" ma wyglądać na krzątaninę.
                spinSpeed = 2.2
                breathSpeed = 3.4
                orbit = 0.58
                spread = 0.20
                dotScale = 0.10
                color = tint
            case .planning:
                // Wolniej i ciaśniej niż szukanie — to jest droższa,
                // dłuższa część tury i ma wyglądać na skupienie, nie na pośpiech.
                spinSpeed = 0.9
                breathSpeed = 1.1
                orbit = 0.44
                spread = 0.16
                dotScale = 0.14
                color = SCPalette.indigo
            case .saving:
                // Bez oddechu: kropki stoją w pierścieniu i tylko się obracają.
                spinSpeed = 1.6
                breathSpeed = 0.8
                orbit = 0.62
                spread = 0.02
                dotScale = 0.12
                color = SCPalette.sage
            }
        }
    }
}

extension SCThinkingOrb.Activity {
    /// Stan orbu dla kroku postępu z serwera.
    ///
    /// Mapowanie idzie po POLACH koperty, nie po liście nazw narzędzi:
    /// `phase` i `writes` liczy serwer, więc dwudzieste narzędzie dostanie
    /// sensowny ruch bez wydania aplikacji. Gdyby to była lista nazw, każde
    /// nowe narzędzie kręciłoby się jak „szukam" do następnego wydania.
    static func forStep(isHandoff: Bool, writes: Bool) -> Self {
        if isHandoff { return .planning }
        if writes { return .saving }
        return .searching
    }
}

#Preview("Stany orbu") {
    HStack(spacing: 28) {
        VStack { SCThinkingOrb(activity: .idle, size: 56); Text("idle").font(.caption) }
        VStack { SCThinkingOrb(activity: .searching, size: 56); Text("szukam").font(.caption) }
        VStack { SCThinkingOrb(activity: .planning, size: 56); Text("planuję").font(.caption) }
        VStack { SCThinkingOrb(activity: .saving, size: 56); Text("zapisuję").font(.caption) }
    }
    .padding(32)
}
