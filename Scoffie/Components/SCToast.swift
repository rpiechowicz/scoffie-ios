import SwiftUI

// MARK: - Model

/// Jedno wewnętrzne powiadomienie — kapsuła, która wyrasta z Dynamic Island.
///
/// „Z wyspy" jest tu FORMĄ, nie mechanizmem, i to jest świadoma decyzja.
/// Prawdziwej wyspy nie da się użyć jako kanału na toasty: jedyne publiczne
/// wejście na nią to ActivityKit, a Live Activity WŁASNEJ aplikacji system
/// chowa, kiedy ta aplikacja jest na wierzchu — czyli dokładnie wtedy, gdy
/// toast ma się pokazać. Do tego Live Activity opisuje zdarzenie trwające
/// (gotowanie, dostawa), a nie zdanie na trzy sekundy, i wymagałaby osobnego
/// targetu widżetu.
///
/// Rysujemy więc kapsułę sami: w stanie zwiniętym ma DOKŁADNIE ramkę wyspy,
/// po czym rozwija się w dół. Złudzenie jest pełne, a kosztuje jeden plik
/// zamiast nowego targetu i tłumaczenia się przy przeglądzie w App Store.
///
/// Toast jest wyłącznie informacyjny — nie ma akcji ani celu nawigacji.
/// Stuknięcie i machnięcie w górę tylko go zamykają.
struct SCToast: Identifiable, Equatable {
    let id = UUID()
    let style: Style
    /// Zdanie główne. Ma się zmieścić w jednej linii przy zwykłym Dynamic
    /// Type — kapsuła nie jest miejscem na akapit.
    let title: String
    /// Doprecyzowanie pod tytułem. `nil` zostawia kapsułę niską.
    let message: String?

    init(style: Style, title: String, message: String? = nil) {
        self.style = style
        self.title = title
        self.message = message
    }

    /// Dwa toasty są „tym samym", gdy niosą tę samą treść — identyfikator
    /// jest z definicji różny, więc nie może brać udziału w porównaniu.
    /// Na tym stoi tłumienie powtórek w `SCToastCenter`.
    static func == (lhs: SCToast, rhs: SCToast) -> Bool {
        lhs.style == rhs.style && lhs.title == rhs.title && lhs.message == rhs.message
    }

    /// Ile toast zostaje na ekranie.
    ///
    /// Nie stała, bo „Zapisano" czyta się w sekundę, a zdanie o zerwanym
    /// połączeniu — nie. Podłoga zależy od wagi, sufit od tego, ile czasu
    /// da się zabrać ekranowi, na który użytkownik właśnie patrzy.
    var duration: Duration {
        let base: Double = switch style {
        case .success, .info: 2.6
        case .warning:        3.2
        case .error:          4.0
        }
        let characters = title.count + (message?.count ?? 0)
        let read = 1.5 + Double(characters) * 0.05
        return .seconds(min(6.5, max(base, read)))
    }

    /// Waga zdarzenia. Wybiera barwę akcentu, glif i dotyk.
    enum Style: Equatable {
        /// Udało się — „Zapisano", „Lista zamknięta".
        case success
        /// Neutralna informacja, bez winnego i bez sukcesu.
        case info
        /// Coś wymaga uwagi, ale nic się nie zepsuło.
        case warning
        /// Nie udało się. Domyślne wyjście dla `errorMessage` ze store.
        case error

        /// Barwa akcentu — ZAWSZE w wariancie na ciemne tło.
        ///
        /// Kapsuła jest czarna niezależnie od motywu aplikacji (dlaczego —
        /// patrz `SCToastHost`), więc nie może brać koloru rozwiązanego przez
        /// trait telefonu. `SCPalette.sage` w jasnym motywie to zieleń
        /// przyciemniona pod krem; położona na czerni gaśnie w błoto.
        ///
        /// Sama czwórka barw idzie za tym, co paleta już znaczy gdzie indziej:
        /// szałwia to „zrobione" (`scChecked`), indygo „informacyjnie"
        /// (`scIndigoTint`), masło „uwaga / nowe" (`scButterTint`). Róż jest
        /// jedynym czerwonym w palecie — surowy `Color.red`, który stał
        /// dotąd w czerwonych wierszach błędu, nie należy do tej aplikacji.
        var accent: Color {
            switch self {
            case .success: Self.onBlack(SCPalette.sage)
            case .info:    Self.onBlack(SCPalette.indigo)
            case .warning: Self.onBlack(SCPalette.butter)
            case .error:   Self.onBlack(SCPalette.rose)
            }
        }

        /// Glif w kółku po lewej. Nagi, bez własnej obwódki — kółko wokół
        /// niego rysuje `SCToastHost`, tym samym zestawem liczb, co
        /// `scSoftSurface`.
        var icon: String {
            switch self {
            case .success: "checkmark"
            case .info:    "info"
            case .warning: "exclamationmark"
            case .error:   "xmark"
            }
        }

        /// Dotyk towarzyszący wjazdowi. Ta sama czwórka, co w reszcie
        /// aplikacji (`sensoryFeedback` w Zakupach i u asystenta).
        var feedback: SensoryFeedback {
            switch self {
            case .success: .success
            case .info:    .impact(flexibility: .soft)
            case .warning: .warning
            case .error:   .error
            }
        }

        /// Etykieta dla VoiceOver — kolor i glif same z siebie nic nie mówią.
        var accessibilityPrefix: String {
            switch self {
            case .success: "Gotowe."
            case .info:    "Informacja."
            case .warning: "Uwaga."
            case .error:   "Błąd."
            }
        }

        /// Rozwiązuje barwę z palety w wariancie ciemnym, cokolwiek ustawił
        /// użytkownik. Paleta zostaje jedynym źródłem prawdy — nie ma tu
        /// drugiego kompletu liczb, który mógłby się z nią rozjechać.
        private static func onBlack(_ color: Color) -> Color {
            Color(uiColor: UIColor(color).resolvedColor(
                with: UITraitCollection(userInterfaceStyle: .dark)
            ))
        }
    }
}

// MARK: - Kolejka

/// Jedyne wejście do toastów. Trzyma ten, który jest na ekranie, i kolejkę
/// tych, które czekają.
///
/// Kolejka, a nie stos naraz: kapsuła udaje wyspę, a wyspa jest jedna.
/// Dwa toasty jednocześnie zdradziłyby, że to zwykły widok — i zabrałyby
/// górę ekranu, na której w Kalendarzu i Planie stoi nagłówek.
@MainActor
@Observable
final class SCToastCenter {
    /// Toast na ekranie. `nil` znaczy, że nie ma czego pokazywać — ale widok
    /// może jeszcze przez chwilę domykać poprzedni (patrz `gap`).
    private(set) var current: SCToast?

    private var queue: [SCToast] = []
    private var timer: Task<Void, Never>?

    /// Ile czeka kapsuła między zjazdem jednego toastu a wjazdem następnego.
    /// Bez tej przerwy druga treść wskakuje w połowie zwijania i całość czyta
    /// się jak mignięcie, a nie jak dwa osobne komunikaty.
    private static let gap: Duration = .milliseconds(420)

    /// Ile toastów czeka w kolejce. Powyżej tego nowe są odrzucane — seria
    /// dwudziestu błędów po zerwanym połączeniu nie ma prawa zająć górnej
    /// krawędzi ekranu na minutę.
    private static let queueLimit = 3

    nonisolated init() {}

    // MARK: Wygodne wejścia

    func success(_ title: String, _ message: String? = nil) {
        show(SCToast(style: .success, title: title, message: message))
    }

    func info(_ title: String, _ message: String? = nil) {
        show(SCToast(style: .info, title: title, message: message))
    }

    func warning(_ title: String, _ message: String? = nil) {
        show(SCToast(style: .warning, title: title, message: message))
    }

    func error(_ title: String, _ message: String? = nil) {
        show(SCToast(style: .error, title: title, message: message))
    }

    /// Błąd prosto z warstwy sieci — kopia idzie przez ten sam mapper, co
    /// komunikaty w store, żeby użytkownik nie zobaczył dwóch różnych zdań
    /// o tej samej awarii.
    func error(_ error: Error) {
        show(SCToast(style: .error, title: UserFacingErrorMapper.message(from: error)))
    }

    // MARK: Sterowanie

    func show(_ toast: SCToast) {
        // Ten sam komunikat, który właśnie wisi, nie miga drugi raz — tylko
        // przedłuża pobyt. Store potrafi ustawić `errorMessage` dwa razy pod
        // rząd (rollback, a zaraz po nim kolejny nieudany load), a użytkownik
        // ma z tego zobaczyć jedno zdanie, nie dwa identyczne.
        if current == toast {
            armTimer(for: toast)
            return
        }
        guard queue.last != toast else { return }
        guard current != nil else {
            present(toast)
            return
        }
        guard queue.count < Self.queueLimit else { return }
        queue.append(toast)
    }

    /// Zamknięcie ręką — stuknięciem albo machnięciem w górę.
    func dismiss() {
        timer?.cancel()
        timer = nil
        advance()
    }

    private func present(_ toast: SCToast) {
        current = toast
        armTimer(for: toast)
    }

    private func armTimer(for toast: SCToast) {
        timer?.cancel()
        timer = Task { [weak self, duration = toast.duration] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.advance()
        }
    }

    /// Zdejmuje bieżący toast i — po przerwie na zwinięcie kapsuły — wpuszcza
    /// następny z kolejki.
    private func advance() {
        current = nil
        timer = nil
        guard !queue.isEmpty else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.gap)
            guard !Task.isCancelled, let self, !self.queue.isEmpty else { return }
            self.present(self.queue.removeFirst())
        }
    }
}

// MARK: - Environment

private struct SCToastCenterKey: EnvironmentKey {
    @MainActor static let defaultValue = SCToastCenter()
}

extension EnvironmentValues {
    /// Kolejka toastów. Domyślna instancja jest prawdziwa, tylko niczym nie
    /// obsadzona — dzięki temu podglądy (`#Preview`) wołają `toasts.success(…)`
    /// bez obstawiania całego korzenia aplikacji.
    var toasts: SCToastCenter {
        get { self[SCToastCenterKey.self] }
        set { self[SCToastCenterKey.self] = newValue }
    }
}

// MARK: - Most ze store

/// Podaje toastowi każdy NOWY komunikat błędu ze store.
///
/// Wisi raz, w korzeniu aplikacji, a nie na każdym ekranie z osobna — i to
/// jest cała różnica względem czerwonych wierszy, które stały wcześniej
/// w Kalendarzu, Zakupach i Przepisach. Tamte pokazywały błąd wyłącznie
/// wtedy, gdy użytkownik akurat patrzył na tę zakładkę; nieudany load
/// katalogu obejrzany z Ustawień przepadał bez śladu. Tu store jest globalny,
/// warstwa toastów też, więc komunikat dociera zawsze.
///
/// Świadomie tylko `onChange`, bez odczytu stanu przy pojawieniu się widoku:
/// błąd jest ZDARZENIEM. Gdyby toast wjeżdżał też za stan zastany, wracanie
/// na zakładkę odtwarzałoby w kółko tę samą starą awarię.
/// Komunikat przychodzi ZAMKNIĘTY W DOMKNIĘCIU (`@autoclosure`), a nie jako
/// gotowa wartość, i to nie jest ozdoba. Gdyby korzeń aplikacji odczytywał
/// `store.errorMessage` u siebie, obserwacja zapięłaby się na jego ciele
/// i każdy nieudany load przebudowywałby całe drzewo — z ekranem startowym
/// i przejściami włącznie. Odczyt w ciele modyfikatora unieważnia tylko jego.
private struct SCErrorToastBridge: ViewModifier {
    let message: () -> String?

    @Environment(\.toasts) private var toasts

    func body(content: Content) -> some View {
        content.onChange(of: message()) { _, new in
            guard let new,
                  !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            toasts.error(new)
        }
    }
}

extension View {
    /// Wystawia `errorMessage` store jako toast.
    func scErrorToast(_ message: @autoclosure @escaping () -> String?) -> some View {
        modifier(SCErrorToastBridge(message: message))
    }
}
