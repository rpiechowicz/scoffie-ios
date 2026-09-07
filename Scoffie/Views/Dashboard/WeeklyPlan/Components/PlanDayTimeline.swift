import SwiftUI

// Plan tygodnia v2 — dzień jako oś czasu.
//
// Źródło: canvas claude.ai → „Weekly Meals - Plan v2.html”, kierunek D
// (`components/plan-v2-d.jsx`). Po lewej szyna czasu: kropka pory na pionowej
// linii, godzina pod nią. Po prawej wiersze BEZ kart — hairline dopiero pod
// treścią, zdjęcie 72 pt przy krawędzi.
//
// Zniknęły przy tym dwa komponenty: karta dnia (`PlanDayCard`) i sekcja
// „Każdy je inaczej” (`PlanDaySplitsSection`). Porę dnia niesie teraz szyna,
// a danie domownika stoi wprost pod daniem domu — mniejsze, podpisane jego
// imieniem i w jego kolorze. To ta sama odpowiedź na „kto je inaczej”, tyle że
// w miejscu, w którym pada pytanie, a nie o pół ekranu niżej.
struct PlanDayTimeline: View {
    let date: Date
    let isToday: Bool
    /// Dni z przeszłości są tylko do czytania — bez „Wybierz przepis”,
    /// „Dodaj posiłek” i menu kontekstowego.
    let isEditable: Bool
    let profile: PlanProfile
    let members: [HouseholdMemberSnapshot]
    /// Sloty do narysowania — w kolejności dnia, już z uwzględnieniem ustawień
    /// gospodarstwa. Oś ich nie wylicza, bo tę samą listę widzi podsumowanie
    /// w nagłówku dnia.
    let slots: [MealSlot]
    /// Warianty posiłku w slocie, już zawężone do bieżącego profilu.
    let meals: (MealSlot) -> [PlanMeal]
    /// Sloty, których ten dzień jeszcze nie pokazuje — z nich wybiera się przy
    /// „Dodaj posiłek”. Pusto = wiersza nie ma czym wypełnić, więc go nie ma.
    let extraSlots: [MealSlot]
    /// Cały widoczny tydzień bez jednego posiłku — i dzień, w który da się
    /// coś dodać. Wtedy nad osią stoi wołanie do asystenta: sześć wierszy
    /// „Nic nie zaplanowano" mówi o dniu, a nikt z nich nie wyczyta, że pusty
    /// jest cały tydzień i że jest na to jeden przycisk.
    var weekIsEmpty: Bool = false
    let onTapMeal: (MealSlot, PlanMeal) -> Void
    let onAddMeal: (MealSlot) -> Void
    let onEditMeal: (MealSlot, PlanMeal) -> Void
    let onRemoveMeal: (MealSlot, PlanMeal) -> Void
    let onAssistant: () -> Void
    /// Pora wybrana z menu „Dodaj posiłek”.
    let onPickExtraSlot: (MealSlot) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.sessionStore) private var sessionStore

    // MARK: - Wiersze

    /// Jeden wiersz osi: pora dnia i wszystko, co w niej stoi.
    private struct Row: Identifiable {
        let slot: MealSlot
        let dishes: [PlanMeal]
        var id: String { slot.rawValue }
    }

    private var rows: [Row] {
        slots.map { Row(slot: $0, dishes: Self.ordered(meals($0))) }
    }

    /// Danie domu przed daniami osobistymi.
    ///
    /// Kolejność jest treścią, a nie kosmetyką: pierwsze danie wiersza nosi
    /// eyebrow z porą dnia i duże zdjęcie, każde następne — imię domownika
    /// i mniejsze zdjęcie. Gdyby danie Zosi trafiło na górę, to ono udawałoby
    /// posiłek całego domu.
    private static func ordered(_ meals: [PlanMeal]) -> [PlanMeal] {
        meals.filter(\.isShared) + meals.filter { !$0.isShared }
    }

    private var showsAddRow: Bool {
        isEditable && !extraSlots.isEmpty
    }

    /// Odcisk treści dnia — po nim animuje się dokładanie i usuwanie posiłków.
    /// Data w nim nie siedzi: zmianę dnia prowadzi `DayPager`, a `.id` niżej
    /// nadaje nowemu dniu świeżą tożsamość, więc nic nie przelatuje między
    /// poniedziałkiem a wtorkiem.
    private var fingerprint: String {
        rows
            .map { "\($0.slot.rawValue):\($0.dishes.map(\.id).joined(separator: ","))" }
            .joined(separator: "|")
            + (showsAddRow ? "|+" : "")
    }

    private var dayKey: String { MealCalendarStore.dateKey(for: date) }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 18)
                .padding(.bottom, 14)

            if weekIsEmpty {
                emptyWeekCallout
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            timeline
        }
        // Wołanie znika tą samą sprężyną, którą pierwszy posiłek wjeżdża na
        // oś niżej — jeden ruch, nie dwa.
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: weekIsEmpty)
        // Świeża tożsamość na każdy dzień: bez niej sprężyna niżej próbowałaby
        // przeprowadzić wiersze poniedziałku w wiersze wtorku dokładnie wtedy,
        // gdy `DayPager` przesuwa całą stronę — dwie animacje na jednym ruchu.
        .id(dayKey)
    }

    // MARK: - Pusty tydzień

    /// Karta nad osią: „ten tydzień jest jeszcze pusty" i droga do asystenta.
    ///
    /// Ta sama akcja, co przycisk z różdżką w nagłówku dnia — ale ten przycisk
    /// jest ikoną bez podpisu i przy pustym tygodniu nikt nie wie, że to
    /// właśnie on. Karta mówi to słowami, raz, i znika z pierwszym posiłkiem.
    private var emptyWeekCallout: some View {
        Button(action: onAssistant) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: MenuConstans.Assistant.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .frame(width: 36, height: 36)
                    .scSoftSurface(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ten tydzień jest jeszcze pusty")
                        .scFont(14.5, weight: .semibold, relativeTo: .footnote)
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))

                    Text("Asystent ułoży go w kilka sekund. Możesz też dodać posiłki ręcznie niżej.")
                        .scFont(12.5, relativeTo: .caption)
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityLabel("Ten tydzień jest jeszcze pusty. Zaplanuj z asystentem")
    }

    // MARK: - Nagłówek dnia

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(Self.longDayFormatter.string(from: date).capitalized)
                        .scFont(22, weight: .bold, relativeTo: .title2)
                        .tracking(-0.5)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if isToday { todayBadge }
                }

                Text(summaryText)
                    .scFont(14, weight: .regular, relativeTo: .footnote)
                    .tracking(-0.15)
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    // Liczby w podsumowaniu przechodzą, zamiast przeskakiwać:
                    // dołożenie obiadu przesuwa „1 z 3” na „2 z 3” i kalorie
                    // w tej samej klatce, w której wiersz wjeżdża na oś.
                    // Sama `.contentTransition` nie wystarczy — musi mieć czym
                    // jechać, stąd ta sama sprężyna, co pod osią niżej.
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.36, dampingFraction: 0.9), value: summaryText)
            }

            Spacer(minLength: 8)

            assistantButton
        }
    }

    private var todayBadge: some View {
        Text("DZIŚ")
            .scFont(10.5, weight: .bold, relativeTo: .caption2)
            .tracking(0.6)
            .foregroundStyle(SCPalette.terracotta)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.14))
            )
            .fixedSize()
    }

    /// Zawsze asystent, nigdy „+”.
    ///
    /// Dodawanie ręczne żyje w wierszach osi („Wybierz przepis”, „Dodaj
    /// posiłek”), więc przycisk nagłówka może być jedną rzeczą przez wszystkie
    /// stany dnia — pełny, częściowy i pusty.
    private var assistantButton: some View {
        Button(action: onAssistant) {
            // `scSoftSurface` zamiast własnego tintu i obwódki: te same liczby,
            // co pod każdym innym akcentowym przyciskiem w aplikacji.
            Image(systemName: MenuConstans.Assistant.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 44, height: 44)
                .scSoftSurface(Circle())
        }
        .buttonStyle(PlanPressStyle())
        .accessibilityLabel("Zaplanuj z asystentem")
    }

    // MARK: - Oś

    private var timeline: some View {
        let list = rows

        return VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.id) { index, row in
                rowView(row, isLast: !showsAddRow && index == list.count - 1)
                    .transition(Self.rowTransition)
            }

            if showsAddRow {
                PlanTimelineAddRow(slots: extraSlots, onPick: onPickExtraSlot)
                    .transition(Self.rowTransition)
            }
        }
        .background(alignment: .topLeading) { railLine }
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: fingerprint)
    }

    /// Wiersz wchodzi i wychodzi tak, jak leży na osi: od góry, z zanikiem.
    /// Bez `move` sam `opacity` zostawiał po usuniętym posiłku dziurę, która
    /// zamykała się dopiero po animacji.
    private static var rowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading))
        )
    }

    /// Pionowa linia szyny — pod treścią, od pierwszej kropki do ostatniej.
    private var railLine: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(width: 1)

            Spacer(minLength: 0)
        }
        .padding(.leading, PlanTimelineMetrics.rail / 2 - 0.5)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func rowView(_ row: Row, isLast: Bool) -> some View {
        if row.dishes.isEmpty {
            PlanTimelineEmptyRow(
                slot: row.slot,
                isLast: isLast,
                isEditable: isEditable,
                onAdd: { onAddMeal(row.slot) }
            )
        } else {
            PlanTimelineRow(
                slot: row.slot,
                dishes: row.dishes,
                members: members,
                showsWhoBadge: profile == .household && members.count > 1,
                isLast: isLast,
                isEditable: isEditable,
                onTapMeal: { onTapMeal(row.slot, $0) },
                onEditMeal: { onEditMeal(row.slot, $0) },
                onAddVariant: { onAddMeal(row.slot) },
                onRemoveMeal: { onRemoveMeal(row.slot, $0) }
            )
        }
    }

    // MARK: - Podsumowanie dnia

    /// „2 z 3 posiłków”, a przy dniu z osobnymi daniami domowników
    /// „3 z 3 posiłków · 5 dań”.
    ///
    /// Kalorii tu już nie ma — tę samą liczbę pokazuje pigułka „Cel dnia" nad
    /// menu, i to obok celu, więc podtytuł powtarzał ją bez kontekstu.
    /// Liczba dań zostaje: mówi coś, czego pigułka nie mówi — że w slotach
    /// stoi więcej niż jedno danie na porę.
    private var summaryText: String {
        let list = rows
        let filled = list.filter { !$0.dishes.isEmpty }.count
        let total = list.count
        let dishes = list.reduce(0) { $0 + $1.dishes.count }

        // Po „z <liczba>” polski rzeczownik stoi w dopełniaczu bez względu na
        // liczbę — „1 z 3 posiłków”, „2 z 4 posiłków”.
        var text = "\(filled) z \(total) posiłków"

        if dishes > filled {
            text += " · \(dishes) \(PolishPlural.form(dishes, one: "danie", few: "dania", many: "dań"))"
        }
        return text
    }

    /// Ilu domowników dzieli się porcjami, albo `nil`, dopóki `SessionStore`
    /// nie dowiezie listy. Pusta lista przed wczytaniem to brak odpowiedzi,
    /// a nie dom jednoosobowy.
    private var knownHouseholdMemberCount: Int? {
        guard sessionStore.didLoadHouseholdMembers else { return nil }
        return max(1, sessionStore.householdMembers.count)
    }

    private static let longDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEEE"
        return f
    }()
}

// MARK: - Miary osi

/// Jedne wymiary dla wszystkich wierszy osi — szyna i wiersz muszą stać
/// w jednym rytmie, a rozjeżdżały się już przy dwóch kopiach tych liczb.
enum PlanTimelineMetrics {
    /// Szerokość kolumny szyny (kropka + godzina).
    static let rail: CGFloat = 46
    /// Odstęp między szyną a treścią wiersza.
    static let gutter: CGFloat = 12
    /// Odstęp nad wierszem.
    static let rowTop: CGFloat = 12
    /// Odstęp pod treścią wiersza, nad hairline'em.
    static let rowBottom: CGFloat = 12
    /// Zdjęcie dania domu i zdjęcie dania domownika.
    static let photo: CGFloat = 72
    static let photoAlt: CGFloat = 56
}

// MARK: - Znacznik na szynie

/// Kropka pory na linii i godzina pod nią.
///
/// Oba elementy niosą własne tło w kolorze strony: linia biegnie ciągiem pod
/// spodem, więc bez maski przecinałaby i pustą kropkę, i cyfry godziny.
struct PlanRailMark: View {
    let time: String?
    let color: Color
    /// Pusta kropka — pora bez posiłku.
    var hollow: Bool = false
    /// Kreskowany obrys — wiersz „Dodaj posiłek”, czyli pora, której jeszcze
    /// nie ma w dniu.
    var dashed: Bool = false
    /// Godzina przygaszona, gdy w porze nic nie stoi.
    var muted: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // 3, nie 6: pierścień maski (`.padding(3)`) wchodzi tu w układ, a w
        // makiecie jest cieniem, który układu nie rusza. Odstęp schodzi o tyle,
        // ile pierścień dokłada — godzina siada tam, gdzie w makiecie.
        VStack(spacing: 3) {
            dot
                .frame(width: 9, height: 9)
                .padding(3)
                .background(Circle().fill(Color.scPageBase(scheme)))

            if let time {
                Text(time)
                    .scFont(12.5, weight: .bold, relativeTo: .caption)
                    .tracking(-0.1)
                    .monospacedDigit()
                    .foregroundStyle(muted ? Color.scFaint(scheme) : Color.scLabel(scheme))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.scPageBase(scheme))
                    )
            }
        }
        // Z tego samego powodu 2, a nie makietowe 5: pierścień maski dokłada
        // 3 pt nad kropką. Środek kropki ma stać na wysokości środka eyebrow
        // w wierszu obok — to jedyna rzecz, którą szyna i treść mają wspólną.
        .padding(.top, 2)
        .frame(width: PlanTimelineMetrics.rail)
    }

    @ViewBuilder
    private var dot: some View {
        if hollow {
            Circle()
                .strokeBorder(
                    color,
                    style: dashed
                        ? StrokeStyle(lineWidth: 1.5, dash: [1.8, 1.8])
                        : StrokeStyle(lineWidth: 1.5)
                )
        } else {
            Circle().fill(color)
        }
    }
}

// MARK: - Wiersz z posiłkiem

/// Jedna pora dnia z tym, co w niej stoi: danie domu, a pod nim ewentualne
/// dania domowników.
struct PlanTimelineRow: View {
    let slot: MealSlot
    let dishes: [PlanMeal]
    let members: [HouseholdMemberSnapshot]
    let showsWhoBadge: Bool
    let isLast: Bool
    let isEditable: Bool
    let onTapMeal: (PlanMeal) -> Void
    let onEditMeal: (PlanMeal) -> Void
    let onAddVariant: () -> Void
    let onRemoveMeal: (PlanMeal) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.sessionStore) private var sessionStore

    var body: some View {
        HStack(alignment: .top, spacing: PlanTimelineMetrics.gutter) {
            PlanRailMark(
                time: sessionStore.mealSlotSchedule.time(for: slot),
                color: slot.cozyAccent
            )

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(dishes.enumerated()), id: \.element.id) { index, meal in
                        dishButton(meal, isAlternative: index > 0)
                    }

                    if showsVariantAction { variantButton }
                }
                .padding(.bottom, PlanTimelineMetrics.rowBottom)

                if !isLast {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                }
            }
        }
        .padding(.top, PlanTimelineMetrics.rowTop)
    }

    /// Dołożenie osobnego dania dla domownika — wprost w wierszu pory.
    ///
    /// Wcześniej ta akcja żyła wyłącznie w menu z przytrzymania, czyli
    /// praktycznie nie istniała: nikt nie przytrzymuje wiersza, żeby sprawdzić,
    /// czy coś się pod nim kryje. A to jedyna droga do dnia z makiety D3, gdzie
    /// pod daniem domu stoi danie Zosi — bez niej „dla kogo” dawało się ustawić
    /// tylko przy pustej porze.
    ///
    /// Znika, gdy w porze stoi już tyle dań, ilu jest domowników: nie ma wtedy
    /// dla kogo dokładać kolejnego, a wiersz nie musi tego proponować sześć
    /// razy dziennie.
    private var showsVariantAction: Bool {
        showsWhoBadge && isEditable && dishes.count < members.count
    }

    private var variantButton: some View {
        Button(action: onAddVariant) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 12, weight: .bold))

                Text("Osobne danie dla kogoś")
                    .scFont(13, weight: .semibold, relativeTo: .footnote)
                    .tracking(-0.2)
            }
            .foregroundStyle(SCPalette.terracotta)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Wiersz rysuje się na 30 pt, żeby nie rozpychać pory dnia, ale
            // palec dostaje 44.
            .scTapHeight(drawn: 30)
        }
        .buttonStyle(PlanPressStyle())
        .accessibilityLabel("Dodaj osobne danie dla domownika, \(slot.title)")
    }

    /// Menu kontekstowe dostaje TYLKO dzień edytowalny.
    ///
    /// Wcześniej `.contextMenu` wisiało zawsze, a pusty warunek w środku
    /// zostawiał na dniu z przeszłości przytrzymanie, które unosiło wiersz
    /// i pokazywało menu bez jednej pozycji.
    @ViewBuilder
    private func dishButton(_ meal: PlanMeal, isAlternative: Bool) -> some View {
        if isEditable {
            dishTapTarget(meal, isAlternative: isAlternative)
                .contextMenu { menuItems(for: meal) }
        } else {
            dishTapTarget(meal, isAlternative: isAlternative)
        }
    }

    private func dishTapTarget(_ meal: PlanMeal, isAlternative: Bool) -> some View {
        Button {
            onTapMeal(meal)
        } label: {
            PlanTimelineDish(
                slot: slot,
                meal: meal,
                members: members,
                audience: audience(for: meal),
                showsWhoBadge: showsWhoBadge,
                isAlternative: isAlternative
            )
        }
        .buttonStyle(PlanPressStyle())
    }

    @ViewBuilder
    private func menuItems(for meal: PlanMeal) -> some View {
        Button { onEditMeal(meal) } label: {
            Label("Zamień przepis lub osoby", systemImage: "arrow.2.squarepath")
        }
        Button { onAddVariant() } label: {
            Label("Dodaj danie dla kogoś innego", systemImage: "person.badge.plus")
        }
        Button(role: .destructive) { onRemoveMeal(meal) } label: {
            Label("Usuń posiłek", systemImage: "trash")
        }
    }

    /// Kogo naprawdę karmi to danie. Wspólny obiad w slocie, w którym stoją
    /// też dania osobiste, obejmuje tylko tych, których te dania nie nazwały.
    private func audience(for meal: PlanMeal) -> [String] {
        dishes.effectiveAudience(for: meal, allMemberIds: members.map(\.id))
    }
}

// MARK: - Danie

/// Treść jednego dania: eyebrow, tytuł, „min · kcal” i zdjęcie po prawej.
///
/// Pierwsze danie wiersza mówi porą dnia w jej kolorze i ma zdjęcie 72 pt;
/// każde następne to danie domownika — imię w jego kolorze i zdjęcie 56 pt,
/// żeby od pierwszego spojrzenia było wiadomo, które danie jest wyjątkiem od
/// którego.
struct PlanTimelineDish: View {
    let slot: MealSlot
    let meal: PlanMeal
    let members: [HouseholdMemberSnapshot]
    let audience: [String]
    let showsWhoBadge: Bool
    let isAlternative: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.sessionStore) private var sessionStore

    private var photoSize: CGFloat {
        isAlternative ? PlanTimelineMetrics.photoAlt : PlanTimelineMetrics.photo
    }

    /// Domownicy nazwani przez to danie, w kolejności składu gospodarstwa.
    private var named: [HouseholdMemberSnapshot] {
        members.filter { audience.contains($0.id) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                    .padding(.top, 2)

                Text(meal.recipe.name)
                    .scFont(isAlternative ? 15.5 : 17, weight: .semibold, relativeTo: .body)
                    .tracking(-0.35)
                    .foregroundStyle(Color.scLabel(scheme))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .padding(.top, 4)

                Text(metaText)
                    .scFont(12.5, weight: .regular, relativeTo: .caption)
                    .tracking(-0.1)
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            photo
        }
        .contentShape(Rectangle())
        // Bez `.accessibilityElement(children: .combine)`: danie siedzi
        // w `Button`, a scalanie dzieci gasi cechę „przycisk” i VoiceOver
        // przestaje mówić, że w wiersz da się stuknąć.
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Eyebrow

    @ViewBuilder
    private var eyebrow: some View {
        if isAlternative, !named.isEmpty {
            eyebrowText(
                named.map { HouseholdMemberStyle.shortName($0.displayName) }
                    .joined(separator: " · "),
                color: HouseholdMemberStyle.color(for: named[0])
            )
        } else {
            eyebrowText(slot.title, color: slot.cozyAccent)
        }
    }

    private func eyebrowText(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .scFont(11, weight: .bold, relativeTo: .caption2)
            .tracking(1)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    // MARK: Zdjęcie

    private var photo: some View {
        thumbnail
            .frame(width: photoSize, height: photoSize)
            .clipShape(
                RoundedRectangle(cornerRadius: isAlternative ? 14 : 16, style: .continuous)
            )
            .overlay(alignment: .bottomTrailing) {
                if showsWhoBadge {
                    PlanWhoBadge(participantIds: audience, members: members, size: 18)
                        .padding(2)
                        .background(Circle().fill(Color.scPageBase(scheme)))
                        // Odznaka wychodzi poza róg zdjęcia, jak w makiecie —
                        // 4 pt mieści się w marginesie strony, więc nic się
                        // nie obcina.
                        .offset(x: 4, y: 4)
                }
            }
    }

    /// Zdjęcie albo kafel zastępczy — jedno ALBO drugie, nie warstwy.
    ///
    /// Wcześniej stały w `ZStack`, a zdjęcie dochodziło nad kaflem z zanikiem
    /// sterowanym `onAppear`. Zanik zaczynał się od `opacity(0)`, więc każda
    /// klatka, w której `onAppear` nie doszło, zostawiała zdjęcie NIEWIDOCZNE
    /// nad poprawnie narysowanym kaflem — czyli wyglądała jak przepis bez
    /// zdjęcia. Ćwierć sekundy zaniku nie jest warta takiego ryzyka; to jest
    /// dokładnie ten sam kształt, którym rysuje miniatury reszta aplikacji
    /// (`RecipeCarouselCard`).
    @ViewBuilder
    private var thumbnail: some View {
        if let url = meal.recipe.imageURL {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    gradientThumb
                }
            }
        } else {
            gradientThumb
        }
    }

    /// Kafel zastępczy z tokenów projektu — gradient akcentu pory, ukośna
    /// kreska i ikona posiłku.
    private var gradientThumb: some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(black: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PlanDiagonalHatch(color: .white.opacity(0.07))

            Image(systemName: slot.icon)
                .font(.system(size: isAlternative ? 20 : 24, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: Tekst

    /// „12 min · 393 kcal”, a gdy ktoś ustawił stepperem inną liczbę porcji niż
    /// wynika z audytorium — „12 min · 393 kcal · 3 porcje”.
    private var metaText: String {
        var parts = [
            "\(meal.recipe.prepTimeMinutes) min",
            "\(perPersonKcal) kcal"
        ]
        if let servings = customServingsText {
            parts.append(servings)
        }
        return parts.joined(separator: " · ")
    }

    private var perPersonKcal: Int {
        Int(
            meal.nutritionPerPerson(knownHouseholdMemberCount: knownHouseholdMemberCount)
                .kcal
                .rounded()
        )
    }

    /// „3 porcje”, ale tylko gdy użytkownik świadomie odszedł od reguły auto.
    private var customServingsText: String? {
        guard let count = knownHouseholdMemberCount,
              meal.isCustomServings(householdMemberCount: count) else { return nil }
        return PolishPlural.servings(meal.effectiveServings(householdMemberCount: count))
    }

    private var knownHouseholdMemberCount: Int? {
        guard sessionStore.didLoadHouseholdMembers else { return nil }
        return max(1, sessionStore.householdMembers.count)
    }

    private var accessibilityText: String {
        var base = "\(slot.title): \(meal.recipe.name), \(meal.recipe.prepTimeMinutes) minut, \(perPersonKcal) kalorii"
        if let servings = customServingsText {
            base += ", \(servings)"
        }
        guard showsWhoBadge else { return base }
        guard !named.isEmpty else { return base + ", wspólne" }
        return base + ", dla: " + named
            .map { HouseholdMemberStyle.shortName($0.displayName) }
            .joined(separator: ", ")
    }
}

// MARK: - Pusta pora

/// Ten sam rytm co wiersz z posiłkiem, jedna cicha akcja ręczna po prawej.
/// Asystent w tym wierszu nie siedzi — jest raz, w nagłówku dnia.
struct PlanTimelineEmptyRow: View {
    let slot: MealSlot
    let isLast: Bool
    let isEditable: Bool
    let onAdd: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.sessionStore) private var sessionStore

    var body: some View {
        HStack(alignment: .top, spacing: PlanTimelineMetrics.gutter) {
            PlanRailMark(
                time: sessionStore.mealSlotSchedule.time(for: slot),
                color: slot.cozyAccent,
                hollow: true,
                muted: true
            )

            VStack(alignment: .leading, spacing: 0) {
                tappableContent
                    .padding(.bottom, PlanTimelineMetrics.rowBottom)

                if !isLast {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                }
            }
        }
        .padding(.top, PlanTimelineMetrics.rowTop)
    }

    /// Celem dotyku jest CAŁY wiersz, a nie sam napis po prawej.
    ///
    /// „Wybierz przepis” to jedyna akcja tej pory dnia, więc trafienie w nią
    /// nie może zależeć od tego, czy palec zmieści się w 100-punktowym napisie
    /// przy prawej krawędzi. Napis zostaje tym, czym jest w makiecie — podpisem
    /// tego, co się stanie.
    @ViewBuilder
    private var tappableContent: some View {
        if isEditable {
            Button(action: onAdd) { content }
                .buttonStyle(PlanPressStyle())
                .accessibilityLabel("\(slot.title): nic nie zaplanowano. Stuknij, aby wybrać przepis.")
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(slot.title): nic nie zaplanowano, dzień nieedytowalny")
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(slot.title.uppercased())
                    .scFont(11, weight: .bold, relativeTo: .caption2)
                    .tracking(1)
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text("Nic nie zaplanowano")
                    .scFont(15, weight: .medium, relativeTo: .subheadline)
                    .tracking(-0.3)
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 4)
            }

            Spacer(minLength: 8)

            if isEditable {
                HStack(spacing: 3) {
                    Text("Wybierz przepis")
                        .scFont(14, weight: .bold, relativeTo: .footnote)
                        .tracking(-0.1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(SCPalette.terracotta)
                .padding(.leading, 12)
                .padding(.trailing, 2)
                .fixedSize()
            }
        }
        // 48 pt to wysokość celu dotyku całego wiersza — tekst zajmuje ~36 pt.
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

// MARK: - Dodaj posiłek

/// Ręczne dodanie pory, której dzień jeszcze nie pokazuje — na końcu osi.
///
/// Wybór pory to `Menu` zaczepione o sam wiersz, a nie `confirmationDialog`.
/// Ten drugi, wystawiany z ekranu planu, rysował się przy GÓRNEJ krawędzi
/// zamiast wyjechać od dołu — ekran ignoruje górny safe area
/// (`ignoresSafeArea(.container, edges: .top)`), żeby tytuł siadł 78 pt od
/// krawędzi, i systemowa plansza liczyła swoje położenie z tej samej,
/// przesuniętej geometrii. `Menu` zaczepia się o widok, z którego wyszło,
/// więc nie ma czego liczyć — a przy okazji od razu widać, co się rozwija.
struct PlanTimelineAddRow: View {
    /// Sloty do wyboru; z nich składa się podpis wiersza.
    let slots: [MealSlot]
    let onPick: (MealSlot) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu {
            ForEach(slots) { slot in
                Button {
                    onPick(slot)
                } label: {
                    Label(slot.title, systemImage: slot.icon)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: PlanTimelineMetrics.gutter) {
                PlanRailMark(
                    time: nil,
                    color: Color.scFaint(scheme),
                    hollow: true,
                    dashed: true
                )
                .padding(.top, 8)

                content
            }
            .padding(.top, PlanTimelineMetrics.rowTop)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dodaj posiłek: \(subtitle)")
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SCPalette.terracotta)
                .frame(width: 30, height: 30)
                .scSoftSurface(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text("Dodaj posiłek")
                    .scFont(14.5, weight: .semibold, relativeTo: .footnote)
                    .tracking(-0.3)
                    .foregroundStyle(Color.scLabel(scheme))

                Text(subtitle)
                    .scFont(12, weight: .regular, relativeTo: .caption)
                    .foregroundStyle(Color.scFaint(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)
        }
        // Kółko z plusem ma 30 pt; z 12 pt odstępu nad wierszem wychodziło
        // 42 — dwa punkty poniżej celu dotyku.
        .frame(minHeight: 44)
    }

    /// „II śniadanie, podwieczorek lub przekąska” — dokładnie te pory, które da
    /// się jeszcze dołożyć. Lista bierze się z ustawień gospodarstwa, więc
    /// podpis nigdy nie obiecuje slotu, którego nie ma w wyborze.
    private var subtitle: String {
        let names = slots.map(Self.inSentence)
        guard let last = names.last else { return "Dodatkowa pora dnia" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " lub " + last
    }

    /// Nazwa pory w środku zdania. „II śniadanie” zostaje z wielkimi „II”,
    /// bo to skrót liczebnika, a nie początek zdania.
    private static func inSentence(_ slot: MealSlot) -> String {
        slot.title.hasPrefix("II ") ? slot.title : slot.title.lowercased()
    }
}

// MARK: - Reakcja na dotyk

/// Lekkie ściśnięcie pod palcem — jedyny sygnał, że wiersz bez karty i bez
/// obwódki jest klikalny. Sprężyna jest krótka, bo reakcja na dotyk ma
/// wyprzedzać ruch palca, a nie iść za nim.
struct PlanPressStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

// MARK: - Ukośna kreska 45°

/// `repeating-linear-gradient(45deg, rgba(255,255,255,0.07) 0 2.5px, transparent 2.5px 11px)`
/// z tokenów projektu — tekstura pod daniem bez zdjęcia.
struct PlanDiagonalHatch: View {
    let color: Color
    var lineWidth: CGFloat = 2.5
    var spacing: CGFloat = 11

    var body: some View {
        Canvas { context, size in
            let diagonal = size.width + size.height
            var x: CGFloat = -size.height
            while x < diagonal {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
