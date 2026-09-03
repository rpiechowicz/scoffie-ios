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
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(WMPalette.indigo.opacity(0.18))
                                Image(systemName: "doc.zipper")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(WMPalette.indigo)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(fileURL?.lastPathComponent ?? "weekly-meals-dane.json")
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(Color.wmLabel(scheme))
                                    .lineLimit(1)
                                Text(statusLine)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Color.wmMuted(scheme))
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
                                .foregroundStyle(Color.wmPageBase(scheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Capsule().fill(WMPalette.terracotta))
                            }
                            .buttonStyle(.plain)
                        } else if !isLoading {
                            Button(action: load) {
                                Text(errorMessage == nil ? "Przygotuj paczkę" : "Spróbuj ponownie")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Color.wmPageBase(scheme))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(Capsule().fill(WMPalette.terracotta))
                            }
                            .buttonStyle(.plain)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WMPalette.terracotta)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.wmTileBg(scheme)))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.wmTileStroke(scheme), lineWidth: 1))

                    Text("Żądanie e-mailem działa dalej: \(LegalDocMeta.contactEmail), z adresu przypisanego do konta. Odpowiadamy w ciągu 30 dni.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(WMPageBackground(scheme: scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .task { load() }
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
                errorMessage = UserFacingErrorMapper.message(from: error)
            }
        }
    }
}
