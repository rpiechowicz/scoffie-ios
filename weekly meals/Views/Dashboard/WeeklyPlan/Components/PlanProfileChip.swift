import SwiftUI

/// Which household lens the Plan screen is showing.
enum PlanProfile: Hashable {
    /// Everything the household eats — shared meals plus every personal one.
    case household
    /// One person: their meals plus everything shared.
    case member(String)

    var memberId: String? {
        if case .member(let id) = self { return id }
        return nil
    }

    /// Does a meal with this audience belong in the current lens?
    /// Shared meals („Wspólne", empty audience) always do.
    func includes(participantIds: [String]) -> Bool {
        switch self {
        case .household:
            return true
        case .member(let id):
            return participantIds.isEmpty || participantIds.contains(id)
        }
    }
}

/// Household / profile chip anchored to the top-right of Plan v2.
/// Tapping it opens `PlanProfileSheet`.
struct PlanProfileChip: View {
    let profile: PlanProfile
    let members: [HouseholdMemberSnapshot]
    var onTap: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var selectedMember: HouseholdMemberSnapshot? {
        guard let id = profile.memberId else { return nil }
        return members.first { $0.id == id }
    }

    private var label: String {
        guard let selectedMember else { return "Dom" }
        return HouseholdMemberStyle.shortName(selectedMember.displayName)
    }

    var body: some View {
        // `padding: '7px 10px 7px 7px', borderRadius: 99, gap: 8` — design.
        Button(action: onTap) {
            HStack(spacing: 8) {
                if let selectedMember {
                    MemberAvatar(member: selectedMember, members: members, size: 26)
                } else {
                    houseAvatar
                }

                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .padding(.trailing, 2)
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            // 6pt → wysokość 38pt, tyle co `EditorialIconButton` obok.
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.wmTileBg(scheme)))
            .overlay(Capsule().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filtr profilu: \(label)")
        .accessibilityHint("Zmień, dla kogo pokazywany jest plan")
    }

    private var houseAvatar: some View {
        Image(systemName: "house.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
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
}
