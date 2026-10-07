import SwiftUI

// Klocki gospodarstwa — JEDNE dla Ustawień (arkusz gospodarstwa i zakładanie
// domu w `SettingsView`) i ostatniego kroku kreatora (`WelcomeHouseholdStep`).
//
// 7.10.2026 (Rafał: „zrób na onboarding user te nowe widoki z ustawień…
// uspójnij to”): kreator rysował nazwę domu, domowników z plakietkami
// wersalikami i zaproszenia po swojemu, a Ustawienia od 6.10.2026 mają
// plakietki zwykłymi literami w tincie, zaproszenie jako ostatni wiersz listy
// i skrzynkę zaproszeń z „Odrzuć” / „Dołącz”. Teraz oba miejsca biorą te
// same widoki stąd; logika (zapis, link, usuwanie domownika) zostaje u nich.

// MARK: - Nazwa domu

/// Karta z polem nazwy domu — zakładanie gospodarstwa w Ustawieniach i krok
/// „Gospodarstwo” w kreatorze. Licznik pilnuje górnej granicy
/// (`SessionStore.householdNameLengthRange`, 2–50 wszędzie), błąd stoi pod
/// polem i gaśnie przy pierwszej zmianie nazwy.
struct HouseholdNameField: View {
    @Binding var name: String
    @Binding var error: String?

    @Environment(\.colorScheme) private var scheme

    private static let maxLength = SessionStore.householdNameLengthRange.upperBound

    private var trimmedCount: Int {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSheetSectionLabel(title: "Nazwa")

            TextField("Np. Dom", text: $name)
                .textInputAutocapitalization(.words)
                .font(.sc(size: 15.5, weight: .medium))
                .foregroundStyle(Color.scLabel(scheme))
                .tint(SCPalette.terracotta)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.scChipBg(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            error != nil
                                ? SCInlineErrorText.tint.opacity(0.6)
                                : Color.scTileStroke(scheme),
                            lineWidth: error != nil ? 1.5 : 1
                        )
                )
                .onChange(of: name) { _, _ in
                    if error != nil { error = nil }
                }

            if let error {
                SCInlineErrorText(error)
                    .padding(.horizontal, 4)
            }

            HStack {
                Spacer()
                Text("\(trimmedCount)/\(Self.maxLength)")
                    .font(.sc(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(
                        trimmedCount > Self.maxLength
                            ? SCInlineErrorText.tint
                            : Color.scFaint(scheme)
                    )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }
}

// MARK: - Domownik

/// Mała plakietka przy imieniu — „Ty” w terakocie, „Właściciel” w maśle,
/// zwykłymi literami w tincie (6.10.2026; wersaliki 9,5 pt odstawały od
/// reszty aplikacji). Stały rozmiar (`fixedSize`): przy długim imieniu
/// skraca się imię, a nie plakietka.
struct HouseholdMemberBadge: View {
    let text: String
    let color: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.sc(size: 11.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(scheme == .dark ? 0.16 : 0.12), in: Capsule())
            .fixedSize()
    }
}

/// Wiersz domownika: awatar, imię i plakietki — nic więcej (Rafał,
/// 23.09.2026: dieta i alergeny „tu nie mają sensu”). Jedna linijka, więc
/// każdy wiersz ma tę samą wysokość — wyznacza ją awatar. Z prawej opcjonalna
/// akcja (menu domownika, kręciołek usuwania). Kreska nad wierszem od
/// drugiego w górę, wcięta pod imię.
struct HouseholdMemberRow<Trailing: View>: View {
    let displayName: String
    let avatarUrl: String?
    let colorIndex: Int?
    let seed: String
    let isMe: Bool
    let isOwner: Bool
    let showsRule: Bool
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    /// Rola dla VoiceOver — to samo, co plakietki przy imieniu.
    private var roleDescription: String {
        let role = isOwner ? "Właściciel" : "Domownik"
        return isMe ? "\(role), to Ty" : role
    }

    var body: some View {
        HStack(spacing: 12) {
            // Kolor z backendu + ziarno z id — dokładnie to, czym ten sam
            // domownik świeci na Planie.
            ProfileAvatar(
                avatarUrl: avatarUrl,
                displayName: displayName,
                size: 40,
                colorIndex: colorIndex,
                seed: seed
            )

            HStack(spacing: 6) {
                Text(displayName)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                if isMe {
                    HouseholdMemberBadge(text: "Ty", color: SCPalette.terracotta)
                }

                if isOwner {
                    HouseholdMemberBadge(text: "Właściciel", color: SCPalette.butter)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(displayName)
            .accessibilityValue(roleDescription)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if showsRule {
                HouseholdRowRule()
            }
        }
    }
}

extension HouseholdMemberRow where Trailing == EmptyView {
    init(
        displayName: String,
        avatarUrl: String?,
        colorIndex: Int?,
        seed: String,
        isMe: Bool,
        isOwner: Bool,
        showsRule: Bool
    ) {
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.colorIndex = colorIndex
        self.seed = seed
        self.isMe = isMe
        self.isOwner = isOwner
        self.showsRule = showsRule
        self.trailing = { EmptyView() }
    }
}

/// Kreska między wierszami karty domowników — wcięta pod imię (14 + 40 + 12).
struct HouseholdRowRule: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(Color.scRule(scheme))
            .frame(height: 1)
            .padding(.leading, 14 + 40 + 12)
    }
}

// MARK: - Zaproszenie

/// Ostatni wiersz karty domowników — miejsce na kolejną osobę: przerywane
/// kółko z plusem w miejscu awatara, tytuł i warunki linku, z prawej krążek
/// udostępniania (Ustawienia). Ten sam wiersz w kreatorze stoi BEZ krążka
/// i bez terakoty w tytule (`Phase.later`): domu jeszcze nie ma, więc nie ma czego
/// udostępnić — link wyśle się z Ustawień.
struct HouseholdInviteRowLabel: View {
    enum Phase: Equatable {
        /// Link gotowy — krążek „udostępnij”.
        case ready
        /// Linku jeszcze nie ma — krążek „przygotuj ponownie”.
        case retry
        /// Link się tworzy — kręciołek w krążku.
        case loading
        /// Kreator: zaprosi się po utworzeniu domu.
        case later
    }

    let title: String
    let subtitle: String
    let phase: Phase

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(
                    SCPalette.terracotta.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
                .background(Circle().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.12 : 0.08)))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "plus")
                        .font(.sc(size: 16, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(phase == .later ? Color.scLabel(scheme) : SCPalette.terracotta)
                Text(subtitle)
                    .font(.sc(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)

            if phase != .later {
                Group {
                    if phase == .loading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(SCPalette.terracotta)
                    } else {
                        Image(systemName: phase == .ready ? "square.and.arrow.up" : "arrow.clockwise")
                            .font(.sc(size: 14, weight: .semibold))
                            .foregroundStyle(SCPalette.terracotta)
                    }
                }
                .frame(width: 34, height: 34)
                .scChromeGlass(in: Circle(), tint: SCPalette.terracotta.opacity(scheme == .dark ? 0.3 : 0.22))
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            HouseholdRowRule()
        }
    }
}

// MARK: - Zaproszenia czekające na użytkownika

/// Skrzynka zaproszeń: dom, kto zaprasza, do kiedy — i „Odrzuć” / „Dołącz”.
///
/// Powód istnienia jest prosty: zaproszenie było wyłącznie linkiem
/// w komunikatorze. Kto otworzył je w złym momencie — bo należał już do
/// innego gospodarstwa albo zamknął alert — nie miał w aplikacji ŻADNEGO
/// śladu, że coś do niego przyszło. W kreatorze to jedyna alternatywa dla
/// zakładania własnego domu.
struct HouseholdInvitationsCard: View {
    let invitations: [HouseholdInvitationSnapshot]
    /// Użytkownik ma już dom — dołączenie oznacza jego opuszczenie, więc
    /// przycisk mówi „Przenieś się”, a nie samo „Dołącz”.
    let hasHousehold: Bool
    let onAccept: (HouseholdInvitationSnapshot) -> Void
    let onDecline: (HouseholdInvitationSnapshot) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetSectionLabel(title: "Zaproszenia")

            VStack(spacing: 0) {
                ForEach(Array(invitations.enumerated()), id: \.element.id) { index, invitation in
                    row(invitation, isLast: index == invitations.count - 1)
                }
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
        }
    }

    private func row(_ invitation: HouseholdInvitationSnapshot, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                EditorialSettingsTileIcon(icon: "envelope.open.fill", color: SCPalette.butter)

                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.householdName)
                        .font(.sc(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))

                    Text(invitation.subtitle)
                        .font(.sc(size: 12, weight: .regular))
                        .foregroundStyle(Color.scMuted(scheme))

                    if let expiry = invitation.expiresAtText {
                        Text("Ważne do: \(expiry)")
                            .font(.sc(size: 11, weight: .medium))
                            .foregroundStyle(Color.scMuted(scheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                // Neutralne szkło obok „Dołącz” (szkło w tincie) — jak
                // `AssistantGhostButton`, nie ciężka szara płyta.
                Button {
                    onDecline(invitation)
                } label: {
                    Text("Odrzuć")
                        .font(.sc(size: 13, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .scChromeGlass(in: Capsule(style: .continuous))
                }
                .buttonStyle(PlanPressStyle(scale: 0.96))

                Button {
                    onAccept(invitation)
                } label: {
                    Text(hasHousehold ? "Przenieś się" : "Dołącz")
                        .font(.sc(size: 13, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .scSoftCapsule()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasHousehold ? "Przenieś się do \(invitation.householdName)" : "Dołącz do \(invitation.householdName)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.leading, 16 + 32 + 14)
            }
        }
    }
}
