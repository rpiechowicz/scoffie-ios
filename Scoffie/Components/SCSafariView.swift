import SafariServices
import SwiftUI
import UIKit

/// Strona z sieci w Safari WEWNĄTRZ aplikacji (`SFSafariViewController`).
///
/// Do stron, które są nasze i żyją na scoffie.app (pomoc), a nie do treści,
/// które trzeba przepisać w aplikacji: użytkownik zostaje tam, skąd przyszedł,
/// ma pasek adresu Safari (widać, że to strona, a nie ekran aplikacji),
/// „Zamknij” i udostępnianie, a odnośniki `mailto:` otwierają Pocztę.
///
/// Stawiać w `.sheet` z `.ignoresSafeArea()`. `onFinish` przychodzi po
/// „Zamknij” — arkusz chowa się wtedy sam, ale wiązanie `isPresented`
/// też musi wrócić do `false`, inaczej następne stuknięcie nic by nie
/// otworzyło.
struct SCSafariView: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(SCPalette.terracotta)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        var onFinish: (() -> Void)?

        init(onFinish: (() -> Void)?) {
            self.onFinish = onFinish
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish?()
        }
    }
}
