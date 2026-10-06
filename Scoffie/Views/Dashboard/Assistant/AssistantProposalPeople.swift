import SwiftUI

// „Kto co je” w propozycji planu (27.09.2026, Rafał: „jak wchodzi więcej dań,
// więcej osób, to robi się totalne zamieszanie i user gubi się w sekundę”).
//
// Klocki wspólne dla karty w rozmowie i przeglądu propozycji
// (`AssistantProposalReviewSheet`): JEDNA etykieta „dla kogo”
// (`ProposalAudience`), JEDNA pigułka z awatarami (`ProposalAudiencePill`,
// na `PlanWhoBadge` z Planu) i filtr osób (`ProposalPersonFilter`). To, co
// propozycja zmienia w planie, mówi od 6.10.2026 sam wiersz przeglądu
// („Nowe”, „Zamiast: …”, usunięcie) — półarkusz „Co się zmieni” odpadł.

// MARK: - Dla kogo

/// „Cały dom” / „Ty” / „Ania” / „Ty i Ania” / „Ania, Tomek i Ty” — z
/// `participantIds` dania (puste = cały dom). W domu jednoosobowym `nil`:
/// nie ma kogo rozróżniać, więc żadnego „dla kogo” na ekranie.
enum ProposalAudience {
    static func label(
        _ participantIds: [String],
        members: [HouseholdMemberSnapshot],
        me: String?
    ) -> String? {
        guard members.count > 1 else { return nil }
        let named = members.filter { participantIds.contains($0.id) }
        if participantIds.isEmpty || named.isEmpty || named.count == members.count {
            return "Cały dom"
        }
        // „Ty” na końcu — po polsku „Ania i Ty”, nie „Ty i Ania”.
        let ordered = named.filter { $0.id != me } + named.filter { $0.id == me }
        let names = ordered.map { $0.id == me ? "Ty" : HouseholdMemberStyle.shortName($0.displayName) }
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) i \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " i " + (names.last ?? "")
        }
    }

    /// Czy danie jest dla całego domu (albo dom ma jedną osobę).
    static func isShared(_ participantIds: [String], members: [HouseholdMemberSnapshot]) -> Bool {
        let named = members.filter { participantIds.contains($0.id) }
        return participantIds.isEmpty || named.isEmpty || named.count == members.count
    }

    /// Czy osoba `person` je to danie; `nil` = wszyscy.
    static func eats(_ participantIds: [String], person: String?) -> Bool {
        guard let person else { return true }
        return participantIds.isEmpty || participantIds.contains(person)
    }
}

/// Awatary (albo domek) + imiona — „dla kogo” przy daniu. Rysuje się tylko
/// w domu z więcej niż jedną osobą.
struct ProposalAudiencePill: View {
    let participantIds: [String]
    let members: [HouseholdMemberSnapshot]
    let me: String?
    var size: CGFloat = 18
    /// Pigułka na tle (strona dania) albo sam wiersz (listy).
    var filled: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let label = ProposalAudience.label(participantIds, members: members, me: me) {
            HStack(spacing: 6) {
                PlanWhoBadge(participantIds: participantIds, members: members, size: size)
                Text(label)
                    .font(.system(size: filled ? 13.5 : 12.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(filled ? AssistantLook.ink(scheme) : AssistantLook.muted(scheme))
                    .lineLimit(1)
            }
            .padding(.leading, filled ? 5 : 0)
            .padding(.trailing, filled ? 10 : 0)
            .frame(height: filled ? 28 : nil)
            .background {
                if filled {
                    Capsule(style: .continuous).fill(AssistantLook.field(scheme))
                }
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dla: \(label)")
        }
    }
}

/// „Wszyscy · Ty · Ania · Tomek” — co je KONKRETNA osoba. Kapsuły z awatarem
/// i imieniem, zaznaczenie w kolorze osoby (`scChoiceSurface(.chip)`).
struct ProposalPersonFilter: View {
    let members: [HouseholdMemberSnapshot]
    let me: String?
    /// `nil` = wszyscy.
    @Binding var selection: String?

    @Environment(\.colorScheme) private var scheme

    /// Ty pierwszy — najczęściej pytasz, co JA jem.
    private var ordered: [HouseholdMemberSnapshot] {
        members.filter { $0.id == me } + members.filter { $0.id != me }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(id: nil, title: "Wszyscy", accent: AssistantLook.terra(scheme)) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AssistantLook.terra(scheme))
                        .frame(width: 20, height: 20)
                }
                ForEach(ordered) { member in
                    chip(
                        id: member.id,
                        title: member.id == me ? "Ty" : HouseholdMemberStyle.shortName(member.displayName),
                        accent: HouseholdMemberStyle.color(for: member)
                    ) {
                        MemberAvatar(member: member, members: members, size: 20)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip<Avatar: View>(
        id: String?,
        title: String,
        accent: Color,
        @ViewBuilder avatar: () -> Avatar
    ) -> some View {
        let isOn = selection == id
        return Button {
            withAnimation(.smooth(duration: 0.25)) { selection = id }
        } label: {
            HStack(spacing: 6) {
                avatar()
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(isOn ? accent : AssistantLook.ink(scheme))
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(height: 32)
            .scChoiceSurface(Capsule(style: .continuous), isOn: isOn, accent: accent, style: .chip)
            .scTapHeight(drawn: 32)
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
