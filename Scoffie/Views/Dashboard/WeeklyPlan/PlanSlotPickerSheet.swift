import SwiftUI

/// Wybiera przepis *i jego audytorium* dla jednej pary `(dzień, slot)` i pisze
/// go wprost do planu tygodnia — cel „Wybierz przepis” / „Zamień przepis”
/// z osi dnia (`PlanDayTimeline`).
///
/// Źródło układu: canvas claude.ai → „Weekly Meals - Plan v2.html”, artboard F1
/// (`components/plan-v2-edit.jsx`, `P2PickSheet`).
///
/// **Wybór, potem potwierdzenie — nie zapis od pierwszego stuknięcia.**
/// Poprzednia wersja zapisywała przepis w chwili stuknięcia w kafel, więc
/// rząd chipów „Dla kogo” trzeba było zauważyć i ustawić ZANIM się cokolwiek
/// dotknęło. Kto tego nie zrobił — a to jest domyślne zachowanie oka, które
/// szuka jedzenia, a nie ustawień — dostawał posiłek zapisany jako „Wspólne”
/// i nie miał gdzie tego odkręcić. Teraz stuknięcie zaznacza, a stopka mówi
/// wprost, dla kogo danie poleci, zanim poleci.
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
    @State private var scope: Scope = .fitting
    @State private var isSaving = false
    /// Pusty zbiór znaczy „Wspólne" — je całe gospodarstwo.
    @State private var selectedParticipants: Set<String> = []
    /// Zaznaczony przepis. `nil` = nic jeszcze nie wybrano, więc nie ma czego
    /// zapisać i przycisk stopki jest wyłączony.
    @State private var selectedRecipeId: UUID?

    /// Zakres listy. Zastąpił dwa osobne przełączniki („tylko ulubione”
    /// w pasku narzędzi i ukryte „pokaż cały katalog” w notce), których razem
    /// nie dało się odczytać z ekranu — teraz widać wprost, którą listę się
    /// ogląda.
    private enum Scope: String, CaseIterable, Identifiable {
        case fitting, all, favourites
        var id: String { rawValue }

        var title: String {
            switch self {
            case .fitting:    return "Pasujące"
            case .all:        return "Wszystkie"
            case .favourites: return "Ulubione"
            }
        }
    }

    // MARK: - Derived

    /// Przepisy, które w ogóle wolno wstawić w ten slot.
    ///
    /// Dopasowanie po `Recipe.fits(_:)`, a nie po kategorii bazowej: dzięki
    /// temu owsianka („Śniadania") pojawia się także w drugim śniadaniu
    /// i w przekąsce, o ile ma tam ustawiony slot.
    private var scopeCatalog: [Recipe] {
        switch scope {
        case .fitting:    return recipeCatalogStore.recipes.filter { $0.fits(slot) }
        case .all:        return recipeCatalogStore.recipes
        case .favourites: return recipeCatalogStore.recipes.filter(\.favourite)
        }
    }

    /// Ile dań przepada przez zawężenie do slotu — do decyzji, czy pokazać
    /// wyjście awaryjne w pustym stanie.
    private var hiddenBySlotCount: Int {
        recipeCatalogStore.recipes.filter { !$0.fits(slot) }.count
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

    private var filtered: [Recipe] {
        // Ta sama kolejność, co na Przepisach: najpierw preferencje (dieta
        // i alergeny odsiewają, cel porządkuje), potem szukanie.
        var list = personalization.apply(to: scopeCatalog)
        if !debouncedSearch.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(debouncedSearch) ||
                $0.description.localizedCaseInsensitiveContains(debouncedSearch)
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

    // MARK: - Body

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                controls
                    .padding(.horizontal, 20)

                // Kreska pod sterowaniem, żeby przewijana lista miała o co się
                // zatrzymać. Bez niej pierwszy wiersz dojeżdżał wprost pod
                // przełącznik zakresu i wyglądał, jakby padding się urwał.
                Rectangle()
                    .fill(Color.scRule(scheme))
                    .frame(height: 1)
                    .padding(.top, 14)

                list

                footer
            }
            .padding(.top, 18)
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
    }

    // MARK: - Góra arkusza

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            audienceSection
                .padding(.top, 18)

            searchField
                .padding(.top, 14)

            scopePicker
                .padding(.top, 10)

            if let errorMessage = mealStore.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 10)
            }
        }
    }

    /// „Dla kogo” — chipy, a gdy nie ma z kogo wybierać, zdanie mówiące dlaczego.
    ///
    /// Cichy brak tego rzędu był najgorszą z możliwych odpowiedzi: dom
    /// jednoosobowy dostawał arkusz bez śladu po tym, że przypisywanie dań
    /// konkretnym osobom w ogóle istnieje, i wyglądało to jak brakująca
    /// funkcja, a nie jak brak domowników.
    @ViewBuilder
    private var audienceSection: some View {
        if roster.count > 1 {
            PlanAudienceChips(
                members: roster,
                selection: $selectedParticipants
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("DLA KOGO")
                    .scFont(9, weight: .bold, relativeTo: .caption2)
                    .tracking(2)
                    .foregroundStyle(Color.scMuted(scheme))

                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))

                    Text("Na razie planujesz dla siebie. Dodaj domownika w Ustawieniach, żeby przypisywać dania konkretnym osobom.")
                        .scFont(12, weight: .medium, relativeTo: .caption)
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
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

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(contextLine)
                    .scFont(10, weight: .bold, relativeTo: .caption2)
                    .tracking(2)
                    .foregroundStyle(slot.cozyAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(editing == nil ? "Wybierz przepis" : "Zmień przepis")
                    .scFont(24, weight: .bold, relativeTo: .title2)
                    .tracking(-0.5)
                    .foregroundStyle(Color.scLabel(scheme))
            }

            Spacer(minLength: 8)

            SCSheetCloseButton { dismiss() }
        }
    }

    /// „OBIAD · PONIEDZIAŁEK, 8 WRZ · 14:00” — slot bez stałej pory gubi ostatni człon
    /// razem z separatorem, zamiast zostawić wiszącą kropkę.
    private var contextLine: String {
        var parts = [
            slot.title.uppercased(),
            Self.dayFormatter.string(from: date).uppercased()
        ]
        if let time = sessionStore.mealSlotSchedule.time(for: slot) {
            parts.append(time)
        }
        return parts.joined(separator: " · ")
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.scFaint(scheme))

            TextField("Szukaj w przepisach", text: $searchText)
                .textFieldStyle(.plain)
                .scFont(15, weight: .regular, relativeTo: .subheadline)
                .foregroundStyle(Color.scLabel(scheme))
                .submitLabel(.search)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść szukanie")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(Scope.allCases) { option in
                let isOn = option == scope
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        scope = option
                    }
                } label: {
                    Text(option.title)
                        .scFont(13.5, weight: .semibold, relativeTo: .footnote)
                        .tracking(-0.2)
                        .foregroundStyle(isOn ? Color.scLabel(scheme) : Color.scMuted(scheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.scTileBg(scheme))
                                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                    // Zaznaczenie SUWA się między segmentami,
                                    // zamiast gasnąć w jednym i zapalać w drugim.
                                    .matchedGeometryEffect(id: "scope", in: scopeNS)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.scChipBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    @Namespace private var scopeNS

    // MARK: - Lista

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if hiddenByPersonalizationCount > 0 {
                    personalizationNote
                        .padding(.bottom, 6)
                }

                if filtered.isEmpty, !recipeCatalogStore.didLoad {
                    // Katalog jeszcze jedzie. „Brak wyników” w tym momencie
                    // to nieprawda, którą użytkownik czyta jako pustą apkę.
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, recipe in
                        row(recipe, isLast: index == filtered.count - 1)
                            .task {
                                await recipeCatalogStore.loadNextPageIfNeeded(
                                    currentItemId: recipe.id,
                                    threshold: 8
                                )
                            }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        // Przewijanie listy chowa klawiaturę — inaczej zasłania ona przycisk
        // potwierdzenia dokładnie wtedy, gdy użytkownik znalazł już przepis.
        .scrollDismissesKeyboard(.interactively)
        // Lista jest jedyną przewijaną częścią arkusza — góra z chipami
        // i stopka z przyciskiem stoją, bo obie odpowiadają na pytanie
        // „co się stanie, gdy stuknę”, i muszą być widoczne w tej chwili.
        .frame(maxHeight: .infinity)
    }

    private func row(_ recipe: Recipe, isLast: Bool) -> some View {
        let isOn = recipe.id == selectedRecipeId

        // Zaznaczenie działa jak pokrętło wyboru, nie jak checkbox: stuknięcie
        // w zaznaczony wiersz go NIE odznacza. Odznaczenie w trybie edycji
        // zostawiało arkusz bez przepisu do zapisania i wyszarzało przycisk,
        // choć użytkownik chciał zmienić tylko to, dla kogo danie jest.
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                selectedRecipeId = recipe.id
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    thumbnail(recipe)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.name)
                            .scFont(15.5, weight: .semibold, relativeTo: .subheadline)
                            .tracking(-0.3)
                            .foregroundStyle(Color.scLabel(scheme))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Text("\(recipe.prepTimeMinutes) min · \(Int(recipe.nutritionPerServing.kcal.rounded())) kcal")
                            .scFont(12.5, weight: .regular, relativeTo: .caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.scMuted(scheme))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    selectionMark(isOn: isOn)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())

                if !isLast {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                }
            }
        }
        .buttonStyle(PlanPressStyle(scale: 0.99))
        .accessibilityLabel(recipe.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func selectionMark(isOn: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isOn ? SCPalette.terracotta : .clear)
            Circle()
                .stroke(
                    isOn ? .clear : Color.scLabel(scheme).opacity(0.22),
                    lineWidth: 1.6
                )
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
    }

    /// Zdjęcie albo kafel zastępczy — jedno ALBO drugie.
    ///
    /// Warstwowy `ZStack` ze zdjęciem dochodzącym zanikiem nad kaflem zostawiał
    /// przepisy bez widocznego zdjęcia: zanik startował od `opacity(0)`
    /// i sterował nim `onAppear`, więc gdy nie doszedł, na wierzchu stał
    /// przezroczysty obrazek. Tu jest ten sam kształt, co w `RecipeCarouselCard`.
    private func thumbnail(_ recipe: Recipe) -> some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderThumb
                    }
                }
            } else {
                placeholderThumb
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var placeholderThumb: some View {
        ZStack {
            LinearGradient(
                colors: [slot.cozyTint, slot.cozyTint.mix(black: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            PlanDiagonalHatch(color: .white.opacity(0.07))

            Image(systemName: slot.icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    /// Notka nad listą. Bez niej krótka lista wygląda na brak przepisów,
    /// a nie na skutek ustawień z zupełnie innego ekranu.
    private var personalizationNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .bold))

            Text("Ukryto \(hiddenByPersonalizationCount) \(PolishPlural.recipesNoun(hiddenByPersonalizationCount)) spoza Twojej diety i alergenów.")
                .scFont(12, weight: .semibold, relativeTo: .caption)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(SCPalette.sage.mix(black: 0.20))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SCPalette.sage.opacity(scheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SCPalette.sage.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))

            Text("Brak wyników")
                .scFont(17, weight: .bold, relativeTo: .body)
                .foregroundStyle(Color.scLabel(scheme))

            Text(emptyStateHint)
                .scFont(13, weight: .medium, relativeTo: .footnote)
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)

            if scope == .fitting, hiddenBySlotCount > 0, debouncedSearch.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                        scope = .all
                    }
                } label: {
                    Text("Pokaż wszystkie przepisy")
                        .scFont(13.5, weight: .semibold, relativeTo: .footnote)
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .scSoftCapsule()
                }
                .buttonStyle(PlanPressStyle(scale: 0.96))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptyStateHint: String {
        if !debouncedSearch.isEmpty { return "Spróbuj innej frazy." }
        switch scope {
        case .fitting:
            return "Żaden przepis nie ma jeszcze oznaczenia \u{201E}\(slot.title)\u{201D}."
        case .favourites:
            return "Nie masz jeszcze ulubionych przepisów."
        case .all:
            return "Katalog jest pusty."
        }
    }

    // MARK: - Stopka

    /// Audytorium powiedziane wprost NAD przyciskiem, a nie w nim.
    ///
    /// W przycisku musiałoby stać „Dodaj dla Zosi”, czyli imię w dopełniaczu —
    /// a polskiej odmiany imion nie da się wyliczyć regułą, która nie kaleczy
    /// co dziesiątego („Marek” → „Marka”, ale „Paweł” → „Pawła”). Osobny wiersz
    /// z awatarami mówi to samo w mianowniku i przy okazji pokazuje twarze.
    private var footer: some View {
        SCSheetFooter {
            if roster.count > 1 {
                audienceSummary
            }

            // Ten sam przycisk, co w każdym innym arkuszu aplikacji: terakota
            // w wariancie „soft” (tint + obwódka, bez gradientu i cienia).
            // Wcześniej to CTA malowało się po swojemu i było jedyną pełną
            // plamą koloru w całej apce.
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

    private var audienceSummary: some View {
        HStack(spacing: 8) {
            PlanWhoBadge(participantIds: participantsToSave, members: roster, size: 22)

            Text(audienceText)
                .scFont(13, weight: .semibold, relativeTo: .footnote)
                .tracking(-0.2)
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
    }

    private var audienceText: String {
        let ids = participantsToSave
        guard !ids.isEmpty else { return "Dla całego domu" }
        let names = roster
            .filter { ids.contains($0.id) }
            .map { HouseholdMemberStyle.shortName($0.displayName) }
        return "Tylko dla: " + names.joined(separator: ", ")
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
        Task { @MainActor in
            _ = await store.upsertWeekSlot(
                recipe: recipe,
                participantIds: participantsToSave,
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

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEEE, d MMM"
        return f
    }()
}
