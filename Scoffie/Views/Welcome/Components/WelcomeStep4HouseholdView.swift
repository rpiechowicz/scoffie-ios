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
//
// Od 24.09.2026 (Rafał: „widoki, które są stare i odbiegają od designu”)
// w układzie Ustawień → Gospodarstwo: nazwa jak imię w „Twoich danych”
// (kafelek domu, nazwa w miejscu, ołówek, kreska) z podpowiedziami do
// stuknięcia, a domownicy jako lista — Ty z plakietkami „TY” i
// „WŁAŚCICIEL”, pod spodem miejsce na resztę.
struct WelcomeStep4HouseholdView: View {
    @Binding var householdName: String
    let firstName: String
    let avatarInitial: String
    let errorMessage: String?
    var pendingInvitations: [HouseholdInvitationSnapshot] = []
    var onAcceptInvitation: ((String) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sessionStore) private var sessionStore
    @FocusState private var isHouseholdFieldFocused: Bool

    /// Podpowiedzi nazwy — stuknięcie wpisuje ją w pole. Bez imienia
    /// w środku („Dom Rafała”): odmiana imion po polsku to loteria.
    /// Trzy, nie cztery: na iPhonie 16e czwarta ścinała pozostałe do „Nasz d…”.
    private static let nameSuggestions = ["Dom", "Nasz dom", "Mieszkanie"]

    var body: some View {
        // Ten sam kontener, co pozostałe kroki (ScrollView, ten sam odstęp
        // od góry): krok gospodarstwa był gołym VStackiem z własnym
        // wyrównaniem, przez co treść i stopka siadały inaczej niż na
        // krokach 1–4.
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WelcomeLayout.sectionSpacing) {
                SCStepHeader(
                    icon: "house.fill",
                    eyebrow: "Ostatni krok",
                    title: "Stwórz gospodarstwo",
                    subtitle: "Wspólny plan i lista zakupów dla domowników."
                )

                WelcomeSection(title: "Nazwa gospodarstwa") {
                    nameCard
                }

                WelcomeSection(title: "Domownicy") {
                    membersCard
                }

                WelcomeSection(title: pendingInvitations.isEmpty ? "Masz zaproszenie?" : "Czekające zaproszenia") {
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

    /// Nazwa jak imię w „Twoich danych”: kafelek domu, nazwa edytowana
    /// w miejscu, ołówek i kreska zapalające się przy edycji, a pod spodem
    /// podpowiedzi do stuknięcia.
    private var nameCard: some View {
        let trimmed = householdName.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                EditorialSettingsTileIcon(icon: "house.fill", color: SCPalette.terracotta, size: 44, radius: 12)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        TextField("Np. Nasz dom", text: $householdName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($isHouseholdFieldFocused)
                            .submitLabel(.done)
                            .font(.system(size: 18, weight: .bold))
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(colorScheme))

                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isHouseholdFieldFocused ? SCPalette.terracotta : Color.scFaint(colorScheme))
                    }

                    Rectangle()
                        .fill(isHouseholdFieldFocused ? SCPalette.terracotta : Color.scRule(colorScheme))
                        .frame(height: isHouseholdFieldFocused ? 1.5 : 1)
                }
                .animation(.smooth(duration: 0.18), value: isHouseholdFieldFocused)
            }
            .contentShape(Rectangle())
            .onTapGesture { isHouseholdFieldFocused = true }

            HStack(spacing: 6) {
                ForEach(Self.nameSuggestions, id: \.self) { suggestion in
                    let isOn = trimmed == suggestion
                    Button {
                        withAnimation(.smooth(duration: 0.18)) {
                            householdName = suggestion
                        }
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isOn ? SCPalette.terracotta : Color.scLabel(colorScheme))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .scChoiceSurface(Capsule(style: .continuous), isOn: isOn, style: .chip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Nazwa: \(suggestion)")
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(16)
        .welcomeCard()
    }

    /// Domownicy jak w Ustawieniach → Gospodarstwo: Ty z plakietkami i pod
    /// kreską puste miejsce na resztę — zaprasza się ich po utworzeniu.
    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ProfileAvatar(
                    avatarUrl: nil,
                    displayName: firstName.isEmpty ? avatarInitial : firstName,
                    size: 40,
                    seed: sessionStore.currentUserId ?? firstName
                )

                HStack(spacing: 6) {
                    Text(firstName.isEmpty ? "Ty" : firstName)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(colorScheme))
                        .lineLimit(1)
                    badge("TY", color: SCPalette.terracotta)
                    badge("WŁAŚCICIEL", color: SCPalette.butter)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color.scRule(colorScheme))
                .frame(height: 1)
                .padding(.leading, 14 + 40 + 12)

            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.scMuted(colorScheme))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.scChipBg(colorScheme)))
                    .overlay(
                        Circle().strokeBorder(
                            Color.scFaint(colorScheme),
                            style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Domownicy dołączą z linku")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.scLabel(colorScheme))
                    Text("Wyślesz go z Ustawień po utworzeniu")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.scMuted(colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .welcomeCard()
        .accessibilityElement(children: .combine)
    }

    /// Plakietka przy imieniu — ta sama, co w Ustawieniach → Gospodarstwo.
    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(colorScheme == .dark ? 0.16 : 0.12), in: Capsule())
            .fixedSize()
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
