import SwiftUI

/// Picks a recipe *and its audience* for a single `(day, slot)` pair and writes
/// it straight to the week plan — the `+ Dodaj` / „Zmień przepis" target of
/// Plan v2.
///
/// The audience chips sit above the grid and default to „Wspólne", so adding a
/// normal household meal stays a single tap. Naming people instead is what
/// turns the slot into a „Każdy je inaczej" split.
///
/// To nie jest już jedyne wejście do planu: szczegół przepisu ma własny arkusz
/// „Dodaj do planu", z tym samym rzędem chipów (`PlanAudienceChips`) i dodatkowo
/// ze stepperem porcji. Ten arkusz zostaje wejściem „od strony planu" — startuje
/// od znanego `(dzień, slot)` i pyta o przepis. Kalendarz otwiera go tak samo,
/// więc obie zakładki przypisują identycznie.
struct PlanSlotPickerSheet: View {
    let date: Date
    let slot: MealSlot
    let weekStartISO: String
    let members: [HouseholdMemberSnapshot]
    /// Meal being edited — preloads the audience chips and highlights its
    /// recipe. `nil` adds a new variant to the slot.
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
        // Seeded here rather than in `.task`: that ran after `await`ing the
        // recipe catalog, so a chip tapped in the meantime was silently reset
        // and the meal saved as „Wspólne".
        _selectedParticipants = State(
            initialValue: Set(editing?.participantIds ?? defaultParticipantIds)
        )
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.weeklyMealStore) private var mealStore
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore

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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var onlyFavourites = false
    /// Zdejmuje zawężenie do slotu i pokazuje cały katalog.
    ///
    /// Potrzebne z dwóch powodów. Pierwszy jest przejściowy: dopóki katalog
    /// nie przejdzie klasyfikacji slotów, świeżo włączony podwieczorek nie
    /// ma czego pokazać. Drugi zostaje na stałe — czasem na podwieczorek je
    /// się wczorajszy obiad i aplikacja nie ma prawa tego zabronić.
    @State private var showsWholeCatalog = false
    @State private var isSaving = false
    /// Empty means „Wspólne" — the whole household eats it.
    @State private var selectedParticipants: Set<String> = []

    // MARK: - Derived

    /// Przepisy, które w ogóle wolno wstawić w ten slot.
    ///
    /// Dopasowanie po `Recipe.fits(_:)`, a nie po kategorii bazowej: dzięki
    /// temu owsianka („Śniadania") pojawia się także w drugim śniadaniu
    /// i w przekąsce, o ile ma tam ustawiony slot. Bez tego dodatkowe posiłki
    /// startowałyby z pustą listą i wyglądałyby na zepsute.
    private var slotCatalog: [Recipe] {
        guard !showsWholeCatalog else { return recipeCatalogStore.recipes }
        return recipeCatalogStore.recipes.filter { $0.fits(slot) }
    }

    /// Ile dań przepada przez zawężenie do slotu — do przypisu i do decyzji,
    /// czy w ogóle pokazać wyjście awaryjne.
    private var hiddenBySlotCount: Int {
        guard !showsWholeCatalog else { return 0 }
        return recipeCatalogStore.recipes.filter { !$0.fits(slot) }.count
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

    /// Ile przepisów w tym slocie zabiera dieta / alergeny — do notki nad
    /// siatką, żeby krótka lista nie wyglądała na brak danych.
    private var hiddenByPersonalizationCount: Int {
        personalization.hiddenCount(
            in: slotCatalog
        )
    }

    private var filtered: [Recipe] {
        // Ta sama kolejność, co na Przepisach: najpierw preferencje (dieta
        // i alergeny odsiewają, cel porządkuje), potem lokalne zawężenia.
        var list = personalization.apply(to: slotCatalog)
        if onlyFavourites {
            list = list.filter(\.favourite)
        }
        if !debouncedSearch.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(debouncedSearch) ||
                $0.description.localizedCaseInsensitiveContains(debouncedSearch)
            }
        }
        return list
    }

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 2 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    private func cardWidth(for total: CGFloat) -> CGFloat {
        let count: CGFloat = horizontalSizeClass == .compact ? 2 : 3
        let horizontalPadding: CGFloat = 44   // 22pt each side
        let spacing: CGFloat = 12 * (count - 1)
        return max(150, floor((total - horizontalPadding - spacing) / count))
    }

    /// Audience to persist. Zwijanie „wszyscy" do „Wspólne" i przecięcie
    /// z aktualnym składem gospodarstwa siedzą teraz w `PlanAudienceChips`,
    /// żeby oba arkusze wysyłały identyczny payload.
    private var participantsToSave: [String] {
        PlanAudienceChips.collapsed(selectedParticipants, members: members)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    WMPageBackground(scheme: scheme)
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header

                            // Jednoosobowe gospodarstwo nie ma czego wybierać —
                            // każdy posiłek i tak jest „Wspólne".
                            if members.count > 1 {
                                PlanAudienceChips(
                                    members: members,
                                    selection: $selectedParticipants
                                )
                            }

                            if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            if showsWholeCatalog {
                                wholeCatalogNote
                            }

                            if hiddenByPersonalizationCount > 0 {
                                personalizationNote
                            }

                            if filtered.isEmpty {
                                emptyState
                            } else {
                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(filtered) { recipe in
                                        card(recipe: recipe, width: cardWidth(for: proxy.size.width))
                                            .task {
                                                await recipeCatalogStore.loadNextPageIfNeeded(
                                                    currentItemId: recipe.id,
                                                    threshold: 8
                                                )
                                            }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle(slot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if editing != nil {
                        Button("Zapisz") { saveAudienceOnly() }
                            .font(.body.weight(.semibold))
                            .disabled(isSaving)
                    } else {
                        favouritesToggle
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Szukaj przepisów")
            .task { await recipeCatalogStore.loadIfNeeded() }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    debouncedSearch = newValue
                }
            }
            .onDisappear { searchDebounceTask?.cancel() }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(slot.title.uppercased()) · \(Self.dayFormatter.string(from: date).uppercased())")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(slot.cozyAccent)

            Text(editing == nil ? "Wybierz przepis" : "Zmień przepis")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.wmLabel(scheme))

            Text(
                members.count > 1
                    ? "Wybierz dla kogo, potem stuknij przepis."
                    : "Jedno stuknięcie przypisuje przepis do tego dnia."
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.wmMuted(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favouritesToggle: some View {
        Button {
            onlyFavourites.toggle()
        } label: {
            Image(systemName: onlyFavourites ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(onlyFavourites ? WMPalette.terracotta : Color.wmMuted(scheme))
        }
        .accessibilityLabel(onlyFavourites ? "Pokaż wszystkie przepisy" : "Pokaż tylko ulubione")
    }

    private func card(recipe: Recipe, width: CGFloat) -> some View {
        let isCurrent = recipe.id == editing?.recipe.id

        return Button {
            assign(recipe)
        } label: {
            RecipeCarouselCard(
                recipe: recipe,
                width: width,
                selectionCount: isCurrent ? 1 : 0,
                showsHeart: !isCurrent
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrent ? "\(recipe.name), obecnie przypisany" : recipe.name)
    }

    /// Notka nad siatką. Bez niej krótka lista wygląda na brak przepisów,
    /// a nie na skutek ustawień z zupełnie innego ekranu — tak samo jak
    /// „Lista zawężona filtrami" w arkuszu kategorii na Przepisach.
    private var personalizationNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .bold))

            Text(personalizationNoteText)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(WMPalette.sage.mix(black: 0.20))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WMPalette.sage.opacity(scheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WMPalette.sage.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var personalizationNoteText: String {
        let count = hiddenByPersonalizationCount
        let noun = RecipeCountNoun.label(for: count)
        return "Ukryto \(count) \(noun) spoza Twojej diety i alergenów."
    }

    /// Widoczna tylko po ręcznym zdjęciu zawężenia — informuje, że lista nie
    /// jest już listą „pod ten posiłek", i pozwala jednym stuknięciem wrócić.
    /// Bez tego użytkownik zostawałby w trybie, o którego włączeniu zdążył
    /// zapomnieć, i dziwił się, czemu na przekąskę podsuwana jest zapiekanka.
    private var wholeCatalogNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 11, weight: .bold))

            Text("Pokazujemy cały katalog, nie tylko dania oznaczone jako \u{201E}\(slot.title)\u{201D}.")
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button("Zawęź") {
                withAnimation(.smooth(duration: 0.2)) { showsWholeCatalog = false }
            }
            .font(.system(size: 12, weight: .bold))
            .buttonStyle(.plain)
        }
        .foregroundStyle(WMPalette.terracotta)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WMPalette.terracotta.opacity(0.28), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.wmMuted(scheme))

            Text("Brak wyników")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.wmLabel(scheme))

            Text(emptyStateHint)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.wmMuted(scheme))
                .multilineTextAlignment(.center)

            if hiddenBySlotCount > 0 {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { showsWholeCatalog = true }
                } label: {
                    Text("Pokaż wszystkie przepisy")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(WMPalette.terracotta)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.16 : 0.10))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptyStateHint: String {
        if !debouncedSearch.isEmpty { return "Spróbuj innej frazy." }
        if hiddenBySlotCount > 0 {
            return "Żaden przepis nie ma jeszcze oznaczenia \u{201E}\(slot.title)\u{201D}."
        }
        return "Spróbuj zmienić filtr."
    }

    // MARK: - Actions

    private func assign(_ recipe: Recipe) {
        guard !isSaving else { return }
        isSaving = true
        // Arkusz zamyka się od razu: wpis optymistyczny ląduje w store przed
        // wyjściem w sieć, więc plan pod spodem już pokazuje wybór. Czekanie
        // na ack (w edycji: dwa round-tripy po sockecie) przetrzymywało
        // arkusz ~pół sekundy z przygaszoną siatką. Błąd zapisu wraca
        // rollbackiem w store i komunikatem `errorMessage` na widoku planu.
        let store = mealStore
        let completion = onSaveCompleted
        Task { @MainActor in
            _ = await store.upsertWeekSlot(
                recipe: recipe,
                participantIds: participantsToSave,
                // Ten arkusz nie ma steppera porcji, więc świadomie nie wysyła
                // pola — a pominięcie znaczy dla serwera „nie ruszaj tego, co
                // wybrał użytkownik". Na nowym wpisie policzy porcje
                // z audytorium („Wspólne" = liczba domowników); na istniejącym
                // zostawi zapisaną wartość, a przeliczy ją tylko wtedy, gdy
                // nikt jej wcześniej ręcznie nie nadpisał (czyli równała się
                // regule auto ze starego audytorium). Dzięki temu zmiana
                // chipów nie kasuje świadomego „gotuję 4 porcje", a przełączenie
                // „Wspólne → tylko ja" nie zostawia porcji dla dwojga.
                plannedServings: nil,
                // Liczba domowników jest potrzebna do optymistycznego wpisu:
                // bez niej „Wspólne" migałoby jedną porcją, zanim przyjdzie
                // odpowiedź serwera. Pusta lista to brak odpowiedzi, nie dom
                // jednoosobowy — wtedy porcje liczy serwer i przysyła je
                // w potwierdzeniu zapisu.
                householdMemberCount: members.isEmpty ? nil : members.count,
                // In edit mode a different pick replaces the meal being edited
                // rather than piling a second variant into the slot.
                replacingRecipeId: editing?.recipe.id,
                for: date,
                slot: slot,
                weekStart: weekStartISO
            )
            completion?()
        }
        dismiss()
    }

    /// „Zapisz" in edit mode — keeps the recipe, rewrites who it is for.
    private func saveAudienceOnly() {
        guard let editing, !isSaving else { return }
        isSaving = true
        // Ten sam natychmiastowy dismiss, co w `assign` — wpis optymistyczny
        // już stoi, ack dogania w tle.
        let store = mealStore
        let completion = onSaveCompleted
        Task { @MainActor in
            _ = await store.upsertWeekSlot(
                recipe: editing.recipe,
                participantIds: participantsToSave,
                // Porcji nie wysyłamy z tego samego powodu, co w `assign`:
                // ten arkusz zmienia wyłącznie audytorium, a pominięte pole
                // zostawia ręcznie ustawioną liczbę porcji w spokoju.
                householdMemberCount: members.isEmpty ? nil : members.count,
                for: date,
                slot: slot,
                weekStart: weekStartISO
            )
            completion?()
        }
        dismiss()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEEE, d MMM"
        return f
    }()
}
