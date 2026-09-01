import PhotosUI
import SwiftUI
import UIKit

// Zdjęcie dla asystenta — wybór, przygotowanie i wysyłka.
//
// Zasada, na której stoi cały ten plik: zdjęcie NIE JEST przechowywane.
// Idzie do modelu na czas jednej odpowiedzi i znika — ani telefon, ani serwer
// nie trzymają go po turze. Dlatego nie ma tu cache'u, nie ma pliku
// tymczasowego i nie ma galerii załączników.

/// Zdjęcie gotowe do wysłania: dane dla serwera i miniatura dla ekranu.
struct AssistantAttachment: Equatable {
    /// `image/jpeg` — jedyny format, w którym wysyłamy.
    let mediaType: String
    /// base64 bez prefiksu `data:`.
    let data: String
    /// Podgląd w polu i w dymku; żyje tak długo, jak rozmowa na ekranie.
    let preview: UIImage

    static func == (lhs: AssistantAttachment, rhs: AssistantAttachment) -> Bool {
        lhs.data == rhs.data
    }
}

enum AssistantPhotoPreparer {
    /// Dłuższy bok po przeskalowaniu.
    ///
    /// Model i tak czyta obraz w swojej rozdzielczości, a każdy piksel powyżej
    /// tego progu to tokeny i sekundy wysyłki na komórce. 1024 px wystarcza,
    /// żeby rozpoznać etykiety na słoikach.
    static let maxDimension: CGFloat = 1024
    /// Sufit po stronie serwera to ~2 MB; celujemy znacznie niżej, bo
    /// odrzucona wysyłka po dziesięciu sekundach jest gorsza niż gorsze zdjęcie.
    static let maxBytes = 1_200_000

    /// Skaluje i kompresuje zdjęcie do rozmiaru, który przejdzie przez sieć.
    ///
    /// Jakość schodzi stopniowo, a nie od razu na najniższą: większość zdjęć
    /// mieści się w limicie już przy 0,7 i nie ma powodu psuć ich wszystkich
    /// dla tych kilku, które się nie mieszczą.
    static func prepare(_ image: UIImage) -> AssistantAttachment? {
        let scaled = downscale(image)
        for quality in stride(from: 0.7, through: 0.3, by: -0.2) {
            guard let data = scaled.jpegData(compressionQuality: quality) else {
                continue
            }
            if data.count <= maxBytes {
                return AssistantAttachment(
                    mediaType: "image/jpeg",
                    data: data.base64EncodedString(),
                    preview: scaled
                )
            }
        }
        return nil
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Aparat. SwiftUI nie ma własnego, więc most do `UIImagePickerController`.
///
/// Świadomie bez edycji kadru: dokładanie kroku między „zrób zdjęcie"
/// a „wyślij" po to, żeby przyciąć lodówkę, nie ma sensu.
struct AssistantCameraPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        private let onPicked: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onPicked: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onFinish = onFinish
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onPicked(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            onFinish()
        }
    }
}

/// Miniatura załącznika nad polem tekstowym, z krzyżykiem do zdjęcia.
///
/// Załącznik musi być WIDOCZNY przed wysłaniem: inaczej użytkownik nie wie,
/// czy asystent zobaczy zdjęcie, i wpisuje to samo w słowach na wszelki wypadek.
struct AssistantAttachmentPreview: View {
    let attachment: AssistantAttachment
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Image(uiImage: attachment.preview)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Zdjęcie w załączniku")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wmLabel(scheme))
                Text("Asystent zobaczy je tylko przy tej odpowiedzi")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.wmFaint(scheme))
            }

            Spacer(minLength: 0)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.wmTileBg(scheme)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Usuń zdjęcie")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.wmInsetSurface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.wmCardStroke(scheme), lineWidth: 1)
        )
    }
}
