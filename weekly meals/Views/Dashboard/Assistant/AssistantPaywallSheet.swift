import StoreKit
import SwiftUI

/// Paywall PRO — otwierany z „Odblokuj PRO" (limity, zablokowane pole).
///
/// Trzy plany nazwane wielkością domu: Solo, Duet, Rodzina. Nikt nie liczy
/// domowników — większy dom po prostu zużywa pulę szybciej, więc wybiera
/// wyższy plan. Każdy plan podaje KONKRETNE ilości (App Store 3.1.2(c)),
/// te same, które egzekwuje serwer.
///
/// Dopóki serwer nie weryfikuje transakcji, przycisk zakupu jest nieaktywny
/// i mówi dlaczego — bez pobierania pieniędzy za coś, czego nie umiemy jeszcze
/// włączyć.
struct AssistantPaywallSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var subscriptions = SubscriptionStore()
    @State private var selected = SubscriptionCatalog.recommended
    @State private var notice: String?
    @State private var showTerms = false
    @State private var showPrivacy = false

    private let perks: [(icon: String, accent: AssistantAccent, title: String, detail: String)] = [
        ("sparkles", .terracotta, "Plan tygodnia w jednym zdaniu", "Asystent zna dietę, alergeny i cele całego domu. Propozycję dodajesz Ty."),
        ("arrow.triangle.2.circlepath", .indigo, "Podmiany i domykanie makro", "Każda zmiana ma powód i różnicę kalorii. Oglądanie propozycji bez limitu."),
        ("person.2.fill", .sage, "Jedna subskrypcja, cały dom", "Kupuje jedna osoba, korzystają wszyscy domownicy ze zgodą."),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WMPageBackground(scheme: scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialSheetHeader(eyebrow: "Asystent AI", title: "Wybierz plan") {
                            dismiss()
                        }

                        Text("Pula na próbę się kończy, apetyt nie. Plan dobiera się do wielkości domu — im więcej osób, tym szybciej znika pula wiadomości.")
                            .font(.system(size: 14.5))
                            .lineSpacing(3)
                            .foregroundStyle(Color.wmMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 10) {
                            ForEach(SubscriptionCatalog.all) { plan in
                                planRow(plan)
                            }
                        }

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

                        if let notice {
                            Text(notice)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(WMPalette.terracotta)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WMPalette.terracotta.opacity(0.12)))
                        }

                        Text("Subskrypcja odnawia się automatycznie co miesiąc, dopóki jej nie wyłączysz w ustawieniach App Store najpóźniej 24 h przed końcem okresu. Płatność pobiera Apple. Plan zmienisz w każdej chwili — wyższy działa od razu, niższy od następnego okresu.")
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
                        isEnabled: subscriptions.product(for: selected) != nil
                            && SubscriptionCatalog.purchasesEnabled
                            && !subscriptions.isPurchasing,
                        isLoading: subscriptions.isPurchasing
                    ) {
                        guard let product = subscriptions.product(for: selected) else { return }
                        Task {
                            switch await subscriptions.purchase(product) {
                            case .purchased:
                                notice = "Dziękujemy! Plan włączy się, gdy serwer potwierdzi zakup."
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
        if let product = subscriptions.product(for: selected) {
            return "Wybierz \(selected.name) za \(product.displayPrice)"
        }
        return "Wybierz \(selected.name)"
    }

    /// Wiersz planu: nazwa, dla kogo, ILOŚCI (wymóg 3.1.2(c)) i cena z App Store.
    private func planRow(_ plan: SubscriptionPlan) -> some View {
        let isSelected = plan == selected
        let product = subscriptions.product(for: plan)
        return Button {
            selected = plan
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? WMPalette.terracotta : Color.clear)
                    Circle()
                        .stroke(isSelected ? Color.clear : Color.wmFaint(scheme), lineWidth: 1.5)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.wmPageBase(scheme))
                    }
                }
                .frame(width: 22, height: 22)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.name)
                            .font(.system(size: 16, weight: .bold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.wmLabel(scheme))
                        if plan == SubscriptionCatalog.recommended {
                            Text("najczęściej wybierany")
                                .font(.system(size: 10, weight: .bold))
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .foregroundStyle(WMPalette.sage)
                                .padding(.horizontal, 7)
                                .frame(height: 18)
                                .background(Capsule().fill(Color.wmSageTint(scheme)))
                        }
                    }
                    Text(plan.seatsLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.wmMuted(scheme))
                    Text(plan.quantityLine)
                        .font(.system(size: 13))
                        .lineSpacing(1.5)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(product?.displayPrice ?? "—")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? WMPalette.terracotta : Color.wmLabel(scheme))
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.wmAccentTint(scheme) : Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? WMPalette.terracotta.opacity(0.45) : Color.wmTileStroke(scheme), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(plan.name), \(plan.seatsLabel), \(plan.quantityLine)")
    }
}
