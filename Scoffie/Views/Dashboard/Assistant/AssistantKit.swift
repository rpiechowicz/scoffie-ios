import SwiftUI

// Powłoka ekranu asystenta — nagłówek, szkic odpowiedzi w trakcie tury
// i linia „Uwzględniłem”. Wiersz „myślę" nad odpowiedzią żyje
// w `AssistantThoughtLine.swift`, atomy kart w `AssistantCardKit.swift`,
// briefing pustego ekranu w `AssistantBriefingCard.swift`.

// MARK: - Nagłówek

/// Nagłówek zakładki w dwóch rozmiarach.
///
/// Duży tytuł ma sens wyłącznie na pustym ekranie — w trwającej rozmowie
/// zjada wiersz treści, a tytuł rozmowy niesie więcej informacji niż słowo
/// „Asystent”. Kompaktowy pasek oddaje te ~40 pt strumieniowi wiadomości.
enum AssistantHeaderMode: Equatable {
    case large
    /// Tytuł nadaje serwer z pierwszej wiadomości; `nil` = jeszcze nie doszedł.
    case compact(title: String?)
}

struct AssistantHeader<MenuContent: View>: View {
    typealias Mode = AssistantHeaderMode

    let mode: Mode
    var onNewConversation: () -> Void
    /// Plakietka po lewej od akcji — stan puli w trakcie próby.
    var accessory: AnyView?
    /// Pozycje menu ⋯ — systemowe `Menu` z ikonami, nie arkusz z dołu.
    @ViewBuilder var menu: () -> MenuContent

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch mode {
        case .large:
            // `.center`, nie `.top`: plakietka (28 pt) i przycisk ⋯ (38 pt)
            // mają różne wysokości. Bez `Spacer`a: tytuł bierze resztę
            // i w razie czego schodzi do 0,9 skali, plakietka — swój rozmiar.
            HStack(alignment: .center, spacing: 10) {
                Text("Asystent")
                    .font(.system(size: 32, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                accessory
                    .fixedSize(horizontal: true, vertical: false)
                actions(compact: false)
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.top, SCPageMetrics.top)
            .padding(.bottom, 12)

        case let .compact(title):
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Asystent")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(SCPalette.terracotta)

                    Text(title ?? "Nowa rozmowa")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                accessory
                    .fixedSize(horizontal: true, vertical: false)
                actions(compact: true)
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.top, 58)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func actions(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact {
                // W rozmowie „nowa” jest częstsza niż menu — i to ona wygrywa
                // miejsce przy krawędzi. Historia siedzi w menu ⋯.
                EditorialIconButton(icon: "square.and.pencil", accessibilityTitle: "Nowa rozmowa", action: onNewConversation)
                menuButton
            } else {
                menuButton
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Ta sama pigułka co `EditorialIconButton`, ale jako etykieta `Menu`.
    private var menuButton: some View {
        Menu {
            menu()
        } label: {
            SCCircleIconLabel(icon: "ellipsis", size: 38)
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Więcej opcji asystenta")
    }
}

// MARK: - Szkic odpowiedzi

/// Szkic odpowiedzi w trakcie tury — tekst „pisze się" pod wskaźnikiem.
///
/// Serwer streamuje z modelu, ale telefon odpytuje co sekundę, więc bez
/// tego widoku tekst wskakiwałby akapitami raz na sekundę. Tu odsłania się
/// znak po znaku i DOGANIA serwer w ~0,9 s od każdej porcji — oko widzi
/// ciągłe pisanie, a nie serię skoków. Liczone z zegara względem kotwicy
/// ustawianej przy każdej zmianie tekstu; żadnej pętli na `@State`, więc
/// przebudowy widoku (nowy krok postępu, nowa porcja) niczego nie zatrzymują.
///
/// Serwer oddaje CAŁY dotychczasowy tekst, nie przyrost — i potrafi go
/// wyzerować, gdy runda skończyła się narzędziem (preambuła „sprawdzę plan…"
/// nie jest odpowiedzią). Gdy nowy tekst nie zaczyna się od pokazanego,
/// odsłanianie rusza od zera zamiast pokazywać znaki, których już nie ma.
struct AssistantDraftAnswer: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchorDate = Date()
    @State private var anchorCount = 0
    /// Znaki na sekundę; rośnie z zaległością, żeby nigdy nie zostać w tyle.
    @State private var rate: Double = 45

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let shown = reduceMotion ? text.count : revealedCount(at: context.date)
            AssistantAnswer(text: String(text.prefix(shown)))
        }
        .onChange(of: text) { old, new in
            let now = Date()
            let current = min(revealedCount(at: now), new.count)
            let continues = new.hasPrefix(String(old.prefix(current)))
            anchorCount = continues ? current : 0
            anchorDate = now
            rate = max(45, Double(new.count - anchorCount) / 0.9)
        }
    }

    private func revealedCount(at date: Date) -> Int {
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        return min(text.count, anchorCount + Int(elapsed * rate))
    }
}

// MARK: - „Uwzględniłem: …”

/// Jedna linia pod odpowiedzią: z czym serwer ją policzył (tydzień, dla
/// kogo, cel). To jest miejsce, w którym łapie się, że asystent wziął złego
/// domownika.
struct AssistantUsedContextLine: View {
    let items: [String]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.scFaint(scheme))
                .padding(.top, 2)
            Text("Uwzględniłem: " + items.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
