import SwiftUI

/// Visual identity for a household member on Plan v2.
///
/// The design canvas gives every person a colour from the Cozy Kitchen accent
/// set and two-letter initials (Marek → butter „MK", Ania → sage „AN",
/// Lena → indigo „LE"). The backend stores none of that, so it is derived
/// here from the member's position in the household roster — which
/// `households:listMembers` returns in a stable order.
enum HouseholdMemberStyle {
    /// Accent order matches the design's household sample. Beyond the fifth
    /// member colours repeat; a household that large is already past the point
    /// where colour alone identifies anyone, and the avatar carries initials.
    private static let palette: [Color] = [
        WMPalette.butter,
        WMPalette.sage,
        WMPalette.indigo,
        WMPalette.terracottaDeep,
        WMPalette.terracotta
    ]

    static func color(for memberId: String, in members: [HouseholdMemberSnapshot]) -> Color {
        guard let index = members.firstIndex(where: { $0.id == memberId }) else {
            return WMPalette.terracotta
        }
        return palette[index % palette.count]
    }

    /// „Rafał Piechowicz" → „RP", „Ania" → „AN".
    static func initials(_ displayName: String) -> String {
        let words = displayName
            .split(separator: " ", omittingEmptySubsequences: true)
            .prefix(2)

        if words.count >= 2 {
            return words.compactMap(\.first).map(String.init).joined().uppercased()
        }

        let first = displayName.trimmingCharacters(in: .whitespaces)
        guard !first.isEmpty else { return "?" }
        return String(first.prefix(2)).uppercased()
    }

    /// First name only — what the design puts under an avatar and inside chips.
    static func shortName(_ displayName: String) -> String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
}

/// Who a meal is for, as the design renders it: a house glyph for „Wspólne",
/// one tinted avatar for a single person, or an overlapping stack for a subset.
struct PlanWhoBadge: View {
    let participantIds: [String]
    let members: [HouseholdMemberSnapshot]
    var size: CGFloat = 22

    @Environment(\.colorScheme) private var scheme

    /// Members actually named by the meal, in roster order so the stack is
    /// stable. Ids of people who since left the household simply drop out.
    private var named: [HouseholdMemberSnapshot] {
        members.filter { participantIds.contains($0.id) }
    }

    var body: some View {
        if participantIds.isEmpty || named.isEmpty {
            sharedBadge
        } else if named.count == 1 {
            MemberAvatar(member: named[0], members: members, size: size)
        } else {
            HStack(spacing: -size * 0.32) {
                ForEach(Array(named.prefix(3).enumerated()), id: \.element.id) { index, member in
                    MemberAvatar(member: member, members: members, size: size)
                        .overlay(
                            Circle().stroke(Color.wmCanvas(scheme), lineWidth: 1.5)
                        )
                        .zIndex(Double(3 - index))
                }
            }
        }
    }

    private var sharedBadge: some View {
        Image(systemName: "house.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Circle()
            )
            .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
            .accessibilityLabel("Wspólne")
    }
}

/// Single member avatar — remote photo when there is one, tinted initials
/// otherwise.
struct MemberAvatar: View {
    let member: HouseholdMemberSnapshot
    let members: [HouseholdMemberSnapshot]
    var size: CGFloat = 22

    var body: some View {
        let tint = HouseholdMemberStyle.color(for: member.id, in: members)

        Group {
            if let raw = member.avatarUrl, let url = URL(string: raw) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        initialsCircle(tint: tint)
                    @unknown default:
                        initialsCircle(tint: tint)
                    }
                }
            } else {
                initialsCircle(tint: tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(tint.opacity(0.5), lineWidth: 1))
        .accessibilityLabel(member.displayName)
    }

    private func initialsCircle(tint: Color) -> some View {
        ZStack {
            LinearGradient(
                colors: [tint, tint.mix(black: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )

            Text(HouseholdMemberStyle.initials(member.displayName))
                .font(.system(size: max(9, size * 0.4), weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
