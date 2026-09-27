import SwiftUI

/// Wybiera przepis *i jego audytorium* dla jednej pary `(dzień, slot)` i pisze
/// go wprost do planu tygodnia — cel „Wybierz przepis” / „Zamień przepis”
/// z osi dnia (`PlanDayTimeline`).
///
/// Układ (runda 8, 23.09.2026) jest ten sam, co listy kategorii na
/// Przepisach, i stoi na tych samych klockach (`RecipeListKit.swift`):
/// nagłówek z kafelkiem pory i datą, szukanie, wiersze `EditorialRecipeRow`
/// — tu z kółkiem wyboru — a w stopce „Dla kogo” nad przyciskiem. Zawężanie
/// („Ulubione” i filtry kategorii tej pory) mieszka w arkuszu pod przyciskiem
/// filtrów; pigułek pod szukaniem i „Wszystkich pór” nie ma od rundy 10
/// (Rafał: „nie chcę jeść obiadu na śniadanie”, „od tego mamy filtry”). Wcześniej
/// arkusz miał własny nagłówek, własne pole szukania, przełącznik „Pasujące /
/// Wszystkie / Ulubione” i własne wiersze. Rafał: „żeby wszystko trzymało się
/// kupy, nie było nic, co jest odrębnie nowe”.
///
/// **Wybór, potem potwierdzenie — nie zapis od pierwszego stuknięcia.**
/// Poprzednia wersja zapisywała przepis w chwili stuknięcia w kafel, więc
/// rząd chipów „Dla kogo” trzeba było zauważyć i ustawić ZANIM się cokolwiek
/// dotknęło. Kto tego nie zrobił — a to jest domyślne zachowanie oka, które
/// szuka jedzenia, a nie ustawień — dostawał posiłek zapisany jako „Wspólne”
/// i nie miał gdzie tego odkręcić. Teraz stuknięcie zaznacza, a chipy stoją
/// tuż nad przyciskiem, który zapisuje.
struct PlanSlotPickerSheet: View {
    let date: Date
    let slot: MealSlot
    let weekStartISO: String
    let members: [HouseholdMemberSnapshot]
    /// Edytowany posiłek — zasiewa chipy audytorium i zaznacza swój przepis.
    /// `nil` dokłada do slotu nowy wariant.
    let editing: PlanMeal?
    /// Fires po potwierdzeniu zapisu przez serwer — już PO zamknięciu arkusza.
    /// Odświeżenie listy zakupów musi czekać na ack, nie na sam dismiss,
    /// inaczej pobiera listę policzoną ze starego planu.
    let onSaveCompleted: (() -> Void)?

    init(
        date: Date,
        slot: MealSlot,
        weekStartISO: String,
        members: [HouseholdMemberSnapshot],
        editing: PlanMeal?,
        defaultParticipantIds: [String] = [],
        onSaveCompleted: (() -> Void)? = nil
    ) {
        self.date = date
        self.slot = slot
        self.weekStartISO = weekStartISO
        self.members = members
        self.editing = editing
        self.onSaveCompleted = onSaveCompleted
        // Zasiane tutaj, a nie w `.task`: tamto szło po `await` na katalog
        // przepisów, więc chip stuknięty w międzyczasie był po cichu zerowany,
        // a posiłek zapisywał się jako „Wspólne”.
        _selectedParticipants = State(
            initialValue: Set(editing?.participantIds ?? defaultParticipantIds)
        )
        _selectedRecipeId = State(initialValue: editing?.recipe.id)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme

    // Te same klucze, co na widoku Przepisów. Bez nich wybór posiłku do planu
    // szedł po surowym katalogu i podsuwał wegetarianinowi schabowego —
    // dokładnie to danie, którego lista Przepisów mu nie pokazuje.
    @AppStorage(RecipePersonalization.Keys.diet)
    private var dietPreferenceRaw: String = DietPreference.none.rawValue
    @AppStorage(RecipePersonalization.Keys.allergens)
    private var allergensRaw: String = ""
    @AppStorage(RecipePersonalization.Keys.goal)
    private var goalRaw: String = UserGoal.healthy.rawValue
    @AppStorage(RecipePersonalization.Keys.calorieGoal)
    private var calorieGoal: Int = RecipePersonalization.defaultCalorieGoal
    @AppStorage(RecipePersonalization.Keys.enabled)
    private var isPersonalizationEnabled: Bool = true

    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    /// Tylko ulubione — kafelek „Ulubione” w arkuszu filtrów (dawniej segment
    /// „Ulubione”, potem pigułka pod szukaniem).
    @State private var favouritesOnly = false
    /// Filtry kategorii tej pory (smak, rodzaj dania, mięso) — te same opcje,
    /// co w liście kategorii na Przepisach, ale własne dla tego wyboru.
    @State private var categoryFilter = RecipeCategoryFilter()
    @State private var isFilterSheetPresented = false
    @State private var isSaving = false
    /// Pusty zbiór znaczy „Wspólne" — je całe gospodarstwo.
    @State private var selectedParticipants: Set<String> = []
    /// Zaznaczony przepis. `nil` = nic jeszcze nie wybrano, więc nie ma czego
    /// zapisać i przycisk stopki jest wyłączony.
    @State private var selectedRecipeId: UUID?

    // MARK: - Derived

    /// Kategoria, której filtry dostaje pora — II śniadanie i podwieczorek
    /// filtrują się jak przekąski, bo pod nie podpadają na Przepisach.
    private var category: RecipesCategory { slot.baseCategory }
    private var accent: Color { slot.cozyAccent }

    /// Przepisy, które w ogóle wolno wstawić w ten slot.
    ///
    /// Dopasowanie po `Recipe.fits(_:)`, a nie po kategorii bazowej: dzięki
    /// temu owsianka („Śniadania") pojawia się także w drugim śniadaniu
    /// i w przekąsce, o ile ma tam ustawiony slot.
    private var scopeCatalog: [Recipe] {
        let base = recipeCatalogStore.recipes.filter { $0.fits(slot) }
        return favouritesOnly ? base.filter { $0.favourite } : base
    }

    /// Filtry z arkusza (aspekty i „Ulubione”) — plakietka na przycisku.
    private var activeFilterCount: Int {
        categoryFilter.activeCount + (favouritesOnly ? 1 : 0)
    }

    private var personalization: RecipePersonalization {
        RecipePersonalization(
            dietRaw: dietPreferenceRaw,
            allergensRaw: allergensRaw,
            goalRaw: goalRaw,
            calorieGoal: calorieGoal,
            isEnabled: isPersonalizationEnabled
        )
    }

    /// Ile przepisów zabiera dieta / alergeny — do notki nad listą, żeby
    /// krótka lista nie wyglądała na brak danych.
    private var hiddenByPersonalizationCount: Int {
        personalization.hiddenCount(in: scopeCatalog)
    }

    /// Pula po dopasowaniu, przed filtrami kategorii i szukaniem — na niej
    /// liczy kafelki arkusz filtrów.
    ///
    /// Ta sama kolejność, co na Przepisach: najpierw preferencje (dieta
    /// i alergeny odsiewają, cel porządkuje), potem reszta.
    private var pool: [Recipe] {
        personalization.apply(to: scopeCatalog)
    }

    private var trimmedSearch: String {
        debouncedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleRecipes(in pool: [Recipe]) -> [Recipe] {
        var list = pool
        if categoryFilter.isActive {
            // W aspektach kategorii PORY, także dla dań z innych kategorii
            // (owsianka w II śniadaniu) — liczone po kategorii dania
            // wypadały przy każdym filtrze rodzaju.
            let filter = categoryFilter
            let facetCategory = category
            list = list.filter {
                filter.matches(RecipeFilterFactsCache.facetValues(for: $0, in: facetCategory))
            }
        }
        let query = trimmedSearch
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                $0.description.localizedCaseInsensitiveContains(query)
            }
        }
        return list
    }

    /// Audytorium w formie, którą rozumie backend. Zwijanie „wszyscy” do
    /// „Wspólne” i przecięcie z aktualnym składem siedzą w `PlanAudienceChips`,
    /// żeby oba wejścia do planu wysyłały identyczny payload.
    private var participantsToSave: [String] {
        PlanAudienceChips.collapsed(selectedParticipants, members: roster)
    }

    private var selectedRecipe: Recipe? {
        guard let selectedRecipeId else { return nil }
        return recipeCatalogStore.recipes.first { $0.id == selectedRecipeId }
            ?? editing?.recipe
    }

    /// Skład gospodarstwa — najpierw żywy ze `SessionStore`, a dopiero potem
    /// ten podany przy otwarciu arkusza.
    ///
    /// Arkusz dostaje listę jako `let`, więc gdy skład dojeżdżał z serwera
    /// PO jego otwarciu, chipy „Dla kogo” już się nie pojawiały — arkusz
    /// zostawał z pustą listą sprzed odpowiedzi.
    private var roster: [HouseholdMemberSnapshot] {
        sessionStore.householdMembers.isEmpty ? members : sessionStore.householdMembers
    }

    // MARK: - Body

    var body: some View {
        let available = pool
        let rows = visibleRecipes(in: available)

        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Przypięta góra — ta sama, co w liście kategorii.
                RecipeListSheetTop(searchPrompt: "Szukaj przepisu", searchText: $searchText) {
                    header
                }

                list(rows: rows, poolIsEmpty: available.isEmpty)

                footer(visible: rows)
            }
        }
        .task { await recipeCatalogStore.loadIfNeeded() }
        // Skład gospodarstwa dociągamy TAKŻE stąd, nie tylko z ekranu planu:
        // to tutaj jest jedyne miejsce, w którym brak domowników coś zmienia
        // (znikają chipy „Dla kogo”), więc arkusz nie może polegać na tym,
        // że ktoś przed nim zdążył listę pobrać.
        .task { await sessionStore.refreshHouseholdMembers(force: false) }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                debouncedSearch = newValue
            }
        }
        .onDisappear { searchDebounceTask?.cancel() }
        .sheet(isPresented: $isFilterSheetPresented) {
            RecipeCategoryFilterSheet(
                category: category,
                // Pula BEZ „tylko ulubionych” — kafelek „Ulubione” w arkuszu
                // liczy, ile z niej zostanie po zaznaczeniu.
                recipes: personalization.apply(to: recipeCatalogStore.recipes.filter { $0.fits(slot) }),
                filter: $categoryFilter,
                slot: slot,
                favouritesOnly: $favouritesOnly
            )
            .presentationDetents([.large])
            .dashboardLiquidSheet()
        }
    }

    // MARK: - Nagłówek

    private var header: some View {
        EditorialSheetHeader(
            eyebrow: slot.title,
            title: editing == nil ? "Wybierz przepis" : "Zmień przepis",
            icon: slot.icon,
            accent: accent,
            subtitle: dateLine,
            onClose: { dismiss() }
        ) {
            RecipeListFilterButton(count: activeFilterCount, accent: accent) {
                isFilterSheetPresented = true
            }
        }
    }

    /// „Środa, 23 września · 08:00” — slot bez stałej pory gubi ostatni człon
    /// razem z separatorem, zamiast zostawić wiszącą kropkę.
    private var dateLine: String {
        let day = Self.dayFormatter.string(from: date)
        var parts = [String(day.prefix(1)).uppercased() + String(day.dropFirst())]
        if let time = sessionStore.mealSlotSchedule.time(for: slot) {
            parts.append(time)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Lista

    private func list(rows: [Recipe], poolIsEmpty: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                    SCInlineErrorText(errorMessage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 8)
                }

                // Karta nad listą — ta sama, co w liście kategorii. Bez niej
                // krótka lista wygląda na brak przepisów, a nie na skutek
                // ustawień z zupełnie innego ekranu. Nad pustym stanem jej
                // nie ma — ten mówi o diecie sam.
                if !rows.isEmpty,
                   let diet = RecipeListContextCard.Row.personalization(
                       personalization,
                       hidden: hiddenByPersonalizationCount
                   ) {
                    RecipeListContextCard(rows: [diet])
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                if rows.isEmpty, !recipeCatalogStore.didLoad {
                    // Katalog jeszcze jedzie. „Brak wyników” w tym momencie
                    // to nieprawda, którą użytkownik czyta jako pustą apkę.
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else if rows.isEmpty {
                    emptyState(poolIsEmpty: poolIsEmpty)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                } else {
                    // Zaznaczenie działa jak pokrętło wyboru, nie jak
                    // checkbox: stuknięcie w zaznaczony wiersz go NIE
                    // odznacza. Odznaczenie w trybie edycji zostawiało arkusz
                    // bez przepisu do zapisania i wyszarzało przycisk, choć
                    // użytkownik chciał zmienić tylko to, dla kogo danie jest.
                    RecipeRowStack(
                        recipes: rows,
                        mode: .select(selectedRecipeId),
                        accent: accent
                    ) { recipe in
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                            selectedRecipeId = recipe.id
                        }
                    }
                }
            }
            .padding(.top, 8)
            // Zapas na cień stopki (`SCEdgeShade`), który leży na liście.
            .padding(.bottom, SCEdgeShade.bottomHeight)
        }
        .scrollIndicators(.hidden)
        .scScrollEdgeFade()
        // Przewijanie listy chowa klawiaturę — inaczej zasłania ona przycisk
        // potwierdzenia dokładnie wtedy, gdy użytkownik znalazł już przepis.
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.selection, trigger: selectedRecipeId)
        // Lista jest jedyną przewijaną częścią arkusza — góra z szukaniem
        // i stopka z „Dla kogo” stoją, bo obie odpowiadają na pytanie
        // „co się stanie, gdy stuknę”, i muszą być widoczne w tej chwili.
        .frame(maxHeight: .infinity)
    }

    /// Pusty stan mówi, co opróżniło listę, a przycisk zdejmuje dokładnie to
    /// — karta z kafelkiem powodu (`RecipeListEmptyState`).
    private func emptyState(poolIsEmpty: Bool) -> some View {
        let forSlot = "na \(slot.accusativeName)"
        let hasFilters = categoryFilter.isActive || favouritesOnly
        let clearFilters = RecipeListEmptyState.Action(title: "Wyczyść filtry") {
            withAnimation(.smooth(duration: 0.2)) {
                categoryFilter = RecipeCategoryFilter()
                favouritesOnly = false
            }
        }

        if !trimmedSearch.isEmpty {
            return RecipeListEmptyState(
                icon: "magnifyingglass",
                accent: accent,
                title: "Brak wyników",
                message: "Nic \(forSlot) nie pasuje do tej frazy. Spróbuj innej.",
                actions: hasFilters ? [clearFilters] : []
            )
        }
        if categoryFilter.isActive, !poolIsEmpty {
            return RecipeListEmptyState(
                icon: "line.3.horizontal.decrease",
                accent: accent,
                title: "Nic nie pasuje do filtrów",
                message: "Poluzuj filtry, żeby zobaczyć przepisy \(forSlot).",
                actions: [clearFilters]
            )
        }
        if favouritesOnly, scopeCatalog.isEmpty {
            return RecipeListEmptyState(
                icon: "heart",
                accent: SCPalette.terracotta,
                title: "Brak ulubionych \(forSlot)",
                message: "Przepis dodasz do ulubionych sercem w jego szczegółach.",
                actions: [
                    .init(title: "Pokaż wszystkie przepisy", icon: "list.bullet") {
                        withAnimation(.smooth(duration: 0.2)) { favouritesOnly = false }
                    }
                ]
            )
        }
        if !scopeCatalog.isEmpty {
            return RecipeListEmptyState(
                icon: personalization.diet == .none ? "exclamationmark.shield" : personalization.diet.icon,
                accent: personalization.diet == .none ? SCPalette.terracotta : personalization.diet.accent,
                title: personalization.diet == .none ? "Alergeny ukrywają wszystko" : "Dieta ukrywa wszystko",
                message: favouritesOnly
                    ? "Twoja dieta i alergeny ukrywają wszystkie ulubione przepisy \(forSlot)."
                    : "Twoja dieta i alergeny ukrywają wszystkie przepisy \(forSlot).",
                actions: favouritesOnly ? [clearFilters] : []
            )
        }
        return RecipeListEmptyState(
            icon: slot.icon,
            accent: accent,
            title: "Brak przepisów \(forSlot)",
            message: "Żaden przepis nie ma jeszcze oznaczenia \u{201E}\(slot.title)\u{201D}."
        )
    }

    // MARK: - Stopka

    /// „Dla kogo” stoi tuż nad przyciskiem, a nie w nim.
    ///
    /// W przycisku musiałoby stać „Dodaj dla Zosi”, czyli imię w dopełniaczu —
    /// a polskiej odmiany imion nie da się wyliczyć regułą, która nie kaleczy
    /// co dziesiątego („Marek” → „Marka”, ale „Paweł” → „Pawła”). Chipy mówią
    /// to samo w mianowniku, pokazują twarze i dają się przestawić w miejscu,
    /// w którym zapada decyzja.
    private func footer(visible rows: [Recipe]) -> some View {
        SCSheetFooter {
            if let selected = selectedRecipe, !rows.contains(where: { $0.id == selected.id }) {
                hiddenSelection(selected)
            }

            audience

            // Ten sam przycisk, co w każdym innym arkuszu aplikacji: terakota
            // w wariancie „soft” (tint + obwódka, bez gradientu i cienia).
            EditorialPrimaryActionButton(
                title: ctaTitle,
                icon: ctaIcon,
                isEnabled: selectedRecipeId != nil,
                isLoading: isSaving,
                // Domknięcie, nie goła referencja do metody — projekt ma
                // włączone `InferSendableFromCaptures` (SE-0418) i referencje
                // metod w takich miejscach potrafią rozjechać wnioskowanie
                // typu z błędem wskazującym zupełnie inną linię.
                action: { confirm() }
            )
        }
    }

    /// Zaznaczony przepis, którego nie ma już na liście (schowały go filtry,
    /// ulubione albo szukanie) — przycisk pod spodem zapisze właśnie jego,
    /// więc musi być widać, co to jest.
    private func hiddenSelection(_ recipe: Recipe) -> some View {
        HStack(spacing: 10) {
            EditorialRecipeCover(recipe: recipe, size: 28, cornerRadius: 8)

            Text(recipe.name)
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)

            Spacer(minLength: 8)

            SCRadioMark(isOn: true, size: 18)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wybrany przepis: \(recipe.name)")
    }

    /// Chipy domowników, a gdy nie ma z kogo wybierać — zdanie mówiące dlaczego.
    ///
    /// Cichy brak tego rzędu był najgorszą z możliwych odpowiedzi: dom
    /// jednoosobowy dostawał arkusz bez śladu po tym, że przypisywanie dań
    /// konkretnym osobom w ogóle istnieje, i wyglądało to jak brakująca
    /// funkcja, a nie jak brak domowników.
    @ViewBuilder
    private var audience: some View {
        if roster.count > 1 {
            PlanAudienceChips(
                members: roster,
                selection: $selectedParticipants
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))

                Text("Dla Ciebie · domowników dodasz w Ustawieniach")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var ctaTitle: String {
        guard let editing else { return "Dodaj do planu" }
        return selectedRecipeId == editing.recipe.id ? "Zapisz zmiany" : "Zamień przepis"
    }

    private var ctaIcon: String {
        guard let editing else { return "plus" }
        return selectedRecipeId == editing.recipe.id ? "checkmark" : "arrow.2.squarepath"
    }

    private var canConfirm: Bool {
        !isSaving && selectedRecipeId != nil
    }

    // MARK: - Actions

    private func confirm() {
        guard canConfirm else { return }
        if let editing, selectedRecipeId == editing.recipe.id {
            saveAudienceOnly(editing)
        } else if let recipe = selectedRecipe {
            assign(recipe)
        }
    }

    private func assign(_ recipe: Recipe) {
        isSaving = true
        // Arkusz zamyka się od razu: wpis optymistyczny ląduje w store przed
        // wyjściem w sieć, więc plan pod spodem już pokazuje wybór. Błąd
        // zapisu wraca rollbackiem w store i komunikatem `errorMessage`
        // na widoku planu.
        let store = mealStore
        let completion = onSaveCompleted
        // Ten sam przepis już stoi w tej porze dla kogoś innego — dokładamy
        // osoby, zamiast przepisać audytorium (i zostawić tamtą osobę bez
        // posiłku). Obejmuje cały dom → zapis jako „Wspólne”.
        let existing = mealStore.meals(for: date, slot: slot).first {
            $0.recipe.id == recipe.id && $0.recipe.id != editing?.recipe.id
        }
        let participants = PlanAudienceChips.merged(participantsToSave, with: existing, members: roster)
        Task { @MainActor in
            _ = await store.upsertWeekSlot(
                recipe: recipe,
                participantIds: participants,
                // Ten arkusz nie ma steppera porcji, więc świadomie nie wysyła
                // pola — a pominięcie znaczy dla serwera „nie ruszaj tego, co
                // wybrał użytkownik". Na nowym wpisie policzy porcje
                // z audytorium („Wspólne" = liczba domowników); na istniejącym
                // zostawi zapisaną wartość, a przeliczy ją tylko wtedy, gdy
                // nikt jej wcześniej ręcznie nie nadpisał.
                plannedServings: nil,
                // Liczba domowników jest potrzebna do optymistycznego wpisu:
                // bez niej „Wspólne" migałoby jedną porcją, zanim przyjdzie
                // odpowiedź serwera. Pusta lista to brak odpowiedzi, nie dom
                // jednoosobowy.
                householdMemberCount: roster.isEmpty ? nil : roster.count,
                // W trybie edycji inny przepis PODMIENIA edytowany posiłek,
                // zamiast dokładać do slotu drugi wariant.
                replacingRecipeId: editing?.recipe.id,
                for: date,
                slot: slot,
                weekStart: weekStartISO
            )
            completion?()
        }
        dismiss()
    }

    /// „Zapisz zmiany” w trybie edycji — przepis zostaje, zmienia się to,
    /// dla kogo jest.
    private func saveAudienceOnly(_ editing: PlanMeal) {
        isSaving = true
        let store = mealStore
        let completion = onSaveCompleted
        Task { @MainActor in
            _ = await store.upsertWeekSlot(
                recipe: editing.recipe,
                participantIds: participantsToSave,
                // Porcji nie wysyłamy z tego samego powodu, co w `assign`.
                householdMemberCount: roster.isEmpty ? nil : roster.count,
                for: date,
                slot: slot,
                weekStart: weekStartISO
            )
            completion?()
        }
        dismiss()
    }

    /// „środa, 23 września” — pełna nazwa miesiąca w dopełniaczu.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEEE, d MMMM"
        return f
    }()
}
