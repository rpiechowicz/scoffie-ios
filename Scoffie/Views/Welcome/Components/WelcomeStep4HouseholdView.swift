import SwiftUI

// Kreator, krok 5 — załóż gospodarstwo albo dołącz do cudzego.
//
// Zaproszenia, które już czekają na tego użytkownika, są tu KLIKALNE. Sam
// opis „otwórz link" nie wystarczał: ktoś, kto link otworzył i zamknął alert
// (albo otworzył go przed zalogowaniem), zostawał na tym ekranie bez żadnej
// drogi do zaproszenia poza szukaniem wiadomości po raz drugi — a jedynym
// wyjściem było założenie własnego, niepotrzebnego gospodarstwa.
//
// Od 23.09.2026 bez kafla z gradientem, separatora „ALBO” i przerywanej
// ramki, która wyglądała jak przycisk, a nim nie była: dwie sekcje z
// etykietami aplikacji i karty `scTileBg`.
struct WelcomeStep4HouseholdView: View {
    @Binding var householdName: String
    let firstName: String
    let avatarInitial: String
    let errorMessage: String?
    var pendingInvitations: [HouseholdInvitationSnapshot] = []
    var onAcceptInvitation: ((String) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isHouseholdFieldFocused: Bool

    var body: some View {
        // Ten sam kontener, co pozostałe kroki (ScrollView, ten sam odstęp
        // od góry): krok gospodarstwa był gołym VStackiem z własnym
        // wyrównaniem, przez co treść i stopka siadały inaczej niż na
        // krokach 1–4.
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WelcomeLayout.sectionSpacing) {
                WelcomeHeader(
                    icon: "house.fill",
                    eyebrow: "Ostatni krok",
                    title: "Stwórz gospodarstwo",
                    subtitle: "Gospodarstwo to Wasz wspólny kąt w Scoffie: jeden plan tygodnia i jedna lista zakupów. Planujesz tylko dla siebie? Też je załóż — po prostu jednoosobowe."
                )

                WelcomeSection(title: "Nazwa gospodarstwa", hint: "Zobaczą ją domownicy, których zaprosisz.") {
                    nameCard
                }

                WelcomeSection(
                    title: pendingInvitations.isEmpty ? "Masz zaproszenie?" : "Czekające zaproszenia",
                    hint: pendingInvitations.isEmpty
                        ? "Ktoś z Twojego domu już korzysta ze Scoffie? Dołącz do niego, zamiast zakładać nowe."
                        : "Dołącz jednym stuknięciem — od razu zobaczysz Wasz plan i listę zakupów."
                ) {
                    if pendingInvitations.isEmpty {
                        linkHintCard
                    } else {
                        VStack(spacing: 10) {
                            ForEach(pendingInvitations) { invitation in
                                invitationCard(invitation)
                            }
                        }
                    }
                }

                if let errorMessage, !errorMessage.isEmpty {
                    SCInlineErrorText(errorMessage)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, WelcomeLayout.horizontal)
            .padding(.top, WelcomeLayout.topInset)
            .padding(.bottom, WelcomeLayout.bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scScrollEdgeFade()
        .scrollDismissesKeyboard(.interactively)
    }

    /// Pole nazwy i pod kreską domownicy: Ty i puste miejsce na resztę.
    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.scFaint(colorScheme))
                TextField("Np. Nasz dom", text: $householdName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isHouseholdFieldFocused)
                    .submitLabel(.done)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.scLabel(colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.scRule(colorScheme))
                .frame(height: 1)
                .padding(.horizontal, 14)

            HStack(spacing: 10) {
                AvatarStack(initial: avatarInitial)
                Text("Domowników zaprosisz po utworzeniu")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scMuted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .welcomeCard()
    }

    /// Bez czekających zaproszeń: jedna informacja, skąd się je bierze.
    /// Nie przycisk — dołączenie zaczyna się od linku, nie od tego ekranu.
    private var linkHintCard: some View {
        HStack(spacing: 12) {
            SCHeaderIconWell(icon: "link", accent: SCPalette.sage, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Otwórz link od domownika")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.scLabel(colorScheme))
                Text("Scoffie dołączy Cię do jego domu.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.scMuted(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .welcomeCard()
        .accessibilityElement(children: .combine)
    }

    private func invitationCard(_ invitation: HouseholdInvitationSnapshot) -> some View {
        Button {
            onAcceptInvitation?(invitation.token)
        } label: {
            HStack(spacing: 12) {
                SCHeaderIconWell(icon: "envelope.open.fill", accent: SCPalette.terracotta, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.householdName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(colorScheme))
                    Text(invitation.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Dołącz")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .scSoftCapsule()
            }
            .padding(14)
            .welcomeCard()
            .contentShape(RoundedRectangle(cornerRadius: WelcomeLayout.cardRadius, style: .continuous))
        }
        .buttonStyle(PlanPressStyle())
        .accessibilityLabel("Dołącz do \(invitation.householdName)")
        .accessibilityHint(invitation.subtitle)
    }
}

private struct AvatarStack: View {
    let initial: String
    @Environment(\.colorScheme) private var colorScheme

    private let bubbleSize: CGFloat = 28

    var body: some View {
        // Obok siebie, bez zachodzenia: karta (`scTileBg`) jest
        // półprzezroczysta, więc dawna obwódka „w kolorze tła” pod drugim
        // kółkiem prześwitywałaby zamiast je przycinać.
        HStack(spacing: 4) {
            avatarBubble
            placeholderBubble
        }
        .accessibilityHidden(true)
    }

    /// Inicjał w tincie terakoty, jak awatary domowników w Ustawieniach →
    /// Gospodarstwo — nie pełne koło z gradientem.
    private var avatarBubble: some View {
        Text(initial)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(SCPalette.terracotta)
            .frame(width: bubbleSize, height: bubbleSize)
            .background(Circle().fill(SCPalette.terracotta.opacity(colorScheme == .dark ? 0.22 : 0.16)))
    }

    private var placeholderBubble: some View {
        Image(systemName: "plus")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.scMuted(colorScheme))
            .frame(width: bubbleSize, height: bubbleSize)
            .background(Circle().fill(Color.scChipBg(colorScheme)))
            .overlay(
                Circle()
                    .strokeBorder(
                        Color.scFaint(colorScheme),
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])
                    )
            )
    }
}

#Preview("Dark") {
    StatefulPreviewContainer(name: "") { name in
        ZStack {
            SCPageBackground(scheme: .dark).ignoresSafeArea()
            WelcomeStep4HouseholdView(
                householdName: name,
                firstName: "Rafał",
                avatarInitial: "R",
                errorMessage: nil
            )
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Light") {
    StatefulPreviewContainer(name: "Dom Piechowiczów") { name in
        ZStack {
            SCPageBackground(scheme: .light).ignoresSafeArea()
            WelcomeStep4HouseholdView(
                householdName: name,
                firstName: "Rafał",
                avatarInitial: "R",
                errorMessage: nil
            )
        }
        .preferredColorScheme(.light)
    }
}

private struct StatefulPreviewContainer<Content: View>: View {
    @State private var name: String
    let content: (Binding<String>) -> Content

    init(name: String, @ViewBuilder content: @escaping (Binding<String>) -> Content) {
        _name = State(initialValue: name)
        self.content = content
    }

    var body: some View {
        content($name)
    }
}
