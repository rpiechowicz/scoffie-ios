import SwiftUI

/// Rząd chipów „Wspólne / Marek / Ania …" — miejsce, w którym wybiera się
/// audytorium posiłku wstawianego do planu.
///
/// Wyciągnięte z `PlanSlotPickerSheet`, bo do planu prowadzi teraz drugie
/// wejście — arkusz „Dodaj do planu" ze szczegółu przepisu. Dwie kopie tego
/// samego rzędu rozjechałyby się przy pierwszej poprawce wyglądu, a co gorsza
/// każda mogłaby inaczej zwijać „wszyscy zaznaczeni" przed wysyłką.
///
/// Odznaczenie wszystkich wraca do „Wspólne", więc slot zawsze ma określone
/// audytorium.
struct PlanAudienceChips: View {
    let members: [HouseholdMemberSnapshot]
    /// Pusty zbiór znaczy „Wspólne" — danie je całe gospodarstwo.
    @Binding var selection: Set<String>
    /// Etykieta nad chipami — krojem `EditorialSheetSectionLabel`, jak
    /// „Dzień”, „Posiłek” i „Porcje” w arkuszu „Dodaj do planu”. Dawniej
    /// miała własne 9 pt z trackingiem 2 i jako jedyna w arkuszu odstawała.
    var sectionLabel: String = "Dla kogo"
    /// Wołane po każdej zmianie wyboru. Arkusz z porcjami podpina tu
    /// przestawienie steppera, żeby liczba porcji nadążała za audytorium,
    /// dopóki użytkownik nie ruszy go ręcznie.
    var onChange: ((Set<String>) -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    // MARK: - Reguły audytorium
    //
    // Statyczne, bo potrzebują ich obie strony: widok, żeby pokazać liczbę
    // porcji zanim cokolwiek poleci, i kod zapisujący, żeby wysłać to samo.

    /// Audytorium w formie, którą rozumie backend.
    ///
    /// Zaznaczenie wszystkich domowników to dokładnie to samo zdanie, co
    /// niezaznaczenie nikogo, więc zwija się do pustej listy. To nie jest
    /// kosmetyka: pusta lista uczestników jest dla serwera jedynym znakiem
    /// „Wspólne" i tylko po niej liczy porcje z liczby domowników zamiast
    /// z długości listy — a przy okazji filtr profilu w Planie pokazuje takie
    /// danie każdemu.
    ///
    /// Bierze całe `members`, a nie samą ich liczbę, bo przed zwinięciem
    /// trzeba przeciąć wybór z aktualnym składem gospodarstwa. Zaznaczenie
    /// potrafi przeżyć osobę: arkusz zasiewa je z zapisanego posiłku, więc
    /// po czyimś wyjściu z gospodarstwa zostaje w nim id, którego backend nie
    /// zna i całe żądanie leci na `PLAN_PARTICIPANT_NOT_IN_HOUSEHOLD`.
    /// Zwijanie „wszyscy → []" też musi patrzeć na przecięcie — inaczej
    /// nadmiarowe id psuje porównanie i wybór „wszyscy" jedzie jako lista
    /// imienna, czyli już nie „Wspólne".
    static func collapsed(_ selection: Set<String>, members: [HouseholdMemberSnapshot]) -> [String] {
        if selection.isEmpty { return [] }
        let known = members.map(\.id).filter { selection.contains($0) }
        if known.isEmpty { return [] }
        if known.count == members.count { return [] }
        // Sortujemy, żeby ten sam wybór dawał zawsze ten sam payload —
        // kolejność w `members` zależy od odpowiedzi serwera.
        return known.sorted()
    }

    /// Audytorium zapisu, gdy TEN SAM przepis już stoi w porze dla kogoś
    /// innego: suma osób, zwinięta do „Wspólne”, gdy obejmuje cały dom.
    ///
    /// Pozycja planu to jedna para (pora, przepis), więc zapis tego samego
    /// przepisu dla drugiej osoby PRZEPISYWAŁ audytorium pierwszej — ktoś,
    /// kto miał już ten obiad, zostawał bez posiłku (Rafał, 23.09.2026:
    /// „powinno automatycznie wykryć i zmienić na domostwo”).
    static func merged(
        _ participants: [String],
        with existing: PlanMeal?,
        members: [HouseholdMemberSnapshot]
    ) -> [String] {
        guard let existing else { return participants }
        // Któreś z nich je już całe domostwo — i tak zostaje.
        if existing.isShared || participants.isEmpty { return [] }
        return collapsed(Set(existing.participantIds).union(participants), members: members)
    }

    /// Ile osób realnie je danie — źródło reguły auto-porcji po stronie
    /// klienta, bliźniacze do tego, co liczy serwer, gdy `plannedServings`
    /// nie przyjdzie w payloadzie.
    static func eaterCount(_ selection: Set<String>, memberCount: Int) -> Int {
        selection.isEmpty ? max(1, memberCount) : selection.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialSheetSectionLabel(title: sectionLabel)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    chip(
                        title: "Wspólne",
                        tint: SCPalette.terracotta,
                        isOn: selection.isEmpty,
                        avatar: AnyView(houseGlyph)
                    ) {
                        apply([])
                    }

                    ForEach(members) { member in
                        let tint = HouseholdMemberStyle.color(for: member.id, in: members)
                        chip(
                            title: HouseholdMemberStyle.shortName(member.displayName),
                            tint: tint,
                            isOn: selection.contains(member.id),
                            avatar: AnyView(MemberAvatar(member: member, members: members, size: 20))
                        ) {
                            toggle(member.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func chip(
        title: String,
        tint: Color,
        isOn: Bool,
        avatar: AnyView,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                avatar

                Text(title)
                    .font(.system(size: 13, weight: isOn ? .bold : .semibold))
                    .foregroundStyle(isOn ? Color.scLabel(scheme) : Color.scMuted(scheme))
                    .lineLimit(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? tint.opacity(scheme == .dark ? 0.22 : 0.16) : Color.scTileBg(scheme))
            )
            .overlay(
                Capsule().stroke(
                    isOn ? tint.opacity(scheme == .dark ? 0.55 : 0.45) : Color.scTileStroke(scheme),
                    lineWidth: isOn ? 1.4 : 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var houseGlyph: some View {
        Image(systemName: "house.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(
                LinearGradient(
                    colors: [SCPalette.terracotta, SCPalette.terracotta.mix(black: 0.22)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Circle()
            )
    }

    // MARK: - Actions

    private func toggle(_ memberId: String) {
        var next = selection
        if next.contains(memberId) {
            next.remove(memberId)
        } else {
            next.insert(memberId)
        }
        apply(next)
    }

    /// Jedno przejście dla każdej zmiany, żeby `onChange` nie dało się
    /// przegapić przy dokładaniu kolejnego chipa.
    private func apply(_ next: Set<String>) {
        selection = next
        onChange?(next)
    }
}

// MARK: - Preview

/// Trzyma stan za chipy, bo `.constant` zamroziłoby je w podglądzie i nie dało
/// się sprawdzić, jak wygląda zaznaczenie.
private struct PlanAudienceChipsPreviewHost: View {
    @Environment(\.colorScheme) private var scheme
    @State private var selection: Set<String> = ["m2"]

    private let members: [HouseholdMemberSnapshot] = [
        HouseholdMemberSnapshot(
            id: "m1",
            displayName: "Rafał Piechowicz",
            email: nil,
            avatarUrl: nil,
            avatarColor: 0,
            role: "OWNER"
        ),
        HouseholdMemberSnapshot(
            id: "m2",
            displayName: "Ania Nowak",
            email: nil,
            avatarUrl: nil,
            avatarColor: 3,
            role: "MEMBER"
        ),
        HouseholdMemberSnapshot(
            id: "m3",
            displayName: "Marek",
            email: nil,
            avatarUrl: nil,
            avatarColor: 5,
            role: "MEMBER"
        )
    ]

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                PlanAudienceChips(members: members, selection: $selection)

                Text("Jedzących: \(PlanAudienceChips.eaterCount(selection, memberCount: members.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .padding(.horizontal, 22)
        }
    }
}

#Preview("Plan Audience Chips — Dark") {
    PlanAudienceChipsPreviewHost()
        .preferredColorScheme(.dark)
}

#Preview("Plan Audience Chips — Light") {
    PlanAudienceChipsPreviewHost()
        .preferredColorScheme(.light)
}
