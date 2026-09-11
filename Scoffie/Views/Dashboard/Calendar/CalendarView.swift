import SwiftUI

struct CalendarView: View {
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.colorScheme) private var scheme

    // Cel dnia mieszka w Ustawieniach → „Dieta i alergeny" i w profilu; tu
    // czytamy go tymi samymi kluczami, co Plan tygodnia, bo tylko
    // `@AppStorage` odświeży pigułkę, gdy ktoś przestawi suwak i wróci.
    @AppStorage(RecipePersonalization.Keys.calorieGoal)
    private var calorieGoal: Int = RecipePersonalization.defaultCalorieGoal
    @AppStorage(RecipePersonalization.Keys.goal)
    private var goalRaw: String = UserGoal.healthy.rawValue
    @AppStorage(BodyMetrics.Keys.heightCm) private var profileHeightCm: Int = 0
    @AppStorage(BodyMetrics.Keys.weightKg) private var profileWeightKg: Double = 0
    @AppStorage(BodyMetrics.Keys.sex) private var profileSexRaw: String = ""
    @AppStorage(BodyMetrics.Keys.yearOfBirth) private var profileYearOfBirth: Int = 0
    @AppStorage(BodyMetrics.Keys.activityLevel)
    private var profileActivityRaw: Int = ActivityLevel.light.rawValue
    @AppStorage(DailyNutritionTargets.Keys.proteinG)
    private var proteinOverride: Int = DailyNutritionTargets.Keys.noOverride
    @AppStorage(DailyNutritionTargets.Keys.fatG)
    private var fatOverride: Int = DailyNutritionTargets.Keys.noOverride
    @AppStorage(DailyNutritionTargets.Keys.carbsG)
    private var carbsOverride: Int = DailyNutritionTargets.Keys.noOverride

    // Flaga i cel kroków przez @AppStorage, nie przez computed property na
    // store — tylko @AppStorage gwarantuje re-render, gdy arkusz „Zdrowie"
    // zmieni wartość (store trzyma je w UserDefaults poza swoim stanem
    // @Observable).
    @AppStorage(HealthStepsStore.Keys.enabled) private var stepsEnabled: Bool = false
    @AppStorage(HealthStepsStore.Keys.stepsGoal) private var stepsGoal: Int = HealthStepsStore.defaultStepsGoal

    @State private var detailTarget: DetailTarget?
    /// Arkusz „Cel dnia" spod pigułki nad dolnym menu.
    ///
    /// `item`, a nie `isPresented`: ten ekran ma już `.sheet(item:)` na
    /// szczegółach posiłku, a SwiftUI potrafi zgubić `.sheet(isPresented:)`
    /// stojący wcześniej w tym samym łańcuchu modyfikatorów. Ta sama lekcja,
    /// co w Planie tygodnia.
    @State private var simpleSheet: SimpleSheet?

    private enum SimpleSheet: String, Identifiable {
        case dayGoal
        var id: String { rawValue }
    }
    /// Wymiary obszaru zakładki: szerokość idzie na szerokość pigułki,
    /// wysokość na sufit arkusza „Cel dnia".
    @State private var pageWidth: CGFloat = 0
    @State private var pageHeight: CGFloat = 0

    /// Dzień oglądany w Kalendarzu. Własny stan zakładki — Plan ma swój,
    /// wspólny zostaje tylko tydzień.
    @State private var selectedDate: Date = Date()

    /// Danie, które użytkownik sam przełożył na talerz stuknięciem
    /// w sekwencję pod nim. `nil` znaczy „pokaż to, co trzeba” — czyli
    /// następny posiłek dnia (`focusedItem`).
    ///
    /// Trzymamy sam identyfikator, a nie cały posiłek: plan potrafi przyjść
    /// z serwera zmieniony ręką domownika w trakcie oglądania, a wtedy
    /// przechowana kopia dania byłaby już nieprawdą. Identyfikator, który
    /// przestał pasować do dnia, po prostu wraca do wartości domyślnej.
    @State private var pickedCardId: String?

    /// Skąd ma wjechać nowe danie na talerz: `1` z prawej, `-1` z lewej,
    /// `0` w miejscu. Ustawiane W TEJ SAMEJ zmianie stanu, co powód ruchu
    /// (zmiana dnia, stuknięcie w talerzyk), bo przejście wstawienia czyta
    /// go w tym samym przebiegu układu — patrz `CalendarPlate.swap`.
    @State private var plateDirection: Int = 0

    /// Licznik przełożeń talerza ręką użytkownika — wyłącznie do haptyki.
    /// Rośnie tylko przy stuknięciu w talerzyk albo w linię dnia, a nie przy
    /// każdej zmianie wybranego dania: dzień ma swój sygnał w pagerze.
    @State private var plateMoves = 0

    /// Licznik KAŻDEGO ustawienia kierunku (dzień, talerzyk, linia dnia) —
    /// zegar gaszący kierunek wisi na nim, a nie na samej wartości.
    @State private var plateMotion = 0

    /// Licznik odhaczeń z pieczątki — haptyka zapisu. Odhaczenie to jedyny
    /// zapis na tym ekranie i ma być czuć pod palcem, że coś się stało.
    @State private var eatenToggles = 0

    // MARK: Obrót tacy

    /// Dzień, który właśnie wyjeżdża z kadru — rysowany jako druga, martwa
    /// kopia obok dnia wchodzącego, dopóki nie zjedzie. `nil` = nic nie jedzie.
    @State private var outgoingDate: Date?
    /// Przypięcie, jakie miał dzień wyjeżdżający — kopia ma wyglądać
    /// dokładnie tak, jak ten dzień wyglądał w chwili machnięcia, a nie
    /// wrócić do domyślnego dania w połowie odjazdu.
    @State private var outgoingPick: String?
    /// Postęp obrotu: `1` = nowy dzień poza kadrem, stary na miejscu;
    /// `0` = osiadło. Jedna liczba prowadzi wszystkie piętra obu dni.
    @State private var dayTurn: CGFloat = 0
    /// `1` = dzień do przodu (stary wyjeżdża w lewo, nowy wjeżdża z prawej).
    @State private var turnDirection: Int = 0
    /// Licznik obrotów — zegar sprzątający kopię wyjeżdżającą wisi na nim.
    @State private var turnCount = 0

    /// Miejsca talerzyków w sekwencji — skąd danie wznosi się na talerz.
    ///
    /// Klasa, nie wartość w `@State`: sekwencja melduje miejsca z układu
    /// (`onGeometryChange`), także klatka po klatce w trakcie obrotu tacy,
    /// a każdy zapis do `@State` przebudowywałby całą stronę dnia. Zapis
    /// do pola klasy nie przebudowuje niczego; odczyt następuje przy
    /// najbliższym przebiegu — czyli przy stuknięciu, kiedy miejsca są
    /// potrzebne i od dawna osiadłe.
    @State private var geometry = CalendarDayGeometry()
    /// Rośnie, gdy sekwencja zgłosi talerzyk, którego jeszcze nie znała
    /// (nowy dzień, zmieniony plan). Talerz czyta tę liczbę przy liczeniu
    /// miejsca, więc przebudowuje się raz po pierwszym meldunku dnia — i od
    /// tej chwili jego przejście zejścia zna drogę powrotną. Bez tego
    /// pierwsze przełożenie po wejściu w dzień gasiłoby stare danie
    /// w miejscu: SwiftUI bierze przejście zejścia z ostatniego przebiegu,
    /// w którym widok istniał, a ten przebieg był PRZED meldunkiem.
    @State private var cellRevision = 0

    private final class CalendarDayGeometry {
        /// Dzień, z którego pochodzą meldunki. Inny dzień zaczyna od zera:
        /// miejsca poprzedniego nie mają już adresata, a słownik nie ma
        /// rosnąć z każdym przewiniętym tygodniem.
        var dayKey = ""
        var cellCenters: [String: CGPoint] = [:]
        var cellPlateSize: CGFloat = 46

        /// `true`, gdy sekwencja zgłosiła talerzyk, którego jeszcze nie było
        /// — jedyny meldunek, po którym strona ma się przebudować. Zwykły
        /// ruch (obrót tacy klatka po klatce) tylko nadpisuje liczby.
        func report(_ item: CalendarPlateItem, at center: CGPoint, size: CGFloat, on dayKey: String) -> Bool {
            var changed = false
            if self.dayKey != dayKey {
                self.dayKey = dayKey
                cellCenters.removeAll(keepingCapacity: true)
                changed = true
            }
            if cellCenters.updateValue(center, forKey: item.id) == nil {
                changed = true
            }
            cellPlateSize = size
            return changed
        }
    }

    /// Posiłek otwarty w szczegółach, razem ze slotem, z którego przyszedł.
    ///
    /// Szczegół pozwala teraz przestawić liczbę porcji, a zapis musi trafić
    /// w ten konkretny wpis planu — sam `Recipe` nie mówi, o który slot chodzi.
    private struct DetailTarget: Identifiable {
        let date: Date
        let slot: MealSlot
        let meal: PlanMeal
        /// Przepis z pełnymi szczegółami; `meal.recipe` bywa wersją skróconą.
        var recipe: Recipe

        var id: String {
            "\(MealCalendarStore.dateKey(for: date)).\(slot.rawValue).\(meal.id)"
        }
    }

    // MARK: - Derived

    /// Kalendarz is a personal day view: only what *you* eat. Someone else's
    /// variant of a slot is their business, and counting it here inflated the
    /// day's macros against a per-person goal.
    private func myMeals(for slot: MealSlot, on date: Date) -> [PlanMeal] {
        let all = mealStore.meals(for: date, slot: slot)
        guard let userId = sessionStore.currentUserId else { return all }
        return all.visibleTo(memberId: userId)
    }

    /// Sloty rysowane dla wybranego dnia: włączone przez gospodarstwo plus
    /// te, w których mimo wyłączenia coś stoi. Ta sama reguła co w Planie —
    /// wyłączenie posiłku ukrywa slot, ale nigdy nie ukrywa jedzenia.
    private func visibleSlots(on date: Date) -> [MealSlot] {
        sessionStore.mealSlots.visibleSlots(
            planned: mealStore.plan(for: date).plannedSlots
        )
    }

    private func dayMeals(on date: Date) -> [PlanMeal] {
        visibleSlots(on: date).flatMap { myMeals(for: $0, on: date) }
    }

    /// Posiłki dnia, który pokazuje PRZYPIĘTY nagłówek (oś i licznik).
    /// Strona dnia rysuje z własnego argumentu — przez chwilę po machnięciu
    /// pokazuje jeszcze poprzedni dzień, a nagłówek już nowy.
    private var selectedDayMeals: [PlanMeal] {
        dayMeals(on: selectedDate)
    }

    /// Ilu domowników dzieli się porcjami, albo `nil`, dopóki `SessionStore`
    /// nie dowiezie listy.
    ///
    /// Pusta lista przed wczytaniem to brak odpowiedzi, a nie dom
    /// jednoosobowy — podstawiona tu jedynka dzieliłaby zapisane porcje przez
    /// jedną osobę i licznik kalorii pokazywałby przez pierwszą sekundę
    /// wielokrotność prawdziwej wartości.
    private var knownHouseholdMemberCount: Int? {
        guard sessionStore.didLoadHouseholdMembers else { return nil }
        return max(1, sessionStore.householdMembers.count)
    }

    /// Posiłki faktycznie odhaczone przez zalogowanego użytkownika. To one —
    /// a nie sam plan — zasilają licznik kalorii i makra: zaplanowany obiad
    /// nie jest dowodem, że ktokolwiek go zjadł.
    private var eatenMeals: [PlanMeal] {
        selectedDayMeals.filter { $0.isEaten(by: sessionStore.currentUserId) }
    }

    /// Dzienny cel — ta sama reguła i te same klucze, co w Planie tygodnia.
    private var dailyTargets: DailyNutritionTargets {
        DailyNutritionTargets.resolve(
            calorieGoal: calorieGoal,
            goal: UserGoal(rawValue: goalRaw) ?? .healthy,
            metrics: BodyMetrics(
                heightCm: profileHeightCm,
                weightKg: profileWeightKg,
                yearOfBirth: profileYearOfBirth,
                activityRaw: profileActivityRaw,
                sexRaw: profileSexRaw
            ),
            proteinOverride: proteinOverride,
            fatOverride: fatOverride,
            carbsOverride: carbsOverride
        )
    }

    /// Wybrany dzień policzony raz — pigułka nad menu i arkusz „Cel dnia"
    /// biorą liczby stąd.
    ///
    /// Ta sama pigułka co w Planie tygodnia, ale KARMIONA CZYM INNYM: Plan
    /// sumuje to, co zaplanowane, a Kalendarz wyłącznie to, co odhaczone.
    /// Zaplanowany obiad nie jest dowodem, że ktokolwiek go zjadł, więc
    /// wpuszczenie go do licznika kalorii byłoby po prostu nieprawdą.
    ///
    /// Do sumy — ale nie do listy. Arkusz dostaje WSZYSTKIE dania dnia
    /// (`isEaten` decyduje tylko o tym, co wchodzi do sumy), bo lista, która
    /// pokazuje wyłącznie zjedzone, na dzień przed pierwszym odhaczeniem jest
    /// pusta i wygląda jak dzień bez planu. Niezjedzone stoją tam wygaszone,
    /// z kreskowanym kółkiem — widać, że są, i widać, że jeszcze nie liczą.
    private var eatenNutrition: PlanDayNutrition {
        eatenDayNutrition(on: selectedDate)
    }

    /// To samo dla dowolnego dnia — strona dnia w `DayPager` liczy z własnego
    /// argumentu, a nie ze stanu ekranu.
    private func eatenDayNutrition(on date: Date) -> PlanDayNutrition {
        let userId = sessionStore.currentUserId
        return PlanDayNutrition.make(
            slots: visibleSlots(on: date),
            meals: { myMeals(for: $0, on: date) },
            knownHouseholdMemberCount: knownHouseholdMemberCount,
            isEaten: { $0.isEaten(by: userId) }
        )
    }

    /// Suma CAŁEGO planu dnia, bez pytania o odhaczenie — „ile ten dzień miał
    /// ważyć". Środek łuku i dopisek „odhacz cały dzień" mówią o planie,
    /// a nie o wyniku, więc muszą liczyć osobno.
    ///
    /// Osobna funkcja zamiast jednej z przełącznikiem: `isEaten` jest
    /// domknięciem, a domknięcie postawione w wyrażeniu warunkowym obok `nil`
    /// potrafi w tym projekcie zamienić się w `ambiguous use of 'init'`
    /// zgłoszone kilkadziesiąt linii wyżej (SE-0418, patrz `CLAUDE.md`).
    private func planNutrition(on date: Date) -> PlanDayNutrition {
        PlanDayNutrition.make(
            slots: visibleSlots(on: date),
            meals: { myMeals(for: $0, on: date) },
            knownHouseholdMemberCount: knownHouseholdMemberCount
        )
    }

    /// Pigułka „Cel dnia" jest węższa od dolnego menu i to jest jedyna rzecz,
    /// która mówi, co jest nawigacją, a co podglądem. Liczby jak w Planie —
    /// jedna pigułka, jedna szerokość.
    private var goalBarWidth: CGFloat {
        guard pageWidth > 0 else { return 0 }
        let limit = pageWidth - SCPageMetrics.horizontal * 2
        return min(max(pageWidth * 0.82, 310), limit)
    }

    /// Odhaczać można dziś i wstecz. Dzień z przyszłości nie ma czego
    /// odhaczać, a przeszły jest zablokowany tylko do *planowania* — to, co
    /// już się wydarzyło, wolno zapisać.
    private func canLogEatenMeals(on date: Date) -> Bool {
        Calendar.current.startOfDay(for: date)
            <= Calendar.current.startOfDay(for: Date())
    }

    /// Pasek kroków: integracja „Zdrowie" włączona i dzień dzisiejszy lub
    /// przeszły — ta sama granica co przy odhaczaniu posiłków.
    ///
    /// Liczone z podanego dnia, a nie ze stanu ekranu: strona dnia rysuje się
    /// z własnego argumentu i przez czas zjazdu pokazuje jeszcze poprzedni
    /// dzień.
    private func stepsBarVisible(on date: Date) -> Bool {
        stepsEnabled && canLogEatenMeals(on: date)
    }

    /// Set of "yyyy-MM-dd" keys for visible days that already have ≥1 meal — drives the sage planned-dot.
    private var plannedDates: Set<String> {
        var set = Set<String>()
        for date in datesViewModel.dates {
            let plan = mealStore.plan(for: date)
            if !plan.allRecipes.isEmpty {
                set.insert(plan.dateKey)
            }
        }
        return set
    }

    /// One card per planned variant visible to the current user, plus an
    /// empty card for untouched slots. `myMeals` already filters a split meal
    /// down to this user's variant, so a slot normally yields one card.
    private struct DayCard: Identifiable {
        let slot: MealSlot
        let meal: PlanMeal?
        var id: String {
            meal.map { "\(slot.rawValue).\($0.id)" } ?? "\(slot.rawValue).empty"
        }
    }

    private func dayCards(on date: Date) -> [DayCard] {
        visibleSlots(on: date).flatMap { slot -> [DayCard] in
            let meals = myMeals(for: slot, on: date)
            guard !meals.isEmpty else { return [DayCard(slot: slot, meal: nil)] }
            return meals.map { DayCard(slot: slot, meal: $0) }
        }
    }

    // MARK: - Talerz dnia

    /// Dania dnia gotowe do narysowania na talerzu i w sekwencji pod nim.
    ///
    /// Jedno miejsce, w którym model planu (`PlanMeal`, rozkład gospodarstwa,
    /// zegar) zamienia się w fakty dla widoku. Talerz nie liczy nic sam:
    /// „następny”, „za ile” i „od której przy garnkach” zależą od CAŁEGO dnia,
    /// więc muszą wyjść z jednego rachunku — inaczej pierścień wokół talerza
    /// i obwódka w sekwencji wskazałyby dwa różne dania.
    ///
    /// Puste pory też tu wchodzą, jako pozycje bez nazwy. Dawna lista mówiła
    /// „Nic nie zaplanowano” osobnym wierszem i to była prawdziwa odpowiedź,
    /// a nie jej brak — kreskowany talerzyk w sekwencji mówi dokładnie to samo,
    /// tylko ciszej.
    private func plateItems(cards: [DayCard], on date: Date, now: Date) -> [CalendarPlateItem] {
        let statuses = statusMap(cards: cards, on: date, now: now)
        let schedule = sessionStore.mealSlotSchedule
        let calendar = Calendar.current
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isPast = calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
        let nowMinutes = MealSlotSchedule.minutes(from: now, calendar: calendar)
        let userId = sessionStore.currentUserId

        return cards.map { card -> CalendarPlateItem in
            let minutes = schedule.minutes(for: card.slot)
            let time = schedule.time(for: card.slot)

            // Odliczanie ma sens wyłącznie dzisiaj. We wtorek nikt nie pyta,
            // ile zostało do czwartkowego obiadu.
            var minutesAway: Int?
            if isToday, let minutes { minutesAway = minutes - nowMinutes }

            guard let meal = card.meal else {
                return CalendarPlateItem(
                    id: card.id,
                    slot: card.slot,
                    status: .planned,
                    time: time,
                    title: nil,
                    imageURL: nil,
                    kcal: 0,
                    prepMinutes: 0,
                    cookFrom: nil,
                    servingsNote: nil,
                    minutesAway: minutesAway,
                    isMissed: false
                )
            }

            let prep = max(0, meal.recipe.prepTimeMinutes)
            // Godzina „od której przy garnkach” liczy się wstecz od pory
            // posiłku. Danie, którego nie trzeba przygotowywać (jogurt
            // z lodówki), nie ma czego zapowiadać — i wtedy nie ma też tej
            // godziny.
            var cookFrom: String?
            if prep > 0, let minutes {
                cookFrom = MealSlotSchedule.format(max(0, minutes - prep))
            }

            return CalendarPlateItem(
                id: card.id,
                slot: card.slot,
                status: statuses[card.id] ?? .planned,
                time: time,
                title: meal.recipe.name,
                imageURL: meal.recipe.imageURL,
                kcal: perPersonKcal(meal),
                prepMinutes: prep,
                cookFrom: cookFrom,
                servingsNote: servingsNote(meal),
                minutesAway: minutesAway,
                isMissed: isPast && !meal.isEaten(by: userId)
            )
        }
    }

    /// Które danie stoi na talerzu — albo `nil`, gdy talerz ma być pusty.
    ///
    /// Wybór użytkownika ma pierwszeństwo, ale tylko dopóki pasuje do dnia —
    /// plan potrafi przyjść z serwera zmieniony ręką domownika w trakcie
    /// oglądania. Wybrać wolno także pustą porę (stuknięcie w kreskowany
    /// talerzyk mówi wtedy „nic nie zaplanowano”), ale sam z siebie ekran
    /// pustej pory nie wybiera: dalej idzie reguła, którą niósł kiedyś
    /// środek łuku — pokaż to, co jest teraz przed użytkownikiem. Dzień
    /// domknięty otwiera się na ostatnim daniu, bo to ono jest końcem tej
    /// historii; dzień bez ani jednego dania — na pustym talerzu.
    private func focusedItem(from items: [CalendarPlateItem], pick: String?) -> CalendarPlateItem? {
        if let pick, let picked = items.first(where: { $0.id == pick }) {
            return picked
        }
        if let next = items.first(where: { $0.status == .next }) { return next }

        let meals = items.filter { !$0.isEmptySlot }
        guard !meals.isEmpty else { return nil }
        if let firstUneaten = meals.first(where: { !$0.isEaten }) { return firstUneaten }
        return meals.last
    }

    /// Kafel dnia stojący za danym talerzem — stąd wraca `PlanMeal` potrzebny
    /// do odhaczenia i do szczegółów. `CalendarPlateItem` niesie same fakty
    /// do narysowania i celowo nie ciągnie za sobą modelu.
    private func card(withId id: String, on date: Date) -> DayCard? {
        dayCards(on: date).first(where: { $0.id == id })
    }

    /// „2 porcje” — dopisek pod talerzem tylko wtedy, gdy ktoś świadomie
    /// odszedł od reguły auto. To, że coś jest domyślne, nie jest informacją.
    private func servingsNote(_ meal: PlanMeal) -> String? {
        guard let count = knownHouseholdMemberCount,
              meal.isCustomServings(householdMemberCount: count)
        else { return nil }
        return PolishPlural.servings(meal.effectiveServings(householdMemberCount: count))
    }

    // MARK: - Budżet wysokości

    /// Tryb układu dnia — ile ekran oddaje talerzowi, a ile reszcie.
    ///
    /// Trzy stopnie, od najwygodniejszego: zwykły (nazwa dania na dwie
    /// linijki, pełne kolumny sekwencji, odstęp 16), zwarty (jedna linijka,
    /// węższe kolumny, odstęp 12) i ciasny (bez rzędu pigułek, najwęższe
    /// kolumny). Wybór jest wyłącznie funkcją WYSOKOŚCI zakładki i tego,
    /// czy integracja kroków jest włączona — nigdy dnia. Gdyby zależał od
    /// dnia (kroki są rysowane tylko dziś i wstecz), machnięcie z dziś na
    /// jutro zmieniałoby tryb, a z nim wielkość talerza, liczbę linijek nazwy
    /// i miejsce sekwencji — na oczach użytkownika, w środku przejścia.
    private struct DayFit {
        let compact: Bool
        let tight: Bool
        /// Czy piętro kroków w ogóle stoi na tym ekranie. `false` tylko wtedy,
        /// gdy nawet ciasny tryb nie mieści talerza `minSize` obok kroków
        /// (iPhone SE): kroki schodzą, zanim talerz zejdzie do ikonki. To
        /// także decyzja z wysokości i flagi, nigdy z dnia — więc na SE nie
        /// ma ich w żaden dzień, a nie tylko w ten, w który by nie weszły.
        let reservesSteps: Bool
        /// Odstęp między piętrami i nad pierwszym. Bazowo 16 (zwarty: 12).
        /// Na wysokich ekranach rośnie do 26, żeby nadmiar ponad pełny talerz
        /// rozkładał się RÓWNO między piętra, zamiast zbierać się jedną
        /// pustką pod linią dnia — odstęp ma być wszędzie ten sam, także
        /// na Pro Max.
        let gap: CGFloat

        var titleLines: Int { compact ? 1 : 2 }
        var showsChips: Bool { !tight }
        var maxColumn: CGFloat {
            if tight { return 42 }
            return compact ? 48 : CalendarPlateStrip.designColumn
        }
    }

    /// Szacunkowe wysokości pięter — WYŁĄCZNIE do wyboru trybu i odstępu.
    ///
    /// Prawdziwy rozdział miejsca robi układ priorytetami (patrz `dayBody`);
    /// te liczby mają być tylko na tyle bliskie prawdy, żeby wybrać tryb,
    /// w którym talerz wychodzi największy, i żeby rozłożyć nadmiar. Pomyłka
    /// o kilka punktów przesuwa próg między trybami albo zostawia kilka
    /// punktów pustki na dole; nigdy nie powoduje nachodzenia, bo talerz
    /// i tak dostaje tylko to, co realnie zostało (`plateSize(in:)`).
    private enum DayTierEstimate {
        static let kicker: CGFloat = 13
        static let headline: CGFloat = 41
        static let titleGap: CGFloat = 5
        static let titleLine: CGFloat = 22
        static let chips: CGFloat = 30 + 12
        static let steps: CGFloat = 70

        /// Talerzyk wybrany + obwódka + podpisy w dwóch linijkach.
        static func strip(maxColumn: CGFloat) -> CGFloat {
            (maxColumn * 56 / 62).rounded() + 6 + 8 + 14 + 2 + 12
        }
    }

    /// Tryb, w którym talerz wychodzi największy przy zadanej wysokości.
    ///
    /// Zwykły zostaje, dopóki daje talerz przynajmniej 120 pt — poniżej
    /// tego zwarty daje go więcej, niż zwykły traci na drugiej linijce
    /// nazwy. Zwarty zostaje, dopóki daje pełną podłogę (`minSize`); dalej
    /// jest ciasny. Jeśli nawet ciasny nie mieści podłogi obok kroków,
    /// kroki schodzą z ekranu i rachunek idzie od nowa bez nich.
    private func dayFit(area: CGSize, reservesSteps: Bool) -> DayFit {
        /// Stałe piętra, liczba odstępów i bazowy odstęp danego trybu.
        func budget(compact: Bool, tight: Bool) -> (fixed: CGFloat, gaps: CGFloat, gap: CGFloat) {
            let probe = DayFit(compact: compact, tight: tight, reservesSteps: reservesSteps, gap: compact ? 12 : 16)
            var fixed = DayTierEstimate.kicker
                + DayTierEstimate.headline
                + DayTierEstimate.titleGap
                + DayTierEstimate.titleLine * CGFloat(probe.titleLines)
                + DayTierEstimate.strip(maxColumn: probe.maxColumn)
                + CalendarDayLine.height
            // Odstęp nad nadpisem i cztery między piętrami.
            var gaps: CGFloat = 5
            if probe.showsChips { fixed += DayTierEstimate.chips }
            if reservesSteps {
                fixed += DayTierEstimate.steps
                gaps += 1
            }
            return (fixed, gaps, probe.gap)
        }

        func plate(compact: Bool, tight: Bool) -> CGFloat {
            let b = budget(compact: compact, tight: tight)
            let slot = area.height - b.fixed - b.gaps * b.gap
            return slot * CalendarPlate.defaultSize / (CalendarPlate.defaultSize + CalendarPlate.maxRimInset * 2)
        }

        if reservesSteps, plate(compact: true, tight: true) < CalendarPlate.minSize {
            return dayFit(area: area, reservesSteps: false)
        }

        let compact: Bool
        let tight: Bool
        if plate(compact: false, tight: false) >= 120 {
            compact = false
            tight = false
        } else if plate(compact: true, tight: false) >= CalendarPlate.minSize {
            compact = true
            tight = false
        } else {
            compact = true
            tight = true
        }

        // Nadmiar ponad pełny talerz z rantami rozkłada się po równo między
        // odstępy — w czterech piątych, bo to szacunek: gdyby wziąć całość
        // i szacunek okazał się o kilka punktów za mały, odstępy zjadłyby
        // talerzowi to, czego nie było, i zszedłby poniżej pełnego rozmiaru
        // na ekranie, na którym miejsca jest aż nadto.
        let chosen = budget(compact: compact, tight: tight)
        let plateBox = CalendarPlate.defaultSize + CalendarPlate.maxRimInset * 2
        let surplus = area.height - chosen.fixed - chosen.gaps * chosen.gap - plateBox
        var gap = chosen.gap
        if surplus > 0 {
            gap += min(10, (surplus * 0.8 / chosen.gaps).rounded(.down))
        }
        return DayFit(compact: compact, tight: tight, reservesSteps: reservesSteps, gap: gap)
    }

    /// Średnica talerza dopasowana do miejsca, które dla niego zostało.
    ///
    /// `slot` to zmierzona wysokość pudełka talerza w kolumnie dnia — czyli
    /// dokładnie to, czego nie wzięły piętra o własnej, stałej wysokości
    /// (nadpis, podpis, sekwencja, linia dnia, kroki). Dzięki temu strona
    /// dnia mieści się bez przewijania na każdym telefonie: między iPhonem
    /// SE a Pro Max jest prawie 200 pt różnicy w pionie i to talerz je
    /// pochłania, a nie linia dnia znikająca za krawędzią.
    ///
    /// Rant talerza jest rysowany POZA jego ramką i skaluje się razem z nim,
    /// więc pudełko dzieli się w proporcji 168 : 194 — wtedy pudełko równa
    /// się zdjęciu plus rantom z obu stron przy KAŻDEJ wielkości, a odstęp od
    /// rantu do nadpisu i do odliczania wynosi dokładnie tyle, co między
    /// pozostałymi piętrami. Odejmowanie stałych 26 pt dawało przy małym
    /// talerzu (rant 6, nie 13) siedem punktów luzu więcej niż gdzie indziej.
    ///
    /// Talerz NIGDY nie wychodzi poza pudełko: podłoga `minSize` obowiązuje
    /// tylko wtedy, gdy się mieści, a zaokrąglenie idzie W DÓŁ — tak samo
    /// jak rant (`CalendarPlate.rimInset(for:)`), żeby zdjęcie plus dwa ranty
    /// nie przekroczyły pudełka nawet o punkt. O to, żeby pudełko nie było
    /// mniejsze od podłogi, dba wybór trybu (`dayFit`), który na najkrótszym
    /// ekranie zdejmuje kroki, zanim talerz zejdzie do ikonki.
    private func plateSize(in slot: CGSize) -> CGFloat {
        let rimRatio = CalendarPlate.defaultSize / (CalendarPlate.defaultSize + CalendarPlate.maxRimInset * 2)
        let byHeight = slot.height * rimRatio
        let byWidth = slot.width - 48
        let fit = min(CalendarPlate.defaultSize, min(byHeight, byWidth))
        let floor = min(CalendarPlate.minSize, byHeight)
        return max(0, max(floor, fit)).rounded(.down)
    }

    /// Zdanie pod sekwencją: co jest dalej względem tego, co stoi na talerzu.
    ///
    /// Kolejność sprawdzania jest kolejnością ważności. Najpierw „następny”
    /// — jeśli użytkownik ogląda co innego, to jest jedyna rzecz, do której
    /// musi umieć wrócić. Potem domknięcie dnia — ale tylko gdy na talerzu
    /// stoi OSTATNIE danie: przy wcześniejszym „Potem: kolacja” jest bardziej
    /// na miejscu niż gratulacje, a pusta pora za ostatnim daniem nie ma
    /// prawa zasłaniać domknięcia. Na końcu sąsiad w sekwencji, bo to on
    /// odpowiada na „co dalej”.
    private func dayNote(items: [CalendarPlateItem], focused: CalendarPlateItem?) -> CalendarDayNote {
        guard let focused else { return .empty(slots: items.count) }

        if let next = items.first(where: { $0.status == .next }), next.id != focused.id {
            return .next(next)
        }

        let meals = items.filter { !$0.isEmptySlot }
        let allEaten = !meals.isEmpty && meals.allSatisfy { $0.isEaten }
        if allEaten, focused.id == meals.last?.id { return .closed }

        if let index = items.firstIndex(where: { $0.id == focused.id }), index + 1 < items.count {
            return .after(items[index + 1])
        }
        return .last(focused)
    }

    /// Przekłada talerz na `target`, zapamiętując kierunek ruchu.
    ///
    /// Kierunek liczy się z MIEJSC w sekwencji: danie na prawo wjeżdża na
    /// talerz z prawej, na lewo — z lewej. Z pustego talerza (dzień bez dań)
    /// nowy talerzyk wskakuje w miejscu — pusty krążek nie ma pozycji
    /// w sekwencji, więc nie ma skąd wjeżdżać — ale to nadal ruch, z haptyką.
    /// Ustawiany W TEJ SAMEJ zmianie stanu, co wybór, bo przejście wstawienia
    /// nowego talerza czyta go w tym samym przebiegu układu (patrz
    /// `CalendarPlate.swap`).
    ///
    /// `pin` mówi, czy wybór ma zostać zapamiętany (stuknięcie w talerzyk),
    /// czy tylko wrócić do tego, co ekran uznaje za właściwe (powrót do
    /// następnego posiłku z linii dnia). W obu razach talerz jedzie tak samo.
    /// Haptyka idzie stąd, a nie z sekwencji: przekłada się talerz także
    /// stuknięciem w linię dnia, a sekwencja sama z siebie nie wie, czy
    /// wybrany talerzyk zmienił się od stuknięcia, czy od zmiany dnia.
    private func movePlate(
        to target: CalendarPlateItem,
        pin: Bool,
        in items: [CalendarPlateItem],
        from current: CalendarPlateItem?
    ) {
        let from = current.flatMap { c in items.firstIndex(where: { $0.id == c.id }) }
        let to = items.firstIndex(where: { $0.id == target.id }) ?? from ?? 0

        if let from, to == from {
            plateDirection = 0
        } else {
            plateDirection = from.map { to > $0 ? 1 : -1 } ?? 0
            plateMotion += 1
            plateMoves += 1
        }
        pickedCardId = pin ? target.id : nil
    }

    /// Stan każdego posiłku dnia względem „teraz", po jednym wpisie na
    /// kafel (klucz = `DayCard.id`).
    ///
    /// Liczone RAZ dla całego dnia i wspólne dla osi i dla listy: „następny"
    /// zależy od tego, co stoi w pozostałych porach, więc wiersz nie umie
    /// tego rozstrzygnąć sam. Gdyby oba miejsca liczyły osobno, prędzej czy
    /// później obwódka na osi i kropka w checkboksie wskazałyby dwa różne
    /// posiłki.
    private func statusMap(cards: [DayCard], on date: Date, now: Date) -> [String: CalendarMealStatus] {
        let isToday = Calendar.current.isDate(date, inSameDayAs: now)
        let userId = sessionStore.currentUserId
        let schedule = sessionStore.mealSlotSchedule

        // Po godzinie, nie po kolejności slotów: „następny" to pierwszy
        // nieodhaczony posiłek, który dopiero nadejdzie, a kolejność pór dnia
        // wolno w ustawieniach przestawić wbrew zegarowi.
        let ordered = cards
            .filter { $0.meal != nil }
            .sorted {
                (schedule.minutes(for: $0.slot) ?? Int.max)
                    < (schedule.minutes(for: $1.slot) ?? Int.max)
            }

        var map: [String: CalendarMealStatus] = [:]
        var nextTaken = !isToday

        for card in ordered {
            guard let meal = card.meal else { continue }

            if meal.isEaten(by: userId) {
                map[card.id] = .eaten
            } else if schedule.minutes(for: card.slot) == nil {
                map[card.id] = .anytime
            } else if !nextTaken {
                nextTaken = true
                map[card.id] = .next
            } else {
                map[card.id] = isToday ? .later : .planned
            }
        }
        return map
    }

    /// Udział jednej osoby w kaloriach posiłku — ta sama liczba, którą talerz
    /// pokazuje w pigułce i którą sumuje pigułka celu nad dolnym menu.
    private func perPersonKcal(_ meal: PlanMeal) -> Int {
        Int(
            meal.nutritionPerPerson(knownHouseholdMemberCount: knownHouseholdMemberCount)
                .kcal
                .rounded()
        )
    }

    /// Live `favourite` flag from the recipe catalog. The meal store snapshots
    /// `Recipe.favourite` at plan-save time and never resyncs, so we look up
    /// the current state by recipe id and fall back to the snapshot.
    private func isFavourite(_ recipe: Recipe) -> Bool {
        if let live = recipeCatalogStore.recipes.first(where: { $0.id == recipe.id }) {
            return live.favourite
        }
        return recipe.favourite
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                // Jeden zegar na cały ekran, nie dwa. „Następny posiłek"
                // i znacznik „teraz" na osi liczą się z tej samej chwili, co
                // odliczanie w wierszu („za 4 h 19 min") — dwa niezależne
                // `TimelineView` potrafiłyby przez kilka sekund wskazywać
                // dwa różne posiłki. Minuta wystarczy: oś ma podziałkę
                // godzinową, a odliczanie i tak jest w minutach.
                TimelineView(.everyMinute) { context in
                    page(now: context.date)
                }
            }
            // Pigułka wchodzi bezpiecznym obszarem, a nie `overlay`. Różnica
            // jest w tym, co dzieje się z listą pod spodem: `overlay`
            // zostawiał ostatni wiersz POD szkłem, gdzie było go widać, ale
            // nie dało się w niego stuknąć. `safeAreaInset` doksięgowuje
            // wysokość pigułki do wnętrza `ScrollView`, więc treść nadal
            // przelatuje pod szkłem przy przewijaniu, ale kończy się nad nim.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlanDayGoalBar(
                    nutrition: eatenNutrition,
                    targets: dailyTargets,
                    // Pigułka liczy ZJEDZONE, więc dzień przed pierwszym
                    // odhaczeniem ma w niej same zera — i nie da się z niej
                    // odróżnić dnia z planem od dnia pustego. Blada warstwa
                    // pod każdym torem mówi, dokąd ten dzień ma dojść.
                    planned: planNutrition(on: selectedDate),
                    action: { simpleSheet = .dayGoal }
                )
                .frame(width: goalBarWidth)
                .padding(.bottom, 8)
                // Pierwsza klatka nie zna jeszcze szerokości zakładki,
                // a pigułka o zerowej szerokości mignęłaby jako kreska.
                .opacity(goalBarWidth > 0 ? 1 : 0)
            }
            // Wymiary obszaru zakładki: szerokość na pigułkę, wysokość na
            // sufit arkusza „Cel dnia". Mierzone spod spodu, żeby pomiar nie
            // ruszał układu.
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size, initial: true) { _, size in
                            pageWidth = size.width
                            pageHeight = size.height
                        }
                }
            }
            // Pasek nawigacji zostaje na miejscu, ale pusty i przezroczysty:
            // nagłówek ekranu jest przypięty, więc nie ma czego pod niego
            // wsunąć i materiał `.bar` już się nie zapala. Pusty element
            // trzyma pasek przed zwinięciem.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            // The empty nav-bar layer would otherwise intercept taps in the
            // ~44pt zone above the week bar, blocking the day chips. We let
            // SwiftUI keep rendering the bar (so the auto-blur still runs),
            // but disable its UIKit hit testing so touches fall through to
            // the scroll content underneath. There are no real toolbar
            // items, so nothing legitimate is lost.
            .background(NavBarHitTestPassthrough())
            .onAppear {
                selectedDate = datesViewModel.dayWithinVisibleWeek(selectedDate)
            }
            .onChange(of: datesViewModel.weekStartISO) { _, _ in
                selectedDate = datesViewModel.selectedDate
            }
            .onChange(of: selectedDate) { _, newValue in
                datesViewModel.selectDate(newValue)
            }
            .task(id: datesViewModel.weekStartISO) {
                await mealStore.loadWeekPlanFromBackend(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
                // Zdjęcia całego tygodnia do pamięci podręcznej ZANIM ktoś
                // machnie na kolejny dzień. Z pamięci podręcznej talerz
                // dostaje zdjęcie w tej samej klatce, w której wjeżdża;
                // bez tego pierwsze wejście w dzień pokazywało gradient
                // pory, a zdjęcie wskakiwało w środku przejścia — chyba że
                // ktoś odwiedził wcześniej Plan tygodnia, który robi to samo.
                ImagePrefetcher.prefetch(
                    datesViewModel.dates
                        .flatMap { date in MealSlot.allCases.flatMap { mealStore.meals(for: date, slot: $0) } }
                        .compactMap { $0.recipe.imageURL }
                )
                // Świeży plan = świeży rozkład przypomnień o gotowaniu.
                // Hook cyklu życia (`.background`) też go przelicza, ale
                // dopiero przy wyjściu z aplikacji — a tydzień potrafi
                // przyjść z serwera zmieniony ręką domownika.
                sessionStore.rescheduleMealReminders()
            }
            // Kroki dnia spoza kroczącego okna (przeglądanie przeszłości) —
            // leniwy, czysto lokalny odczyt z HealthKit, bez wysyłki.
            .task(id: MealCalendarStore.dateKey(for: selectedDate)) {
                await sessionStore.healthStepsStore?
                    .refreshIfNeeded(for: selectedDate)
            }
            // Kalendarz nie planuje — picker zniknął stąd celowo. Dwie drogi
            // dodawania posiłków (Plan i Kalendarz) robiły to samo w dwóch
            // miejscach i myliły się nawzajem; układanie tygodnia ma teraz
            // jedno miejsce, a Kalendarz odpowiada na „co jem i czy zjadłem".
            .sheet(item: $simpleSheet) { which in
                switch which {
                case .dayGoal:
                    PlanDayGoalSheet(
                        date: selectedDate,
                        nutrition: eatenNutrition,
                        targets: dailyTargets,
                        // 0,9 wysokości zakładki: arkusz „do treści" nie ma
                        // prawa dojechać pod sam pasek stanu, bo wtedy
                        // przestaje być podglądem, a zaczyna być ekranem.
                        maxHeight: pageHeight * 0.9
                    )
                    // Bez `presentationDetents` — arkusz podaje własny,
                    // policzony z treści.
                    .dashboardLiquidSheet()
                }
            }
            .sheet(item: $detailTarget) { target in
                RecipeDetailView(
                    recipe: target.recipe,
                    onToggleFavorite: {
                        Task { @MainActor in
                            await recipeCatalogStore.toggleFavorite(recipeId: target.recipe.id)
                            let refreshed = await recipeCatalogStore.loadRecipeDetail(recipeId: target.recipe.id)
                                ?? recipeCatalogStore.recipes.first(where: { $0.id == target.recipe.id })
                                ?? target.recipe
                            // Podmieniamy sam przepis, nie cały cel — `id`
                            // zostaje ten sam, więc arkusz się nie przeładowuje
                            // i porcje wybrane stepperem przeżywają serduszko.
                            detailTarget?.recipe = refreshed
                        }
                    },
                    onClose: { detailTarget = nil },
                    // Stepper startuje od liczby, którą pokazuje reszta ekranu.
                    // Posiłek bez zapisanej wartości podstawia tu regułę auto,
                    // bo zero i jedynka nie są tym samym co „nie ustawiono".
                    // Nieznana liczba domowników nie może zamienić się w
                    // jedynkę — wtedy stepper startuje od tego, na ile porcji
                    // napisany jest sam przepis, a nie od liczby, której nikt
                    // nie wybierał.
                    initialServings: target.meal.effectiveServings(
                        knownHouseholdMemberCount: knownHouseholdMemberCount
                    ) ?? target.recipe.servings,
                    context: .planned(day: target.date, slot: target.slot),
                    onSaveServings: { newValue in
                        saveServings(newValue, for: target)
                    }
                )
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
        }
    }

    // MARK: - Pieces

    /// Cały ekran przy zadanej chwili. Przypięty zostaje pasek dni i nagłówek
    /// dnia — wszystko, co odpowiada na „gdzie jestem”. Talerz, sekwencja
    /// i linia dnia jadą razem z dniem, bo one tym dniem są.
    ///
    /// Łuk doby, który stał tu wcześniej, zszedł z ekranu razem z listą
    /// wierszy pod nim: rysował „gdzie w dobie jestem” kosztem miejsca na
    /// odpowiedź, po którą otwiera się tę zakładkę — „co teraz jem”.
    private func page(now: Date) -> some View {
        // „Dzisiaj" liczone z zegara strony, nie z `Date()` w trzech
        // miejscach: plakietka w nagłówku, pierścień „następnego" i odliczanie
        // pod talerzem muszą mówić o TEJ SAMEJ chwili.
        let isToday = Calendar.current.isDate(selectedDate, inSameDayAs: now)

        return VStack(alignment: .leading, spacing: 0) {
            Group {
                // Kalendarz nie ma tytułu — pasek dni sam mówi, co to za
                // ekran. Układ ignoruje górny safe area (rozciąga się pod
                // pasek nawigacji), więc pełne 78 pt idzie tu jako jawny
                // padding, tak jak tytuł na pozostałych zakładkach.
                EditorialWeekBar(
                    datesViewModel: datesViewModel,
                    selectedDate: $selectedDate,
                    plannedDates: plannedDates
                )
                .padding(.horizontal, SCPageMetrics.horizontal)
                .padding(.top, SCPageMetrics.top)

                // Nazwa dnia i plakietka z kropkami („4 z 5 zjedzone").
                // Przypięta razem z paskiem dni, bo odpowiada na to samo
                // pytanie: który to dzień i ile z niego jest już za mną.
                CalendarDayHeader(
                    date: selectedDate,
                    isToday: isToday,
                    eaten: eatenMeals.count,
                    total: selectedDayMeals.count
                )
                .padding(.horizontal, SCPageMetrics.horizontal)
                .padding(.top, 14)
            }
            // Przypięty blok rośnie z Dynamic Type, a strona dnia pod nim ma
            // pismo o stałych rozmiarach i stały budżet wysokości. Przy
            // rozmiarach dostępności pasek dni i nagłówek zabierały talerzowi
            // sto punktów i piętra wychodziły pod pigułkę celu — sufit na
            // największym zwykłym rozmiarze trzyma je w budżecie.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            DayPager(
                datesViewModel: datesViewModel,
                selectedDate: $selectedDate,
                // 16, nie 40: pigułka „Cel dnia" wstawia pod treść własny
                // bezpieczny obszar, więc to już tylko prześwit MIĘDZY linią
                // dnia a szkłem.
                bottomPadding: 16,
                // Stuknięcie w pasek dni i strzałki tygodnia jadą tak samo
                // jak machnięcie palcem. Warunek jest jeden: strona MUSI
                // rysować dzień z argumentu, bo na czas zjazdu pager
                // pokazuje jeszcze poprzedni dzień.
                animatesSelectionChanges: true,
                // Kalendarz się NIE przewija. Cały dzień to jeden widok
                // i ma się zmieścić — a żeby strona mogła się do czegokolwiek
                // dopasować, musi najpierw dostać prawdziwą wysokość. Wewnątrz
                // `ScrollView` nie ma czegoś takiego: tam wysokość jest
                // nieskończona, więc talerz nie wiedziałby, ile miejsca dla
                // niego zostało, i zamiast maleć — wypychał resztę dnia poza
                // krawędź. (Plan tygodnia zostaje przewijany: tam lista kafli
                // JEST dłuższa od ekranu.)
                scrolls: false,
                // Scena stoi, dane się przekładają. Zjazd całej strony w bok
                // mówił oczom „to inny ekran", a to ten sam talerz z innym
                // dniem — zdjęcie ma zrobić „pop", odliczanie przerolować,
                // sekwencja wejść kryciem. Pusty dzień to w tym języku po
                // prostu talerz bez dania, a nie osobna strona.
                motion: .morph,
                // Kierunek dla talerza — w tej samej transakcji, co zmiana
                // dnia. Dzień do przodu wjeżdża z prawej, do tyłu z lewej.
                // Obrót tacy, faza pierwsza (bez animacji, ta sama klatka co
                // zmiana daty): stary dzień zostaje jako kopia wyjeżdżająca
                // z przypięciem, jakie miał, nowy staje poza kadrem
                // (`dayTurn = 1`). Przypięcie schodzi tu, a nie klatkę
                // później — pusta pora ma ten sam identyfikator każdego dnia
                // („lunch.empty”), więc przypięta wczoraj otwierałaby jutro
                // na sobie. Kierunek talerza zeruje się: zmianę dnia niesie
                // obrót tacy, nie rozkwit talerza.
                onDayChange: { change in
                    outgoingDate = change.from
                    outgoingPick = pickedCardId
                    pickedCardId = nil
                    plateDirection = 0
                    turnDirection = change.forward ? 1 : -1
                    dayTurn = 1
                    turnCount += 1
                },
                // Faza druga, klatkę później: oba dni jadą jedną sprężyną —
                // tą samą, którą jedzie podkreślenie na pasku dni.
                onDayTurn: {
                    withAnimation(DayNavigationMotion.spring) { dayTurn = 0 }
                }
            ) { date in
                dayPage(for: date, now: now)
            }
        }
        // Układ wchodzi pod pasek nawigacji, żeby siadał w miejscu z projektu
        // (~78 pt od góry ekranu) zamiast być zepchniętym o jego ~44 pt.
        // Przezroczysty pasek nadal stoi na wierzchu.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Jeden dzień: nadpis z porą, talerz, podpis pod nim, sekwencja dań
    /// i jedno zdanie na koniec. Ruch palcem w bok przestawia dzień, tak samo
    /// jak w Planie tygodnia.
    ///
    /// Wszystko liczy się tu z `date`, a nie z `selectedDate`: `DayPager`
    /// trzyma starą stronę na ekranie przez czas zjazdu, więc strona
    /// czytająca stan ekranu podmieniałaby treść w połowie animacji — na
    /// oczach użytkownika, zanim jeszcze zjechała.
    private func dayPage(for date: Date, now: Date) -> some View {
        // Jeden pomiar na całą stronę dnia. Z niego bierze się i szerokość
        // sekwencji, i tryb układu (zwykły / zwarty / ciasny).
        GeometryReader { geo in
            // Obrót tacy: dzień wychodzący i dzień wchodzący to DWA osobne
            // widoki, prowadzone jedną liczbą (`dayTurn`). Nie są to
            // przejścia SwiftUI — przejście zejścia pamięta kierunek z chwili
            // wstawienia, więc po „w przód, potem w tył” stary dzień
            // odjeżdżałby w tę samą stronę, z której wjeżdża nowy. Jawne
            // przesunięcia liczone z bieżącego stanu nie mają tej pamięci.
            // Tożsamość po dniu (`.id`) z przejściem `.identity`: nowy dzień
            // to świeży widok, który od pierwszej klatki stoi tam, gdzie
            // każe mu `dayTurn`, a nie animuje się z miejsca starego.
            ZStack {
                if let outgoingDate {
                    dayBody(
                        for: outgoingDate,
                        now: now,
                        area: geo.size,
                        pick: outgoingPick,
                        turn: DayTurn(progress: dayTurn, direction: turnDirection, outgoing: true)
                    )
                    .id("out|\(MealCalendarStore.dateKey(for: outgoingDate))|\(turnCount)")
                    .transition(.identity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                dayBody(
                    for: date,
                    now: now,
                    area: geo.size,
                    pick: pickedCardId,
                    turn: DayTurn(progress: dayTurn, direction: turnDirection, outgoing: false)
                )
                .id(MealCalendarStore.dateKey(for: date))
                .transition(.identity)
            }
        }
        .padding(.horizontal, SCPageMetrics.horizontal)
        // Jedna haptyka na jedno przełożenie talerza — stuknięcie w talerzyk
        // albo w linię dnia. Zmiana dnia ma swój sygnał w pagerze. Odhaczenie
        // ma własny, cięższy: to zapis, nie nawigacja.
        .sensoryFeedback(.selection, trigger: plateMoves)
        .sensoryFeedback(.impact(weight: .medium), trigger: eatenToggles)
        // Kierunek wjazdu talerza gaśnie, gdy sprężyna osiądzie. Bez tego
        // danie, które zmieniło się z innego powodu niż ruch użytkownika
        // (plan przyszedł z serwera zmieniony ręką domownika), wjeżdżałoby
        // z kierunku ostatniego stuknięcia. Zerowanie po osiadnięciu nie
        // rusza żadnego przejścia: tożsamość talerza się wtedy nie zmienia.
        //
        // Zadanie wisi na LICZNIKU ruchów, nie na wartości kierunku: dwa
        // stuknięcia w tę samą stronę w ciągu pół sekundy nie zmieniają
        // wartości, a zegar ma ruszyć od nowa. I wychodzi przy anulowaniu
        // — anulowane zadanie, które mimo to zeruje kierunek, gasiłoby go
        // klatkę po tym, jak nowy ruch właśnie go ustawił.
        .task(id: plateMotion) {
            guard plateMotion > 0 else { return }
            do {
                try await Task.sleep(for: .milliseconds(420))
            } catch {
                return
            }
            plateDirection = 0
        }
        // Kopia wyjeżdżająca schodzi z drzewa, gdy sprężyna osiądzie —
        // niewidoczna i tak, ale rysowana. Zegar na liczniku obrotów,
        // odporny na anulowanie, z tego samego powodu co wyżej.
        .task(id: turnCount) {
            guard turnCount > 0 else { return }
            do {
                try await Task.sleep(for: .milliseconds(520))
            } catch {
                return
            }
            outgoingDate = nil
            outgoingPick = nil
        }
    }

    // MARK: - Obrót tacy

    /// Gdzie na tacy stoi dzień: postęp obrotu, kierunek i czy to dzień
    /// wychodzący, czy wchodzący.
    private struct DayTurn {
        /// `1` = nowy dzień poza kadrem, stary na miejscu; `0` = osiadło.
        let progress: CGFloat
        /// `1` = dzień do przodu.
        let direction: Int
        let outgoing: Bool

        /// Piętro dnia na tacy z własną głębią. `travel` w punktach w bok,
        /// `lift` w górę (dalsza krawędź tacy), `shrink` jako ułamek skali.
        func effect(travel: CGFloat, lift: CGFloat, shrink: CGFloat) -> DayTurnEffect {
            DayTurnEffect(
                progress: progress,
                direction: CGFloat(direction),
                outgoing: outgoing,
                travel: travel,
                lift: lift,
                shrink: shrink
            )
        }
    }

    /// Jedno piętro dnia jadące po tacy.
    ///
    /// Taca widziana z przodu: danie odjeżdżające w bok cofa się na dalszą
    /// krawędź — unosi się, maleje i gaśnie — a wjeżdżające przychodzi tą
    /// samą drogą od drugiej strony. Każde piętro ma własną głębię
    /// (paralaksa): talerz jedzie najdalej i najwyżej, podpis mniej,
    /// sekwencja i linia dnia ledwie. Wszystkie z JEDNEJ liczby `progress`,
    /// więc zawsze w takcie.
    ///
    /// `Animatable` po `progress`: SwiftUI interpoluje surową liczbę,
    /// a położenie liczy się z niej przy każdej klatce. Stary dzień gaśnie
    /// kwadratem (szybko z oczu), nowy wchodzi kwadratem od drugiej strony
    /// (widoczny wcześnie, jeszcze w drodze) — nakładają się krótko.
    private struct DayTurnEffect: ViewModifier, Animatable {
        var progress: CGFloat
        let direction: CGFloat
        let outgoing: Bool
        let travel: CGFloat
        let lift: CGFloat
        let shrink: CGFloat

        var animatableData: CGFloat {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let p = max(0, min(progress, 1))
            // Ile drogi ma za sobą to piętro: nowe wjeżdża (p → 0), stare
            // wyjeżdża (1 − p → 1).
            let away = outgoing ? 1 - p : p
            let side = outgoing ? -direction : direction
            let fade = Double(away) * Double(away)

            content
                .scaleEffect(1 - shrink * away)
                .offset(x: side * travel * away, y: -lift * away)
                .opacity(1 - fade)
        }
    }

    /// Piętra dnia w zmierzonym pudełku.
    ///
    /// Kolejność jest kolejnością czytania: pora → danie → co z nim → reszta
    /// dnia → co dalej. Każde piętro poza talerzem ma WŁASNĄ, stałą wysokość
    /// — tę samą na pustym dniu i na pełnym, przy krótkiej nazwie i przy
    /// długiej, przy czterech porach i przy sześciu — a między piętrami
    /// (i nad pierwszym) stoi wszędzie ten sam odstęp. To są dwa warunki
    /// tego, żeby talerz stał na każdym dniu w tym samym miejscu i żeby nic
    /// nie podskakiwało przy przekładaniu talerzy ani przy zmianie dnia.
    ///
    /// Rozdział wysokości idzie priorytetami układu, nie rachunkiem. Piętra
    /// o stałej wysokości mają priorytet 1 — dostają swoje jako pierwsze.
    /// Talerz (priorytet 0) bierze WSZYSTKO, co zostało, do sufitu ze swojego
    /// pełnego rozmiaru z rantami. Jeśli coś jeszcze zostanie, zostaje pustym
    /// miejscem pod linią dnia — kolumna jest przypięta do góry i nie
    /// potrzebuje do tego rozpórki (rozpórka kosztowałaby jeden odstęp
    /// z budżetu talerza, także wtedy, gdy sama ma zero wysokości).
    private func dayBody(
        for date: Date,
        now: Date,
        area: CGSize,
        pick: String?,
        turn: DayTurn
    ) -> some View {
        // Kafle dnia policzone RAZ. Cała strona przelicza się co minutę
        // (zegar odliczania), a kafle stały za trzema osobnymi wywołaniami
        // — statusy, dania, powrót do wpisu planu.
        let cards = dayCards(on: date)
        let items = plateItems(cards: cards, on: date, now: now)
        let canLog = canLogEatenMeals(on: date)
        // Kroki są rysowane dziś i wstecz, ale REZERWOWANE na każdy dzień,
        // gdy integracja jest włączona: piętro stoi zawsze, treść wchodzi
        // i schodzi. Inaczej machnięcie z dziś na jutro zabierałoby
        // osiemdziesiąt punktów spod talerza i cała scena by się przesuwała.
        let fit = dayFit(area: area, reservesSteps: stepsEnabled)
        let showsSteps = fit.reservesSteps && stepsBarVisible(on: date)

        let focused = focusedItem(from: items, pick: pick)
        let canToggle = canLog && focused?.isEmptySlot == false
        let note = dayNote(items: items, focused: focused)
        // Ziarno wariantów zdań: ten sam dzień mówi zawsze tak samo, kolejny
        // inaczej (`CalendarVoice`).
        let dayKey = MealCalendarStore.dateKey(for: date)

        // Szczegóły otwiera zdjęcie na talerzu i nazwa dania pod nim. Osobna
        // zmienna, a nie wyrażenie warunkowe przy wywołaniu: domknięcie obok `nil`
        // w wyrażeniu warunkowym potrafi w tym projekcie zamienić się
        // w `ambiguous use of 'init'` zgłoszone kilkadziesiąt linii wyżej
        // (SE-0418, patrz `CLAUDE.md`).
        var openDetail: (() -> Void)?
        if let focused, !focused.isEmptySlot {
            openDetail = { openMeal(withCardId: focused.id, on: date) }
        }

        // Miejsca talerzyków melduje tylko dzień WCHODZĄCY. Kopia wyjeżdżająca
        // ma te same kolumny, tylko w drodze — jej meldunki byłyby szumem.
        var reportCell: ((CalendarPlateItem, CGPoint, CGFloat) -> Void)?
        if !turn.outgoing {
            reportCell = { item, center, size in
                if geometry.report(item, at: center, size: size, on: dayKey) {
                    cellRevision += 1
                }
            }
        }

        return VStack(spacing: fit.gap) {
            CalendarPlateKicker(item: focused)
                .modifier(turn.effect(travel: 36, lift: 0, shrink: 0))
                .layoutPriority(1)

            // Pudełko talerza: bierze całą resztę wysokości, ale nie więcej
            // niż pełny talerz z rantami. Talerz stoi w nim na środku,
            // a `plateSize(in:)` dzieli pudełko w proporcji zdjęcia do rantów
            // — więc odstęp od nadpisu do rantu i od rantu do odliczania to
            // dokładnie `gap`, przy każdej wielkości talerza.
            //
            // Menu kontekstowe siedzi na SAMYM talerzu, przed rozciągnięciem
            // na pudełko, a jego podgląd jest kołem z rantem — inaczej długie
            // przytrzymanie w pustym rogu pudełka unosiło prostokąt z poświatą
            // i marginesami.
            GeometryReader { slot in
                let size = plateSize(in: slot.size)
                let slotFrame = slot.frame(in: .named(CalendarPlateStrip.daySpace))

                CalendarPlate(
                    item: focused,
                    direction: plateDirection,
                    size: size,
                    canToggle: canToggle,
                    onToggle: { toggleEaten(withCardId: focused?.id, on: date) },
                    onOpenDetail: openDetail,
                    origin: liftOrigin(
                        for: focused,
                        on: dayKey,
                        plateCenter: CGPoint(x: slotFrame.midX, y: slotFrame.midY),
                        revision: cellRevision
                    ),
                    // Pierwszy przebieg pudełka bywa zerowy — bez sufitu od dołu
                    // skala wychodziłaby nieskończona.
                    originScale: geometry.cellPlateSize / max(size, 1)
                )
                .contentShape(.contextMenuPreview, Circle().inset(by: -CalendarPlate.rimInset(for: size)))
                .contextMenu { plateActions(for: focused, on: date, canLog: canLog) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: CalendarPlate.defaultSize + CalendarPlate.maxRimInset * 2)
            // Talerz jedzie najdalej i najwyżej — to on jest daniem na tacy.
            .modifier(turn.effect(travel: 140, lift: 24, shrink: 0.16))
            // Nad podpisem i sekwencją: danie w drodze między talerzykiem
            // a talerzem przechodzi przez oba piętra i ma lecieć NAD nimi,
            // a nie chować się pod nazwą dania i sąsiednimi talerzykami.
            // Bez tego rysowałoby się pod nimi, bo w kolumnie późniejsze
            // piętro leży wyżej.
            .zIndex(1)

            CalendarPlateCaption(
                item: focused,
                dayKey: dayKey,
                titleLines: fit.titleLines,
                showsChips: fit.showsChips,
                lean: plateDirection,
                onOpenDetail: openDetail
            )
            .modifier(turn.effect(travel: 72, lift: 6, shrink: 0.04))
            .layoutPriority(1)

            CalendarPlateStrip(
                items: items,
                selectedId: focused?.id,
                width: area.width,
                maxColumn: fit.maxColumn,
                onCellCenter: reportCell,
                onSelect: { movePlate(to: $0, pin: true, in: items, from: focused) }
            )
            .modifier(turn.effect(travel: 56, lift: 0, shrink: 0.05))
            .layoutPriority(1)

            CalendarDayLine(
                note: note,
                dayKey: dayKey,
                onReturnToNext: {
                    guard let next = items.first(where: { $0.status == .next }) else { return }
                    movePlate(to: next, pin: false, in: items, from: focused)
                },
                onSelect: { movePlate(to: $0, pin: true, in: items, from: focused) }
            )
            .modifier(turn.effect(travel: 36, lift: 0, shrink: 0))
            .layoutPriority(1)

            // Kroki z HealthKit: piętro zarezerwowane na każdy dzień
            // (schowana próbka mierzy je sama, tak jak próbka nazwy dania
            // mierzy podpis), treść tylko dziś i wstecz — przyszłość nie ma
            // czego pokazać, nawet zera. Wchodzi i schodzi kryciem
            // z uniesieniem, tym samym ruchem, którym zmienia się dzień.
            if fit.reservesSteps {
                ZStack {
                    EditorialStepsBar(steps: nil, goal: stepsGoal, source: nil)
                        .hidden()
                        .accessibilityHidden(true)

                    if showsSteps {
                        let day = sessionStore.healthStepsStore?.steps(for: date)
                        EditorialStepsBar(
                            steps: day?.steps,
                            goal: stepsGoal,
                            source: day?.source
                        )
                        .transition(.opacity.combined(with: .offset(y: 12)))
                    }
                }
                .modifier(turn.effect(travel: 36, lift: 0, shrink: 0))
                .layoutPriority(1)
            }
        }
        // Ten sam odstęp nad nadpisem, co między piętrami: nagłówek dnia
        // nad pagerem kończy się dokładnie tam, gdzie zaczyna się strona,
        // i bez tego nazwa dnia siedziała nadpisowi na karku.
        .padding(.top, fit.gap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Jedna przestrzeń współrzędnych dla talerza i sekwencji — w niej
        // sekwencja melduje środki talerzyków, a talerz mierzy własny środek.
        .coordinateSpace(.named(CalendarPlateStrip.daySpace))
    }

    /// Skąd danie wznosi się na talerz: środek jego talerzyka w sekwencji
    /// względem środka talerza. `nil`, gdy sekwencja tego dnia jeszcze nie
    /// zameldowała (pierwsza klatka dnia) albo talerz jest pusty — wtedy
    /// talerz rozkwita w miejscu. `revision` to licznik meldunków
    /// (`cellRevision`): zero znaczy „nikt się nie zameldował”, a sam odczyt
    /// wiąże talerz z licznikiem, żeby przebudował się po meldunku.
    private func liftOrigin(
        for item: CalendarPlateItem?,
        on dayKey: String,
        plateCenter: CGPoint,
        revision: Int
    ) -> CGPoint? {
        guard let item, revision > 0, geometry.dayKey == dayKey,
              let cell = geometry.cellCenters[item.id] else { return nil }
        return CGPoint(x: cell.x - plateCenter.x, y: cell.y - plateCenter.y)
    }

    /// Długie przytrzymanie talerza: odhaczenie, szczegóły i ulubione.
    ///
    /// Jeden mechanizm może być niewidoczny, drugi musi być widoczny — i to
    /// ten drugi uczy pierwszego. Odhaczanie i szczegóły mają swoje
    /// stuknięcia (pieczątka w rogu i samo zdjęcie), więc menu jest tu
    /// przede wszystkim dla serduszka, które zeszło z ekranu razem z listą.
    /// Pusty talerz nie ma czego oferować — pusty budowniczy menu znaczy
    /// w SwiftUI „bez menu".
    @ViewBuilder
    private func plateActions(
        for item: CalendarPlateItem?,
        on date: Date,
        canLog: Bool
    ) -> some View {
        if let item,
           !item.isEmptySlot,
           let card = card(withId: item.id, on: date),
           let meal = card.meal {
            if canLog {
                // Tą samą drogą, co stuknięcie w talerz — z przypięciem dania
                // i wyzerowaniem kierunku. Bezpośrednie wołanie sklepu
                // omijało jedno i drugie i talerz odjeżdżał spod menu.
                Button {
                    toggleEaten(withCardId: item.id, on: date)
                } label: {
                    Label(
                        item.isEaten ? "Cofnij oznaczenie" : "Oznacz jako zjedzone",
                        systemImage: item.isEaten ? "arrow.uturn.backward" : "checkmark.circle"
                    )
                }
            }

            Button {
                handleAssignedTap(meal, slot: card.slot, on: date)
            } label: {
                Label("Szczegóły posiłku", systemImage: "text.below.photo")
            }

            Button {
                toggleFavorite(meal.recipe)
            } label: {
                Label(
                    isFavourite(meal.recipe) ? "Usuń z ulubionych" : "Dodaj do ulubionych",
                    systemImage: isFavourite(meal.recipe) ? "heart.slash" : "heart"
                )
            }
        }
    }

    // MARK: - Actions

    /// Stuknięcie w pieczątkę w rogu talerza odhacza danie, które na nim
    /// stoi — i ZOSTAWIA je na talerzu.
    ///
    /// Bez przypięcia „następny” przechodziłby na kolejne danie w tej samej
    /// chwili, w której sklep zapisuje odhaczenie, i talerz odjeżdżałby
    /// spod palca: użytkownik nigdy nie zobaczyłby pieczątki na daniu,
    /// które właśnie stuknął, cofnięcie musiałby szukać w sekwencji,
    /// a szybkie podwójne stuknięcie odhaczałoby dwa różne dania. Przypięte
    /// danie zostaje, pieczątka i pierścień zmieniają się w miejscu,
    /// a linia dnia od razu podaje drogę do następnego. Przypięcie schodzi
    /// przy zmianie dnia (`onChange(of: selectedDate)`) i przy powrocie
    /// z linii dnia (`movePlate(pin: false)`).
    ///
    /// Talerz dostaje same fakty do narysowania (`CalendarPlateItem`), więc
    /// wpis planu trzeba tu odszukać po identyfikatorze kafla. Dzień, który
    /// w międzyczasie przyszedł z serwera zmieniony, po prostu nie odda
    /// kafla — i wtedy stuknięcie nic nie robi, zamiast zapisać coś na
    /// nieistniejącym posiłku.
    private func toggleEaten(withCardId id: String?, on date: Date) {
        guard let id,
              let card = card(withId: id, on: date),
              let meal = card.meal
        else { return }

        pickedCardId = id
        plateDirection = 0
        eatenToggles += 1
        toggleEaten(meal, slot: card.slot, on: date)
    }

    /// Stuknięcie w zdjęcie na talerzu albo w nazwę dania otwiera szczegóły
    /// — jedyne miejsce, w którym przestawia się liczbę porcji.
    private func openMeal(withCardId id: String, on date: Date) {
        guard let card = card(withId: id, on: date), let meal = card.meal else { return }
        handleAssignedTap(meal, slot: card.slot, on: date)
    }
    private func handleAssignedTap(_ meal: PlanMeal, slot: MealSlot, on date: Date) {
        Task { @MainActor in
            let full = await recipeCatalogStore.loadRecipeDetail(recipeId: meal.recipe.id) ?? meal.recipe
            detailTarget = DetailTarget(date: date, slot: slot, meal: meal, recipe: full)
        }
    }

    /// Zapisuje liczbę porcji zmienioną stepperem w szczegółach.
    ///
    /// Audytorium zostaje nietknięte — zmieniamy ile gotujemy, a nie dla kogo.
    /// `plannedServings` idzie jawnie, więc serwer nie nadpisze go regułą auto.
    private func saveServings(_ servings: Int, for target: DetailTarget) {
        Task { @MainActor in
            _ = await mealStore.upsertWeekSlot(
                recipe: target.meal.recipe,
                participantIds: target.meal.participantIds,
                plannedServings: servings,
                householdMemberCount: knownHouseholdMemberCount,
                for: target.date,
                slot: target.slot,
                weekStart: datesViewModel.weekStartISO
            )
            detailTarget = nil
            await shoppingListStore.load(
                weekStart: datesViewModel.weekStartISO,
                force: true
            )
        }
    }

    private func toggleEaten(_ meal: PlanMeal, slot: MealSlot, on date: Date) {
        let isEaten = meal.isEaten(by: sessionStore.currentUserId)
        Task { @MainActor in
            await mealStore.setMealEaten(
                !isEaten,
                recipeId: meal.recipe.id,
                for: date,
                slot: slot,
                weekStart: datesViewModel.weekStartISO
            )
            // Odhaczony posiłek nie ma o czym przypominać. Bez tego kolacja
            // odhaczona po południu i tak zawołałaby wieczorem „pora gotować"
            // — u kogoś, kto siedzi w aplikacji i właśnie powiedział, że zjadł.
            sessionStore.rescheduleMealReminders()
        }
    }

    private func toggleFavorite(_ recipe: Recipe) {
        Task { @MainActor in
            await recipeCatalogStore.toggleFavorite(recipeId: recipe.id)
        }
    }
}

#Preview {
    CalendarView()
}

// MARK: - Nav bar hit-test pass-through
//
// SwiftUI's `NavigationStack` keeps the toolbar layer "live" so the auto-blur
// material can fade in on scroll, but that layer also captures touches across
// its full ~44pt height — even when the toolbar is visually empty. That
// blocks the week-bar chips from receiving taps once the layout extends
// under it via `.ignoresSafeArea(.container, edges: .top)`.
//
// We don't have any real toolbar items here (just an invisible 1×1 placeholder
// used to keep the bar from collapsing). Disabling user interaction on the
// underlying `UINavigationBar` lets touches fall through to the SwiftUI
// content below while leaving the auto-blur rendering intact.
private struct NavBarHitTestPassthrough: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        BarUnlocker()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class BarUnlocker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Defer one runloop tick so the navigation controller is wired up.
            DispatchQueue.main.async { [weak self] in
                self?.findNavigationBar()?.isUserInteractionEnabled = false
            }
        }

        private func findNavigationBar() -> UINavigationBar? {
            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController,
                   let bar = vc.navigationController?.navigationBar {
                    return bar
                }
                responder = r.next
            }
            return nil
        }
    }
}
