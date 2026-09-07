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
struct PlanDayGoalSheet: View {
    let date: Date
    let nutrition: PlanDayNutrition
    let targets: DailyNutritionTargets
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

    init(
        date: Date,
        nutrition: PlanDayNutrition,
        targets: DailyNutritionTargets,
        maxHeight: CGFloat
    ) {
        self.date = date
        self.nutrition = nutrition
        self.targets = targets
        self.maxHeight = maxHeight
        _contentHeight = State(
            initialValue: Self.estimatedHeight(
                rows: nutrition.entries.count,
                hasMacroTargets: targets.macros != nil
            )
        )
    }

    private static let minHeight: CGFloat = 320

    /// Szacunek z rytmu układu niżej: stała góra z pierścieniami plus wiersz
    /// na posiłek. Nie musi być dokładny — ma tylko trafić w okolicę, zanim
    /// pomiar poda liczbę prawdziwą.
    private static func estimatedHeight(rows: Int, hasMacroTargets: Bool) -> CGFloat {
        let chrome: CGFloat = 320
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

            mealsRule
                .padding(.top, 22)

            mealsList
                .padding(.top, 14)

            if targets.macros == nil {
                macroHint
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Nagłówek

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cel dnia")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .tracking(-0.1)
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Ten sam krążek z krzyżykiem, co w każdym arkuszu Ustawień
            // (`EditorialSheetHeader`) — inny rozmiar albo inne tło robiłyby
            // z zamykania zagadkę zależną od tego, skąd się przyszło.
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.scChipBg(scheme)))
                    .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zamknij")
        }
    }

    /// „Poniedziałek · 3 z 3 posiłków" — ta sama para liczb, co w nagłówku
    /// dnia na osi, żeby arkusz nie opisywał innego dnia niż ekran pod nim.
    private var subtitle: String {
        let day = Self.longDayFormatter.string(from: date).capitalized
        return "\(day) · \(nutrition.filledSlots) z \(nutrition.slotCount) posiłków"
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
        let macros = targets.macros

        return [
            PlanGoalLegendRow.Row(
                id: "kcal",
                title: "Kalorie",
                color: SCMacroPalette.calories,
                value: nutrition.kcal,
                target: targets.kcal,
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
    private var macroHint: some View {
        Text("Cele makro policzymy, gdy uzupełnisz sylwetkę w Ustawieniach → Twoje dane.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.scMuted(scheme))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Posiłki

    private var mealsRule: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color.scRule(scheme))
                .frame(height: 1)

            Text("W POSIŁKACH")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.scFaint(scheme))
        }
    }

    private var mealsList: some View {
        VStack(spacing: 12) {
            ForEach(nutrition.entries) { entry in
                PlanGoalMealRow(entry: entry)
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
            // Ułamek sekundy zwłoki: arkusz musi zdążyć usiąść na swojej
            // wysokości, inaczej pierścienie odsłaniają się w trakcie wjazdu
            // i oba ruchy się zjadają.
            withAnimation(.easeOut(duration: 0.9).delay(0.12)) {
                isRevealed = true
            }
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
                    .font(.system(size: 12.5, weight: .semibold))
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
                    Text(verbatim: String(row.value))
                        .font(.system(size: 12.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(row.isOverTarget ? row.color : Color.scLabel(scheme))

                    Text(trailingText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                }
                .lineLimit(1)
                .fixedSize()
            }

            // Kreska postępu tylko tam, gdzie jest do czego mierzyć. Pusty tor
            // pod wierszem bez celu obiecywałby liczbę, której nie ma.
            if let progress = row.progress {
                GeometryReader { geo in
                    let width = geo.size.width
                    // Odsłonięcie i wartość w jednej liczbie, żeby kreska
                    // i pierścień obok jechały tą samą drogą.
                    let shown = isRevealed ? CGFloat(max(progress, 0)) : 0

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.scBarTrack(scheme))

                        Capsule()
                            .fill(row.color)
                            .frame(width: width * min(shown, 1), height: 3)

                        // Nadmiar — druga kreska po tej samej ścieżce, z cieniem
                        // pod spodem. Ten sam język, co w pierścieniu: pełne
                        // koło plus warstwa na nim. Przy zerze kapsuła o
                        // szerokości zero nie rysuje niczego, więc nie ma tu
                        // czego chować pod `if`.
                        Capsule()
                            .fill(row.color)
                            .frame(width: width * min(max(shown - 1, 0), 1), height: 3)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                    .frame(height: 3)
                }
                .frame(height: 3)
            }
        }
        .onAppear {
            // Ta sama krzywa i to samo opóźnienie, co pod pierścieniami —
            // legenda i wykres wypełniają się jednym ruchem.
            withAnimation(.easeOut(duration: 0.9).delay(0.12)) {
                isRevealed = true
            }
        }
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
        // Kolor liczby jest jedynym znakiem przekroczenia — VoiceOver musi
        // dostać to samo słowami.
        return row.isOverTarget ? base + ", cel przekroczony" : base
    }
}

// MARK: - Wiersz posiłku

/// Jeden posiłek dnia albo pusta pora — miniatura, nazwa, rozbicie makr
/// i kalorie po prawej.
struct PlanGoalMealRow: View {
    let entry: PlanDayNutrition.Entry

    @Environment(\.colorScheme) private var scheme

    private static let thumbSize: CGFloat = 38

    var body: some View {
        HStack(spacing: 10) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.slot.cozyAccent.opacity(entry.isPlanned ? 1 : 0.35))
                        .frame(width: 5, height: 5)

                    Text(title)
                        .font(.system(size: 13.5, weight: entry.isPlanned ? .semibold : .regular))
                        .tracking(-0.2)
                        .foregroundStyle(
                            entry.isPlanned ? Color.scLabel(scheme) : Color.scMuted(scheme)
                        )
                        .lineLimit(1)
                }

                if entry.isPlanned {
                    Text(macroText)
                        .font(.system(size: 11, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
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
                    .font(.system(size: 13.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))

                Text("kcal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .fixedSize()
        } else {
            Text("— kcal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize()
        }
    }
}
