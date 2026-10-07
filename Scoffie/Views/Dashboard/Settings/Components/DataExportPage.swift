import SwiftUI

/// „Pobierz moje dane" (art. 15 i 20 RODO) — jedno stuknięcie: serwer składa
/// plik JSON, telefon oddaje go do arkusza udostępniania (Pliki, Mail,
/// AirDrop). Plik leży w katalogu tymczasowym i znika z systemem.
///
/// Ekran WEPCHNIĘTY w arkusz „Prywatność i regulamin” (systemowy pasek
/// z „wstecz”), nie osobny arkusz nad nim.
struct DataExportPage: View {
    let client: DataExportAPIClient

    @Environment(\.colorScheme) private var scheme

    @State private var fileURL: URL?
    @State private var fileSize: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    /// Pobranie padło — także na łączności, której `inlineMessage` nie
    /// opisuje (brak sieci ma swój pasek), a stopka i tak ma dać ponowienie.
    @State private var didFail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                fileCard

                Text("Profil, preferencje, przepisy, posiłki, kroki, zgody i rozmowy z asystentem — bez danych innych domowników. Żądanie e-mailem: \(LegalDocMeta.contactEmail).")
                    .font(.sc(size: 12.5))
                    .foregroundStyle(Color.scFaint(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scSheetFooter { footerButton }
        .scSheetFooterEdge()
        .scPushedPage("Pobierz moje dane")
        .task { load() }
        // Pełny eksport (profil, rozmowy, kroki) nie może leżeć w tmp po
        // zejściu z ekranu — kto chciał, już go zapisał albo wysłał.
        .onDisappear {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        }
    }

    /// Plik i jego stan w JEDNEJ karcie: kafelek z archiwum, nazwa pliku,
    /// pod nią „Przygotowuję…” / „Gotowe · 182 KB” / błąd.
    private var fileCard: some View {
        HStack(spacing: 12) {
            EditorialSettingsTileIcon(icon: "doc.zipper", color: SCPalette.teal, size: 44, radius: 11)

            VStack(alignment: .leading, spacing: 3) {
                Text(fileURL?.lastPathComponent ?? "scoffie-dane.json")
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                if let errorMessage {
                    SCInlineErrorText(errorMessage)
                } else {
                    Text(statusLine)
                        .font(.sc(size: 13))
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.scTileBg(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .animation(SCMotion.textRoll, value: statusLine)
    }

    /// Jeden przycisk w szklanej stopce: gotowy plik = arkusz udostępniania,
    /// błąd = ponowienie, w trakcie = ten sam przycisk ze spinnerem.
    @ViewBuilder
    private var footerButton: some View {
        if let fileURL {
            ShareLink(item: fileURL) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.sc(size: 13, weight: .heavy))
                    Text("Zapisz albo wyślij")
                        .font(.sc(size: 14, weight: .bold))
                        .tracking(-0.1)
                }
                .foregroundStyle(SCPalette.terracotta)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .scSoftCapsule(SCPalette.terracotta)
            }
            .buttonStyle(PlanPressStyle(scale: 0.97))
        } else if didFail, !isLoading {
            EditorialPrimaryActionButton(
                title: "Spróbuj ponownie",
                icon: "arrow.clockwise",
                action: { load() }
            )
        } else {
            EditorialPrimaryActionButton(
                title: "Zapisz albo wyślij",
                icon: "square.and.arrow.up",
                isLoading: isLoading,
                action: { load() }
            )
        }
    }

    private var statusLine: String {
        if isLoading { return "Przygotowuję…" }
        if let fileSize { return "Gotowe · \(fileSize)" }
        if didFail { return "Nie udało się pobrać" }
        return "Jeszcze nie pobrano"
    }

    private func load() {
        guard !isLoading, fileURL == nil else { return }
        isLoading = true
        errorMessage = nil
        didFail = false
        Task { @MainActor in
            defer { isLoading = false }
            do {
                let url = try await client.downloadExport()
                fileURL = url
                let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                fileSize = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            } catch {
                didFail = true
                errorMessage = UserFacingErrorMapper.inlineMessage(from: error)
            }
        }
    }
}
