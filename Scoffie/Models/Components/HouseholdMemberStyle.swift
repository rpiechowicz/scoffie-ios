import SwiftUI

/// Visual identity for a household member on Plan v2.
///
/// Kolor bierze się z `avatarColor` przydzielonego przez backend przy
/// kończeniu onboardingu — tego samego, którym maluje się awatar konta
/// w Ustawieniach. Dzięki temu jedna osoba ma jeden kolor w całej aplikacji.
///
/// Wcześniej kolor liczył się z POZYCJI domownika na liście gospodarstwa.
/// Miało to dwie wady: ta sama osoba wyglądała inaczej w profilu niż w Planie,
/// a dołączenie kogoś nowego przestawiało kolory wszystkim pozostałym.
enum HouseholdMemberStyle {
    static func color(for memberId: String, in members: [HouseholdMemberSnapshot]) -> Color {
        guard let member = members.first(where: { $0.id == memberId }) else {
            return WMPalette.terracotta
        }
        return color(for: member)
    }

    /// Pierwszy przystanek gradientu awatara — dominujący odcień tej osoby.
    /// Chip i awatar mówią wtedy tym samym kolorem.
    static func color(for member: HouseholdMemberSnapshot) -> Color {
        ProfileAvatar.baseColor(index: member.avatarColor, seed: member.id)
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
        // Ten sam awatar co w Ustawieniach: zdjęcie, a w jego braku gradient
        // z `avatarColor` przydzielonego przez backend. Wcześniej domownicy
        // byli kolorowani po POZYCJI na liście gospodarstwa, więc ta sama
        // osoba miała jeden kolor w profilu i inny w Planie, a dołączenie
        // kogoś nowego przestawiało kolory wszystkim.
        ProfileAvatar(
            avatarUrl: member.avatarUrl,
            displayName: member.displayName,
            size: size,
            colorIndex: member.avatarColor,
            seed: member.id
        )
        .accessibilityLabel(member.displayName)
    }

}
