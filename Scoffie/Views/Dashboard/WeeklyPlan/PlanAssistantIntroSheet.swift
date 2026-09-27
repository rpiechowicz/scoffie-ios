import SwiftUI

// „Ułożę Ci ten tydzień” — arkusz zachęty asystenta, otwierany pigułką „Ułóż”
// w nagłówku Planu.
//
// Od 27.09.2026 na klockach reszty aplikacji (Rafał: „dopracuj, żeby był
// zgodny z resztą”): nagłówek `EditorialSheetHeader` z JEDNYM zdaniem, punkty
// jako etykiety `SCTag` (jak strony wprowadzenia Asystenta) zamiast trzech
// osobnych kart z opisami, podgląd tygodnia w stroju listy zestawu ze strony
// „Wszystko pasuje?” (`ProposalRecap`: wiersz na dzień z krążkami zdjęć)
// i stopka `scSheetFooter` z JEDNYM przyciskiem — „Wolę ułożyć sam” dublowało
// krzyżyk. Dania podglądu to prawdziwe przepisy z katalogu odsiane dietą
// i alergenami z Ustawień (`AssistantIntroDish.week`), nie losowe z całości —
// podgląd pod etykietą „Alergeny” nie może pokazać dania z alergenem.
// Tego samego dnia runda 2 („dopracuj, żeby było bardziej wow”): tydzień
// SKŁADA SIĘ na oczach i pokazuje zamianę dania (`PlanAssistantWeekPreview`).
//
// Każda etykieta sprawdzona w backendzie 27.09.2026 (zmieniasz planer —
// popraw etykietę):
// - dieta, alergeny i wykluczenia KAŻDEGO jedzącego to filtry twarde planera
//   (`hardFilterReason` w `meal-plan-engine.ts`), a przy zapisie jeszcze
//   `collectPlanViolations`;
// - cel kalorii i makro osoby — koszt dnia osoby wobec jej celu
//   (`eaterDayCost`), porcje dobierane per osoba (`portionFor`);
// - bez powtórek — `WEIGHTS.repeat` w `weekRelationCost` za każde powtórzenie
//   w tygodniu (`REPEAT_FORCED` dopiero, gdy pula nie starcza).
// Zdjęte obietnice: „w kilka sekund” (tura trwa 25–240 s), „w tygodniu do
// 30 minut, w weekend dłużej” (`maxPrepTimeMinutes` telefon wysyła jako
// `null`), „sezonowe składniki” (planer nie zna sezonu), „ulubione wracają”
// (waga ulubionych to −0,05 — prawie nic).
struct PlanAssistantIntroSheet: View {
    let members: [HouseholdMemberSnapshot]
    /// Dni widocznego tygodnia — podpisy wierszy podglądu.
    let days: [Date]
    /// Pory, które dom planuje (Ustawienia → „Posiłki w planie”) — z nich
    /// podgląd bierze dania.
    let slots: [MealSlot]
    /// Czy w widocznym tygodniu stoi już cokolwiek. Zmienia obietnicę, a nie
    /// samą planszę: „ułożę” brzmi jak groźba nadpisania komuś, kto ma już
    /// pół tygodnia rozpisane ręcznie.
    var weekIsEmpty: Bool = true
    let onOpenAssistant: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore

    /// Dania podglądu — dobierane RAZ, gdy katalog jest pod ręką; nie tasują
    /// się przy przerysowaniu.
    @State private var week: [[AssistantIntroDish]] = []
    /// Dania do pokazu zamiany — spoza tygodnia, z tej samej puli.
    @State private var spares: [AssistantIntroDish] = []
    @State private var hasAppeared = false

    private var isSolo: Bool { members.count <= 1 }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                EditorialSheetHeader(
                    eyebrow: "Asystent",
                    title: weekIsEmpty ? "Ułożę Ci ten tydzień" : "Uzupełnię ten tydzień",
                    icon: MenuConstans.Assistant.icon,
                    subtitle: subtitle,
                    onClose: { dismiss() }
                )
                .padding(.horizontal, SCPageMetrics.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        AllergenChipFlow(spacing: 8) {
                            ForEach(Array(tags.enumerated()), id: \.element.id) { index, tag in
                                SCTag(title: tag.title, icon: tag.icon, accent: tag.accent)
                                    .scReveal(hasAppeared, order: index)
                            }
                        }
                        .accessibilityElement(children: .combine)

                        if !week.isEmpty {
                            PlanAssistantWeekPreview(days: days, week: week, spares: spares)
                                .scReveal(hasAppeared, order: tags.count)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SCPageMetrics.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .animation(.smooth(duration: 0.35), value: week.isEmpty)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .scScrollEdgeFade()
                .scSheetFooter {
                    EditorialPrimaryActionButton(
                        title: weekIsEmpty ? "Ułóż z Asystentem" : "Uzupełnij z Asystentem",
                        icon: MenuConstans.Assistant.icon
                    ) {
                        dismiss()
                        onOpenAssistant()
                    }
                }
            }
        }
        .task {
            // Klatka oddechu — w `onAppear` stan zmieniał się w klatce
            // wstawienia i kaskada nie miała czego złapać (`SCReveal`).
            try? await Task.sleep(for: .milliseconds(80))
            hasAppeared = true
        }
        .task { await recipeCatalogStore.loadIfNeeded() }
        .onChange(of: recipeCatalogStore.recipes.count, initial: true) { _, _ in
            guard week.isEmpty else { return }
            let recipes = recipeCatalogStore.recipes
            let picked = AssistantIntroDish.week(from: recipes, slots: slots)
            guard let first = picked.first, let slot = PlanAssistantWeekPreview.mainSlot(in: first) else { return }
            // Zapas PRZED tygodniem: podgląd wchodzi do drzewa z kompletem.
            spares = AssistantIntroDish.spares(
                from: recipes,
                slot: slot,
                excluding: Set(picked.flatMap { $0.map(\.id) })
            )
            week = picked
        }
    }

    // MARK: - Treść

    /// Jedno zdanie, bez obietnic, których arkusz nie dotrzyma: bez liczby
    /// dni (w niedzielę z tygodnia zostaje jeden) i bez „nie ruszę tego, co
    /// stoi” — arkusz nie wie, co asystent zrobi z zaplanowanym dniem.
    private var subtitle: String {
        guard weekIsEmpty else {
            return "Powiedz, czego brakuje, a dopiszę resztę tygodnia."
        }
        return isSolo
            ? "Cały tydzień posiłków, a każde danie możesz potem zamienić."
            : "Cały tydzień posiłków dla domu, a każde danie możesz potem zamienić."
    }

    /// Krótkie, żeby stały w JEDNYM wierszu (jak etykiety wprowadzenia
    /// Asystenta) — „Twój cel kalorii” zawijało „Bez powtórek” do drugiego.
    private var tags: [AssistantIntroTag] {
        [
            AssistantIntroTag(
                title: isSolo ? "Dieta i alergeny" : "Alergeny",
                icon: "checkmark.shield.fill",
                accent: SCPalette.sage
            ),
            AssistantIntroTag(
                title: isSolo ? "Twój cel" : "Cel każdego",
                icon: "flame.fill",
                accent: SCPalette.terracotta
            ),
            AssistantIntroTag(
                title: "Bez powtórek",
                icon: "arrow.triangle.2.circlepath",
                accent: SCPalette.indigo
            ),
        ]
    }
}

// MARK: - Podgląd tygodnia

/// „Tak może wyglądać” — siedem dni w stroju listy zestawu ze strony
/// „Wszystko pasuje?” (`ProposalRecap` w `AssistantCards.swift`): karta
/// `scTileBg` + `scTileStroke`, w wierszu do trzech nałożonych krążków zdjęć,
/// dzień z porą i nazwa dania z przodu. Ciaśniej niż tam (miniatura 42,
/// nazwa w jednej linii): siedem dni mieści się nad stopką bez przewijania.
///
/// Ruch (runda 2, „bardziej wow”) opowiada, co zrobi asystent, językiem
/// reszty aplikacji:
/// 1. SKŁADANIE — karta wchodzi z pustymi wierszami (szkielet: krążki i paski
///    w kolorze obwódki), a dni wypełniają się po kolei: krążki wskakują
///    sprężyną jeden po drugim, nazwa dania PISZE SIĘ (`SCTypedText`), na końcu
///    wiersza szałwiowy ptaszek. Licznik posiłków w nagłówku roluje, a znak
///    Asystenta obok etykiety „myśli” (`SCLivingMark`, nastrój `thinking`)
///    i podskakuje, gdy tydzień stoi.
/// 2. ZAMIANA — co kilka sekund jeden dzień podświetla się terakotą, ptaszek
///    przechodzi w kręcące się strzałki, a danie przenika w inne z zapasu
///    (zdjęcie, nazwa roluje jak w Kalendarzu, `SCMotion.textRoll`) — to jest
///    obietnica z podtytułu: „każde danie możesz potem zamienić”.
/// Przy „Ogranicz ruch” tydzień stoi od razu gotowy, bez pokazu zamiany.
private struct PlanAssistantWeekPreview: View {
    let days: [Date]
    let week: [[AssistantIntroDish]]
    let spares: [AssistantIntroDish]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Ile dni już „ułożonych”.
    @State private var built = 0
    /// Dania po pokazowej zamianie: [numer dnia: danie].
    @State private var swapped: [Int: AssistantIntroDish] = [:]
    /// Dzień, w którym właśnie trwa zamiana.
    @State private var swapping: Int?
    @State private var cheer = 0

    private static let thumb: CGFloat = 42
    private static let small: CGFloat = 28

    /// Pierwszy dzień rusza, gdy karta jest w połowie wejścia (`scReveal`).
    private static let firstRow: Double = 0.45
    private static let rowStep: Double = 0.22
    /// Nazwa dania pisze się chwilę po pierwszym krążku.
    private static let typingLag: Double = 0.12
    private static let typingRate: Double = 80
    /// Dni do zamiany — nie po kolei, żeby oko nie przewidziało następnego.
    private static let swapOrder = [3, 0, 5, 2, 6, 1, 4]

    /// Nazwę w wierszu niesie obiad (albo pierwsza pora, gdy domu obiad nie
    /// dotyczy) — jego zdjęcie stoi z przodu, a pora jest w podpisie.
    static func mainSlot(in dishes: [AssistantIntroDish]) -> MealSlot? {
        (dishes.first { $0.slot == .lunch } ?? dishes.first)?.slot
    }

    private struct Row: Identifiable {
        let id: Int
        let label: String
        let main: AssistantIntroDish
        let others: [AssistantIntroDish]
        /// Wszystkie dania dnia — do licznika posiłków.
        let count: Int
    }

    private var rows: [Row] {
        zip(days.prefix(7), week).enumerated().compactMap { index, pair in
            let (day, dishes) = pair
            guard let slot = Self.mainSlot(in: dishes),
                  let original = dishes.first(where: { $0.slot == slot }) else { return nil }
            let main = swapped[index] ?? original
            return Row(
                id: index,
                label: "\(Self.dayFormatter.string(from: day).capitalized) · \(slot.lowercaseName)",
                main: main,
                others: Array(dishes.filter { $0.id != original.id }.prefix(2)),
                count: dishes.count
            )
        }
    }

    private var isBuilding: Bool { built < week.count }

    private var placedMeals: Int {
        rows.prefix(built).reduce(0) { $0 + $1.count }
    }

    var body: some View {
        let rows = self.rows

        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

            ForEach(rows) { row in
                VStack(spacing: 0) {
                    if row.id > 0 {
                        Rectangle()
                            .fill(Color.scTileStroke(scheme))
                            .frame(height: 1)
                            .padding(.leading, 16 + Self.thumb + 12)
                            .padding(.trailing, 16)
                    }
                    rowView(row, isBuilt: row.id < built, isSwapping: swapping == row.id)
                }
            }
        }
        .padding(.bottom, 6)
        .background(
            RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AssistantCardMetrics.listRadius, style: .continuous)
                .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Przykładowy tydzień: \(rows.map { "\($0.label), \($0.main.name)" }.joined(separator: "; "))")
        .task { await play() }
    }

    // MARK: - Nagłówek

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            SCLivingMark(
                mood: isBuilding ? .thinking : .idle,
                color: AssistantLook.terraFill(scheme),
                size: 16,
                cheer: cheer,
                glows: false
            )
            .frame(width: 16, height: 16)

            Text("Tak może wyglądać")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(AssistantLook.faint(scheme))
                .lineLimit(1)

            Spacer(minLength: 8)

            // Liczba rośnie razem z tygodniem — cyfry rolują.
            Text(PolishPlural.meals(placedMeals))
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AssistantLook.muted(scheme))
                .contentTransition(.numericText(value: Double(placedMeals)))
                .animation(.smooth(duration: 0.3), value: placedMeals)
        }
    }

    // MARK: - Wiersz

    private func rowView(_ row: Row, isBuilt: Bool, isSwapping: Bool) -> some View {
        HStack(spacing: 12) {
            thumbnails(row, isBuilt: isBuilt, isSwapping: isSwapping)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.label)
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(isSwapping ? AssistantLook.terra(scheme) : AssistantLook.muted(scheme))
                    .lineLimit(1)
                    .opacity(isBuilt ? 1 : 0)
                    .background(alignment: .leading) {
                        skeleton(width: 92, height: 8, visible: !isBuilt)
                    }

                // Stoi od pierwszej klatki (przezroczysty), pisze się
                // w chwili, w której wiersz się składa; zamiana roluje go.
                SCTypedText(
                    row.main.name,
                    playKey: 1,
                    rate: Self.typingRate,
                    delay: Self.firstRow + Self.rowStep * Double(row.id) + Self.typingLag
                )
                .font(.system(size: 15.5, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(AssistantLook.ink(scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) {
                    skeleton(width: 168, height: 11, visible: !isBuilt)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusIcon(isBuilt: isBuilt, isSwapping: isSwapping)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AssistantLook.terraTint(scheme))
                .opacity(isSwapping ? 1 : 0)
        )
        .padding(.horizontal, 6)
        .animation(.smooth(duration: 0.3), value: isSwapping)
        .animation(.smooth(duration: 0.3), value: isBuilt)
    }

    /// Pasek szkieletu w kolorze obwódki — miejsce, w którym zaraz stanie tekst.
    private func skeleton(width: CGFloat, height: CGFloat, visible: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(Color.scTileStroke(scheme))
            .frame(width: width, height: height)
            .opacity(visible ? 1 : 0)
    }

    /// Szałwiowy ptaszek, gdy dzień stoi; przy zamianie — kręcące się
    /// strzałki w terakocie.
    private func statusIcon(isBuilt: Bool, isSwapping: Bool) -> some View {
        Image(systemName: isSwapping ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(isSwapping ? AssistantLook.terra(scheme) : AssistantLook.sage(scheme))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.rotate, isActive: isSwapping)
            .frame(width: 22, height: 22)
            .scaleEffect(isBuilt ? 1 : 0.3)
            .opacity(isBuilt ? 1 : 0)
            // Ptaszek domyka wiersz, gdy nazwa jest już prawie napisana.
            .animation(.spring(response: 0.4, dampingFraction: 0.55).delay(isBuilt ? 0.4 : 0), value: isBuilt)
            .accessibilityHidden(true)
    }

    /// Do trzech nałożonych krążków w kwadracie miniatury (jak w
    /// `ProposalRecap`). Pod każdym szkielet — pusty krążek, na który
    /// danie wskakuje sprężyną. Przy zamianie krążek z przodu przenika
    /// w nowe danie i na chwilę rośnie.
    private func thumbnails(_ row: Row, isBuilt: Bool, isSwapping: Bool) -> some View {
        let far = Self.thumb - Self.small
        let dishes = [row.main] + row.others
        return ZStack(alignment: .topLeading) {
            ForEach(Array(dishes.enumerated()), id: \.offset) { index, dish in
                ZStack {
                    Circle().fill(Color.scTileStroke(scheme))

                    ZStack {
                        AssistantThumbnail(url: dish.imageURL, size: Self.small)
                            .clipShape(Circle())
                            .id(dish.id)
                            .transition(.opacity)
                    }
                    .scaleEffect(isBuilt ? 1 : 0.2)
                    .opacity(isBuilt ? 1 : 0)
                    .animation(
                        .spring(response: 0.42, dampingFraction: 0.6).delay(0.07 * Double(index)),
                        value: isBuilt
                    )
                }
                .frame(width: Self.small, height: Self.small)
                .overlay(Circle().strokeBorder(Color.scTileBg(scheme), lineWidth: 2))
                .scaleEffect(index == 0 && isSwapping ? 1.12 : 1)
                .offset(
                    x: index == 1 ? far : (index == 2 ? far / 2 : 0),
                    y: index == 0 ? 0 : (index == 1 ? far / 2 : far)
                )
                .zIndex(Double(-index))
            }
        }
        .frame(width: Self.thumb, height: Self.thumb, alignment: .topLeading)
    }

    // MARK: - Pokaz

    private func play() async {
        guard !reduceMotion else {
            built = week.count
            return
        }
        try? await Task.sleep(for: .seconds(Self.firstRow))
        for index in week.indices {
            if Task.isCancelled { return }
            built = index + 1
            try? await Task.sleep(for: .seconds(Self.rowStep))
        }
        // Ostatnia nazwa dopisuje się jeszcze chwilę.
        try? await Task.sleep(for: .seconds(0.45))
        if Task.isCancelled { return }
        cheer += 1

        let order = Self.swapOrder.filter { $0 < week.count }
        guard !spares.isEmpty, !order.isEmpty else { return }
        var round = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(round == 0 ? 1.4 : 2.6))
            if Task.isCancelled { return }
            let day = order[round % order.count]
            swapping = day
            try? await Task.sleep(for: .seconds(0.6))
            if Task.isCancelled { return }
            withAnimation(SCMotion.textRoll) {
                swapped[day] = spares[round % spares.count]
            }
            try? await Task.sleep(for: .seconds(0.75))
            if Task.isCancelled { return }
            swapping = nil
            round += 1
        }
    }

    /// „poniedziałek” → „Poniedziałek”.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEEE"
        return f
    }()
}

#Preview("Ułożę Ci ten tydzień") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            PlanAssistantIntroSheet(
                members: [],
                days: (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: .now) ?? .now },
                slots: MealSlot.core,
                onOpenAssistant: {}
            )
            .presentationDetents([.large])
        }
}
