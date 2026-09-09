import SwiftUI

// MARK: - Geometria wyspy

/// Liczby opisujące Dynamic Island i miejsce, w którym kapsuła ma z niej
/// wyrosnąć.
///
/// Wszystko idzie z bezpiecznego obszaru u góry, a nie z listy modeli
/// telefonów: taka lista starzeje się co wrzesień, a wcięcie jest tym samym
/// pomiarem, który system i tak podaje każdemu widokowi.
enum SCToastMetrics {
    /// Ramka wyspy — identyczna na wszystkich telefonach, które ją mają.
    static let islandSize = CGSize(width: 126, height: 37.33)

    /// Poniżej tej wysokości wcięcia telefon wyspy nie ma.
    ///
    /// Wartości z życia: wyspa 59 albo 62 pt, wcięcie 47/48/50, przycisk
    /// Początek 20, orientacja pozioma 0. Próg 51 rozdziela te grupy
    /// z zapasem po obu stronach — i przy okazji łapie poziomą orientację,
    /// w której wyspa leży z boku i nie da się z niej nic wyprowadzić.
    private static let islandInsetFloor: CGFloat = 51

    /// O ile wyspa stoi WYŻEJ niż górna krawędź bezpiecznego obszaru.
    ///
    /// Jedna liczba na wszystkie telefony, i to nie przypadek: przy wcięciu
    /// 59 pt wyspa zaczyna się 11 pt od góry ekranu, przy 62 pt — 14 pt.
    /// W obu przypadkach 48 pt nad bezpiecznym obszarem, więc tabela modeli
    /// jest niepotrzebna.
    private static let islandTopFromInset: CGFloat = 48

    struct Layout {
        /// Przesunięcie kapsuły względem GÓRNEJ KRAWĘDZI BEZPIECZNEGO OBSZARU
        /// — bo w niej, a nie w krawędzi ekranu, ma początek `GeometryReader`
        /// warstwy toastów. Ujemne wchodzi w pas wyspy, dodatnie schodzi pod
        /// wcięcie.
        var topOffset: CGFloat
        /// Szerokość kapsuły po rozwinięciu.
        var expandedWidth: CGFloat
        /// Czy kapsuła naprawdę wyrasta z wyspy, czy tylko zjeżdża z góry.
        var hasIsland: Bool
    }

    static func layout(in proxy: GeometryProxy) -> Layout {
        let hasIsland = proxy.safeAreaInsets.top >= islandInsetFloor
        // Bez wyspy nie ma czego udawać — kapsuła siada tuż POD bezpiecznym
        // obszarem, żeby nie wejść w zegarek ani we wcięcie.
        let topOffset = hasIsland ? -islandTopFromInset : 8
        let width = min(proxy.size.width - 28, 384)
        return Layout(
            topOffset: topOffset,
            expandedWidth: max(width, islandSize.width),
            hasIsland: hasIsland
        )
    }
}

// MARK: - Widok

/// Kapsuła toastu i cała jej animacja.
///
/// Mieszka w OSOBNYM oknie (`scToastLayer`), nie w drzewie widoków aplikacji.
/// Powód jest prozaiczny: pół tej aplikacji to arkusze — Zakupy, asystent,
/// każdy ekran Ustawień — a arkusz rysuje się nad całą zawartością okna
/// razem z jej nakładkami. Toast wpięty w korzeń byłby niewidoczny dokładnie
/// wtedy, gdy najczęściej ma coś do powiedzenia.
struct SCToastHost: View {
    let center: SCToastCenter

    /// Ramka kapsuły w układzie okna — okno bierze z niej jedyny obszar,
    /// w którym łapie dotyk. Wszystko poza nią ma trafiać do aplikacji pod
    /// spodem, bo okno toastu przykrywa cały ekran.
    var onFrameChange: (CGRect) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Toast rysowany w tej chwili. To NIE jest to samo, co `center.current`:
    /// kolejka zdejmuje toast od razu, a kapsuła musi się jeszcze zwinąć
    /// z powrotem do wyspy. Przez te ~0,4 s żyje tutaj.
    @State private var shown: SCToast?
    @State private var isOpen = false
    @State private var contentHeight: CGFloat = SCToastMetrics.islandSize.height
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        // Świadomie BEZ `ignoresSafeArea`: pod nim `GeometryReader` potrafi
        // zgłosić zerowe wcięcia, a to z nich bierze się cała pozycja kapsuły.
        // Zamiast tego licząc od krawędzi bezpiecznego obszaru wchodzimy
        // w pas wyspy ujemnym przesunięciem — rysowanie poza tę krawędź
        // i tak nie jest przycinane.
        GeometryReader { proxy in
            let layout = SCToastMetrics.layout(in: proxy)

            Group {
                if let shown {
                    capsule(shown, layout: layout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: layout.topOffset)
        }
        .task(id: center.current?.id) { await drive() }
        .sensoryFeedback(trigger: shown?.id) { _, _ in
            shown?.style.feedback
        }
    }

    // MARK: Kapsuła

    @ViewBuilder
    private func capsule(_ toast: SCToast, layout: SCToastMetrics.Layout) -> some View {
        let island = SCToastMetrics.islandSize
        let width = isOpen ? layout.expandedWidth : island.width
        let height = isOpen ? max(island.height, contentHeight) : island.height

        // Czerń jest dosłowna i nie zmienia się z motywem aplikacji: wyspa
        // to wygaszony fragment ekranu OLED, czyli #000. Kapsuła w cieplejszym
        // grafitcie (choćby `scPageBase`) pokazałaby przy krawędziach wyspy
        // szew i cała sztuczka by się rozsypała. Stąd też jasny tekst
        // w obu motywach — na czerni nie ma innego wyjścia.
        Capsule(style: .continuous)
            .fill(.black)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                // Treść ma STAŁĄ szerokość docelową i jest przycinana kształtem
                // kapsuły. Gdyby zwężała się razem z nią, tekst przelewałby
                // się między liniami w trakcie animacji — a to widać.
                content(toast)
                    .frame(width: layout.expandedWidth, alignment: .leading)
                    .opacity(isOpen ? 1 : 0)
                    .blur(radius: reduceMotion || isOpen ? 0 : 2.5)
                    .animation(contentCurve, value: isOpen)
            }
            .clipShape(Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(toast.style.accent.opacity(isOpen ? 0.28 : 0), lineWidth: 0.8)
            }
            // Cień rzuca SPŁASZCZONA kapsuła i nic więcej — stąd
            // `compositingGroup` przed nim i poświata dopiero za nim.
            // Odwrotna kolejność kazałaby SwiftUI policzyć cień także
            // z rozmytej plamy akcentu i spod kapsuły wychodziła wtedy
            // brudna obwódka zamiast miękkiego cienia.
            .compositingGroup()
            .shadow(color: .black.opacity(isOpen ? 0.42 : 0), radius: 18, x: 0, y: 10)
            // Poświata w barwie akcentu — jedyne, co odróżnia tę kapsułę od
            // czarnego prostokąta, i jedyny ślad palety na powierzchni, która
            // musi zostać czarna. Zgaszona do zera w stanie zwiniętym, żeby
            // nic nie wystawało zza prawdziwej wyspy.
            .background {
                Capsule(style: .continuous)
                    .fill(toast.style.accent)
                    .frame(width: width * 0.72, height: height)
                    .blur(radius: 26)
                    .opacity(isOpen ? 0.28 : 0)
                    .offset(y: 8)
            }
            // Niewidoczna kopia treści rozłożona na docelowej szerokości —
            // stąd bierze się wysokość, do której kapsuła ma urosnąć. Bez
            // pomiaru trzeba by ją zgadywać, a Dynamic Type zmienia ją
            // o kilkanaście punktów.
            .background(alignment: .topLeading) {
                content(toast)
                    .frame(width: layout.expandedWidth, alignment: .leading)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        contentHeight = $0
                    }
            }
            .offset(y: dragOffset)
            .animation(morph, value: isOpen)
            .animation(morph, value: contentHeight)
            .contentShape(Capsule(style: .continuous))
            .onTapGesture { center.dismiss() }
            .gesture(dismissDrag)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                onFrameChange($0)
            }
            .onDisappear { onFrameChange(.zero) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(toast.style.accessibilityPrefix) \(toast.title)")
            .accessibilityValue(toast.message ?? "")
            .accessibilityAddTraits(.isStaticText)
    }

    private func content(_ toast: SCToast) -> some View {
        HStack(spacing: 11) {
            Image(systemName: toast.style.icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(toast.style.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(toast.style.accent.opacity(0.18)))
                .overlay(Circle().strokeBorder(toast.style.accent.opacity(0.45), lineWidth: 1))
                // Glif dociąga sprężyną chwilę po tekście — to jedyny ruch,
                // który tu wolno przesadzić, bo jest wielkości paznokcia.
                .scaleEffect(isOpen ? 1 : 0.4)
                .animation(iconCurve, value: isOpen)

            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .scFont(14.5, weight: .semibold, relativeTo: .subheadline)
                    .tracking(-0.2)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let message = toast.message {
                    Text(message)
                        .scFont(12.5, weight: .regular, relativeTo: .caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.vertical, 11)
        // Podłoga wysokości: sama treść jednowierszowa dałaby kapsułę ledwie
        // wyższą od wyspy i rozwinięcie przestałoby być widoczne.
        .frame(minHeight: 54)
    }

    // MARK: Ruch

    /// Wyrastanie i zwijanie. Sprężyna prawie bez odbicia — kapsuła ma
    /// wypłynąć z wyspy, a nie odskoczyć od niej. Zjazd jest krótszy
    /// i sztywniejszy: wracanie tam, skąd się przyszło, nie potrzebuje
    /// tyle uwagi, co pojawienie się.
    private var morph: Animation {
        if reduceMotion { return .easeOut(duration: 0.22) }
        return isOpen
            ? .spring(response: 0.46, dampingFraction: 0.84)
            : .spring(response: 0.34, dampingFraction: 0.94)
    }

    /// Treść wchodzi PO kapsule, nie razem z nią — najpierw otwiera się
    /// czerń, dopiero potem pojawiają się słowa. To ta zwłoka sprawia, że
    /// całość czyta się jak jeden ruch, a nie jak wjeżdżający baner.
    private var contentCurve: Animation {
        if reduceMotion { return .easeOut(duration: 0.2) }
        return isOpen
            ? .easeOut(duration: 0.24).delay(0.07)
            : .easeIn(duration: 0.11)
    }

    private var iconCurve: Animation {
        if reduceMotion { return .easeOut(duration: 0.2) }
        return isOpen
            ? .spring(response: 0.40, dampingFraction: 0.62).delay(0.1)
            : .easeIn(duration: 0.11)
    }

    /// Machnięcie w górę zamyka. W dół kapsuła prawie nie idzie — opór
    /// mówi „tędy nie", zamiast pozwolić przeciągnąć ją na pół ekranu.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let dy = value.translation.height
                dragOffset = dy < 0 ? dy : dy * 0.16
            }
            .onEnded { value in
                let flicked = value.predictedEndTranslation.height < -50
                if value.translation.height < -14 || flicked {
                    center.dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        dragOffset = 0
                    }
                }
            }
    }

    /// Trzyma `shown` w zgodzie z kolejką i rozkłada zmianę na dwie klatki.
    private func drive() async {
        if let incoming = center.current {
            guard shown?.id != incoming.id else { return }
            if shown != nil {
                // Podmiana treści na już otwartej kapsule: najpierw wraca ona
                // do wyspy i dopiero stamtąd wychodzi z nowym zdaniem.
                // Przenikanie w miejscu wyglądałoby jak błąd rysowania, bo
                // między komunikatami zmienia się i szerokość, i wysokość.
                // Tędy przechodzi też powrót paska braku sieci po chwilowym
                // „Zapisano".
                isOpen = false
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            shown = incoming
            dragOffset = 0
            isOpen = false
            // Jedna klatka w stanie zwiniętym. Bez niej SwiftUI policzy
            // wstawienie widoku i otwarcie w jednej transakcji, więc kapsuła
            // pojawi się od razu rozwinięta — bez wyrastania z wyspy.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            isOpen = true
        } else {
            guard shown != nil else { return }
            isOpen = false
            try? await Task.sleep(for: .milliseconds(380))
            // Kolejka mogła w tym czasie wpuścić następny toast — wtedy
            // `drive()` ruszyło od nowa i to zadanie nie ma już nic do
            // sprzątania.
            guard !Task.isCancelled, center.current == nil else { return }
            shown = nil
        }
    }
}

// MARK: - Okno

/// Okno, które przepuszcza dotyk wszędzie poza kapsułą.
///
/// `point(inside:)` zwracające `false` sprawia, że UIKit w ogóle nie
/// rozpatruje tego okna i szuka dalej — pod spodem stoi okno aplikacji.
/// Bez tego przezroczysta nakładka na cały ekran zjadałaby każde stuknięcie.
private final class SCToastWindow: UIWindow {
    var interactiveRect: CGRect = .zero

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Kapsuła zwinięta ma ramkę wyspy i zaraz zniknie — przez te dwie
        // klatki nie ma prawa zabierać stuknięć z okolic wyspy.
        guard interactiveRect.height > SCToastMetrics.islandSize.height + 4 else { return false }
        return interactiveRect.contains(point)
    }
}

/// Zakłada okno toastów przy pierwszym pojawieniu się w scenie.
private struct SCToastWindowInstaller: UIViewRepresentable {
    let center: SCToastCenter

    func makeUIView(context: Context) -> UIView { Installer(toasts: center) }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class Installer: UIView {
        // NIE `center` — `UIView` ma już własne `center` typu `CGPoint`
        // i nazwa po cichu weszłaby z nim w kolizję.
        private let toasts: SCToastCenter
        private var overlay: SCToastWindow?

        init(toasts: SCToastCenter) {
            self.toasts = toasts
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) nieużywane") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard overlay == nil, let scene = window?.windowScene else { return }

            let overlay = SCToastWindow(windowScene: scene)
            let host = UIHostingController(
                rootView: SCToastHost(center: toasts) { [weak overlay] rect in
                    overlay?.interactiveRect = rect
                }
            )
            host.view.backgroundColor = .clear
            overlay.rootViewController = host
            overlay.backgroundColor = .clear
            // Nad wszystkim, co rysuje aplikacja — łącznie z arkuszami
            // i alertami.
            //
            // `makeKeyAndVisible` świadomie NIE, samo `isHidden = false`.
            // Kluczowe okno zostaje przy aplikacji i to jest tu ważniejsze,
            // niż wygląda: pasek stanu i wskaźnik ekranu głównego biorą styl
            // z korzenia okna kluczowego. Przejęcie klucza przez nakładkę
            // przestawiłoby kolor zegarka na cudzy — a ona nie ma pojęcia,
            // jaki motyw wybrał użytkownik. Przy okazji klawiatura i pole
            // tekstowe zostają tam, gdzie były.
            overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
            overlay.isHidden = false
            self.overlay = overlay
        }
    }
}

extension View {
    /// Zakłada warstwę toastów nad całą aplikacją i wpina kolejkę do
    /// środowiska, żeby dowolny widok mógł sięgnąć po `@Environment(\.toasts)`.
    func scToastLayer(_ center: SCToastCenter) -> some View {
        environment(\.toasts, center)
            .background {
                SCToastWindowInstaller(center: center)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Podgląd

/// Podgląd rysuje kapsułę wprost w drzewie widoków (bez osobnego okna) —
/// w kanwie Xcode nie ma sceny, w której dałoby się je założyć.
private struct SCToastPreviewStage: View {
    @Environment(\.colorScheme) private var scheme
    @State private var center = SCToastCenter()

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme).ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()
                SCSoftButton(title: "Zapisano", trailingIcon: nil, accent: SCPalette.sage) {
                    center.success("Plan zapisany", "Czwartek, 4 posiłki")
                }
                SCSoftButton(title: "Informacja", trailingIcon: nil, accent: SCPalette.indigo) {
                    center.info("Lista zamknięta")
                }
                SCSoftButton(title: "Uwaga", trailingIcon: nil, accent: SCPalette.butter) {
                    center.warning("Cookidoo prosi o ponowne logowanie")
                }
                SCSoftButton(title: "Błąd", trailingIcon: nil, accent: SCPalette.rose) {
                    center.error("Nie udało się zapisać", "Spróbuj ponownie za chwilę.")
                }
                // Pasek stanu: zostaje, dopóki go nie zgasisz, i wraca po
                // każdym komunikacie chwilowym. Tak wygląda brak sieci.
                SCSoftButton(title: "Pasek: brak sieci", trailingIcon: nil, accent: SCPalette.butter) {
                    center.setPersistent(
                        SCToast(
                            style: .warning,
                            title: "Brak połączenia z internetem",
                            message: "Widzisz ostatnio pobrane dane."
                        )
                    )
                }
                SCSoftButton(title: "Pasek: zgaś", trailingIcon: nil, accent: SCPalette.sage) {
                    center.setPersistent(nil)
                    center.success("Połączenie wróciło")
                }
                Spacer()
            }
            .padding(24)

            SCToastHost(center: center)
        }
    }
}

#Preview("Toasty — ciemny") {
    SCToastPreviewStage().preferredColorScheme(.dark)
}

#Preview("Toasty — jasny") {
    SCToastPreviewStage().preferredColorScheme(.light)
}
