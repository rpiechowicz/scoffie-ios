import LinkPresentation
import UIKit

/// Systemowy arkusz udostępniania linku z własnym podglądem.
///
/// Nie `ShareLink` ze SwiftUI, z dwóch powodów. Adres przepisu powstaje
/// dopiero po stuknięciu (`recipes:shareLink` — link domu zakłada się na
/// serwerze), a `ShareLink` chce go znać, zanim się narysuje. I tylko
/// `UIActivityViewController` mówi, czy użytkownik NAPRAWDĘ coś wysłał
/// (`completed`) — a licznik „udostępniono” ma liczyć wysłane, nie otwarte
/// arkusze.
///
/// Treścią jest SAM adres: iMessage i WhatsApp zrobią z niego kartę ze
/// strony. `LPLinkMetadata` (tytuł + zdjęcie) jest dla nagłówka arkusza —
/// bez niej system pokazywałby goły adres, zanim sam pobierze stronę.
enum SCShareSheet {
    /// Pokazuje arkusz nad tym, co jest na wierzchu (także nad arkuszem
    /// szczegółów). `onCompleted` przychodzi po faktycznym wysłaniu — przy
    /// anulowaniu nie przychodzi wcale.
    ///
    /// `message` — zdanie wysyłane razem z adresem (zaproszenie domownika:
    /// „Dołącz do naszego domu…”). Przepis go nie ma: tam kartę robi strona.
    static func present(
        url: URL,
        title: String,
        image: UIImage?,
        message: String? = nil,
        onCompleted: @escaping @MainActor () -> Void
    ) {
        guard let presenter = topViewController() else { return }

        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = title
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
        }

        var items: [Any] = [SCLinkActivityItem(url: url, metadata: metadata)]
        if let message, !message.isEmpty {
            items.append(message)
        }
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        // Uchwyt dymka na iPadzie; na telefonie arkusz i tak wjeżdża od dołu.
        controller.popoverPresentationController?.sourceView = presenter.view
        controller.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 0,
            height: 0
        )
        // Handler bywa wołany więcej niż raz (rozszerzenie anulowane
        // w środku, arkusz zostaje) — dlatego liczy się tylko `completed`,
        // a nie samo wywołanie.
        controller.completionWithItemsHandler = { _, completed, _, _ in
            guard completed else { return }
            Task { @MainActor in
                onCompleted()
            }
        }
        presenter.present(controller, animated: true)
    }

    /// Kontroler na wierzchu okna aplikacji. Okna zasłony i toastów nie są
    /// kluczowe (`isHidden = false` bez `makeKeyAndVisible`), więc kluczowe
    /// okno sceny to zawsze okno aplikacji.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let window = scene?.keyWindow
            ?? scene?.windows.first(where: { $0.windowLevel == .normal && !$0.isHidden }) else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// Adres + podgląd dla `UIActivityViewController`.
///
/// `nonisolated`, bo arkusz pyta o treść przez protokół Objective-C, a obie
/// wartości są niezmienne od chwili utworzenia.
nonisolated private final class SCLinkActivityItem: NSObject, UIActivityItemSource {
    private let url: URL
    private let metadata: LPLinkMetadata

    init(url: URL, metadata: LPLinkMetadata) {
        self.url = url
        self.metadata = metadata
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        metadata
    }
}
