import Observation
import SwiftUI
import UIKit

/// Wyłącznik starych buildów (2.10.2026): serwer mówi, czy ta wersja może
/// jeszcze działać (`GET /public/app-version`, backend `config/app-version.ts`),
/// a gdy nie — aplikację zasłania ekran „Zaktualizuj Scoffie”.
///
/// Pyta przy starcie i po każdym powrocie na wierzch (najwyżej raz na minutę),
/// bez logowania — ekran ma zadziałać też na logowaniu i przy zepsutej sesji.
/// KAŻDY kłopot (brak sieci, 404 starszego backendu, 429, zły JSON) PRZEPUSZCZA:
/// sprawdzenie, które się nie udało, nigdy nie blokuje aplikacji. Decyzję
/// podejmuje serwer (`updateRequired`) — telefon wersji nie porównuje.
@Observable
final class SCAppUpdateGate {
    /// Ta wersja jest za stara — ekran zasłania wszystko.
    private(set) var isRequired = false
    private(set) var storeURL = SCAppUpdateGate.defaultStoreURL

    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private var inFlight = false

    static let defaultStoreURL = URL(string: "https://apps.apple.com/app/id6808608589")!
    private static let minimumInterval: TimeInterval = 60

    private struct Status: Decodable {
        let updateRequired: Bool
        let storeUrl: String?
    }

    /// `force` — przy starcie, bez patrzenia na ostatnie sprawdzenie.
    func check(force: Bool = false) async {
        if inFlight { return }
        if !force, let lastCheck, Date().timeIntervalSince(lastCheck) < Self.minimumInterval { return }
        inFlight = true
        defer { inFlight = false }

        // Nieudane sprawdzenie nie liczy się do odstępu — następny powrót
        // na wierzch spróbuje znowu.
        guard let status = await Self.fetch() else { return }
        lastCheck = Date()
        if let raw = status.storeUrl, let url = URL(string: raw) {
            storeURL = url
        }
        if status.updateRequired && !isRequired {
            // Klawiatura mieszka w oknie NAD tym ekranem — chowa się z nim.
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
        isRequired = status.updateRequired
    }

    private static func fetch() async -> Status? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard var components = URLComponents(
            url: AppEnvironment.apiBaseURL.appendingPathComponent("public/app-version"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "version", value: version),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Status.self, from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Ekran

private struct SCAppUpdateRequiredView: View {
    let gate: SCAppUpdateGate
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            if gate.isRequired {
                content
                    // VoiceOver omija `point(inside:)` — bez tego dałoby się
                    // gestem przejść do aplikacji pod spodem.
                    .accessibilityAddTraits(.isModal)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: gate.isRequired)
    }

    private var content: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                SCScoffieMark(size: 72)
                    .padding(.bottom, 24)
                Text("Zaktualizuj Scoffie")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Color.scLabel(scheme))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
                Text("Ta wersja nie jest już obsługiwana. Nowa czeka w App Store.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.scMuted(scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                EditorialPrimaryActionButton(
                    title: "Zaktualizuj",
                    icon: "arrow.down.circle.fill",
                    action: { openURL(gate.storeURL) }
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Okno

/// Okno nad WSZYSTKIM: arkuszami, trybem Gotuj, zasłoną sesji i toastami
/// (`alert + 2`). Zabiera dotyk tylko wtedy, gdy ekran stoi.
private final class SCAppUpdateWindow: UIWindow {
    var gate: SCAppUpdateGate?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        gate?.isRequired == true
    }
}

private struct SCAppUpdateGateInstaller: UIViewRepresentable {
    let gate: SCAppUpdateGate
    let colorScheme: ColorScheme?

    func makeUIView(context: Context) -> UIView {
        Installer(gate: gate, style: Self.style(for: colorScheme))
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
        private let gate: SCAppUpdateGate
        private var overlay: SCAppUpdateWindow?
        private var style: UIUserInterfaceStyle

        init(gate: SCAppUpdateGate, style: UIUserInterfaceStyle) {
            self.gate = gate
            self.style = style
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) nieużywane") }

        /// Osobne okno nie dostaje `preferredColorScheme` aplikacji.
        func apply(style: UIUserInterfaceStyle) {
            self.style = style
            overlay?.overrideUserInterfaceStyle = style
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard overlay == nil, let scene = window?.windowScene else { return }

            let overlay = SCAppUpdateWindow(windowScene: scene)
            overlay.gate = gate
            let host = UIHostingController(rootView: SCAppUpdateRequiredView(gate: gate))
            host.view.backgroundColor = .clear
            overlay.rootViewController = host
            overlay.backgroundColor = .clear
            // Jak zasłona sesji: bez `makeKeyAndVisible`, pasek stanu zostaje
            // przy oknie aplikacji.
            overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 2)
            overlay.overrideUserInterfaceStyle = style
            overlay.isHidden = false
            self.overlay = overlay
        }
    }
}

extension View {
    /// Zakłada okno ekranu „Zaktualizuj Scoffie” (`SCAppUpdateGate`).
    func scAppUpdateGate(_ gate: SCAppUpdateGate, colorScheme: ColorScheme?) -> some View {
        background {
            SCAppUpdateGateInstaller(gate: gate, colorScheme: colorScheme)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}
