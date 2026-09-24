import Observation
import SwiftUI
import UIKit

/// Zasłona przejść między fazami aplikacji: logowanie, kreator, pulpit,
/// wylogowanie, usunięcie konta.
///
/// Każda zmiana korzenia idzie tą samą drogą: zasłona w kolorze tła wchodzi
/// nad WSZYSTKO (także nad arkusze), pod nią korzeń przestawia się bez
/// animacji, a potem zasłona schodzi. Wcześniej korzeń robił crossfade sam
/// i widać było, co działo się w jego trakcie:
/// - po założeniu domu pulpit i loader wjeżdżały RAZEM, więc przez pół
///   przejścia przez półprzezroczysty loader prześwitywał Kalendarz;
/// - przy usunięciu konta preferencje czyściły się pod otwartym arkuszem
///   profilu, więc przez chwilę było widać wartości domyślne, a arkusz
///   zjeżdżał już nad pustym pulpitem;
/// - dwa kryjące ekrany w połowie crossfade'u mają po 50 % krycia i przez
///   oba przebijało okno — logowanie → kreator ciemniało w pół drogi.
///
/// Stan sesji czyści się dopiero POD zasłoną: kto kończy sesję, czeka na
/// `cover()` (patrz `SessionStore.signOut()` / `deleteAccount()`).
@Observable
final class SCSessionCurtain {
    /// Cel zasłony. Widok animuje się do niego sam i melduje, kiedy doszedł.
    private(set) var isRaised = false
    /// Zasłona w pełni kryje ekran — pod nią można przestawiać, co się chce.
    private(set) var isCovering = false
    /// Okno zasłony istnieje. Bez niego (podgląd, proces w tle przed sceną)
    /// `cover()` nie ma na co czekać i wraca od razu.
    @ObservationIgnored fileprivate var isInstalled = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Zasłania ekran i wraca, gdy zasłona jest już w pełni kryjąca.
    /// Wołane w trakcie opuszczania — zawraca ją w górę.
    func cover() async {
        guard isInstalled, UIApplication.shared.applicationState != .background else { return }
        if isCovering { return }
        // Klawiatura mieszka w oknie NAD zasłoną — schowana dopiero pod nią
        // zjeżdżałaby po odsłonięciu nad nowym ekranem. Chowa się razem
        // z wejściem zasłony.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            isRaised = true
        }
    }

    /// Odsłania ekran. Kryjąca przestaje być od razu — kolejne `cover()`
    /// musi poczekać, aż zasłona znów dojdzie do góry.
    func lift() {
        isCovering = false
        isRaised = false
    }

    /// Zamyka BEZ animacji wszystko, co okno aplikacji ma przedstawione
    /// (arkusze, pełne ekrany). Wołane pod zasłoną, zanim korzeń się
    /// przestawi: arkusz, którego widok-rodzic znika z drzewa, UIKit zamyka
    /// sam — ale z animacją, i ta animacja szła już po odsłonięciu, nad
    /// ekranem logowania (usunięcie konta z arkusza profilu).
    ///
    /// Alerty zostają: alert zaproszenia wisi nad korzeniem, nie w nim,
    /// a zamknięty z zewnątrz rozjechałby się ze swoim `isPresented`.
    func dismissPresentedScreens() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !($0 is SCSessionCurtainWindow) }
        for window in windows {
            guard let root = window.rootViewController,
                  let presented = root.presentedViewController,
                  !(presented is UIAlertController) else { continue }
            root.dismiss(animated: false)
        }
    }

    fileprivate func didCover() {
        guard isRaised else { return }
        isCovering = true
        resumeWaiters()
    }

    fileprivate func didUncover() {
        // Nikt nie może zawisnąć na zasłonie, która zeszła, zanim doszła
        // do góry — lepiej przestawić korzeń na widoku niż nigdy.
        resumeWaiters()
    }

    private func resumeWaiters() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

// MARK: - Widok

private enum SCSessionCurtainMotion {
    /// Wejście krótsze niż zejście: zakrycie ma nie opóźniać tego, co
    /// użytkownik właśnie zrobił, a odsłonięcie jest tym, co ogląda.
    static let rise: Animation = .easeIn(duration: 0.24)
    static let fall: Animation = .easeOut(duration: 0.36)
}

private struct SCSessionCurtainView: View {
    let curtain: SCSessionCurtain
    @Environment(\.colorScheme) private var scheme
    @State private var opacity: Double = 0
    /// Numer bieżącego ruchu. Przerwany ruch też woła swoje `completion`,
    /// a meldunek ze starego ruchu nie może udawać, że zasłona doszła.
    @State private var generation = 0

    var body: some View {
        Color.scCanvas(scheme)
            .ignoresSafeArea()
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: curtain.isRaised) { _, raised in
                move(raised: raised)
            }
    }

    private func move(raised: Bool) {
        generation += 1
        let current = generation
        withAnimation(raised ? SCSessionCurtainMotion.rise : SCSessionCurtainMotion.fall) {
            opacity = raised ? 1 : 0
        } completion: {
            guard current == generation else { return }
            if raised {
                curtain.didCover()
            } else {
                curtain.didUncover()
            }
        }
    }
}

// MARK: - Okno

/// Okno zasłony: nad arkuszami i alertami aplikacji, pod toastami.
/// Zabiera dotyk tylko wtedy, gdy zasłona stoi — w trakcie przejścia nic
/// pod nią nie ma prawa się stuknąć.
private final class SCSessionCurtainWindow: UIWindow {
    var curtain: SCSessionCurtain?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        curtain?.isRaised == true || curtain?.isCovering == true
    }
}

private struct SCSessionCurtainInstaller: UIViewRepresentable {
    let curtain: SCSessionCurtain
    let colorScheme: ColorScheme?

    func makeUIView(context: Context) -> UIView {
        Installer(curtain: curtain, style: Self.style(for: colorScheme))
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? Installer)?.apply(style: Self.style(for: colorScheme))
    }

    private static func style(for scheme: ColorScheme?) -> UIUserInterfaceStyle {
        switch scheme {
        case .light: .light
        case .dark:  .dark
        default:     .unspecified
        }
    }

    private final class Installer: UIView {
        private let curtain: SCSessionCurtain
        private var overlay: SCSessionCurtainWindow?
        private var style: UIUserInterfaceStyle

        init(curtain: SCSessionCurtain, style: UIUserInterfaceStyle) {
            self.curtain = curtain
            self.style = style
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) nieużywane") }

        /// Osobne okno nie dostaje `preferredColorScheme` aplikacji — bez
        /// tego wymuszony jasny motyw przy ciemnym systemie dawałby ciemną
        /// zasłonę nad kremowym ekranem.
        func apply(style: UIUserInterfaceStyle) {
            self.style = style
            overlay?.overrideUserInterfaceStyle = style
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard overlay == nil, let scene = window?.windowScene else { return }

            let overlay = SCSessionCurtainWindow(windowScene: scene)
            overlay.curtain = curtain
            let host = UIHostingController(rootView: SCSessionCurtainView(curtain: curtain))
            host.view.backgroundColor = .clear
            overlay.rootViewController = host
            overlay.backgroundColor = .clear
            // Tak jak okno toastów: bez `makeKeyAndVisible`, żeby pasek stanu
            // i klawiatura zostały przy oknie aplikacji. Poziom tuż pod
            // toastami (`alert + 1`) — kapsuła „brak sieci” może stać nad
            // zasłoną, reszta aplikacji nie.
            overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue)
            overlay.overrideUserInterfaceStyle = style
            overlay.isHidden = false
            self.overlay = overlay
            curtain.isInstalled = true
        }
    }
}

extension View {
    /// Zakłada okno zasłony przejść sesji (`SCSessionCurtain`).
    func scSessionCurtain(_ curtain: SCSessionCurtain, colorScheme: ColorScheme?) -> some View {
        background {
            SCSessionCurtainInstaller(curtain: curtain, colorScheme: colorScheme)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}
