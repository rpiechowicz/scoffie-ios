import StoreKit
import SwiftUI

/// Paywall PRO — otwierany z „Odblokuj PRO" (limity, zablokowane pole).
/// Jedna oferta (PRO miesięcznie dla całego domu), cena z App Store, trzy
/// konkrety zamiast listy marketingowej, przywracanie zakupów i linki do
/// regulaminu i polityki (App Store 3.1.2). Dopóki serwer nie weryfikuje
/// transakcji, przycisk zakupu jest nieaktywny i mówi dlaczego — bez
/// pobierania pieniędzy za nic.
struct AssistantPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var subscriptions = SubscriptionStore()
    @State private var notice: String?
    @State private var showTerms = false
    @State private var showPrivacy = false

    private let perks: [(icon: String, accent: AssistantAccent, title: String, detail: String)] = [
        ("sparkles", .terracotta, "200 wiadomości miesięcznie", "Plan tygodnia, podmiany, makro, zakupy — dla całego domu, nie per osoba."),
        ("checkmark.rectangle.stack.fill", .sage, "30 zapisów planu miesięcznie", "Każde „Dodaj do planu”. Oglądanie propozycji dalej bez limitu."),
        ("person.2.fill", .indigo, "Jedna subskrypcja, cały dom", "Kupuje jedna osoba, korzystają wszyscy domownicy ze zgodą."),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WMPageBackground(scheme: scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialSheetHeader(eyebrow: "Asystent AI", title: "Weekly Meals PRO") {
                            dismiss()
                        }

                        Text("Pula na próbę się kończy, apetyt nie. PRO odnawia limity co miesiąc dla całego gospodarstwa.")
                            .font(.system(size: 14.5))
                            .lineSpacing(3)
                            .foregroundStyle(Color.wmMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        AssistantSurfaceCard {
                            ForEach(Array(perks.enumerated()), id: \.offset) { index, perk in
                                HStack(alignment: .top, spacing: 12) {
                                    AssistantIconTile(icon: perk.icon, accent: perk.accent, size: 36, radius: 11)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(perk.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .tracking(-0.25)
                                            .foregroundStyle(Color.wmLabel(scheme))
                                        Text(perk.detail)
                                            .font(.system(size: 13))
                                            .lineSpacing(2)
                                            .foregroundStyle(Color.wmMuted(scheme))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .overlay(alignment: .top) {
                                    if index > 0 { Rectangle().fill(Color.wmRule(scheme)).frame(height: 1) }
                                }
                            }
                        }

                        priceCard

                        if let notice {
                            Text(notice)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(WMPalette.terracotta)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WMPalette.terracotta.opacity(0.12)))
                        }

                        Text("Subskrypcja odnawia się automatycznie co miesiąc, dopóki jej nie wyłączysz w ustawieniach App Store najpóźniej 24 h przed końcem okresu. Płatność pobiera Apple.")
                            .font(.system(size: 11.5))
                            .lineSpacing(2)
                            .foregroundStyle(Color.wmFaint(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 14) {
                            Button("Regulamin") { showTerms = true }
                            Button("Polityka prywatności") { showPrivacy = true }
                            Spacer()
                            Button("Przywróć zakupy") {
                                Task {
                                    await subscriptions.restore()
                                    notice = subscriptions.lastError ?? "Sprawdziliśmy zakupy w App Store."
                                }
                            }
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(WMPalette.terracotta)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)

                AssistantStickyFooter {
                    WMSoftButton(
                        title: purchaseTitle,
                        leadingIcon: "sparkles",
                        trailingIcon: nil,
                        isEnabled: subscriptions.proMonthly != nil && SubscriptionCatalog.purchasesEnabled && !subscriptions.isPurchasing,
                        isLoading: subscriptions.isPurchasing
                    ) {
                        guard let product = subscriptions.proMonthly else { return }
                        Task {
                            switch await subscriptions.purchase(product) {
                            case .purchased:
                                notice = "Dziękujemy! PRO włączy się, gdy serwer potwierdzi zakup."
                            case .pending:
                                notice = "Zakup czeka na zatwierdzenie (np. Poproś o zakup)."
                            case .cancelled:
                                notice = nil
                            case let .failed(message):
                                notice = message
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDragIndicator(.visible)
        .task { await subscriptions.loadProducts() }
        .sheet(isPresented: $showTerms) {
            LegalDocumentSheet(title: "Regulamin") { TermsOfServiceContent() }
        }
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentSheet(title: "Polityka prywatności") { PrivacyPolicyContent() }
        }
    }

    private var purchaseTitle: String {
        if !SubscriptionCatalog.purchasesEnabled { return "Wkrótce w App Store" }
        if let product = subscriptions.proMonthly { return "Subskrybuj za \(product.displayPrice) / miesiąc" }
        return "Subskrybuj"
    }

    private var priceCard: some View {
        AssistantSurfaceCard(padding: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    AssistantSectionLabel(text: "PRO · miesięcznie", color: WMPalette.sage)
                    if let product = subscriptions.proMonthly {
                        Text(product.displayPrice)
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(Color.wmLabel(scheme))
                        Text("za gospodarstwo, odnawiane co miesiąc")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.wmMuted(scheme))
                    } else if subscriptions.isLoadingProducts {
                        ProgressView().padding(.vertical, 6)
                    } else {
                        Text("Cena widoczna w App Store")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.wmLabel(scheme))
                        Text(subscriptions.lastError ?? "Oferta pojawi się, gdy PRO będzie dostępne w App Store.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.wmMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
