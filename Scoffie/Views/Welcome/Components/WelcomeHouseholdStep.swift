import SwiftUI

// Kreator, krok 4 — załóż gospodarstwo albo dołącz do cudzego.
//
// 7.10.2026 (Rafał: „zrób na onboarding user te nowe widoki z ustawień…
// uspójnij to”): te same klocki co Ustawienia → Gospodarstwo i zakładanie
// domu (`HouseholdKit`): skrzynka zaproszeń z „Odrzuć” / „Dołącz” na górze,
// pole nazwy z licznikiem, karta „Domownicy” z Tobą (plakietki „Ty”
// i „Właściciel”) i wierszem zaproszenia jako ostatnim — tu bez krążka
// udostępniania, bo domu jeszcze nie ma (link wyśle się z Ustawień).
//
// Zaproszenia, które już czekają na tego użytkownika, są tu KLIKALNE. Sam
// opis „otwórz link” nie wystarczał: ktoś, kto link otworzył i zamknął alert
// (albo otworzył go przed zalogowaniem), zostawał na tym ekranie bez drogi
// do zaproszenia — a jedynym wyjściem było założenie własnego domu.
struct WelcomeHouseholdStep: View {
    @Binding var householdName: String
    let firstName: String
    let avatarUrl: String?
    /// Ziarno awatara — id konta, jak w Ustawieniach.
    let seed: String
    let errorMessage: String?
    var pendingInvitations: [HouseholdInvitationSnapshot] = []
    var onAcceptInvitation: ((String) -> Void)? = nil
    var onDeclineInvitation: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    /// Błąd pod polem nazwy — w kreatorze zawsze pusty: zbyt krótka nazwa
    /// wyłącza „Utwórz gospodarstwo”, a licznik pokazuje długość. Błąd
    /// z serwera stoi pod kartami (`errorMessage`).
    @State private var nameError: String? = nil

    var body: some View {
        WelcomeStepPage {
            SCStepHeader(
                icon: "house.fill",
                accent: SCPalette.indigo,
                eyebrow: "Gospodarstwo",
                title: "Stwórz gospodarstwo",
                subtitle: "Wspólny plan i lista zakupów dla domowników."
            )
            .padding(.bottom, WelcomeLayout.headerSpacing)

            // Nad resztą, jak w Ustawieniach: dla kogoś zaproszonego to
            // właściwa droga, a nie zakładanie własnego domu.
            if !pendingInvitations.isEmpty {
                HouseholdInvitationsCard(
                    invitations: pendingInvitations,
                    hasHousehold: false,
                    onAccept: { onAcceptInvitation?($0.token) },
                    onDecline: { onDeclineInvitation?($0.token) }
                )
                .padding(.bottom, 20)
            }

            HouseholdNameField(name: $householdName, error: $nameError)

            EditorialSheetSectionLabel(title: "Domownicy")
                .padding(.top, 20)
            membersCard

            // Jedyny ślad drogi przez zaproszenie, gdy żadne nie czeka.
            if pendingInvitations.isEmpty {
                Text("Masz link od domownika? Otwórz go, a dołączysz do jego domu.")
                    .font(.sc(size: 12, weight: .medium))
                    .foregroundStyle(Color.scFaint(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
            }

            if let errorMessage, !errorMessage.isEmpty {
                SCInlineErrorText(errorMessage)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 6)
                    .padding(.top, 10)
            }
        }
    }

    /// Domownicy jak w Ustawieniach → Gospodarstwo: Ty z plakietkami, pod
    /// kreską miejsce na kolejną osobę.
    private var membersCard: some View {
        VStack(spacing: 0) {
            HouseholdMemberRow(
                displayName: firstName.isEmpty ? "Twoje konto" : firstName,
                avatarUrl: avatarUrl,
                colorIndex: nil,
                seed: seed,
                isMe: true,
                isOwner: true,
                showsRule: false
            )

            HouseholdInviteRowLabel(
                title: "Domownicy dołączą z linku",
                subtitle: "Wyślesz go z Ustawień po utworzeniu",
                phase: .later
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
