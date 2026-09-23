import SwiftUI

/// „Cel dnia" — dzień planu zestawiony z osobistym celem: pierścienie, cztery
/// wiersze legendy i rozbicie na posiłki.
///
/// Źródło: canvas claude.ai → „Weekly Meals - Plan v2.html” (artboardy „pełny
/// dzień" i „tylko śniadanie"). Wchodzi się tu z pigułki nad dolnym menu
/// (`PlanDayGoalBar`) i to ona decyduje o kształcie arkusza: skoro pigułka
/// mówi jedną liczbę, arkusz ma pokazać, skąd ta liczba się wzięła — i nic
/// ponadto.
///
/// **Arkusz kończy się tam, gdzie kończy się treść.** Detent liczy się
/// z wysokości zmierzonej po ułożeniu (`onGeometryChange`), a nie z `.medium`
/// czy `.large`: dzień z trzema posiłkami zajmuje pół ekranu, dzień z sześcioma
/// — więcej, i w żadnym z nich nie ma czego wypełniać pustką do samej góry.
/// Sufit (`maxHeight`, liczony przez ekran Planu z jego własnej wysokości)
/// pilnuje, żeby najdłuższy dzień nie urósł do pełnego ekranu — wtedy lista
/// posiłków zaczyna się przewijać w środku.
///
/// **Każdy liczy swój talerz.** W domu wieloosobowym obok krzyżyka stoi
/// przełącznik osób obok krzyżyka (`PlanPersonSwitcher`): domyślnie ja, stuknięcie
/// pokazuje dania, sumę i cel domownika. Dawniej arkusz sumował wszystkie
/// dania pory — dwa różne obiady szły do jednego celu i wychodziło ~3000 kcal
/// na osobę, która zje jeden (Rafał, 23.09.2026).
struct PlanDayGoalSheet: View {
    let date: Date
    /// Czyje dni da się tu obejrzeć — w kolejności przełącznika, ja pierwszy.
    /// Jedna osoba (dom jednoosobowy) = bez przełącznika. Plan liczy
    /// zaplanowane, Kalendarz — odhaczone przez tę osobę.
    let people: [PlanDayPerson]
    /// Skład domu — kolory awatarów w przełączniku.
    let members: [HouseholdMemberSnapshot]
    /// Sufit wysokości arkusza — patrz komentarz typu.
    let maxHeight: CGFloat

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// Zmierzona wysokość treści. Zasiana szacunkiem z liczby wierszy, żeby
    /// arkusz wjeżdżał od razu na swoją wysokość — korekta po pomiarze jest
    /// wtedy kilkupunktowa i niewidoczna. Bez zasiewu arkusz wjeżdżał na
    /// wartości minimalnej i doskakiwał w górę na oczach użytkownika.
    @State private var contentHeight: CGFloat
    /// Dolny margines bezpieczny arkusza — `.height()` mierzy się od dołu
    /// ekranu, więc pasek gestu trzeba doliczyć, inaczej ostatni wiersz
    /// wchodzi pod niego.
    @State private var bottomInset: CGFloat = 0
    /// Czyj dzień jest na ekranie.
    @State private var selectedId: String

    init(
        date: Date,
        people: [PlanDayPerson],
        initialPersonId: String? = nil,
        members: [HouseholdMemberSnapshot] = [],
        maxHeight: CGFloat
    ) {
        self.date = date
        self.people = people
        self.members = members
        self.maxHeight = maxHeight
        let first = people.first(where: { $0.id == initialPersonId }) ?? people.first
        _selectedId = State(initialValue: first?.id ?? "")
        _contentHeight = State(
            initialValue: Self.estimatedHeight(
                rows: first?.nutrition.entries.count ?? 0,
                // Cel, który jeszcze nie przyszedł, nie dokłada podpowiedzi
                // o makrach (`macroHint` jest wtedy `nil`).
                hasMacroTargets: first?.targets.map { $0.macros != nil } ?? true
            )
        )
    }

    /// Osoba na ekranie. Pusta lista nie powinna się zdarzyć, ale arkusz
    /// ma się wtedy narysować jako pusty dzień, a nie wywrócić.
    private var person: PlanDayPerson {
        people.first(where: { $0.id == selectedId }) ?? people.first ?? .empty
    }

    private var nutrition: PlanDayNutrition { person.nutrition }

    private static let minHeight: CGFloat = 320

    /// Szacunek z rytmu układu niżej: stała góra z pierścieniami plus wiersz
    /// na posiłek. Nie musi być dokładny — ma tylko trafić w okolicę, zanim
    /// pomiar poda liczbę prawdziwą.
    private static func estimatedHeight(rows: Int, hasMacroTargets: Bool) -> CGFloat {
        // 337 = zmierzone ~317 + ten sam zapas ~20 pt, co wcześniej przy 320:
        // nagłówek arkusza (`EditorialSheetHeader` z eyebrow i zdaniem pod
        // spodem) urósł o ~23,5 pt, a etykieta „W posiłkach” bez kreski nad
        // nią zabiera ~7 pt mniej niż dawna kreska z napisem.
        let chrome: CGFloat = 337
        let list = CGFloat(max(rows, 1)) * 40 + CGFloat(max(rows - 1, 0)) * 12
        return chrome + list + (hasMacroTargets ? 0 : 40)
    }

    private var detentHeight: CGFloat {
        min(max(contentHeight + bottomInset, Self.minHeight), max(maxHeight, Self.minHeight))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                content
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        guard height > 0, abs(height - contentHeight) > 0.5 else { return }
                        contentHeight = height
                    }
            }
            // Dzień, który mieści się w całości, nie ma się od czego odbijać —
            // gumowe przewijanie na nieprzewijalnej treści czyta się jak
            // usterka arkusza.
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        // `ignoresSafeArea()` NA CZYTNIKU, nie na treści: `safeAreaInsets`
        // podaje to, co zostało do odjęcia w TYM miejscu układu, a treść
        // arkusza margines gestu ma już odjęty — bez tego czytnik zwracałby
        // zero i arkusz kończyłby się o pasek gestu za wysoko.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.safeAreaInsets.bottom, initial: true) { _, value in
                        bottomInset = value
                    }
            }
            .ignoresSafeArea()
        }
        .presentationDetents([.height(detentHeight)])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 22)

            goalRow
                .padding(.top, 20)

            // Etykieta sekcji jak w każdym arkuszu, bez kreski nad nią —
            // odstęp wystarcza, żeby oddzielić pierścienie od listy.
            EditorialSheetSectionLabel(title: "W posiłkach")
                // Etykieta ma wcięcie 6 pt pod karty; tu wiersze nie stoją
                // w karcie, więc równa do krawędzi, jak nagłówek i pierścienie.
                .padding(.horizontal, -6)
                .padding(.top, 24)

            mealsList
                .padding(.top, 8)

            if let hint = macroHint {
                Text(hint)
                    .scFont(12, weight: .regular, relativeTo: .caption)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Nagłówek

    /// Domyślny nagłówek arkusza: dzień w eyebrow, „Cel dnia”, a pod spodem
    /// liczba posiłków. Wcześniej własny tytuł bez eyebrow — jedyny arkusz
    /// Planu, który zaczynał się inaczej niż reszta.
    private var header: some View {
        EditorialSheetHeader(
            eyebrow: Self.longDayFormatter.string(from: date),
            title: "Cel dnia",
            subtitle: subtitle,
            onClose: { dismiss() }
        ) {
            if people.count > 1 {
                PlanPersonSwitcher(people: people, members: members, selection: $selectedId)
            }
        }
    }

    /// „3 z 3 posiłków” — pory, w których wybrana osoba ma danie. Kropki na
    /// osi dnia liczą cały dom, więc przy domownikach z osobnymi daniami ta
    /// para może się od nich różnić — arkusz mówi o talerzu jednej osoby.
    ///
    /// W Kalendarzu ta sama para liczy co innego: nie ile pór jest
    /// zaplanowanych, tylko ile już zjedzonych — bo to jest liczba, z której
    /// wzięła się suma nad listą.
    private var subtitle: String {
        let what = nutrition.countsOnlyEaten ? "zjedzone" : "posiłków"
        let count = "\(nutrition.filledSlots) z \(nutrition.slotCount) \(what)"
        // Przy kilku osobach zdanie mówi, CZYJ to dzień — awatar w kapsule
        // obok krzyżyka to za mało, żeby przeczytać to bez zgadywania.
        guard people.count > 1 else { return count }
        let whose = person.isMe ? "Twój dzień" : "Dzień: " + person.name
        return whose + " · " + count
    }

    // MARK: - Pierścienie i legenda

    private var goalRow: some View {
        HStack(alignment: .center, spacing: 18) {
            rings
            legend
        }
    }

    private var rings: some View {
        PlanGoalRings(
            rings: legendRows.map {
                PlanGoalRings.Ring(progress: $0.progress ?? 0, color: $0.color)
            }
        )
        .accessibilityHidden(true)
    }

    private var legend: some View {
        // 14, nie 11: cztery wiersze mają wypełnić wysokość wykresu obok,
        // a nie stać zbite w jego środku.
        VStack(alignment: .leading, spacing: 14) {
            ForEach(legendRows) { row in
                PlanGoalLegendRow(row: row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Kolejność wierszy jest kolejnością pierścieni: kalorie na zewnątrz,
    /// makra do środka.
    ///
    /// Kolory idą z `SCMacroPalette`, wspólnej z licznikiem Kalendarza
    /// i z paskiem pigułki.
    private var legendRows: [PlanGoalLegendRow.Row] {
        let targets = person.targets
        let macros = targets?.macros

        return [
            PlanGoalLegendRow.Row(
                id: "kcal",
                title: "Kalorie",
                color: SCMacroPalette.calories,
                value: nutrition.kcal,
                target: targets?.kcal,
                unit: "kcal"
            ),
            PlanGoalLegendRow.Row(
                id: "protein",
                title: "Białko",
                color: SCMacroPalette.protein,
                value: nutrition.protein,
                target: macros?.proteinG,
                unit: "g"
            ),
            PlanGoalLegendRow.Row(
                id: "fat",
                title: "Tłuszcze",
                color: SCMacroPalette.fat,
                value: nutrition.fat,
                target: macros?.fatG,
                unit: "g"
            ),
            PlanGoalLegendRow.Row(
                id: "carbs",
                title: "Węgle",
                color: SCMacroPalette.carbs,
                value: nutrition.carbs,
                target: macros?.carbsG,
                unit: "g"
            )
        ]
    }

    /// Cel makr da się policzyć dopiero z sylwetki — mówimy to wprost, zamiast
    /// zostawiać trzy wiersze bez prawej strony i pierścienie bez postępu.
    /// Domownik uzupełnia sylwetkę u siebie; cel, który jeszcze nie
    /// przyszedł z serwera, nie jest powodem do podpowiedzi.
    private var macroHint: String? {
        guard let targets = person.targets, targets.macros == nil else { return nil }
        return person.isMe
            ? "Cele makro policzymy, gdy uzupełnisz sylwetkę w Ustawieniach → Twoje dane."
            : "Cele makro pojawią się, gdy \(person.name) uzupełni sylwetkę."
    }

    // MARK: - Posiłki

    private var mealsList: some View {
        VStack(spacing: 12) {
            ForEach(nutrition.entries) { entry in
                PlanGoalMealRow(entry: entry, showsEatenState: nutrition.countsOnlyEaten)
            }
        }
    }

    private static let longDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEEE"
        return f
    }()
}

// MARK: - Osoba i przełącznik

/// Jedna osoba w arkuszu „Cel dnia”: jej posiłki, jej suma i jej cel.
struct PlanDayPerson: Identifiable {
    let id: String
    /// Imię do przełącznika — pierwszy wyraz, jak na chipach „Dla kogo”.
    let name: String
    /// `nil` w domu jednoosobowym.
    let member: HouseholdMemberSnapshot?
    let nutrition: PlanDayNutrition
    /// `nil`, dopóki cel domownika nie przyjdzie z serwera.
    let targets: DailyNutritionTargets?
    let isMe: Bool

    /// Pusty dzień bez celu — zastępstwo, gdyby lista osób była pusta.
    static let empty = PlanDayPerson(
        id: "",
        name: "",
        member: nil,
        nutrition: PlanDayNutrition(
            entries: [],
            total: .zero,
            filledSlots: 0,
            slotCount: 0,
            countsOnlyEaten: false
        ),
        targets: nil,
        isMe: true
    )
}

/// Przełącznik osób obok krzyżyka: kapsuła z awatarami, wybrana osoba
/// rozwija się do awatara z imieniem na tincie swojego koloru.
///
/// Runda 12 — Rafał wrócił do tego układu („1 widok mi się podobał”) po
/// próbie z zakładkami na całą szerokość, ale „dopracować trzeba”:
/// awatary 28 pt z obwódką w kolorze osoby (także niewybrane — widać, kto
/// jest do wyboru), cel dotyku całej wysokości kapsuły, imię wjeżdża
/// kryciem razem z przesunięciem tła, a nie skokiem szerokości; czyj to
/// dzień, mówi też podtytuł arkusza.
struct PlanPersonSwitcher: View {
    let people: [PlanDayPerson]
    let members: [HouseholdMemberSnapshot]
    @Binding var selection: String

    @Environment(\.colorScheme) private var scheme
    @Namespace private var selectionNS

    var body: some View {
        HStack(spacing: 1) {
            ForEach(people) { person in
                segment(person)
            }
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(Color.scChipBg(scheme)))
        .overlay(Capsule(style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: selection)
    }

    private func tint(of person: PlanDayPerson) -> Color {
        person.member.map { HouseholdMemberStyle.color(for: $0.id, in: members) } ?? SCPalette.terracotta
    }

    private func segment(_ person: PlanDayPerson) -> some View {
        let isOn = person.id == selection
        let tint = tint(of: person)

        return Button {
            // Animowana transakcja, nie samo `.animation` na kapsule: podtytuł,
            // liczby legendy i pierścienie w arkuszu też mają się przetoczyć.
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                selection = person.id
            }
        } label: {
            HStack(spacing: 5) {
                avatar(person, tint: tint, isOn: isOn)

                if isOn {
                    Text(person.name)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .padding(.leading, 2)
            .padding(.trailing, isOn ? 9 : 2)
            .frame(height: 26)
            .background {
                if isOn {
                    Capsule(style: .continuous)
                        .fill(tint.opacity(scheme == .dark ? 0.22 : 0.16))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(tint.opacity(scheme == .dark ? 0.55 : 0.45), lineWidth: 1.2)
                        )
                        .matchedGeometryEffect(id: "selection", in: selectionNS)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel(person.isMe ? "\(person.name), Ty" : person.name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func avatar(_ person: PlanDayPerson, tint: Color, isOn: Bool) -> some View {
        Group {
            if let member = person.member {
                MemberAvatar(member: member, members: members, size: 22)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(width: 22, height: 22)
            }
        }
        // Niewybrana osoba przygaszona, ale z obwódką swojego koloru —
        // kółka bez podpisu i tak mają się dać rozróżnić.
        .overlay(Circle().strokeBorder(tint.opacity(isOn ? 0 : 0.6), lineWidth: 1.2))
        .opacity(isOn ? 1 : 0.7)
    }
}

// MARK: - Pierścienie

/// Cztery pierścienie w jednym środku — kalorie na zewnątrz, makra do środka.
///
/// Pojedynczy pierścień rysuje `ActivityRing`: tor, postęp z zaokrąglonym
/// zakończeniem i poświata pod nim. Tutaj dochodzi wyłącznie układ
/// koncentryczny i odsłonięcie: wszystkie cztery jadą z zera przy wejściu
/// arkusza, w tym samym czasie co licznik w środku (`CountingNumber` liczy
/// 0,9 s). Ruch jest jeden, a nie pięć osobnych.
struct PlanGoalRings: View {
    struct Ring {
        let progress: Double
        let color: Color
    }

    let rings: [Ring]

    /// 136, nie 148: bez licznika w środku wykres nie musi już być tak duży,
    /// a te dwanaście punktów przechodzi na legendę, gdzie „1135 / 2100 kcal"
    /// stało dotąd na granicy zawijania. Przy okazji wysokość wykresu schodzi
    /// bliżej wysokości czterech wierszy legendy obok — wcześniej legenda
    /// pływała w środku wyższej kolumny.
    static let size: CGFloat = 136
    /// Grubsze niż wtedy, gdy w środku stał licznik: światło w środku nie musi
    /// już mieścić czterocyfrowej liczby, więc te punkty wracają do pierścieni,
    /// gdzie robią z wykresu obwarzanek zamiast czterech kresek.
    static let lineWidth: CGFloat = 10
    static let spacing: CGFloat = 4

    /// Odsłonięcie wykresu: pierścienie i kreski legendy jadą tą samą krzywą
    /// z tym samym opóźnieniem, żeby cały „Cel dnia" wypełniał się jednym
    /// ruchem. Opóźnienie jest po to, żeby arkusz zdążył usiąść na swojej
    /// wysokości — inaczej odsłonięcie i wjazd zjadają się nawzajem.
    static let revealAnimation: Animation = .easeOut(duration: 0.9).delay(0.12)

    @State private var isRevealed = false

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { index, ring in
                ActivityRing(
                    progress: isRevealed ? CGFloat(ring.progress) : 0,
                    lineWidth: Self.lineWidth,
                    // Ten sam kolor na obu końcach: `ActivityRing` robi z nich
                    // gradient kątowy, a rozjaśniony koniec liczy się przez
                    // `UIColor(self)` — na kolorze dynamicznym (a takie są
                    // wszystkie akcenty `SCPalette`) rozwiązuje się to
                    // wariantem spoza aktualnego motywu. Płaski pierścień jest
                    // tu i tak tym, co pokazuje makieta.
                    startColor: ring.color,
                    endColor: ring.color,
                    trackOpacity: 0.16
                )
                .padding(CGFloat(index) * (Self.lineWidth + Self.spacing))
            }
        }
        .frame(width: Self.size, height: Self.size)
        .onAppear {
            withAnimation(Self.revealAnimation) { isRevealed = true }
        }
    }
}

// MARK: - Wiersz legendy

struct PlanGoalLegendRow: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let color: Color
        let value: Int
        /// `nil` = celu nie da się policzyć (brak sylwetki w profilu).
        let target: Int?
        let unit: String

        var progress: Double? {
            guard let target, target > 0 else { return nil }
            return Double(value) / Double(target)
        }

        /// Cel przekroczony. Bez celu nie ma czego przekroczyć, więc `nil`
        /// jest tu równie dobre jak zero.
        var isOverTarget: Bool { (progress ?? 0) > 1 }

        /// O ile ponad cel, albo `nil`, gdy mieścimy się w nim.
        ///
        /// Na ekranie tej liczby nie ma. Stała chwilę jako „+15" na prawym
        /// końcu wiersza i był to trzeci element w jednej linijce obok „145"
        /// i „/ 130 g" — trzy liczby obok siebie przestawały się czytać jako
        /// cokolwiek. Nadwyżkę niesie teraz sam pasek (przygaszona baza,
        /// nadmiar w pełnej mocy) i kolor liczby. Wartość zostaje dla
        /// VoiceOver, który paska nie widzi.
        var excess: Int? {
            guard let target, value > target else { return nil }
            return value - target
        }
    }

    let row: Row

    @Environment(\.colorScheme) private var scheme
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(row.color)
                    .frame(width: 7, height: 7)

                Text(row.title)
                    .scFont(12.5, weight: .semibold, relativeTo: .caption)
                    .tracking(-0.1)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Spacer(minLength: 6)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    // Po przekroczeniu celu liczba idzie w kolor swojego
                    // makra. Czerwień byłaby tu kłamstwem — 145 g białka przy
                    // celu 130 g to nie jest błąd, tylko fakt, o którym warto
                    // wiedzieć; kolor makra mówi „to ta pozycja wyszła poza",
                    // a nie „zrobiłeś coś źle".
                    // Liczby rolują przy przełączeniu osoby i przy zmianie
                    // dnia — jak cyfry w pigułce nad menu.
                    Text(verbatim: String(row.value))
                        .scFont(12.5, weight: .bold, relativeTo: .caption)
                        .monospacedDigit()
                        .foregroundStyle(row.isOverTarget ? row.color : Color.scLabel(scheme))
                        .contentTransition(.numericText(value: Double(row.value)))

                    Text(trailingText)
                        .scFont(10.5, weight: .semibold, relativeTo: .caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .contentTransition(.numericText())
                }
                .lineLimit(1)
                .fixedSize()
            }

            // Ten sam tor, co w pigułce nad menu (`MacroProgressTrack`): szare
            // tło na to, czego brakuje, kolor na to, co jest, i jasny odcinek
            // od prawej na nadmiar ponad cel. Rysowany tylko tam,
            // gdzie jest do czego mierzyć — pusty tor pod wierszem bez celu
            // obiecywałby liczbę, której nie ma.
            //
            // Krzywa odsłonięcia idzie z `PlanGoalRings`, a nie z domyślnej
            // sprężyny toru: kreska i pierścień obok mają wypełniać się jednym
            // ruchem, a dwie podobne krzywe obok siebie widać jako dwa.
            if let progress = row.progress {
                MacroProgressTrack(
                    progress: isRevealed ? max(progress, 0) : 0,
                    color: row.color,
                    height: 3,
                    animation: PlanGoalRings.revealAnimation
                )
            }
        }
        // Bez `withAnimation` — ruch prowadzi `MacroProgressTrack` własnym
        // modyfikatorem, tą samą krzywą co pierścienie.
        .onAppear { isRevealed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var trailingText: String {
        guard let target = row.target else { return row.unit }
        return "/ \(target) \(row.unit)"
    }

    private var accessibilityLabel: String {
        guard let target = row.target else {
            return "\(row.title): \(row.value) \(row.unit)"
        }
        let base = "\(row.title): \(row.value) z \(target) \(row.unit)"
        guard let excess = row.excess else { return base }
        return base + ", \(excess) \(row.unit) ponad cel"
    }
}

// MARK: - Wiersz posiłku

/// Jeden posiłek dnia albo pusta pora — miniatura, nazwa, rozbicie makr
/// i kalorie po prawej.
struct PlanGoalMealRow: View {
    let entry: PlanDayNutrition.Entry
    /// Czy wiersz ma mówić o odhaczeniu. Włącza to Kalendarz, w którym suma
    /// nad listą liczy wyłącznie zjedzone — bez tego dwa dania po 500 kcal
    /// stałyby obok siebie identycznie, a tylko jedno z nich byłoby w sumie.
    var showsEatenState: Bool = false

    @Environment(\.colorScheme) private var scheme

    private static let thumbSize: CGFloat = 38

    /// Zaplanowane, ale jeszcze niezjedzone — tylko tam, gdzie odhaczenie
    /// w ogóle coś znaczy.
    private var isPending: Bool {
        showsEatenState && entry.isPlanned && !entry.isEaten
    }

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if showsEatenState && entry.isPlanned {
                        // Ptaszek zamiast kropki pory: w Kalendarzu pierwsze
                        // pytanie do wiersza brzmi „liczy się czy nie", a nie
                        // „która to pora" — porę niesie nazwa dania obok.
                        Image(systemName: entry.isEaten
                            ? "checkmark.circle.fill"
                            : "circle.dashed")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                entry.isEaten
                                    ? Color.scChecked(scheme)
                                    : Color.scFaint(scheme)
                            )
                            // Wiersz scala dzieci (`.combine`), więc ta
                            // etykieta wchodzi do zdania czytanego przez
                            // VoiceOver — bez niej stan odhaczenia byłby
                            // wyłącznie kolorem.
                            .accessibilityLabel(entry.isEaten ? "zjedzone" : "niezjedzone")
                    } else {
                        Circle()
                            .fill(entry.slot.cozyAccent.opacity(entry.isPlanned ? 1 : 0.35))
                            .frame(width: 5, height: 5)
                    }

                    Text(title)
                        .scFont(13.5, weight: entry.isPlanned ? .semibold : .regular, relativeTo: .footnote)
                        .tracking(-0.2)
                        .foregroundStyle(
                            entry.isPlanned && !isPending
                                ? Color.scLabel(scheme)
                                : Color.scMuted(scheme)
                        )
                        .lineLimit(1)
                }

                if entry.isPlanned {
                    Text(macroText)
                        .scFont(11, weight: .regular, relativeTo: .caption2)
                        .monospacedDigit()
                        .foregroundStyle(isPending ? Color.scFaint(scheme) : Color.scMuted(scheme))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingKcal
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard let meal = entry.meal else {
            return "\(entry.slot.title) · nic nie zaplanowano"
        }
        return meal.recipe.name
    }

    /// „B 24 · T 26 · W 8 g" — gramy podane raz, na końcu, bo wszystkie trzy
    /// są w tej samej jednostce.
    private var macroText: String {
        let protein = Int(entry.nutrition.protein.rounded())
        let fat = Int(entry.nutrition.fat.rounded())
        let carbs = Int(entry.nutrition.carbs.rounded())
        return "B \(protein) · T \(fat) · W \(carbs) g"
    }

    private var thumbnail: some View {
        Group {
            if let meal = entry.meal, let url = meal.recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: Self.thumbSize, height: Self.thumbSize)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        // Danie jeszcze niezjedzone przygasa — jest w dniu, ale nie ma go
        // w liczbie nad listą, i wiersz musi to powiedzieć bez czytania.
        .saturation(isPending ? 0.35 : 1)
        .opacity(isPending ? 0.6 : 1)
    }

    /// Ten sam kafel zastępczy, co na osi dnia: gradient akcentu pory, ukośna
    /// kreska i ikona posiłku. Pusta pora dostaje go wygaszonego — wiersz ma
    /// być czytelny jako „tu nic nie ma", a nie jako danie bez zdjęcia.
    private var placeholder: some View {
        ZStack {
            if entry.isPlanned {
                LinearGradient(
                    colors: [entry.slot.cozyTint, entry.slot.cozyTint.mix(black: 0.32)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                PlanDiagonalHatch(color: .white.opacity(0.07))
            } else {
                Color.scTileBg(scheme)
            }

            Image(systemName: entry.slot.icon)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(
                    entry.isPlanned ? Color.white.opacity(0.85) : Color.scFaint(scheme)
                )
        }
        .overlay {
            if !entry.isPlanned {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var trailingKcal: some View {
        if entry.isPlanned {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: String(Int(entry.nutrition.kcal.rounded())))
                    .scFont(13.5, weight: .bold, relativeTo: .footnote)
                    .monospacedDigit()
                    .foregroundStyle(isPending ? Color.scFaint(scheme) : Color.scLabel(scheme))

                Text("kcal")
                    .scFont(10, weight: .semibold, relativeTo: .caption2)
                    .foregroundStyle(isPending ? Color.scFaint(scheme) : Color.scMuted(scheme))
            }
            .fixedSize()
        } else {
            Text("— kcal")
                .scFont(11, weight: .semibold, relativeTo: .caption2)
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize()
        }
    }
}
