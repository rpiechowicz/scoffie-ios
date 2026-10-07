import SwiftUI

// MARK: - Przycisk „Dla kogo”

/// „Dla kogo” jako szklany przycisk obok przycisku zapisu — JEDEN w „Wybierz
/// przepis” i w „Dodaj do planu”. Wybrane osoby jako nachodzące awatary, cały
/// dom jako domek. Stuknięcie = SYSTEMOWE menu iOS z ptaszkami (Rafał
/// 4.10.2026: „mechanizm dla kogo trzeba lepiej uprościć, w stylu iOS”):
/// „Cały dom”, pod nim osoby; menu zostaje otwarte, więc kilka osób zaznacza
/// się bez ponownego otwierania. Dawniej osobny arkusz z listą i „Gotowe”.
/// Pusty wybór znaczy „Cały dom” (reguły w `PlanAudienceChips`).
struct PlanAudienceButton: View {
    let members: [HouseholdMemberSnapshot]
    @Binding var selection: Set<String>
    /// Kolor akcentu (kolor pory w „Wybierz przepis”) — glif domku.
    var accent: Color = SCPalette.terracotta
    /// Zostaje w API (nadtytuł dawnego arkusza).
    var eyebrow: String = "Dodaj do planu"
    var me: String? = nil
    var onChange: ((Set<String>) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    private var isWholeHouse: Bool {
        PlanAudienceChips.collapsed(selection, members: members).isEmpty
    }

    private var chosen: [HouseholdMemberSnapshot] {
        let ids = Set(PlanAudienceChips.collapsed(selection, members: members))
        return members.filter { ids.contains($0.id) }
    }

    var body: some View {
        Menu {
            Toggle(isOn: Binding(get: { isWholeHouse }, set: { _ in apply([]) })) {
                Label("Cały dom", systemImage: "house")
            }

            Section("Osoby") {
                ForEach(members, id: \.id) { member in
                    Toggle(isOn: Binding(
                        get: { !isWholeHouse && selection.contains(member.id) },
                        set: { _ in toggle(member.id) }
                    )) {
                        Text(member.id == me ? "\(member.displayName) (Ty)" : member.displayName)
                    }
                }
            }
        } label: {
            label
        }
        .menuActionDismissBehavior(.disabled)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityLabel("Dla kogo: \(Self.summary(selection, members: members, me: me))")
    }

    private var label: some View {
        let chosen = self.chosen
        return HStack(spacing: 6) {
            if chosen.isEmpty {
                Image(systemName: "house.fill")
                    .font(.sc(size: 13, weight: .bold))
                    .foregroundStyle(SCPalette.sage)
            } else {
                HStack(spacing: -7) {
                    ForEach(chosen.prefix(3), id: \.id) { member in
                        MemberAvatar(member: member, members: members, size: 22)
                            .overlay(Circle().strokeBorder(Color.scPageBase(scheme), lineWidth: 1.5))
                    }
                }
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.sc(size: 10, weight: .bold))
                .foregroundStyle(Color.scMuted(scheme))
        }
        .padding(.horizontal, 14)
        .frame(height: 45)
        .scChromeGlass(in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
        .animation(SCMotion.textRoll, value: chosen.map(\.id))
    }

    // MARK: Wybór

    /// Osoba z „Całego domu” startuje od samej siebie; zaznaczenie wszystkich
    /// (dom 3+ osobowy) zwija się z powrotem do „Całego domu”. Ostatniej osoby
    /// się nie odznacza, a w domu dwuosobowym osoby się wykluczają — do
    /// „Całego domu” prowadzi tylko jego wiersz (7.10.2026).
    private func toggle(_ memberId: String) {
        // Stuknięcie w OSOBĘ nigdy po cichu nie daje „Całego domu” (7.10.2026,
        // Rafał: „dodaję posiłek dla domu, potem 2. posiłek dla user2 jako
        // obok — oba chipy są dom”). W domu dwuosobowym każde stuknięcie
        // w osobę przy wybranej jednej osobie zwijało się do „Całego domu”:
        // odznaczenie ostatniej → pusto, dołożenie drugiej → wszyscy. Arkusz
        // „Osobne danie dla kogoś” startuje z jedną osobą, więc „wybranie”
        // user2 zapisywało drugie danie dla całego domu, karta mówiła „Zamień
        // dla wszystkich”, a „Dodaj obok” stawiało dwa dania „Wspólne” — oba
        // z domkiem. „Cały dom” ma własny wiersz menu.
        var next = isWholeHouse ? Set<String>() : Set(PlanAudienceChips.collapsed(selection, members: members))
        if next.contains(memberId) {
            // Ostatnia wybrana osoba zostaje (jak wybrana pozycja w `Picker`).
            guard next.count > 1 else { return }
            next.remove(memberId)
        } else if members.count == 2 {
            // Dwie osoby razem = „Cały dom”, więc tu osoby się wykluczają:
            // stuknięcie w drugą PRZEŁĄCZA na nią, zamiast dokładać.
            next = [memberId]
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
