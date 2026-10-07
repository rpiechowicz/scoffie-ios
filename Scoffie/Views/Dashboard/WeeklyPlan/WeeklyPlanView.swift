import SwiftUI

// Plan tygodnia — v2 „Cozy Kitchen”, kierunek D.
// Źródło: canvas claude.ai → „Weekly Meals - Plan v2.html”
// (`components/plan-v2-d.jsx`, `plan-v2-edit.jsx`, `plan-v2-empty.jsx`).
//
// Układ: tytuł z akcjami i pasek dni — wszystko przypięte do góry — a pod nimi
// jedyna przewijana część ekranu: strona jednego dnia jako OŚ CZASU
// (`PlanDayTimeline`). Ruch palcem w bok przestawia dzień (`DayPager`), tak
// samo jak w Kalendarzu.
//
// Co zmienił kierunek D względem v2.0:
// • Karta dnia i osobna sekcja „Każdy je inaczej” zniknęły. Porę dnia niesie
//   szyna czasu po lewej, a danie domownika stoi wprost pod daniem domu.
// • Przełącznik gospodarstwa zszedł z nagłówka do menu „…”. Oś pokazuje dania
//   wszystkich obok siebie, więc soczewka jednej osoby przestała być czymś,
//   co trzeba mieć pod kciukiem przez cały czas.
// • Asystent siedzi w nagłówku EKRANU, w rzędzie z zakupami i „…”. Nagłówek
//   dnia jest już tylko podpisem: nazwa dnia po lewej, „2 z 3 posiłków” po
//   prawej. Dodawanie ręczne żyje w wierszach osi: „Wybierz przepis”
//   i „Dodaj posiłek”.
//
// Sloty posiłków: dzień rysuje tyle wierszy, ile gospodarstwo ma włączonych
// w Ustawieniach → „Posiłki w planie”, plus te, w których mimo wyłączenia coś
// stoi (`visibleSlots(on:)`). Reszta czeka pod „Dodaj posiłek”.
struct WeeklyPlanView: View {
    @Environment(\.toasts) private var toasts
    @Environment(\.scTabIsActive) private var isActiveTab
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.shoppingListStore) private var shoppingListStore
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme

    /// Dzień planowany w tej zakładce. Własny stan Planu — Kalendarz ma swój,
    /// wspólny zostaje tylko tydzień.
    @State private var selectedDate: Date = Date()
    @State private var profile: PlanProfile = .household
    /// Dieta, alergeny i cele dnia domowników (`households:memberPreferences`)
    /// — do arkusza „Cel dnia” po przełączeniu na inną osobę i do pigułki,
    /// gdy soczewka „…” stoi na kimś innym.
    @State private var memberPreferences: [String: HouseholdMemberPreferences] = [:]
    @State private var pickerTarget: PickerTarget?
    @State private var detailTarget: DetailTarget?
    @State private var showClearDayAlert = false
    @State private var showClearWeekAlert = false
    /// Arkusze bez własnego celu: lista zakupów i „Cel dnia”.
    ///
    /// Jeden `@State` na oba, a nie dwa niezależne `Bool`-e z osobnymi
    /// `.sheet(isPresented:)`. SwiftUI potrafi zgubić wcześniejsze
    /// `.sheet(isPresented:)` w łańcuchu modyfikatorów tego samego widoku,
    /// a ten ekran ma ich cztery — z celami przepisu i wyboru posiłku.
    /// Jeden `item` to jedna prezentacja, więc nie ma czego gubić.
    @State private var simpleSheet: SimpleSheet?

    private enum SimpleSheet: String, Identifiable {
        case products
        case dayGoal
        var id: String { rawValue }
    }

    /// Wysokość obszaru zakładki — z niej liczy się sufit arkusza „Cel dnia".
    /// Arkusz sam jej nie zna: `GeometryReader` w jego wnętrzu podaje wysokość
    /// AKTUALNEGO detentu, a nie tego, do ilu wolno mu urosnąć.
    @State private var pageHeight: CGFloat = 0
    /// Szerokość obszaru zakładki — z niej liczy się szerokość pigułki.
    @State private var pageWidth: CGFloat = 0

    /// Ta sama szerokość co na Pulpicie — jedna reguła (`PlanDayGoalBar.width`).
    private var goalBarWidth: CGFloat { PlanDayGoalBar.width(in: pageWidth) }

    // Cel dnia mieszka w Ustawieniach → „Dieta i alergeny" i w profilu; tu
    // czytamy go tymi samymi kluczami, co Kalendarz, bo tylko `@AppStorage`
    // odświeży pigułkę, gdy ktoś przestawi suwak i wróci na Plan.
    @ProtectedSetting(RecipePersonalization.Keys.calorieGoal)
    private var calorieGoal: Int = RecipePersonalization.defaultCalorieGoal
    @ProtectedSetting(RecipePersonalization.Keys.goal)
    private var goalRaw: String = UserGoal.healthy.rawValue
    @ProtectedSetting(BodyMetrics.Keys.heightCm) private var profileHeightCm: Int = 0
    @ProtectedSetting(BodyMetrics.Keys.weightKg) private var profileWeightKg: Double = 0
    @ProtectedSetting(BodyMetrics.Keys.sex) private var profileSexRaw: String = ""
    @ProtectedSetting(BodyMetrics.Keys.yearOfBirth) private var profileYearOfBirth: Int = 0
    @ProtectedSetting(BodyMetrics.Keys.activityLevel)
    private var profileActivityRaw: Int = ActivityLevel.light.rawValue
    @ProtectedSetting(DailyNutritionTargets.Keys.proteinG)
    private var proteinOverride: Int = DailyNutritionTargets.Keys.noOverride
    @ProtectedSetting(DailyNutritionTargets.Keys.fatG)
    private var fatOverride: Int = DailyNutritionTargets.Keys.noOverride
    @ProtectedSetting(DailyNutritionTargets.Keys.carbsG)
    private var carbsOverride: Int = DailyNutritionTargets.Keys.noOverride

    /// Posiłek otwarty w szczegółach, razem z miejscem, z którego przyszedł.
    ///
    /// Sam `Recipe` tu nie wystarczy: ekran szczegółu pozwala zmienić liczbę
    /// porcji, a zapis musi trafić w ten konkretny wpis planu — czyli
    /// potrzebuje dnia, slotu i dotychczasowego audytorium.
    private struct DetailTarget: Identifiable {
        let date: Date
        let slot: MealSlot
        let meal: PlanMeal
        /// Przepis dociągnięty z pełnymi szczegółami; `meal.recipe` bywa
        /// skróconą wersją z listy planu.
        var recipe: Recipe

        var id: String {
            "\(MealCalendarStore.dateKey(for: date)).\(slot.rawValue).\(meal.id)"
        }
    }

    private struct PickerTarget: Identifiable {
        let date: Date
        let slot: MealSlot
        /// Ustawione, gdy arkusz edytuje istniejący wariant, a nie dokłada nowy.
        let editing: PlanMeal?
        /// Audytorium zaznaczone na starcie. `nil` = domyślne arkusza
        /// (soczewka profilu albo „Wspólne").
        var defaultParticipantIds: [String]? = nil

        var id: String {
            let base = "\(MealCalendarStore.dateKey(for: date)).\(slot.rawValue)"
            return editing.map { "\(base).\($0.id)" } ?? base
        }
    }

    // MARK: - Derived

    private var members: [HouseholdMemberSnapshot] {
        sessionStore.householdMembers
    }

    /// Ilu domowników dzieli się porcjami, albo `nil`, dopóki `SessionStore`
    /// nie dowiezie listy. Pusta lista przed wczytaniem to brak odpowiedzi,
    /// a nie dom jednoosobowy — i to właśnie ta różnica decyduje, czy stepper
    /// porcji pokaże zapisaną liczbę, czy fałszywą jedynkę.
    private var knownHouseholdMemberCount: Int? {
        guard sessionStore.didLoadHouseholdMembers else { return nil }
        return max(1, members.count)
    }

    /// Klucze „yyyy-MM-dd” dni, w których coś już stoi — z nich bierze się
    /// zielona kropka pod paskiem dni i odpowiedź na „czy tydzień jest pusty”.
    private var plannedDates: Set<String> {
        var set = Set<String>()
        for date in datesViewModel.dates {
            let plan = mealStore.plan(for: date)
            if !plan.allMeals.isEmpty { set.insert(plan.dateKey) }
        }
        return set
    }

    /// Ile produktów zostało do kupienia w widocznym tygodniu — liczba na
    /// plakietce przy koszyku. Regułę („co się liczy po zamknięciu listy")
    /// trzyma magazyn, żeby nagłówek Planu i ekran Zakupów nie mogły podać
    /// dwóch różnych liczb.
    private var shoppingRemainingCount: Int {
        shoppingListStore.remainingCount(for: datesViewModel.weekStartISO)
    }

    /// VoiceOver czyta stan razem z akcją — sama plakietka jest dla niego
    /// niewidoczna, bo „19" wypowiedziane osobno nic nie znaczy.
    private var shoppingAccessibilityLabel: String {
        let remaining = shoppingRemainingCount
        guard remaining > 0 else { return "Lista zakupów" }
        return "Lista zakupów, \(PolishPlural.products(remaining)) do kupienia"
    }

    /// Dzienny cel — ta sama reguła, co w Ustawieniach.
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

    /// Czyj dzień liczy pigułka nad menu: osoba z soczewki „…”, a przy
    /// „Cały dom” — ten, kto trzyma telefon.
    ///
    /// Suma „całego domu” nie jest niczyim talerzem: przy dwóch różnych
    /// obiadach w tej samej porze pigułka dodawała oba do jednego osobistego
    /// celu i pokazywała ~3000 kcal osobie, która zje jeden (Rafał,
    /// 23.09.2026). Oś dnia dalej pokazuje dania wszystkich obok siebie —
    /// zmienia się tylko to, co się SUMUJE.
    private var nutritionPersonId: String? {
        profile.memberId ?? sessionStore.currentUserId
    }

    /// Dzień jednej osoby: w każdej porze jej danie osobiste albo wspólne
    /// (`visibleTo(memberId:)`). Dom jednoosobowy — i skład jeszcze
    /// niewczytany — liczy wszystko, co stoi w dniu.
    private func dayNutrition(on date: Date, for personId: String?) -> PlanDayNutrition {
        let person = members.count > 1 ? personId : nil
        return PlanDayNutrition.make(
            slots: visibleSlots(on: date),
            meals: { slot in
                let all = mealStore.meals(for: date, slot: slot)
                guard let person else { return all }
                return all.visibleTo(memberId: person)
            },
            knownHouseholdMemberCount: knownHouseholdMemberCount,
            // Porcja per osoba: talerz osoby z pigułki, nie średnia domu.
            memberId: personId
        )
    }

    /// Wybrany dzień osoby z pigułki — policzony raz dla pigułki nad menu.
    private var selectedDayNutrition: PlanDayNutrition {
        dayNutrition(on: selectedDate, for: nutritionPersonId)
    }

    /// Cel osoby, której dzień liczy pigułka: mój z Ustawień, domownika —
    /// z serwera, a bez danych z domyślnej sylwetki
    /// (`DailyNutritionTargets.forMember`). Pigułka ma dla każdego te same
    /// cztery tory — przełączenie osoby tylko przetacza liczby.
    private func dailyTargets(for personId: String?) -> DailyNutritionTargets {
        guard let personId, personId != sessionStore.currentUserId else { return dailyTargets }
        return memberTargets(personId)
    }

    /// Cel domownika zawsze pełny — patrz `DailyNutritionTargets.forMember`.
    private func memberTargets(_ memberId: String) -> DailyNutritionTargets {
        DailyNutritionTargets.forMember(memberPreferences[memberId]?.targets)
    }

    /// Cele domowników z serwera. Pusta odpowiedź (błąd, anulowanie) NIE
    /// nadpisuje tego, co już jest — inaczej jedno zerwane połączenie
    /// gasiło cele w przełączniku do końca sesji.
    private func refreshMemberPreferences() async {
        guard members.count > 1 else { return }
        let loaded = await sessionStore.loadHouseholdMemberPreferences()
        guard !Task.isCancelled, !loaded.isEmpty else { return }
        memberPreferences = loaded
    }

    /// Osoby w arkuszu „Cel dnia” — ja pierwszy, potem domownicy w kolejności
    /// składu, każdy ze swoimi daniami i swoim celem.
    private var dayGoalPeople: [PlanDayPerson] {
        let me = sessionStore.currentUserId
        guard members.count > 1 else {
            return [
                PlanDayPerson(
                    id: me ?? "me",
                    name: "Ty",
                    member: nil,
                    nutrition: selectedDayNutrition,
                    targets: dailyTargets,
                    isMe: true
                )
            ]
        }
        let ordered = members.filter { $0.id == me } + members.filter { $0.id != me }
        return ordered.map { member in
            let isMe = member.id == me
            return PlanDayPerson(
                id: member.id,
                name: HouseholdMemberStyle.shortName(member.displayName),
                member: member,
                nutrition: dayNutrition(on: selectedDate, for: member.id),
                targets: isMe ? dailyTargets : memberTargets(member.id),
                isMe: isMe
            )
        }
    }

    /// Posiłki slotu, zawężone do bieżącego profilu.
    ///
    /// Danie osobiste bije danie wspólne: jeśli Ania ma swój obiad, jej
    /// soczewka pokazuje właśnie ten obiad, a nie dodatkowo wspólny. Bez tej
    /// reguły dzień jednej osoby liczył każdy slot podwójnie.
    private func visibleMeals(date: Date, slot: MealSlot) -> [PlanMeal] {
        let all = mealStore.meals(for: date, slot: slot)
        guard let memberId = profile.memberId else { return all }
        return all.visibleTo(memberId: memberId)
    }

    /// Dla kogo startuje arkusz „Osobne danie dla kogoś”.
    ///
    /// Nigdy „Wspólne”: z tym domyślnym wybór przepisu bez dotykania chipów
    /// dokładał do pory DRUGIE danie całego domu, więc oba dania dostawały
    /// odznakę domku, a żadne nie należało do nikogo. Bierzemy pierwszą osobę
    /// bez własnego dania w tej porze, z pominięciem planującego — to on
    /// zostaje przy daniu domu, a osobne danie robi się dla kogoś innego.
    private func variantAudience(date: Date, slot: MealSlot) -> [String] {
        let claimed = Set(
            mealStore.meals(for: date, slot: slot)
                .filter { !$0.isShared }
                .flatMap(\.participantIds)
        )
        let uncovered = members.map(\.id).filter { !claimed.contains($0) }
        let others = uncovered.filter { $0 != sessionStore.currentUserId }
        return (others.first ?? uncovered.first).map { [$0] } ?? []
    }

    /// Sloty do narysowania dla jednego dnia.
    ///
    /// Do włączonych w ustawieniach dokładamy te, w których tego dnia coś
    /// stoi. Bez tego wyłączenie podwieczorku sprzątałoby z ekranu posiłki,
    /// które nadal są w bazie i nadal liczą się do listy zakupów — czyli
    /// aplikacja pokazywałaby plan inny niż ten, według którego się kupuje.
    private func visibleSlots(on date: Date) -> [MealSlot] {
        sessionStore.mealSlots.visibleSlots(
            planned: mealStore.plan(for: date).plannedSlots
        )
    }

    /// Pory, których dzień jeszcze nie pokazuje — pod „Dodaj posiłek”.
    /// Pusto znaczy, że dom planuje już wszystkie sześć: wiersza nie ma wtedy
    /// czym wypełnić, więc go nie ma.
    private func extraSlots(on date: Date) -> [MealSlot] {
        let visible = Set(visibleSlots(on: date))
        return MealSlot.allCases.filter { !visible.contains($0) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme)
                    .ignoresSafeArea()

                // Nagłówek i pasek dni stoją, przewija się wyłącznie strona
                // dnia. Wcześniej cała strona była jednym `ScrollView` i przy
                // dłuższym dniu tytuł i pasek dni wyjeżdżały za górną krawędź —
                // czyli to, po czym się nawiguje, znikało dokładnie wtedy, gdy
                // było potrzebne.
                VStack(alignment: .leading, spacing: 0) {
                    Group {
                        // Marginesy wspólne z pozostałymi zakładkami —
                        // tytuł siada w tym samym miejscu co „Przepisy”.
                        headerRow
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, SCPageMetrics.top)
                            // 16, nie 22: pasek dni zaczyna się własnym
                            // wierszem podpisu („TEN TYDZIEŃ · 8–14 WRZ”),
                            // który sam robi odstęp od tytułu.
                            .padding(.bottom, 16)

                        // Pasek dni zamiast przełącznika tygodni: to nawigacja
                        // faktycznie używana na co dzień. Wygląd wspólny
                        // z Kalendarzem, ale wybrany dzień jest osobny —
                        // planowanie i podgląd dnia to dwie różne czynności.
                        EditorialWeekBar(
                            datesViewModel: datesViewModel,
                            selectedDate: $selectedDate,
                            plannedDates: plannedDates
                        )
                        .padding(.horizontal, SCPageMetrics.horizontal)
                        // Bez kreski pod paskiem dni: strona dnia gaśnie pod
                        // nim sama (`scScrollEdgeFade` w `DayPager`), jak treść
                        // pod przypiętym nagłówkiem arkusza. Kreska stała tu
                        // na stałe, także gdy nic pod nią nie przejeżdżało.
                        // Odstęp do nazwy dnia należy w całości do osi
                        // (`PlanDayTimeline`, 14 pt) — tyle, ile w Kalendarzu.
                        // Dawne 14 tutaj + 18 w osi odsuwało dzień od paska.

                        // Bez czerwonego wiersza błędu: od kiedy most z korzenia
                        // aplikacji wystawia `errorMessage` jako toast, ten sam
                        // komunikat renderował się DWA razy — raz jako kapsuła,
                        // raz jako przypis, który dokładał wysokości przypiętemu
                        // nagłówkowi i spychał oś dnia w chwili, gdy treść pod
                        // spodem i tak się przekładała.
                    }

                    DayPager(
                        datesViewModel: datesViewModel,
                        selectedDate: $selectedDate,
                        // 16, nie 32: pigułka „Cel dnia" wstawia pod treść
                        // własny bezpieczny obszar (`safeAreaInset` niżej),
                        // więc to jest już tylko prześwit MIĘDZY ostatnim
                        // wierszem osi a szkłem pigułki.
                        bottomPadding: 16,
                        // Stuknięcie w dzień i strzałki tygodnia jadą tak samo
                        // jak gest — strona rysuje dzień z argumentu, więc
                        // pager może pokazać stary dzień na czas zjazdu.
                        animatesSelectionChanges: true
                    ) { date in
                        dayPage(for: date)
                    }
                }
                // Ten sam trik co w Kalendarzu v2: układ startuje od
                // projektowych 78 pt od GÓRNEJ KRAWĘDZI EKRANU, a nie spod
                // paska nawigacji.
                .ignoresSafeArea(.container, edges: .top)
            }
            // Pigułka wchodzi bezpiecznym obszarem, a nie `overlay`.
            // Różnica jest w tym, co się dzieje z osią dnia pod spodem:
            // `overlay` zostawiał ostatni wiersz („Dodaj posiłek") POD szkłem,
            // gdzie było go widać, ale nie dało się w niego stuknąć.
            // `safeAreaBar` doksięgowuje wysokość pigułki do wnętrza
            // `ScrollView`, więc treść nadal przelatuje pod szkłem przy
            // przewijaniu, ale kończy się nad nim — a pod pigułką leży natywny
            // efekt krawędzi przewijania. Nad systemowym paskiem zakładek
            // stawia ją sam bezpieczny obszar.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                PlanDayGoalBar.dock(width: goalBarWidth) {
                    PlanDayGoalBar(
                        nutrition: selectedDayNutrition,
                        targets: dailyTargets(for: nutritionPersonId),
                        tab: .plan,
                        action: {
                            simpleSheet = .dayGoal
                            // Cel domownika mógł się zmienić od ostatniego
                            // odczytu — arkusz dociąga świeży w tle.
                            Task { await refreshMemberPreferences() }
                        }
                    )
                }
            }
            // Miękki, jawnie — `.automatic` z Xcode Cloud wychodził jako
            // `.hard` (kreska i kryjące tło, patrz `scSheetFooterEdge`).
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            // Wymiary obszaru zakładki: wysokość idzie na sufit arkusza
            // „Cel dnia", szerokość na szerokość pigułki. Mierzone spod spodu,
            // żeby pomiar nie ruszał układu.
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.size, initial: true) { _, size in
                            pageHeight = size.height
                            pageWidth = size.width
                        }
                }
            }
            // Pasek nawigacji SCHOWANY — jak w Zakupach i na korzeniu Przepisów.
            // Pusty, ale żywy pasek leżał na wierszu nagłówka i łapał
            // stuknięcia; hak wyłączający mu dotyk (`NavBarHitTestPassthrough`)
            // pod systemowym `TabView` przestał działać — koszyk i „…” były
            // martwe (Rafał 6.10.2026). Plan nie wpycha żadnych ekranów, więc
            // pasek nie ma tu nic do pokazania.
            .toolbar(.hidden, for: .navigationBar)
            .task(id: datesViewModel.weekStartISO) {
                await mealStore.loadWeekPlanFromBackend(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
                prefetchWeekImages()
            }
            // Plakietka przy koszyku musi znać stan listy, ZANIM ktokolwiek
            // otworzy arkusz — inaczej pokazywałaby zero do pierwszego
            // wejścia w zakupy. `load` idzie po cache, więc arkusz otwarty
            // chwilę później nie płaci za to drugim zapytaniem.
            .task(id: datesViewModel.weekStartISO) {
                await shoppingListStore.load(weekStart: datesViewModel.weekStartISO)
            }
            .task {
                // Imiona, kolory i odznaki „dla kogo” biorą się ze składu
                // gospodarstwa, więc musi być wczytany.
                await sessionStore.refreshHouseholdMembers(force: false)
            }
            // Cele domowników do przełącznika osób w „Cel dnia” — przy każdej
            // zmianie składu. Dom jednoosobowy nie ma kogo przełączać.
            .task(id: members.map(\.id)) {
                await refreshMemberPreferences()
            }
            // Powrót na zakładkę: dzień mógł zostać zmieniony na innej.
            // Flaga zamiast `onAppear`, bo zakładki żyją wszystkie naraz.
            .onChange(of: isActiveTab, initial: true) { _, active in
                guard active else { return }
                selectedDate = datesViewModel.dayWithinVisibleWeek(selectedDate)
                mealStore.observeWeek(
                    weekStart: datesViewModel.weekStartISO,
                    dates: datesViewModel.dates
                )
            }
            .onChange(of: datesViewModel.weekStartISO) { _, _ in
                selectedDate = datesViewModel.selectedDate
            }
            .onChange(of: selectedDate) { _, newValue in
                datesViewModel.selectDate(newValue)
            }
            // Domownika, którego nie ma na liście, nie da się zaplanować —
            // przy zniknięciu ze składu wracamy do soczewki całego domu.
            .onChange(of: members.map(\.id)) { _, ids in
                if let id = profile.memberId, !ids.contains(id) {
                    profile = .household
                }
            }
            .alert("Wyczyść ten dzień", isPresented: $showClearDayAlert) {
                Button("Wyczyść", role: .destructive) { clearActiveDay() }
                Button("Anuluj", role: .cancel) { }
            } message: {
                Text("Wszystkie posiłki tego dnia zostaną usunięte z planu.")
            }
            .alert("Wyczyść cały tydzień", isPresented: $showClearWeekAlert) {
                Button("Wyczyść", role: .destructive) { clearWeek() }
                Button("Anuluj", role: .cancel) { }
            } message: {
                Text("Plan całego tygodnia zostanie usunięty razem z posiłkami przypisanymi do dni.")
            }
            .sheet(item: $simpleSheet) { which in
                switch which {
                case .products:
                    ProductsView(topPadding: 24)
                case .dayGoal:
                    PlanDayGoalSheet(
                        date: selectedDate,
                        people: dayGoalPeople,
                        // Arkusz otwiera się na tej samej osobie, co pigułka.
                        initialPersonId: nutritionPersonId,
                        members: members,
                        // 0,9 wysokości zakładki: arkusz „do treści" nie ma
                        // prawa dojechać pod sam pasek stanu, bo wtedy
                        // przestaje być podglądem, a zaczyna być ekranem.
                        maxHeight: pageHeight * 0.9
                    )
                    // Bez `presentationDetents` — arkusz podaje własny,
                    // policzony z treści (patrz `PlanDayGoalSheet`).
                    .dashboardLiquidSheet()

                }
            }
            // Skrót z karty asystenta: przełączenie zakładki to za mało,
            // bo lista zakupów jest arkuszem wewnątrz tego ekranu.
            //
            // Arkusz rusza chwilę PO przełączeniu: systemowy `TabView` buduje
            // Plan przy pierwszym wyborze, a arkusz pokazany w tej samej
            // aktualizacji co wstawienie zakładki do okna potrafi przepaść
            // („not in the window hierarchy”).
            .onChange(of: sessionStore.opensShoppingList, initial: true) { _, wants in
                guard wants else { return }
                sessionStore.opensShoppingList = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    simpleSheet = .products
                }
            }
            // „Zaplanuj” na pustej porze w „Dziś”: planowanie ma jedno miejsce,
            // więc tamta zakładka tylko tu prowadzi — ten dzień w Planie i od
            // razu wybór przepisu na tę porę, jak stuknięcie pustej pory na osi.
            // Z tego samego powodu co lista zakupów — chwilę po przełączeniu.
            .onChange(of: sessionStore.planSlotRequest, initial: true) { _, request in
                guard let request else { return }
                sessionStore.planSlotRequest = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    openPlanRequest(request)
                }
            }
            .sheet(item: $pickerTarget) { target in
                PlanSlotPickerSheet(
                    date: target.date,
                    slot: target.slot,
                    weekStartISO: datesViewModel.weekStartISO,
                    members: members,
                    editing: target.editing,
                    // Planowanie przez soczewkę jednej osoby znaczy, że posiłek
                    // jest dla niej, dopóki nie powiesz inaczej.
                    defaultParticipantIds: target.defaultParticipantIds
                        ?? profile.memberId.map { [$0] } ?? [],
                    // Po acku serwera, nie po dismissie — arkusz zamyka się
                    // przed końcem zapisu, a lista zakupów liczona ze starego
                    // planu byłaby do wyrzucenia.
                    onSaveCompleted: { refreshShoppingList() }
                )
                .presentationDetents([.large])
                .dashboardLiquidSheet()
            }
            .sheet(item: $detailTarget) { target in
                RecipeDetailView(
                    // Żywy przepis z katalogu: serce nadąża za zapisem, a cel
                    // (`detailTarget`) nie jest podmieniany po zapisie — przy
                    // zamkniętym i otwartym w międzyczasie innym posiłku
                    // podmiana wpisywała stary przepis do nowego arkusza.
                    recipe: recipeCatalogStore.recipes.first(where: { $0.id == target.recipe.id }) ?? target.recipe,
                    onSetFavourite: { value in
                        Task { await recipeCatalogStore.setFavourite(recipeId: target.recipe.id, to: value) }
                    },
                    onClose: { detailTarget = nil },
                    // Stepper startuje od liczby, którą pokazuje wiersz planu.
                    // Posiłek bez zapisanej wartości podstawia tu regułę auto,
                    // bo „nie ustawiono” to nie to samo co jedna porcja.
                    initialServings: target.meal.effectiveServings(
                        knownHouseholdMemberCount: knownHouseholdMemberCount
                    ) ?? target.recipe.servings,
                    context: .planned(day: target.date, slot: target.slot),
                    onSaveServings: { newValue in
                        saveServings(newValue, for: target)
                    },
                    // Porcja każdego jedzącego ze stepperem co 0,5 — przy
                    // każdym posiłku; bez listy domowników zostaje stepper
                    // porcji łącznych.
                    personalPortions: RecipeDetailPortions(
                        meal: target.meal,
                        members: sessionStore.householdMembers,
                        viewerId: sessionStore.currentUserId
                    ),
                    onSavePortions: { all, changed in
                        savePortions(all: all, changed: changed, for: target)
                    }
                )
                .recipeDetailSheet()
            }
        }
    }

    // MARK: - Pieces

    /// Średnica pigułek akcji w nagłówku Planu — 34 pt, jak `P2Circle`
    /// w makiecie. Akcje są dwie (zakupy i „…”); tytuł schodzi o stopień
    /// pisma sam, gdy trzeba, przez `ViewThatFits` w `EditorialPageHeader`.
    private static let headerActionSize: CGFloat = 34

    private var headerRow: some View {
        EditorialPageHeader(title: "Plan tygodnia") {
            // Bez `GlassEffectContainer`: grupa szkła składa krążki w jedną
            // warstwę, a plakietka koszyka wystaje poza krążek — nie może
            // wisieć w czymś, co ją przytnie albo wtopi w szkło. Asystent („Ułóż” i jego plansza) zszedł stąd 4.10.2026
            // na prośbę Rafała — do Asystenta prowadzi zakładka i menu „…”.
            HStack(spacing: 6) {
                // Lista zakupów wchodzi stąd, a nie z dolnego menu: powstaje
                // z TEGO planu i ogląda się ją zaraz po jego ułożeniu.
                //
                // Plakietka z liczbą jest ceną za to przeniesienie. Zakupy
                // przestały być zakładką, więc nic na ekranie nie mówiło, że
                // coś w nich zostało — żeby się dowiedzieć, trzeba było
                // otworzyć arkusz. Teraz koszyk niesie tę jedną liczbę, która
                // ma znaczenie: ile produktów czeka na kupienie.
                EditorialIconButton(
                    icon: MenuConstans.Products.icon,
                    size: Self.headerActionSize,
                    tapTarget: 44
                ) {
                    simpleSheet = .products
                }
                .scCountBadge(shoppingRemainingCount)
                .accessibilityLabel(shoppingAccessibilityLabel)

                overflowMenu
            }
        }
    }

    /// Wszystko, co dotyczy CAŁEGO tygodnia, plus wybór soczewki.
    ///
    /// Skoki po tygodniach wyprowadziły się stąd na pasek dni. Zamiast nich
    /// wszedł asystent (skrót prosto do zakładki) i przełącznik profilu.
    private var overflowMenu: some View {
        Menu {
            // Prosto do zakładki asystenta, bez planszy pośrodku.
            Button {
                sessionStore.dashboardTab = .assistant
            } label: {
                Label("Zaplanuj tydzień z asystentem", systemImage: MenuConstans.Assistant.icon)
            }

            if members.count > 1 {
                Menu {
                    Button {
                        profile = .household
                    } label: {
                        Label(
                            "Cały dom",
                            systemImage: profile == .household ? "checkmark" : "house"
                        )
                    }

                    ForEach(members, id: \.id) { member in
                        Button {
                            profile = .member(member.id)
                        } label: {
                            Label(
                                HouseholdMemberStyle.shortName(member.displayName),
                                systemImage: profile.memberId == member.id ? "checkmark" : "person"
                            )
                        }
                    }
                } label: {
                    Label(profileMenuTitle, systemImage: "person.crop.circle")
                }
            }

            Divider()

            Button(role: .destructive) {
                showClearDayAlert = true
            } label: {
                Label(clearDayTitle, systemImage: "eraser")
            }
            Button(role: .destructive) {
                showClearWeekAlert = true
            } label: {
                Label("Wyczyść cały tydzień", systemImage: "trash")
            }
        } label: {
            // Ten sam krążek co `EditorialIconButton` obok, żeby akcje
            // nagłówka stały w jednym rytmie. 34 pt to rysunek; cel dotyku 44.
            SCCircleIconLabel(icon: "ellipsis", size: Self.headerActionSize, iconSize: 14)
                .scTapTarget(drawn: Self.headerActionSize)
        }
        .accessibilityLabel("Więcej opcji planu")
    }

    /// „Pokaż plan: cały dom” / „Pokaż plan: Ania”.
    private var profileMenuTitle: String {
        guard let id = profile.memberId,
              let member = members.first(where: { $0.id == id }) else {
            return "Pokaż plan: cały dom"
        }
        return "Pokaż plan: \(HouseholdMemberStyle.shortName(member.displayName))"
    }

    /// „Wyczyść poniedziałek”, „Wyczyść środę” — nazwa dnia w bierniku.
    ///
    /// Formy z `DateFormatter` są w mianowniku („środa”), a po „wyczyść” stoi
    /// biernik. Różnica dotyczy tylko trzech dni tygodnia, ale to akurat te,
    /// które najczęściej się czyści.
    private var clearDayTitle: String {
        let weekday = PlanWeek.calendar.component(.weekday, from: selectedDate)
        let names = [
            "niedzielę", "poniedziałek", "wtorek", "środę",
            "czwartek", "piątek", "sobotę"
        ]
        let index = max(0, min(names.count - 1, weekday - 1))
        return "Wyczyść \(names[index])"
    }

    /// Strona jednego dnia — oś czasu ze wszystkim, co w nim stoi.
    private func dayPage(for date: Date) -> some View {
        PlanDayTimeline(
            date: date,
            isToday: datesViewModel.isToday(date),
            isEditable: datesViewModel.isEditable(date),
            profile: profile,
            members: members,
            slots: visibleSlots(on: date),
            meals: { slot in visibleMeals(date: date, slot: slot) },
            extraSlots: extraSlots(on: date),
            onTapMeal: { slot, meal in openDetail(date: date, slot: slot, meal: meal) },
            onAddMeal: { slot in
                pickerTarget = PickerTarget(date: date, slot: slot, editing: nil)
            },
            onAddVariant: { slot in
                pickerTarget = PickerTarget(
                    date: date,
                    slot: slot,
                    editing: nil,
                    defaultParticipantIds: variantAudience(date: date, slot: slot)
                )
            },
            onEditMeal: { slot, meal in
                pickerTarget = PickerTarget(date: date, slot: slot, editing: meal)
            },
            onRemoveMeal: { slot, meal in
                removeMeal(date: date, slot: slot, meal: meal)
            },
            onPickExtraSlot: { slot in
                pickerTarget = PickerTarget(date: date, slot: slot, editing: nil)
            }
        )
        // Strona trzyma wspólny margines strony.
        .padding(.horizontal, SCPageMetrics.horizontal)
        // Przeszłość jest tylko do czytania — i ma to być widać, zanim
        // użytkownik dotknie wiersza i nic się nie stanie. 0,82, nie 0,72:
        // przygaszenie nakłada się na już przygaszone `scMuted` w metadanych
        // wiersza („60 min · 604 kcal") i przy 0,72 schodziły one poniżej
        // progu czytelności. Przełączenie tej wartości nie jest animowane
        // celowo — dzieje się między zjazdem a wjazdem strony w `DayPager`,
        // czyli poza ekranem.
        .opacity(datesViewModel.isEditable(date) ? 1 : 0.82)
    }

    // MARK: - Actions

    /// Prośba z zakładki „Dziś” (`PlanSlotRequest`): tydzień i dzień z prośby,
    /// a gdy dzień da się jeszcze planować — wybór przepisu na tę porę.
    ///
    /// Tydzień i dzień idą RAZEM do `datesViewModel` i do stanu ekranu: obie
    /// obserwacje wyżej (`isActiveTab`, `weekStartISO`) czytają dzień
    /// z modelu, więc w jakiejkolwiek kolejności SwiftUI je odpali, zostaje
    /// dzień z prośby.
    private func openPlanRequest(_ request: PlanSlotRequest) {
        datesViewModel.show(day: request.date)
        selectedDate = request.date
        guard let slot = request.slot, datesViewModel.isEditable(request.date) else { return }
        pickerTarget = PickerTarget(
            date: request.date,
            slot: slot,
            editing: nil,
            defaultParticipantIds: request.participantIds
        )
    }

    private func openDetail(date: Date, slot: MealSlot, meal: PlanMeal) {
        Task { @MainActor in
            let full = await recipeCatalogStore.loadRecipeDetail(recipeId: meal.recipe.id) ?? meal.recipe
            detailTarget = DetailTarget(date: date, slot: slot, meal: meal, recipe: full)
        }
    }

    /// Zapisuje liczbę porcji zmienioną stepperem w szczegółach.
    ///
    /// Audytorium zostaje takie, jakie było — użytkownik zmieniał porcje, a nie
    /// to, kto je danie. `plannedServings` idzie jawnie, więc serwer nie
    /// nadpisze go swoją regułą auto.
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
            refreshShoppingList()
        }
    }

    /// Zapisuje porcje osób ustawione w szczegółach. Posiłek z porcjami osób
    /// — każda zmieniona osoba osobnym `setPortion` z własnym tokenem;
    /// posiłek bez nich — pierwsze ustawienie: pełna mapa audytorium
    /// (`REPLACE`) z tokenem pozycji z tej samej migawki.
    private func savePortions(all: [String: Int], changed: [String: Int], for target: DetailTarget) {
        Task { @MainActor in
            if !target.meal.hasPortions {
                _ = await mealStore.upsertWeekSlot(
                    recipe: target.meal.recipe,
                    // Audytorium = klucze mapy (bez byłych domowników), inaczej
                    // serwer odrzuci mapę jako niepasującą do osób.
                    participantIds: target.meal.isShared ? [] : all.keys.sorted(),
                    householdMemberCount: knownHouseholdMemberCount,
                    portions: all,
                    expectedRevision: target.meal.revision,
                    for: target.date,
                    slot: target.slot,
                    weekStart: datesViewModel.weekStartISO
                )
                detailTarget = nil
                refreshShoppingList()
                return
            }
            _ = await mealStore.setPortions(
                changed,
                // Tokeny z posiłku, na którym użytkownik edytował — nie
                // z planu przeładowanego w tle (konflikt zamiast nadpisania).
                expectedRevisions: target.meal.portionRevisions,
                itemId: target.meal.id,
                for: target.date,
                slot: target.slot,
                weekStart: datesViewModel.weekStartISO
            )
            detailTarget = nil
            refreshShoppingList()
        }
    }

    private func removeMeal(date: Date, slot: MealSlot, meal: PlanMeal) {
        Task { @MainActor in
            let ok = await mealStore.removeWeekSlot(
                for: date,
                slot: slot,
                weekStart: datesViewModel.weekStartISO,
                recipe: meal.recipe
            )
            if ok { refreshShoppingList() }
        }
    }

    private func clearActiveDay() {
        let activeDay = selectedDate
        Task { @MainActor in
            for slot in MealSlot.allCases where !mealStore.meals(for: activeDay, slot: slot).isEmpty {
                _ = await mealStore.removeWeekSlot(
                    for: activeDay,
                    slot: slot,
                    weekStart: datesViewModel.weekStartISO
                )
            }
            refreshShoppingList()
        }
    }

    private func clearWeek() {
        // Policzone PRZED kasowaniem — po nim nie ma już czego liczyć, a to
        // jedyna liczba, która mówi, czy zniknęło to, co miało zniknąć.
        // Alert zapytać o to nie mógł: nikt tych posiłków wcześniej nie liczył.
        // Liczymy SLOTY, nie warianty: `allMeals` rozbija posiłek na osobne
        // wpisy dla każdego podziału audytorium, więc tydzień z codzienną
        // kolacją dla dwojga meldowałby czternaście posiłków tam, gdzie plan
        // pokazuje siedem. Reszta aplikacji też liczy slotami.
        let removed = datesViewModel.dates
            .map { mealStore.plan(for: $0).plannedSlots.count }
            .reduce(0, +)
        Task { @MainActor in
            let cleared = await mealStore.clearWeekFromBackend(
                weekStart: datesViewModel.weekStartISO,
                dates: datesViewModel.dates
            )
            // Sześć z siedmiu skasowanych dni jest poza ekranem: użytkownik
            // widzi, jak pustoszeje jeden, i gasnące kropki na pasku dni.
            if cleared {
                if removed > 0 {
                    toasts.success("Tydzień wyczyszczony", "Zniknęło \(PolishPlural.meals(removed)).")
                } else {
                    // „Zniknęło 0 posiłków" to zdanie, którego nikt by nie napisał.
                    toasts.success("Tydzień był już pusty")
                }
            } else {
                // Bez potwierdzenia przy nieudanym kasowaniu użytkownik zostaje
                // po alercie z niczym: przy braku sieci `errorMessage` jest
                // puste, więc most z korzenia też milczy.
                toasts.error("Nie udało się wyczyścić tygodnia", "Plan został bez zmian.")
            }
            refreshShoppingList()
        }
    }

    private func refreshShoppingList() {
        Task { @MainActor in
            await shoppingListStore.load(weekStart: datesViewModel.weekStartISO, force: true)
        }
    }

    private func prefetchWeekImages() {
        let urls = datesViewModel.dates
            .flatMap { date in MealSlot.allCases.flatMap { mealStore.meals(for: date, slot: $0) } }
            .compactMap(\.recipe.imageURL)
        ImagePrefetcher.prefetch(urls)
    }
}

#Preview {
    WeeklyPlanView()
}
