import Observation
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
    ///
    /// `Hashable`, bo kółko z glifem w kapsule ma tożsamość po stylu
    /// (`.id(style)`) — przy podmianie toastu przenika jako całość.
    enum Style: Hashable {
        /// Udało się — „Zapisano", „Lista zamknięta".
        case success
        /// Neutralna informacja, bez winnego i bez sukcesu.
        case info
        /// Coś wymaga uwagi, ale nic się nie zepsuło.
        case warning
        /// Nie udało się. Domyślne wyjście dla `errorMessage` ze store.
        case error

        /// Barwa akcentu — z osobnego kompletu strojonego na czerń.
        ///
        /// Kapsuła jest czarna niezależnie od motywu aplikacji (dlaczego —
        /// patrz `SCToastHost`), a warianty ciemne w `SCPalette` są strojone
        /// pod `canvasDark`, nie pod #000. Na prawdziwej czerni rozjeżdżały
        /// się prawie trzykrotnie w jasności — stąd `SCPalette.OnBlack`
        /// i tam siedzi całe uzasadnienie liczb.
        ///
        /// Znaczenia idą za tym, co paleta już mówi gdzie indziej: szałwia to
        /// „zrobione" (`scChecked`), indygo „informacyjnie" (`scIndigoTint`),
        /// masło „uwaga / nowe" (`scButterTint`). Błąd ma własną barwę, bo
        /// róż był tu czwartym lokatorem i najmniej natarczywym kolorem
        /// aplikacji w najbardziej natarczywej robocie.
        ///
        /// RUSZASZ TE BARWY? Wartości są w `SCPalette.OnBlack`.
        var accent: Color {
            switch self {
            case .success: SCPalette.OnBlack.sage
            case .info:    SCPalette.OnBlack.indigo
            case .warning: SCPalette.OnBlack.butter
            case .error:   SCPalette.OnBlack.ember
            }
        }

        /// Glif WYCIĘTY w krążku. `SCToastHost` wypełnia krążek akcentem
        /// i rysuje glif w czerni kapsuły, więc kontrast glifu równa się
        /// kontrastowi akcentu z `SCPalette.OnBlack` — zestrojenie barw
        /// zestraja tym samym glify.
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
    /// Toast na ekranie. Chwilowy ma pierwszeństwo przed trwałym: „Zapisano"
    /// jest odpowiedzią na to, co użytkownik właśnie zrobił, a pasek braku
    /// sieci opisuje tło i po chwili wróci sam.
    var current: SCToast? {
        if let transient { return transient }
        return isPersistentMuted ? nil : persistent
    }

    /// Toast na czas — znika sam po `duration`.
    private var transient: SCToast?

    /// Toast na STAN — zostaje, dopóki trwa to, co go wywołało, i nie ma
    /// własnego licznika. Tak robią aplikacje, w których brak sieci jest
    /// czytelny: komunikat o stanie trwającym nie może znikać po trzech
    /// sekundach, bo wtedy kłamie — stan trwa dalej, tylko już go nie widać.
    private var persistent: SCToast?

    /// Użytkownik odsunął pasek trwały ręką. Wraca dopiero przy następnej
    /// ZMIANIE stanu — pokazywanie go z powrotem od razu byłoby kłótnią
    /// z człowiekiem, który właśnie powiedział, że wie.
    private var isPersistentMuted = false

    /// Licznik zdarzeń godnych dotyku i ogłoszenia: nowy toast chwilowy albo
    /// NOWY pasek stanu W CHWILI, GDY TRAFIA NA EKRAN. Pasek wracający po
    /// chwilowym „Zapisano" go nie podbija — to nie jest nowa wiadomość,
    /// tylko ta sama, znów widoczna. Widok wiesza na tym `sensoryFeedback`
    /// i ogłoszenie VoiceOver, zamiast na tożsamości treści.
    private(set) var feedbackCount = 0

    /// Pasek stanu ustawiony, gdy na ekranie był toast chwilowy — dotyk
    /// należy mu się dopiero, gdy się pokaże. Podbicie licznika w chwili
    /// ustawienia zagrałoby wzorem TEGO, co widać (np. sukcesu „Zapisano"),
    /// a sam pasek wjechałby potem po cichu.
    private var persistentAwaitsFeedback = false

    private var queue: [SCToast] = []
    private var timer: Task<Void, Never>?

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
        if transient == toast {
            armTimer(for: toast)
            return
        }
        // To samo, co mówi już pasek trwały, nie ma po co przyjeżdżać drugi
        // raz jako komunikat na czas.
        if transient == nil, persistent == toast { return }
        guard queue.last != toast else { return }
        guard transient != nil else {
            present(toast)
            return
        }
        guard queue.count < Self.queueLimit else { return }
        queue.append(toast)
    }

    /// Ustawia albo gasi pasek stanu. `nil` znaczy „stan minął".
    func setPersistent(_ toast: SCToast?) {
        guard persistent != toast else { return }
        persistent = toast
        // Nowy stan zaczyna od zera — wcześniejsze odsunięcie ręką dotyczyło
        // poprzedniego zdania, nie tego.
        isPersistentMuted = false
        persistentAwaitsFeedback = false
        guard toast != nil else { return }
        if transient == nil {
            feedbackCount += 1
        } else {
            persistentAwaitsFeedback = true
        }
    }

    /// Zamknięcie ręką — stuknięciem albo machnięciem w górę.
    func dismiss() {
        timer?.cancel()
        timer = nil
        if transient != nil {
            advance()
        } else if persistent != nil {
            isPersistentMuted = true
        }
    }

    private func present(_ toast: SCToast) {
        transient = toast
        feedbackCount += 1
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

    /// Zdejmuje chwilowy toast i wpuszcza następny z kolejki.
    ///
    /// Bez przerwy między nimi: `SCToastHost` podmienia treść W MIEJSCU
    /// (przenikanie plus dojazd wysokości), więc kapsuła nie wraca do wyspy
    /// między dwoma komunikatami. Gdy kolejka jest pusta, `current` samo
    /// wraca do paska trwałego — jeśli jakiś wisi — również w miejscu.
    private func advance() {
        timer = nil
        guard !queue.isEmpty else {
            transient = nil
            // Pasek ustawiony pod toastem chwilowym dostaje dotyk teraz —
            // w chwili, w której naprawdę wjeżdża na ekran.
            if persistentAwaitsFeedback, persistent != nil, !isPersistentMuted {
                persistentAwaitsFeedback = false
                feedbackCount += 1
            }
            return
        }
        present(queue.removeFirst())
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

// MARK: - Most dla zdarzeń bez ekranu

/// Wystawia toast ustawiony przez store, który NIE MA gdzie go pokazać.
///
/// Są w tej aplikacji zdarzenia bez widoku: transakcja App Store zatwierdzona
/// przez rodzica dwie godziny po prośbie dziecka, tura asystenta, która
/// skończyła się, gdy użytkownik patrzył na plan. Nie da się ich powiesić
/// na ekranie, bo w chwili, gdy się dzieją, żadnego właściwego ekranu nie ma.
///
/// `@autoclosure` z tego samego powodu, co przy `scErrorToast`: gdyby korzeń
/// odczytywał `store.backgroundNotice` u siebie, każda transakcja w tle
/// przebudowywałaby całe drzewo aplikacji.
private struct SCBackgroundToastBridge: ViewModifier {
    let toast: () -> SCToast?
    let onShown: () -> Void

    @Environment(\.toasts) private var toasts

    func body(content: Content) -> some View {
        // `initial: true`, w odróżnieniu od `scErrorToast`. Tam stan zastany
        // ma się NIE odtwarzać, bo błąd jest zdarzeniem. Tu jest odwrotnie:
        // pole kasuje się w chwili pokazania, więc niepusta wartość zastana
        // z definicji znaczy „tego jeszcze nikt nie widział".
        //
        // Bez tego przepadał dokładnie ten przypadek, dla którego ten most
        // powstał: zakup dogadany z Apple przy zamkniętej aplikacji dociera
        // w chwili budowania sesji, gdy na ekranie stoi jeszcze loader.
        // Wartość ustawiona przed zamontowaniem mostu nie była dla `onChange`
        // zmianą — nie pokazywała się, nie kasowała, a pole zostawało zajęte
        // do końca sesji i połykało wszystko następne.
        content.onChange(of: toast(), initial: true) { _, new in
            guard let new else { return }
            toasts.show(new)
            // Skasowanie jest NIEZBĘDNE, nie sprzątaniem: `SCToast` porównuje
            // się po treści i ignoruje identyfikator, więc bez powrotu do
            // `nil` drugie takie samo powiadomienie nie zmieniłoby wartości
            // i przepadłoby po cichu.
            onShown()
        }
    }
}

extension View {
    /// Wpina powiadomienia, które store wystawia spoza jakiegokolwiek ekranu.
    func scBackgroundToast(
        _ toast: @autoclosure @escaping () -> SCToast?,
        onShown: @escaping () -> Void
    ) -> some View {
        modifier(SCBackgroundToastBridge(toast: toast, onShown: onShown))
    }
}

// MARK: - Most z monitora łączności

/// Zamienia stan `ConnectivityMonitor` na komunikat u góry ekranu.
///
/// Dwie rzeczy są tu celowo niesymetryczne — i tak samo rozwiązują to
/// aplikacje, w których brak sieci jest czytelny (Slack, Spotify, Gmail):
///
/// - **brak sieci to pasek TRWAŁY.** Stan trwa, więc komunikat nie ma prawa
///   zniknąć sam po trzech sekundach: użytkownik zostałby z przekonaniem, że
///   już wróciło, choć nic nie wróciło. Zamiast tego wisi, dopóki jest czego
///   dotyczyć, i da się go odsunąć ręką.
/// - **powrót to komunikat na CHWILĘ.** To zdarzenie, nie stan. Ma zrobić
///   jedno: zdjąć niepewność i zejść z drogi.
///
/// Sam moment zapalenia jest opóźniony — patrz `ConnectivityMonitor`.
private struct SCConnectivityToastBridge: ViewModifier {
    @Environment(\.toasts) private var toasts

    func body(content: Content) -> some View {
        content
            .onChange(
                of: ConnectivityMonitor.shared.isOffline,
                initial: true
            ) { wasOffline, isOffline in
                guard !isOffline else {
                    toasts.setPersistent(Self.offlineToast())
                    return
                }
                toasts.setPersistent(nil)
                // „Wróciło" tylko po tym, jak naprawdę zniknęło. Przy starcie
                // aplikacji `initial: true` woła to z obiema wartościami
                // równymi `false` i wtedy nie ma czego ogłaszać.
                if wasOffline {
                    toasts.success("Połączenie wróciło")
                }
            }
            // Diagnoza może się zmienić BEZ zmiany samego „jest offline":
            // telefon traci zasięg, gdy pasek mówi już „nie mogę połączyć się
            // ze Scoffie". Monitor nie zgłasza wtedy nic nowego (`isOffline`
            // stoi na `true`), więc bez tego wyzwalacza pasek zostawałby
            // z nieaktualnym zdaniem.
            //
            // Tylko w stronę UTRATY interfejsu. Powrót też zmienia tę flagę,
            // ale wtedy monitor jest w 1,5-sekundowym oknie potwierdzania
            // i pasek zaraz zgaśnie — podmiana zdania w tej chwili kosztowałaby
            // ostrzegawczy dotyk, drugie ogłoszenie VoiceOver i przywrócenie
            // paska, który użytkownik przed sekundą odsunął ręką.
            .onChange(of: ConnectivityMonitor.shared.isPathSatisfied) { _, satisfied in
                guard !satisfied, ConnectivityMonitor.shared.isOffline else { return }
                toasts.setPersistent(Self.offlineToast())
            }
    }

    /// Dwa różne stany, dwa różne zdania. „Sprawdź internet" przy działającym
    /// Wi-Fi wysyła człowieka do restartu routera, który niczego nie naprawi —
    /// a to nie router nie odpowiada.
    private static func offlineToast() -> SCToast {
        SCToast(
            style: .warning,
            title: ConnectivityMonitor.shared.isPathSatisfied
                ? "Nie mogę połączyć się ze Scoffie"
                : "Brak połączenia z internetem",
            message: "Widzisz ostatnio pobrane dane."
        )
    }
}

extension View {
    /// Wpina pasek braku sieci. Zakładany raz, w korzeniu aplikacji.
    func scConnectivityToast() -> some View {
        modifier(SCConnectivityToastBridge())
    }
}
