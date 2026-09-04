import SwiftUI

/// „Dla kogo planujesz" — the Plan v2 profile picker.
/// Gospodarstwo shows everything; picking a person narrows the week to their
/// meals plus everything the household shares.
struct PlanProfileSheet: View {
    @Binding var profile: PlanProfile
    let members: [HouseholdMemberSnapshot]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DLA KOGO PLANUJESZ")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(WMPalette.terracotta)

                    Text("Wybierz profil")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .padding(.top, 3)
                        .padding(.bottom, 16)

                    row(
                        isSelected: profile == .household,
                        avatar: AnyView(houseAvatar),
                        title: "Gospodarstwo",
                        subtitle: "Wszystkie posiłki domowników",
                        tint: WMPalette.terracotta
                    ) {
                        select(.household)
                    }
                    .padding(.bottom, 8)

                    ForEach(members) { member in
                        let tint = HouseholdMemberStyle.color(for: member.id, in: members)
                        let short = HouseholdMemberStyle.shortName(member.displayName)

                        row(
                            isSelected: profile == .member(member.id),
                            avatar: AnyView(MemberAvatar(member: member, members: members, size: 40)),
                            title: member.displayName,
                            subtitle: "Tylko posiłki — \(short)",
                            tint: tint
                        ) {
                            select(.member(member.id))
                        }
                        .padding(.bottom, 8)
                    }

                    if members.isEmpty {
                        emptyMembersNote
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Pieces

    private func row(
        isSelected: Bool,
        avatar: AnyView,
        title: String,
        subtitle: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(tint)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? tint.opacity(scheme == .dark ? 0.16 : 0.12) : Color.wmTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? tint.opacity(scheme == .dark ? 0.5 : 0.4) : Color.wmTileStroke(scheme),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var houseAvatar: some View {
        Image(systemName: "house.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                LinearGradient(
                    colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.22)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Circle()
            )
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
    }

    /// A household of one has nothing to split, so say so rather than showing
    /// an empty list under „Gospodarstwo".
    private var emptyMembersNote: some View {
        Text("Zaproś domowników w Ustawieniach, żeby planować posiłki osobno dla każdego.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.wmMuted(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func select(_ next: PlanProfile) {
        profile = next
        dismiss()
    }
}
