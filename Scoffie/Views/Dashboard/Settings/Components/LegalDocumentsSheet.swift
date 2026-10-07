import SwiftUI

/// „Prywatność i regulamin" — jeden arkusz z Ustawień, w którym polityka
/// prywatności, regulamin i „Pobierz moje dane" wjeżdżają jako
/// kolejne ekrany TEGO arkusza (push z systemowym „wstecz”), a nie arkusze
/// nad nim. Trzy osobne wiersze w Ustawieniach robiły z sekcji Informacje
/// listę dokumentów; tu jest jedno wejście i komplet w środku.
struct LegalDocumentsSheet: View {
    let dataExportClient: DataExportAPIClient?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            // Nagłówek PRZYPIĘTY nad przewijaną treścią (jak w pozostałych
            // arkuszach) — górny brzeg listy gaśnie pod nim, zamiast kreski.
            VStack(alignment: .leading, spacing: 0) {
                EditorialSheetHeader(
                    eyebrow: "Informacje",
                    title: "Prywatność i regulamin",
                    icon: "hand.raised.fill",
                    accent: SettingsAccent.slate
                ) {
                    dismiss()
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        EditorialSheetSectionLabel(title: "Dokumenty")
                        EditorialSettingsCardGroup {
                            EditorialSettingsRow(
                                icon: "doc.text.fill",
                                iconColor: SettingsAccent.slate,
                                title: "Polityka prywatności",
                                value: "v\(LegalDocMeta.version)",
                                action: { showPrivacy = true }
                            )
                            EditorialSettingsRow(
                                icon: "building.columns.fill",
                                iconColor: SettingsAccent.slate,
                                title: "Regulamin",
                                value: "v\(LegalDocMeta.version)",
                                isLast: true,
                                action: { showTerms = true }
                            )
                        }

                        EditorialSheetSectionLabel(title: "Twoje dane")
                            .padding(.top, 18)
                        EditorialSettingsCardGroup {
                            EditorialSettingsRow(
                                icon: "arrow.down.circle.fill",
                                iconColor: SCPalette.teal,
                                title: "Pobierz moje dane",
                                value: "JSON",
                                isLast: true,
                                action: { showExport = true }
                            )
                            // Bez klienta eksportu (sesja jeszcze nie wstała) push
                            // pokazałby pusty ekran — wiersz czeka wyłączony.
                            .disabled(dataExportClient == nil)
                        }

                        // Wersja, data i kontakt jednym podpisem — bez akapitu.
                        Text("Wersja \(LegalDocMeta.version) · od \(LegalDocMeta.effectiveDate) · \(LegalDocMeta.contactEmail)")
                            .font(.sc(size: 12.5))
                            .foregroundStyle(Color.scFaint(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 6)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scScrollEdgeFade()
            }
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showPrivacy) {
                LegalDocumentPage(title: "Polityka prywatności") {
                    PrivacyPolicyContent()
                }
            }
            .navigationDestination(isPresented: $showTerms) {
                LegalDocumentPage(title: "Regulamin") {
                    TermsOfServiceContent()
                }
            }
            .navigationDestination(isPresented: $showExport) {
                if let dataExportClient {
                    DataExportPage(client: dataExportClient)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Dokument prawny jako ekran WEPCHNIĘTY w arkusz („Prywatność i regulamin”,
/// „Asystent i plan”, wybór planu): systemowy pasek z „wstecz” i tytułem,
/// pod nim sama treść. `LegalDocumentSheet` (własny nagłówek z krzyżykiem)
/// zostaje dla miejsc, w których dokument JEST pierwszym arkuszem — stopka
/// logowania, zgoda Asystenta.
struct LegalDocumentPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scPushedPage(title)
    }
}
