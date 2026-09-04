import SwiftUI

/// „Prywatność i regulamin" — jeden arkusz z Ustawień, z którego otwierają
/// się (jako arkusze nad nim) polityka prywatności, warunki korzystania
/// i „Pobierz moje dane". Trzy osobne wiersze w Ustawieniach robiły z sekcji
/// Informacje listę dokumentów; tu jest jedno wejście i komplet w środku.
struct LegalDocumentsSheet: View {
    let dataExportClient: DataExportAPIClient?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(eyebrow: "Informacje", title: "Prywatność i regulamin") {
                        dismiss()
                    }

                    Text("Wersja \(LegalDocMeta.version) · obowiązuje od \(LegalDocMeta.effectiveDate). Te same dokumenty, które akceptujesz przy logowaniu; aktualne wersje są też na scoffie.app.")
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    EditorialSheetSectionLabel(title: "Dokumenty")
                    EditorialSettingsCardGroup {
                        EditorialSettingsRow(
                            icon: "hand.raised.fill",
                            iconColor: SCPalette.indigo,
                            title: "Polityka prywatności",
                            value: "v\(LegalDocMeta.version)",
                            action: { showPrivacy = true }
                        )
                        EditorialSettingsRow(
                            icon: "doc.text.fill",
                            iconColor: SCPalette.sage,
                            title: "Warunki korzystania",
                            value: "v\(LegalDocMeta.version)",
                            isLast: true,
                            action: { showTerms = true }
                        )
                    }

                    EditorialSheetSectionLabel(title: "Twoje dane")
                    EditorialSettingsCardGroup {
                        EditorialSettingsRow(
                            icon: "square.and.arrow.down.fill",
                            iconColor: SCPalette.terracotta,
                            title: "Pobierz moje dane",
                            value: "JSON",
                            isLast: true,
                            action: { showExport = true }
                        )
                    }

                    Text("Paczka z Twoim profilem, preferencjami, przepisami, posiłkami, krokami, zgodami i rozmowami z asystentem — prawo dostępu i przenoszenia danych (art. 15 i 20 RODO). Bez danych innych domowników.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scFaint(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Pytania i żądania: \(LegalDocMeta.contactEmail)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scFaint(scheme))
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
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentSheet(title: "Polityka prywatności") {
                PrivacyPolicyContent()
            }
        }
        .sheet(isPresented: $showTerms) {
            LegalDocumentSheet(title: "Warunki korzystania") {
                TermsOfServiceContent()
            }
        }
        .sheet(isPresented: $showExport) {
            if let dataExportClient {
                DataExportSheet(client: dataExportClient)
            }
        }
    }
}
