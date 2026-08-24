import SwiftUI

// Recipe detail v2 — "Szczegóły Posiłku" Cozy Kitchen variant F.
// Source: design/Weekly Meals - Szczegoly Posilku.html (RecipeDetailF).
//
// Zdjęcie 320pt wtapia się w płótno strony (bez widocznego szwu na granicy),
// serce wisi w lewym górnym rogu, a xmark w prawym — ten sam wzorzec co
// `EditorialSheetHeader`, żeby każdy arkusz v2 zamykało się tak samo. Pod
// zdjęciem: wiersz eyebrow (pigułka kategorii + stempel czasu), tytuł z lede,
// a dalej cztery sekcje `EditorialSectionTitle` z kolorowymi akcentami —
// „Porcje" (butter), „Wartości odżywcze" (terracotta, asymetryczna siatka
// 1.4 : 1 z kaflem kcal i trzema chipami makro), „Przygotowanie" (sage,
// numerowane kroki) i „Składniki" (indigo, wiersze z gramaturą).
//
// Sekcja porcji jest osią tego ekranu, a nie ozdobą: stepper przelicza
// JEDNOCZEŚNIE makra i gramatury. Wcześniej kafle pokazywały wartości na
// jedną porcję, a lista składników ilości na cały przepis — dwie różne
// liczby porcji obok siebie, żadna podpisana.
//
// Na dole pasek z jednym przyciskiem, którego rola zależy od `context`:
// z katalogu dodaje posiłek do planu, z planu zapisuje samą liczbę porcji.
// ScrollView ignoruje górny bezpieczny obszar, żeby zdjęcie szło od krawędzi
// do krawędzi; serce, xmark i dolny pasek siedzą na overlayach rodzica.

/// Skąd otwarto szczegóły posiłku.
///
/// Ten sam ekran obsługuje trzy wejścia, ale nie wszędzie znaczy to samo:
/// w katalogu przepis dopiero wybieramy, a z planu i z kalendarza patrzymy na
/// posiłek, który ma już swój dzień i slot. Bez tego rozróżnienia przycisk na
/// dole musiałby zgadywać, czy zakłada nowy wpis, czy poprawia istniejący.
enum RecipeDetailContext {
    case catalog
    case planned(day: Date, slot: MealSlot)
}

struct RecipeDetailView: View {
    @Environment(\.colorScheme) private var scheme

    let recipe: Recipe
    var onToggleFavorite: (() -> Void)?
    var onClose: (() -> Void)?

    /// Liczba porcji, od której startuje stepper. Katalog otwiera się na
    /// jednej porcji, a wejście z planu podstawia tu `plannedServings` slotu,
    /// żeby ekran pokazywał to, co użytkownik już wcześniej ustawił.
    let initialServings: Int

    /// Kontekst wywołania — decyduje o przycisku w dolnym pasku.
    let context: RecipeDetailContext

    /// Wołane przyciskiem „Zapisz porcje" w kontekście `.planned`.
    var onSaveServings: ((Int) -> Void)?

    /// Wołane po tym, jak `AddToPlanSheet` wstawi posiłek do planu — z dniem
    /// i slotem, na które trafił, żeby ekran pod spodem mógł się odświeżyć.
    var onAddedToPlan: ((Date, MealSlot) -> Void)?

    /// Widełki są te same, co limit `plannedServings` w backendzie — powyżej
    /// dwunastu porcji to już nie jest gotowanie na tydzień, tylko catering.
    private static let servingsRange = 1...12

    @State private var servings: Int
    @State private var isAddToPlanPresented = false

    /// Czy użytkownik dotknął steppera na tym ekranie.
    ///
    /// Arkusz „Dodaj do planu" potrzebuje tego, żeby wiedzieć, czy wolno mu
    /// przeliczyć porcje z audytorium. Samo porównanie `servings != 1` tu nie
    /// wystarcza: kto podbił na 2 i wrócił na 1, dokonał wyboru, a takie
    /// porównanie uznałoby go za nietkniętą wartość domyślną.
    @State private var didTouchStepper = false

    /// Podnoszona przy „Zapisz porcje" i już nieopuszczana.
    ///
    /// `onSaveServings` jest synchroniczne i tylko odpala zapis w rodzicu,
    /// więc przycisk zostaje aktywny przez całą animację zamykania arkusza —
    /// a to wystarczy, żeby drugie stuknięcie wysłało ten sam upsert po raz
    /// drugi. Flagi nie zerujemy, bo po zapisie ten ekran i tak znika:
    /// odblokowanie przycisku otwierałoby dokładnie to okno, które zamyka.
    @State private var isSavingServings = false

    /// Jawny `init` zamiast memberwise'owego, bo `@State` z porcjami trzeba
    /// zasiać `initialServings`. Kolejność i domyślne wartości są dobrane tak,
    /// żeby dotychczasowe wywołania `RecipeDetailView(recipe:onToggleFavorite:onClose:)`
    /// kompilowały się bez zmian.
    init(
        recipe: Recipe,
        onToggleFavorite: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        initialServings: Int = 1,
        context: RecipeDetailContext = .catalog,
        onSaveServings: ((Int) -> Void)? = nil,
        onAddedToPlan: ((Date, MealSlot) -> Void)? = nil
    ) {
        self.recipe = recipe
        self.onToggleFavorite = onToggleFavorite
        self.onClose = onClose
        self.context = context
        self.onSaveServings = onSaveServings
        self.onAddedToPlan = onAddedToPlan

        // Klamrujemy raz, przy wejściu, i trzymamy przyciętą wartość także
        // jako punkt odniesienia dla „Zapisz porcje" — inaczej slot zapisany
        // kiedyś z wartością spoza widełek wyglądałby na zmieniony od razu
        // po otwarciu ekranu.
        let seed = min(Self.servingsRange.upperBound, max(Self.servingsRange.lowerBound, initialServings))
        self.initialServings = seed
        _servings = State(initialValue: seed)
    }

    /// Porcje jako `Double`, bo skalowanie makr i składników liczy się
    /// ułamkiem `porcje / recipe.servings`.
    private var portions: Double { Double(servings) }

    var body: some View {
        ZStack(alignment: .top) {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    heroPhoto

                    EditorialEyebrowRow(
                        category: recipe.category,
                        prepTimeMinutes: recipe.prepTimeMinutes
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    titleAndDescription
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    if !recipe.additionalSlots.isEmpty {
                        alsoFitsRow
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                    }

                    servingsSection
                        .padding(.horizontal, 20)
                        .padding(.top, 22)

                    nutritionSection
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    if !recipe.preparationSteps.isEmpty {
                        preparationSection
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                    }

                    if !recipe.ingredients.isEmpty {
                        ingredientsSection
                            .padding(.horizontal, 20)
                            .padding(.top, 22)
                    }

                    // Zapas pod dolny pasek: sam pasek to 14 + przycisk 45 + 8,
                    // do tego bezpieczny obszar na dole. Bez tej przerwy
                    // ostatni składnik chowa się pod przyciskiem i wygląda
                    // na ucięty koniec listy.
                    Color.clear.frame(height: 112)
                }
                // Szerokość treści przypięta do szerokości arkusza.
                //
                // Bez tego wystarczy, żeby jeden element policzył sobie
                // szerokość większą niż ekran (kafle makr biorą ją
                // z `GeometryReadera`, a ten w trakcie przejść arkusza potrafi
                // oddać nieaktualną wartość), a obszar przewijania robi się
                // szerszy niż widok. `ScrollView` pozwala go wtedy przesuwać
                // na boki i cała karta jeździ w lewo-prawo pod palcem —
                // mimo że na tym ekranie nie ma czego przewijać w poziomie.
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            heartButton
                .padding(.leading, 16)
                .padding(.top, 12)
        }
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(.trailing, 16)
                .padding(.top, 12)
        }
        .overlay(alignment: .bottom) {
            primaryActionBar
        }
        .sheet(isPresented: $isAddToPlanPresented) {
            // Liczba porcji ze steppera jedzie do arkusza jako punkt startowy:
            // użytkownik właśnie na nią patrzył, więc przestawienie jej przy
            // dodawaniu wyglądałoby na zgubienie jego wyboru.
            // Bez `.presentationDetents` i `.dashboardLiquidSheet()` — arkusz
            // nakłada je sobie sam, a drugi komplet tych samych modyfikatorów
            // prezentacji tylko zaciemniałby, gdzie jest ich źródło.
            AddToPlanSheet(
                recipe: recipe,
                initialServings: servings,
                // Stepper startuje od jedynki, więc każda inna wartość znaczy,
                // że użytkownik świadomie go ruszył — i arkusz nie ma prawa
                // nadpisać jej regułą auto z chipów. Przy jedynce oddajemy
                // decyzję arkuszowi: „Wspólne" w domu dwuosobowym ma pokazać
                // dwie porcje, zanim ktokolwiek cokolwiek stuknie.
                didOverrideServings: didTouchStepper,
                onAdded: { day, slot in
                    onAddedToPlan?(day, slot)
                }
            )
        }
    }

    // MARK: - Hero photo

    private var heroPhoto: some View {
        // 320pt design height, edge-to-edge, fades into the canvas at the
        // bottom 60pt and into a darker scrim at the top 120pt so the heart
        // and close chips read on any photo.
        //
        // Bez `.ignoresSafeArea` — o rozciągnięcie treści pod pasek stanu dba
        // sam ScrollView. Ten modyfikator był tu kiedyś dodatkowo i rozjeżdżał
        // ekran: w arkuszu `.large` górna wstawka bezpiecznego obszaru wynosi
        // zero, więc w spoczynku nie robił nic, ale przy każdej zmianie
        // geometrii arkusza (wjazd, przeciąganie do zamknięcia, wypchnięcie
        // w tył przez „Dodaj do planu") wstawka na moment rosła. Zdjęcie
        // dostawało wtedy nową wysokość, a stojące PRZED nim `.clipped()`
        // przycinało je do poprzednich granic — stąd węższa fotografia
        // i cała treść przesunięta w lewo.
        Color.clear
            .frame(height: 320)
            .background(photoLayer)
            .overlay(topScrim, alignment: .top)
            .overlay(bottomFade, alignment: .bottom)
            .clipped()
    }

    private var photoLayer: some View {
        Group {
            if let url = recipe.imageURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        photoFallback
                    @unknown default:
                        photoFallback
                    }
                }
            } else {
                photoFallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var photoFallback: some View {
        // Editorial shimmer that matches the design's `Skel` primitive —
        // warm canvas-tinted track with a left-to-right highlight pass.
        // The pre-v2 placeholder was a category-gradient + glyph, which
        // read like a different design language on this surface.
        EditorialShimmerBlock(cornerRadius: 0)
    }

    private var topScrim: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(scheme == .dark ? 0.55 : 0.30),
                Color.black.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 120)
        .allowsHitTesting(false)
    }

    private var bottomFade: some View {
        // Matches the WMPageBackground base color at Y≈320 so the photo
        // melts into the canvas — no visible boundary line.
        let target = scheme == .dark
            ? Color(red: 12 / 255, green: 8 / 255, blue: 6 / 255)
            : Color(red: 251 / 255, green: 245 / 255, blue: 234 / 255)
        return LinearGradient(
            colors: [target.opacity(0), target],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 80)
        .allowsHitTesting(false)
    }

    // MARK: - Top chrome (heart + close)

    private var heartButton: some View {
        let liked = recipe.favourite
        let glassFill: Color = scheme == .dark
            ? Color(red: 15 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.55)
            : Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.85)
        let glassStroke: Color = scheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.16)

        return Button(action: { onToggleFavorite?() }) {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(liked ? WMPalette.terracotta : Color.wmLabel(scheme))
                .frame(width: 44, height: 44)
                .background {
                    if liked {
                        Circle().fill(WMPalette.terracotta.opacity(scheme == .dark ? 0.30 : 0.22))
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().fill(glassFill))
                    }
                }
                .overlay(
                    Circle().stroke(
                        liked ? WMPalette.terracotta.opacity(0.55) : glassStroke,
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.18), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(onToggleFavorite == nil ? 0 : 1)
        .disabled(onToggleFavorite == nil)
        .accessibilityLabel(liked ? "Usuń z ulubionych" : "Dodaj do ulubionych")
    }

    private var closeButton: some View {
        Button(action: { onClose?() }) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.wmLabel(scheme))
                .frame(width: 36, height: 36)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(
                            scheme == .dark
                                ? Color(red: 15 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.55)
                                : Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.85)
                        ))
                }
                .overlay(
                    Circle().stroke(
                        scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14),
                        lineWidth: 1
                    )
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.16), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zamknij")
    }

    // MARK: - Title + description

    private var titleAndDescription: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.name)
                .font(.system(size: 30, weight: .heavy))
                .tracking(-0.8)
                .foregroundStyle(Color.wmLabel(scheme))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !recipe.description.isEmpty {
                Text(recipe.description)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sections

    /// Blok porcji. Butter jest jedynym akcentem z palety, który nie jest
    /// jeszcze zajęty na tym ekranie (terracotta trzyma kalorie, sage
    /// przygotowanie, indigo składniki), więc sekcja czyta się jako osobna
    /// rzecz, a nie jako przedłużenie sąsiedniej.
    private var servingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Porcje",
                eyebrow: "Ile gotujesz",
                accent: WMPalette.butter
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    Text(PolishPlural.servings(servings))
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(servings)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 8)

                    WMStepper(
                        value: $servings,
                        range: Self.servingsRange,
                        accessibilityTitle: "Liczba porcji",
                        accessibilityValue: PolishPlural.servings(servings),
                        onChange: { _ in didTouchStepper = true }
                    )
                }

                // Bez tej linijki nie widać, że przepis jest napisany na dwie
                // porcje — a to ona tłumaczy, czemu przy jednej porcji
                // gramatury składników są o połowę mniejsze niż w przepisie.
                Text("Przepis bazowy: \(PolishPlural.servings(recipe.servings))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.wmFaint(scheme))
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.wmTileBg(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
            .animation(.smooth(duration: 0.18), value: servings)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Wartości odżywcze",
                eyebrow: nil,
                accent: WMPalette.terracotta
            )

            EditorialNutritionGrid(
                nutrition: recipe.nutrition(forServings: portions),
                // Przy jednej porcji przelicznik powtarzałby dużą liczbę,
                // więc pokazujemy go dopiero wtedy, gdy jest czym dzielić.
                perServingKcal: servings > 1 ? recipe.nutritionPerServing.kcal : nil
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preparationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Przygotowanie",
                eyebrow: "Krok po kroku",
                accent: WMPalette.sage
            )

            VStack(spacing: 0) {
                let sortedSteps = recipe.preparationSteps.sorted(by: { $0.stepNumber < $1.stepNumber })
                ForEach(Array(sortedSteps.enumerated()), id: \.element.id) { idx, step in
                    EditorialStepRow(
                        index: idx + 1,
                        text: step.instruction,
                        isLast: idx == sortedSteps.count - 1
                    )
                }
            }
            .background(Color.wmTileBg(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ingredientsSection: some View {
        // Gramatury są przeliczone tym samym współczynnikiem co makra wyżej,
        // a eyebrow mówi wprost, na ile porcji — wcześniej brzmiał „Lista
        // zakupów" i nie dało się z niego wyczytać, czego dotyczą liczby.
        let scaled = recipe.ingredients(forServings: portions)

        return VStack(alignment: .leading, spacing: 12) {
            EditorialSectionTitle(
                title: "Składniki",
                // Biernik, bo po „Na" mianownik daje „Na 1 porcja". Kafel
                // porcji i CTA zostają na mianowniku — tam liczba stoi sama,
                // bez przyimka.
                eyebrow: "Na \(PolishPlural.servingsAccusative(servings))",
                accent: WMPalette.indigo
            )

            VStack(spacing: 0) {
                ForEach(Array(scaled.enumerated()), id: \.element.id) { idx, ingredient in
                    EditorialIngredientRow(
                        ingredient: ingredient,
                        isLast: idx == scaled.count - 1
                    )
                }
            }
            .background(Color.wmTileBg(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Dolny pasek akcji

    /// Jeden przycisk przyklejony nad bezpiecznym obszarem. Wygląd przeniesiony
    /// ze stopki `RecipeFilterSheet`, żeby główna akcja w całej aplikacji
    /// wyglądała tak samo. Pasek maluje pod sobą płótno, bo treść scrolla
    /// przejeżdża mu pod spodem.
    private var primaryActionBar: some View {
        Button(action: performPrimaryAction) {
            Text(primaryActionTitle)
                .font(.system(size: 14, weight: .bold))
                .tracking(-0.1)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [WMPalette.terracotta, WMPalette.terracotta.mix(black: 0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: WMPalette.terracotta.opacity(0.28), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!isPrimaryActionEnabled || isSavingServings)
        // Wygaszony, a nie ukryty: „Zapisz porcje" ma być widoczne od wejścia,
        // żeby było wiadomo, co się stanie po ruszeniu steppera.
        .opacity(isPrimaryActionEnabled && !isSavingServings ? 1 : 0.45)
        .animation(.smooth(duration: 0.18), value: isPrimaryActionEnabled)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            Rectangle()
                .fill(Color.wmCanvas(scheme).opacity(0.94))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.wmRule(scheme))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var primaryActionTitle: String {
        switch context {
        case .catalog: return "Dodaj do planu"
        case .planned: return "Zapisz porcje"
        }
    }

    /// W planie zapisywać nie ma czego, dopóki liczba porcji jest ta sama, co
    /// przy wejściu — przycisk aktywny bez zmiany wysyłałby na serwer wartość,
    /// którą ten już ma.
    private var isPrimaryActionEnabled: Bool {
        switch context {
        case .catalog: return true
        case .planned: return servings != initialServings
        }
    }

    private func performPrimaryAction() {
        switch context {
        case .catalog:
            isAddToPlanPresented = true
        case .planned:
            guard !isSavingServings else { return }
            isSavingServings = true
            onSaveServings?(servings)
            onClose?()
        }
    }

    // MARK: - Helpers

    private var categoryAccent: Color {
        RecipeDetailPalette.accent(for: recipe.category)
    }

    /// „Pasuje też na: II śniadanie · Przekąska".
    ///
    /// Przepis należy do jednej kategorii, ale bywa dobry o kilku porach dnia
    /// — i bez tego wiersza użytkownik nie ma skąd wiedzieć, czemu owsianka
    /// pojawia mu się przy dodawaniu drugiego śniadania. To jedyne miejsce,
    /// w którym `suitableSlots` widać wprost.
    private var alsoFitsRow: some View {
        // Etykieta stoi poza scrollem, a chipy jadą w poziomym przewijaniu.
        // Wcześniej wszystko siedziało w jednym HStacku: przy trzech slotach
        // brakowało szerokości, SwiftUI ściskał teksty i „II śniadanie"
        // łamało się w chipie na trzy linijki. `fixedSize` + `lineLimit(1)`
        // zakazują łamania w ogóle, a ScrollView oddaje nadmiar szerokości
        // przewinięciu zamiast kompresji.
        HStack(alignment: .center, spacing: 8) {
            Text("Pasuje też na")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.wmFaint(scheme))
                .fixedSize()

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(recipe.additionalSlots) { slot in
                        HStack(spacing: 5) {
                            Image(systemName: slot.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(slot.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .foregroundStyle(slot.cozyAccent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(slot.cozyAccent.opacity(scheme == .dark ? 0.16 : 0.10))
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Eyebrow row (category pill + divider + prep-time stamp)

private struct EditorialEyebrowRow: View {
    let category: RecipesCategory
    let prepTimeMinutes: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            categoryPill

            Rectangle()
                .fill(Color.wmRule(scheme))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .bold))
                Text(verbatim: "\(prepTimeMinutes) MIN")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.wmMuted(scheme))
        }
    }

    private var categoryPill: some View {
        let accent = RecipeDetailPalette.accent(for: category)
        let fill = accent.opacity(scheme == .dark ? 0.22 : 0.16)
        let stroke = accent.opacity(scheme == .dark ? 0.45 : 0.30)

        return HStack(spacing: 6) {
            Image(systemName: RecipesConstants.icon(for: category))
                .font(.system(size: 11, weight: .bold))
            Text(RecipesConstants.displayName(for: category).uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.7)
                .lineLimit(1)
        }
        .foregroundStyle(accent)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(fill))
        .overlay(Capsule().stroke(stroke, lineWidth: 1))
        .fixedSize()
    }
}

// MARK: - Section title (accent bar + optional eyebrow + title)

private struct EditorialSectionTitle: View {
    let title: String
    let eyebrow: String?
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // No `.shadow()` here — the accent bar sits 16pt above the
            // nutrition grid's terracotta-tinted hero tile, and any glow
            // from this bar bleeds straight onto that tile's top-left
            // corner. A flat fill reads cleanly without the smudge.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(accent)
                .frame(width: 5, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(accent)
                }
                Text(title)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(Color.wmLabel(scheme))
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Asymmetric nutrition grid (1 big kcal tile + 3 stacked macros)

private struct EditorialNutritionGrid: View {
    let nutrition: Nutrition
    /// Kalorie jednej porcji, gdy duża liczba dotyczy kilku. `nil` znaczy
    /// „nie ma czego rozbijać".
    var perServingKcal: Double?

    var body: some View {
        // Design: `gridTemplateColumns: '1.4fr 1fr'`. SwiftUI doesn't have
        // a fractional grid template, so we split available width with a
        // GeometryReader and lay the two columns out manually.
        GeometryReader { geo in
            let gap: CGFloat = 10
            let usable = max(0, geo.size.width - gap)
            let bigW = (usable * 1.4) / 2.4
            // Odjęcie zamiast drugiego mnożenia: `bigW + gap + smallW` musi
            // wyjść co do piksela `geo.size.width`, bo każda nadwyżka rozpycha
            // obszar przewijania i pozwala przesuwać kartę na boki.
            let smallW = usable - bigW

            HStack(alignment: .top, spacing: gap) {
                EditorialKcalTile(value: nutrition.kcal, perServing: perServingKcal)
                    .frame(width: bigW, height: 168)

                VStack(spacing: gap) {
                    EditorialMacroTile(
                        label: "Białko",
                        value: nutrition.protein,
                        unit: "g",
                        icon: "sparkles",
                        accent: WMPalette.indigo
                    )
                    EditorialMacroTile(
                        label: "Węglowodany",
                        value: nutrition.carbs,
                        unit: "g",
                        icon: "leaf.fill",
                        accent: WMPalette.sage
                    )
                    EditorialMacroTile(
                        label: "Tłuszcze",
                        value: nutrition.fat,
                        unit: "g",
                        icon: "drop.fill",
                        accent: WMPalette.terracottaDeep
                    )
                }
                .frame(width: smallW, height: 168)
            }
            // Klamra na wypadek, gdyby któryś kafel zażądał więcej, niż mu
            // przydzielono — nadmiar ma zostać przycięty, a nie rozepchnąć
            // siatkę poza szerokość ekranu.
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: 168)
    }
}

private struct EditorialKcalTile: View {
    let value: Double
    /// Kalorie pojedynczej porcji — mała linijka pod dużą liczbą. Bez niej
    /// przy sześciu porcjach kafel pokazuje cztery cyfry i nic nie mówi
    /// o tym, ile z tego zjada jedna osoba.
    var perServing: Double?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = WMPalette.terracotta
        let formatted = RecipeDetailFormat.integer(value)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    // Icon chip uses `tint(accent, 0.65)` for fill and
                    // `tintBorder(accent, 0.40)` for stroke — mapped to
                    // 0.35/0.60 dark and 0.53/0.80 light per the design's
                    // tint helpers.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(scheme == .dark ? 0.35 : 0.53))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(scheme == .dark ? 0.60 : 0.80), lineWidth: 1)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 32, height: 32)

                Text("KALORIE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.7)
                    .foregroundStyle(accent)
            }

            Spacer(minLength: 8)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formatted)
                    .font(.system(size: 44, weight: .heavy))
                    .tracking(-1.4)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .monospacedDigit()
                    // Zapas skalowania zszedł z 0.7 do 0.5, bo stepper porcji
                    // dowozi tu teraz pięć cyfr z separatorem tysięcy
                    // („10 800" przy dwunastu porcjach tłustego dania),
                    // a przy 0.7 taka liczba nie mieści się w 168pt kaflu.
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: value))

                Text("kcal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))
                    // Jednostka nie negocjuje o miejsce: bez `fixedSize` HStack
                    // rozkłada deficyt szerokości na oba teksty i przy pięciu
                    // cyfrach urywa „kcal" do „kc…", zamiast oddać całe zwężenie
                    // liczbie, którą chroni `minimumScaleFactor`.
                    .lineLimit(1)
                    .fixedSize()
            }

            if let perServing {
                Text("\(RecipeDetailFormat.integer(perServing)) kcal / porcja")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 3)
            }
        }
        .animation(.smooth(duration: 0.18), value: value)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            // Top-left radial highlight — direct port of the design's
            // `radial-gradient(120% 80% at 0% 0%, tint(accent, 0.70) 0%, transparent 60%)`.
            // SwiftUI's `EllipticalGradient` already inherits the tile's
            // aspect ratio, so the falloff matches the design's 1.5:1
            // ellipse closely without a manual scaleEffect.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    EllipticalGradient(
                        stops: [
                            .init(color: accent.opacity(scheme == .dark ? 0.30 : 0.52), location: 0.0),
                            .init(color: accent.opacity(0),                              location: 0.60),
                            .init(color: accent.opacity(0),                              location: 1.0)
                        ],
                        center: UnitPoint(x: -0.05, y: -0.05),
                        startRadiusFraction: 0,
                        endRadiusFraction: 1.0
                    )
                )
        )
        .background(
            // Card base — dark gets a subtle vertical brighten from
            // `cardStrong` (6% cream) to `card` (4% cream) so the tile
            // lifts off the near-black canvas. Light mode lets the page
            // canvas show through (`.clear`) per user spec: the tile
            // should differ from the sheet only via the terracotta
            // gradient + border, not via a second cream tone.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: scheme == .dark
                            ? [
                                Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06),
                                Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.04)
                            ]
                            : [
                                Color.clear,
                                Color.clear
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            // Border opacities ported from the design's `tintBorder(accent, 0.55)`:
            // dark → 1 − 0.55 = 0.45; light → 1 − 0.35 = 0.65.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(scheme == .dark ? 0.45 : 0.65), lineWidth: 1)
        )
    }
}

private struct EditorialMacroTile: View {
    let label: String
    let value: Double
    let unit: String
    let icon: String
    let accent: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                // Icon chip per design: `tint(accent, 0.78)` fill +
                // `tintBorder(accent, 0.60)` stroke → 0.22/0.40 dark and
                // 0.40/0.60 light.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(scheme == .dark ? 0.22 : 0.40))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(accent.opacity(scheme == .dark ? 0.40 : 0.60), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                // The longest Polish label is `WĘGLOWODANY` (11 chars with
                // an `Ę` ogonek that runs wider than a plain `E` at heavy
                // weight). On compact iPhones the small-tile content area
                // can dip under 80pt, so the heavy/wide glyphs truncate
                // before `minimumScaleFactor` engages. Drop a half-point
                // and let the system tighten + scale aggressively before
                // falling back to ellipsis.
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.wmMuted(scheme))
                    .lineLimit(1)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.7)

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(RecipeDetailFormat.macro(value))
                        .font(.system(size: 16, weight: .heavy))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .monospacedDigit()
                        // Kafel makra jest o połowę węższy od kalorycznego,
                        // a stepper porcji potrafi zrobić z „30" cztery cyfry
                        // z przecinkiem — bez skalowania końcówka by uciekła.
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText(value: value))
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.wmMuted(scheme))
                        // Ten sam powód, co przy „kcal": kafel makra jest
                        // węższy, więc urwane „g" pokazałoby się tu jeszcze
                        // wcześniej. Całe zwężenie ma iść w liczbę obok.
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            Spacer(minLength: 0)
        }
        .animation(.smooth(duration: 0.18), value: value)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
    }
}

// MARK: - Steps & ingredients rows

private struct EditorialStepRow: View {
    let index: Int
    let text: String
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(index)")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(WMPalette.sage)
                .monospacedDigit()
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(WMPalette.sage.opacity(scheme == .dark ? 0.55 : 0.40), lineWidth: 1.5)
                )

            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(Color.wmLabel(scheme))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme).opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct EditorialIngredientRow: View {
    let ingredient: Ingredient
    let isLast: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(RecipeDetailFormat.ingredientName(ingredient.name))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.wmLabel(scheme))
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(RecipeDetailFormat.ingredientAmount(ingredient))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.wmMuted(scheme))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.wmRule(scheme).opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Shimmer (matches design's `Skel` primitive)

private struct EditorialShimmerBlock: View {
    var cornerRadius: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    @State private var slide: CGFloat = -1

    var body: some View {
        let track = scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.06)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.06)
        let highlight = scheme == .dark
            ? Color(red: 251 / 255, green: 243 / 255, blue: 232 / 255).opacity(0.10)
            : Color(red: 26 / 255, green: 20 / 255, blue: 17 / 255).opacity(0.10)

        GeometryReader { geo in
            ZStack {
                track

                LinearGradient(
                    stops: [
                        .init(color: track,     location: 0.0),
                        .init(color: highlight, location: 0.5),
                        .init(color: track,     location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 1.6)
                .offset(x: slide * geo.size.width * 1.3)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    slide = 1
                }
            }
        }
    }
}

// MARK: - Palette + formatters

private enum RecipeDetailPalette {
    /// Cozy Kitchen accent per recipe category. Mirrors the meal-slot
    /// mapping used by `EditorialMealCard` so a breakfast recipe surfaces
    /// in butter, lunch in sage, dinner in indigo across both screens.
    static func accent(for category: RecipesCategory) -> Color {
        switch category {
        case .breakfast: return WMPalette.butter
        case .lunch:     return WMPalette.sage
        case .dinner:    return WMPalette.indigo
        case .favourite: return WMPalette.terracotta
        case .all:       return WMPalette.terracotta
        }
    }
}

private enum RecipeDetailFormat {
    static func integer(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value.rounded()))"
    }

    static func macro(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func ingredientName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased(with: Locale(identifier: "pl_PL")) + trimmed.dropFirst()
    }

    static func ingredientAmount(_ ingredient: Ingredient) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        let value = kitchenRounded(ingredient.amount, unit: ingredient.unit)
        let amount = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(amount) \(ingredient.unit.rawValue)"
    }

    /// Ilość zaokrąglona do wartości, którą da się odmierzyć w kuchni.
    ///
    /// Skalowanie porcji dzieli gramatury przez liczbę porcji przepisu, więc
    /// z „5 szt" przy jednej porcji robi się 2,5, a z „100 g" — 33,33. Suche
    /// obcięcie do dwóch miejsc po przecinku daje listę zakupów, po której
    /// nikt nie gotuje. Reguła:
    /// — rzeczy liczone sztukami i miarkami idą do połówki, bo pół jajka
    ///   i pół łyżki da się odmierzyć, a 0,33 łyżki nie;
    /// — gramy i mililitry od 10 w górę tną się do liczby całkowitej, bo przy
    ///   takiej masie ułamek grama to szum wagi kuchennej, a nie informacja;
    ///   poniżej 10 zostaje jedno miejsce, żeby „7,5 g drożdży" nie awansowało
    ///   na 8 g;
    /// — kilogramy i litry zostają z dwoma miejscami, bo w przepisach
    ///   występują właśnie jako ułamki (0,25 kg) i połówka zrobiłaby z ćwierć
    ///   kilo pół.
    /// Z niezerowej ilości nigdy nie wychodzi zero — składnik ma się pojawić
    /// na liście choćby w ilości śladowej.
    private static func kitchenRounded(_ amount: Double, unit: IngredientUnit) -> Double {
        guard amount > 0 else { return amount }

        switch unit {
        case .piece, .teaspoon, .tablespoon, .cup:
            return max(0.5, (amount * 2).rounded() / 2)
        case .gram, .milliliter:
            return amount >= 10 ? amount.rounded() : max(0.1, (amount * 10).rounded() / 10)
        case .kilogram, .liter:
            return max(0.01, (amount * 100).rounded() / 100)
        }
    }
}

#Preview("Recipe Detail v2 — Dark") {
    RecipeDetailView(recipe: RecipesMock.chickenBowl, onToggleFavorite: {})
        .preferredColorScheme(.dark)
}

#Preview("Recipe Detail v2 — Light") {
    RecipeDetailView(recipe: RecipesMock.chickenBowl, onToggleFavorite: {})
        .preferredColorScheme(.light)
}

/// Wejście z planu wygląda inaczej od katalogowego w dwóch miejscach naraz —
/// stepper startuje od zapisanych porcji, a dolny przycisk zapisuje zamiast
/// dodawać — więc drugi podgląd pokazuje właśnie ten wariant.
#Preview("Recipe Detail v2 — z planu, dark") {
    RecipeDetailView(
        recipe: RecipesMock.chickenBowl,
        onToggleFavorite: {},
        initialServings: 2,
        context: .planned(day: Date(), slot: .lunch),
        onSaveServings: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Recipe Detail v2 — z planu, light") {
    RecipeDetailView(
        recipe: RecipesMock.chickenBowl,
        onToggleFavorite: {},
        initialServings: 2,
        context: .planned(day: Date(), slot: .lunch),
        onSaveServings: { _ in }
    )
    .preferredColorScheme(.light)
}
