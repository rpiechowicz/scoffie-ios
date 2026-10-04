import SwiftUI

// MARK: - Przycisk „Dla kogo”

/// „Dla kogo” jako szklany przycisk obok przycisku zapisu — JEDEN w „Wybierz
/// przepis” i w „Dodaj do planu” (Rafał 4.10.2026: „daj taki sam mechanizm
/// wybierania usera z buttonem przy »Dodaj« jako sheet”). Wybrane osoby jako
/// nachodzące awatary, cały dom jako domek; stuknięcie = `PlanAudienceSheet`.
/// Pusty wybór znaczy „Cały dom” (reguły w `PlanAudienceChips`).
struct PlanAudienceButton: View {
    let members: [HouseholdMemberSnapshot]
    @Binding var selection: Set<String>
    /// Kolor akcentu arkusza (kolor pory w „Wybierz przepis”).
    var accent: Color = SCPalette.terracotta
    /// Nadtytuł arkusza — pora albo „Dodaj do planu”.
    var eyebrow: String = "Dodaj do planu"
    var me: String? = nil
    var onChange: ((Set<String>) -> Void)? = nil

    @State private var isPresented = false
    @Environment(\.colorScheme) private var scheme

    private var chosen: [HouseholdMemberSnapshot] {
        let ids = Set(PlanAudienceChips.collapsed(selection, members: members))
        return members.filter { ids.contains($0.id) }
    }

    var body: some View {
        let chosen = self.chosen
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                if chosen.isEmpty {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SCPalette.sage)
                } else {
                    HStack(spacing: -7) {
                        ForEach(chosen.prefix(3), id: \.id) { member in
                            MemberAvatar(member: member, members: members, size: 22)
                                .overlay(Circle().strokeBorder(Color.scPageBase(scheme), lineWidth: 1.5))
                        }
                    }
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .padding(.horizontal, 14)
            .frame(height: 45)
            .scChromeGlass(in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel("Dla kogo: \(PlanAudienceSheet.summary(selection, members: members, me: me))")
        .accessibilityHint("Otwiera wybór domowników")
        .sheet(isPresented: $isPresented) {
            PlanAudienceSheet(
                members: members,
                selection: $selection,
                accent: accent,
                eyebrow: eyebrow,
                me: me,
                onChange: onChange,
                onClose: { isPresented = false }
            )
        }
    }
}

// MARK: - Arkusz „Dla kogo”

/// Wybór, kto je danie (Rafał 4.10.2026: „sheet dla kogo zrób ładniej,
/// dopracuj, bo jest bardzo niewykorzystany”). Wspólny nagłówek z podsumowaniem
/// („Ania i Ty”), wiersz „Cały dom” i lista domowników: awatar w obwódce koloru
/// osoby, imię z „TY” i pole wyboru. Zaznaczenie wszystkich zwija się do
/// „Cały dom”, odznaczenie ostatniej osoby — też (ta sama reguła, co chipy).
/// Dawniej poziomy rząd chipów w pustym arkuszu.
struct PlanAudienceSheet: View {
    let members: [HouseholdMemberSnapshot]
    @Binding var selection: Set<String>
    var accent: Color = SCPalette.terracotta
    var eyebrow: String = "Dodaj do planu"
    var me: String? = nil
    var onChange: ((Set<String>) -> Void)? = nil
    let onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var isWholeHouse: Bool {
        PlanAudienceChips.collapsed(selection, members: members).isEmpty
    }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    EditorialSheetHeader(
                        eyebrow: eyebrow,
                        title: "Dla kogo",
                        icon: "person.2.fill",
                        accent: accent,
                        subtitle: Self.summary(selection, members: members, me: me),
                        subtitleTransition: .opacity,
                        onClose: onClose
                    )

                    card {
                        houseRow
                    }

                    EditorialSheetSectionLabel(title: "Albo wybierz osoby")
                        .padding(.top, 4)

                    card {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            memberRow(member, showsRule: index > 0)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scSheetFooter {
                EditorialPrimaryActionButton(title: "Gotowe", icon: "checkmark", action: onClose)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .presentationDetents([.medium, .large])
        .dashboardLiquidSheet()
    }

    // MARK: Wiersze

    private var houseRow: some View {
        Button {
            apply([])
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SCPalette.sage)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(SCPalette.sage.opacity(scheme == .dark ? 0.18 : 0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cały dom")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(scheme))
                    Text("Wszyscy jedzą to danie")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCRadioMark(isOn: isWholeHouse, size: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityAddTraits(isWholeHouse ? [.isButton, .isSelected] : .isButton)
    }

    private func memberRow(_ member: HouseholdMemberSnapshot, showsRule: Bool) -> some View {
        let tint = HouseholdMemberStyle.color(for: member.id, in: members)
        let isOn = !isWholeHouse && selection.contains(member.id)
        let isMe = member.id == me

        return Button {
            toggle(member.id)
        } label: {
            HStack(spacing: 12) {
                MemberAvatar(member: member, members: members, size: 40)
                    .padding(2.5)
                    .overlay(Circle().strokeBorder(tint.opacity(isOn ? 1 : 0), lineWidth: 2))

                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)
                    if isMe {
                        Text("TY")
                            .font(.system(size: 9.5, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(SCPalette.terracotta)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.12), in: Capsule())
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SCCheckbox(on: isOn, accent: tint, size: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if showsRule {
                    Rectangle()
                        .fill(Color.scTileStroke(scheme))
                        .frame(height: 1)
                        .padding(.leading, 14 + 45 + 12)
                }
            }
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .animation(SCMotion.textRoll, value: isOn)
        .accessibilityLabel(isMe ? "\(member.displayName), Ty" : member.displayName)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return VStack(spacing: 0, content: content)
            .background(shape.fill(Color.scTileBg(scheme)))
            .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }

    // MARK: Wybór

    /// Osoba z „Całego domu” startuje od samej siebie; zaznaczenie wszystkich
    /// zwija się z powrotem do „Całego domu”.
    private func toggle(_ memberId: String) {
        var next = isWholeHouse ? Set<String>() : selection
        if next.contains(memberId) {
            next.remove(memberId)
        } else {
            next.insert(memberId)
        }
        apply(Set(PlanAudienceChips.collapsed(next, members: members)))
    }

    private func apply(_ next: Set<String>) {
        withAnimation(SCMotion.textRoll) { selection = next }
        onChange?(next)
    }

    /// „Cały dom · 3 osoby”, „Ania i Ty”, „Ania, Kuba i Ty”.
    static func summary(_ selection: Set<String>, members: [HouseholdMemberSnapshot], me: String?) -> String {
        let ids = Set(PlanAudienceChips.collapsed(selection, members: members))
        guard !ids.isEmpty else {
            return "Cały dom · \(members.count) \(PolishPlural.form(members.count, one: "osoba", few: "osoby", many: "osób"))"
        }
        let chosen = members.filter { ids.contains($0.id) }
        var names = chosen.filter { $0.id != me }.map { HouseholdMemberStyle.shortName($0.displayName) }
        if let me, ids.contains(me) { names.append("Ty") }
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " i " + last
    }
}
