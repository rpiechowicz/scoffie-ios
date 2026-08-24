import SwiftUI

// Welcome step 4 — Create or join a household. Mirrors NoHouseholdView's
// affordances but in the Cozy Kitchen visual language.
//
// Zaproszenia, które już czekają na tego użytkownika, są tu KLIKALNE. Sam
// opis „otwórz link" nie wystarczał: ktoś, kto link otworzył i zamknął alert
// (albo otworzył go przed zalogowaniem), zostawał na tym ekranie bez żadnej
// drogi do zaproszenia poza szukaniem wiadomości po raz drugi — a jedynym
// wyjściem było założenie własnego, niepotrzebnego gospodarstwa.
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
        VStack(alignment: .leading, spacing: 18) {
            WelcomeStepHeader(
                icon: "house.fill",
                accent: WMPalette.terracotta,
                eyebrow: "Ostatni krok",
                title: "Stwórz gospodarstwo",
                subtitle: "Wspólna przestrzeń dla domowników: plan posiłków, lista zakupów i przepisy. Zaprosisz innych później."
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        WMPalette.sage,
                                        WMPalette.sage.opacity(0.78),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nowe gospodarstwo")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(Color.wmLabel(colorScheme))
                        Text("Nazwa pomoże domownikom rozpoznać wspólne menu.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.wmMuted(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    TextField("Np. Nasz dom", text: $householdName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isHouseholdFieldFocused)
                        .submitLabel(.done)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.wmLabel(colorScheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.wmChipBg(colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.wmTileStroke(colorScheme), lineWidth: 1)
                        )
                )

                HStack(spacing: 10) {
                    AvatarStack(initial: avatarInitial)
                    Text("Domowników zaprosisz po utworzeniu")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(colorScheme))
                }
                .padding(.top, 8)
                .overlay(
                    Divider()
                        .background(Color.wmRule(colorScheme))
                        .padding(.horizontal, -2),
                    alignment: .top
                )
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.wmTileBg(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.wmTileStroke(colorScheme), lineWidth: 1)
                    )
            )

            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.wmTileStroke(colorScheme))
                    .frame(height: 1)
                Text("Albo".uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.wmMuted(colorScheme))
                Rectangle()
                    .fill(Color.wmTileStroke(colorScheme))
                    .frame(height: 1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)

            VStack(spacing: 10) {
                if pendingInvitations.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.wmLabel(colorScheme))
                        Text("Dołącz z linku zaproszenia")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.wmLabel(colorScheme))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                Color.wmFaint(colorScheme),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                            )
                    )

                    Text("Otwórz link otrzymany od domownika — Weekly Meals przejmie zaproszenie automatycznie.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                } else {
                    ForEach(pendingInvitations) { invitation in
                        Button {
                            onAcceptInvitation?(invitation.token)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.open.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(WMPalette.terracotta)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invitation.householdName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.wmLabel(colorScheme))
                                    Text(invitation.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.wmMuted(colorScheme))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text("Dołącz")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(WMPalette.terracotta)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(WMPalette.terracotta.opacity(0.45), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Zaproszenie czeka na Ciebie — możesz dołączyć zamiast zakładać własne gospodarstwo.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(colorScheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 112)
        .padding(.bottom, 170)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct AvatarStack: View {
    let initial: String
    @Environment(\.colorScheme) private var colorScheme

    private let bubbleSize: CGFloat = 28
    private let ringWidth: CGFloat = 2

    var body: some View {
        // Each bubble is `bubbleSize` and gets a `ringWidth` halo of canvas
        // colour around it (via padding + a slightly larger background
        // circle). The negative HStack spacing then lets the next bubble
        // overlap into that halo cleanly — no stroke cutting into content.
        HStack(spacing: -bubbleSize / 3) {
            avatarBubble
                .zIndex(1)
            placeholderBubble
                .zIndex(0)
        }
    }

    private var avatarBubble: some View {
        Text(initial)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: bubbleSize, height: bubbleSize)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                WMPalette.terracotta,
                                WMPalette.terracottaDeep,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .padding(ringWidth)
            .background(Circle().fill(Color.wmCanvas(colorScheme)))
    }

    private var placeholderBubble: some View {
        Image(systemName: "plus")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.wmMuted(colorScheme))
            .frame(width: bubbleSize, height: bubbleSize)
            .background(Circle().fill(Color.wmChipBg(colorScheme)))
            .overlay(
                Circle()
                    .strokeBorder(
                        Color.wmFaint(colorScheme),
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])
                    )
            )
            .padding(ringWidth)
            .background(Circle().fill(Color.wmCanvas(colorScheme)))
    }
}

#Preview("Dark") {
    StatefulPreviewContainer(name: "") { name in
        ZStack {
            WMPalette.canvasDark.ignoresSafeArea()
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
            WMPalette.canvasLight.ignoresSafeArea()
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
