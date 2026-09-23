import SwiftUI

/// „Pobierz moje dane" (art. 15 i 20 RODO) — jedno stuknięcie: serwer składa
/// plik JSON, telefon oddaje go do arkusza udostępniania (Pliki, Mail,
/// AirDrop). Plik leży w katalogu tymczasowym i znika z systemem.
struct DataExportSheet: View {
    let client: DataExportAPIClient

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var fileURL: URL?
    @State private var fileSize: String?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(eyebrow: "Konto i dane", title: "Pobierz moje dane") {
                        dismiss()
                    }

                    Text("Paczka JSON z Twoim profilem, preferencjami, przepisami, posiłkami, krokami, zgodami i rozmowami z asystentem. Bez danych innych domowników.")
                        .font(.system(size: 13.5))
                        .lineSpacing(2)
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(SCPalette.indigo.opacity(0.18))
                                Image(systemName: "doc.zipper")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(SCPalette.indigo)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileURL?.lastPathComponent ?? "scoffie-dane.json")
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(Color.scLabel(scheme))
                                    .lineLimit(1)
                                Text(statusLine)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Color.scMuted(scheme))
                            }
                            Spacer(minLength: 0)
                            if isLoading {
                                ProgressView().controlSize(.small)
                            }
                        }

                        if let fileURL {
                            ShareLink(item: fileURL) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Zapisz albo wyślij")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                .foregroundStyle(SCPalette.terracotta)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .scSoftCapsule()
                            }
                            .buttonStyle(.plain)
                        } else if !isLoading {
                            Button(action: load) {
                                Text(errorMessage == nil ? "Przygotuj paczkę" : "Spróbuj ponownie")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(SCPalette.terracotta)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .scSoftCapsule()
                            }
                            .buttonStyle(.plain)
                        }

                        if let errorMessage {
                            SCInlineErrorText(errorMessage)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.scTileBg(scheme)))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))

                    Text("Żądanie e-mailem działa dalej: \(LegalDocMeta.contactEmail), z adresu przypisanego do konta. Odpowiadamy w ciągu 30 dni.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .task { load() }
        // Pełny eksport (profil, rozmowy, kroki) nie może leżeć w tmp po
        // zamknięciu arkusza — kto chciał, już go zapisał albo wysłał.
        .onDisappear {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        }
    }

    private var statusLine: String {
        if isLoading { return "Serwer składa paczkę…" }
        if let fileSize { return "Gotowe · \(fileSize)" }
        if errorMessage != nil { return "Nie udało się pobrać" }
        return "Jeszcze nie pobrano"
    }

    private func load() {
        guard !isLoading, fileURL == nil else { return }
        isLoading = true
        errorMessage = nil
        Task { @MainActor in
            defer { isLoading = false }
            do {
                let url = try await client.downloadExport()
                fileURL = url
                let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                fileSize = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            } catch {
                errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }
}
