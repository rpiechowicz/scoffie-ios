import SwiftUI
import UIKit

/// Zakładka „Asystent".
///
/// Zakładka, a nie arkusz nad Planem: rozmowa trwa 25–60 sekund i wraca się
/// do niej wiele razy w tygodniu, a wszystko, co chowa się za przyciskiem
/// w nagłówku, jest w praktyce niewidoczne. Miejsce w dolnym menu zwolniły
/// „Produkty", które przeniosły się do nagłówka Planu tygodnia — tam, gdzie
/// i tak powstaje lista zakupów.
///
/// Ekran świadomie nie ma kręciołka: tura trwa dziesiątki sekund, więc
/// zamiast niego stoi cichy wiersz z bieżącym krokiem z serwera („Czytam plan
/// tygodnia", „Zapisuję plan tygodnia") — w miejscu, w którym wyłoni się
/// odpowiedź (`turnSlot`), bez przewijania i bez skoku układu.
struct AssistantView: View {
    let store: AgentStore

    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.mealCalendarStore) private var mealStore
    @Environment(\.recipeCatalogStore) private var recipeCatalogStore
    @Environment(\.colorScheme) private var scheme

    // Cel czytany tak samo jak na Przepisach i w Kalendarzu — jedno źródło,
    // żeby chip kontekstu nie obiecywał innej liczby niż reszta aplikacji.
    @AppStorage(RecipePersonalization.Keys.calorieGoal)
    private var calorieGoal: Int = RecipePersonalization.defaultCalorieGoal

    @State private var draft = ""
    /// Wiadomość poprawiana w tej chwili — razem z jej pierwotną treścią,
    /// żeby dało się wrócić bez pytania serwera.
    @State private var editing: EditingMessage?
    @State private var showsRecipePicker = false
    @State private var showDeleteAlert = false
    @State private var showConversations = false
    @State private var showMemory = false
    @State private var showUsage = false
    /// „Wybierz plan" — z linijki nad polem po wyczerpaniu puli.
    @State private var showPaywall = false
    /// „Prywatność i zgoda" z menu — stan zgody i jej cofnięcie.
    @State private var showConsentReview = false
    /// „Co potrafi asystent" — z menu, z bramki zgody i z onboardingu.
    @State private var showCapabilities = false
    /// „Jak działa asystent" — te same karty co onboarding, z menu.
    @State private var showHowItWorks = false
    /// Hero „Poznaj asystenta" (krok 0) — raz, przed pierwszą zgodą. Po
    /// cofnięciu zgody użytkownik wraca prosto do kroku „Zgoda". Flagi
    /// kasuje `AssistantIntroState.reset()` przy wylogowaniu.
    @AppStorage(AssistantIntroState.welcomeSeenKey) private var welcomeSeen = false
    /// Onboarding pokazywany raz, tuż po włączeniu zgody.
    @AppStorage(AssistantIntroState.onboardingSeenKey) private var onboardingSeen = false
    /// Krok przepływu startowego wybrany ręcznie (Dalej/Wstecz). `nil` =
    /// wyliczany ze stanu zgód i flag (`currentStep`). Nie jest
    /// zapamiętywany: po zabiciu aplikacji user wraca na początek
    /// niedokończonego etapu, nie w środek.
    @State private var introStep: IntroStep?
    /// Ostatnio oglądana karta „Poznaj" — „Wstecz" ze zgody wraca na nią.
    @State private var introCard = 0
    /// Kierunek ostatniego ruchu w przepływie: 1 = dalej, −1 = wstecz.
    /// Treść wjeżdża z krawędzi zgodnej z kierunkiem (jak w przewodniku).
    @State private var introDirection = 1
    /// Potwierdzenia z kroku „Zgoda" — tu, bo „Włącz asystenta" siedzi
    /// w stopce przepływu, poza widokiem bramki.
    @State private var consentDraft = AssistantConsentDraft()

    enum IntroStep: Equatable {
        case hero, consent, cards

        /// Kolejność w przepływie — z niej liczy się kierunek przejścia.
        var order: Int {
            switch self {
            case .hero: return 0
            case .consent: return 1
            case .cards: return 2
            }
        }
    }
    /// Odpowiedź asystenta w trakcie zgłaszania („Zgłoś odpowiedź").
    @State private var reporting: AgentChatMessage?
    /// Czy rozmowa stoi na końcu. Gdy użytkownik odjedzie w górę, żeby coś
    /// doczytać, automatyczne przewijanie MUSI przestać go szarpać.
    @State private var isPinnedToBottom = true
    /// Wysokość okna rozmowy — minimalna wysokość slotu ostatniej tury.
    /// Tylko rośnie: klawiatura nie ma prawa skracać slotu i „pompować" listy.
    @State private var viewportHeight: CGFloat = 0
    /// Rozwinięte karty tygodnia i listy kroków — PO ID WIADOMOŚCI, nie
    /// w `@State` wiersza: odpowiedź ostatniej tury rysuje slot, a po
    /// następnym pytaniu ta sama wiadomość przechodzi do części przed
    /// slotem. To inne miejsce w drzewie, więc mimo tego samego `.id`
    /// SwiftUI stawia nowy widok i zerowałby jego stan — rozwinięty tydzień
    /// zwijał się skokiem w tej samej klatce, w której dopisywało się pytanie.
    @State private var expandedCards: Set<String> = []
    @State private var expandedThoughts: Set<String> = []
    /// Programowe przewinięcie w toku — wycisza pigułkę „na dół". W jednej
    /// transakcji treść rośnie o cały ekran (nowy slot o wysokości okna),
    /// a offset jest jeszcze stary, więc przez 0,25 s geometria mówi
    /// „daleko od dna" i pigułka błyskała przy każdym pytaniu. Dawniej
    /// pytanie dodawało ~60 pt, mniej niż luz, i tego nie było.
    @State private var isAutoScrolling = false
    @State private var autoScrollGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                // Przepływ startowy to STAN ZAKŁADKI, nie arkusze: hero →
                // Zgoda → Poznaj → Start → rozmowa. Nagłówek i tab bar stoją,
                // wymienia się tylko treść — użytkownik czyta to jako ten sam
                // ekran w następnym kroku, nie nowy widok w stosie nawigacji.
                //
                // Wewnątrz przepływu treść jeździ na bok jak w przewodniku
                // „Poznaj aplikację", a stopka (`AssistantIntroFooter`) stoi
                // pod nią poza animowanym obszarem. Pionowe przenikanie
                // zostaje tylko na wejściu do rozmowy.
                Group {
                    if let step = activeIntroStep {
                        introFlow(step)
                    } else {
                        // Pole jako wcięcie bezpiecznego obszaru, nie wiersz
                        // pod listą: rozmowa przewija się POD szkłem pola
                        // i widać ją przez nie — tak samo jak pod dolnym menu,
                        // nad którym pole stoi. To jest cała różnica między
                        // „pole w stylu iOS" a paskiem z kreską.
                        conversation
                            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                    }
                }
                .transition(.assistantIntroStep)
                .animation(.easeOut(duration: 0.28), value: activeIntroStep == nil)
            }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: activeIntroStep)
            // Tytuł ma siadać 78 pt od GÓRY EKRANU — dokładnie tam, gdzie na
            // pozostałych zakładkach. Tam robi to ScrollView z tym samym
            // modyfikatorem; tutaj nagłówek jest przypięty poza scrollem, więc
            // modyfikator idzie na cały VStack.
            //
            // Świadomie tylko region `.container` i tylko krawędź `.top`: bez
            // tego zawężenia klawiatura przestałaby podnosić pole wiadomości,
            // a composer wszedłby pod pasek zakładek. NIE skracać do
            // `.ignoresSafeArea()`.
            .ignoresSafeArea(.container, edges: .top)
        }
        .task {
            await store.openIfNeeded()
            // Plakietka puli w nagłówku potrzebuje liczb od razu, nie dopiero
            // po pierwszym 429. Bez zgody to żądanie po prostu nic nie zwraca.
            _ = await store.loadUsage()
        }
        .onAppear {
            store.setVisible(true)
            // Powrót na zakładkę po przerwie: czysta kartka zamiast
            // dopisywania do rozmowy sprzed pół dnia.
            store.rotateIfStale()
        }
        .onDisappear { store.setVisible(false) }
        .onChange(of: scenePhase) { _, phase in
            // Ten sam próg dla powrotu z tła: aplikacja zminimalizowana
            // w sklepie i otwarta w kuchni to dwie różne rozmowy.
            if phase == .active { store.rotateIfStale() }
        }
        .task {
            // Stan zgód PRZED pierwszym renderem bramki — bez tego nowy
            // użytkownik widział rozmowę, dopóki serwer nie odpowiedział.
            await sessionStore.consentStore?.refresh()
            // Zgoda już na serwerze = ta osoba przeszła hero, zgodę i karty
            // na jakimś telefonie. Lokalne flagi (kasowane przy wylogowaniu)
            // dostają to samo, żeby cofnięcie i ponowne włączenie zgody
            // prowadziło prosto do rozmowy, a nie znów przez onboarding.
            // Nowy użytkownik ma tu zgodę na `false`, więc karty po jego
            // pierwszej zgodzie zostają.
            if sessionStore.consentStore?.assistantGranted == true {
                welcomeSeen = true
                onboardingSeen = true
            }
        }
        .sheet(isPresented: $showUsage) {
            // „Limity asystenta" to ten sam arkusz, co „Asystent i plan"
            // w Ustawieniach — limity i plan to jedna sprawa i jedno
            // miejsce, a nie dwa ekrany z tymi samymi liczbami.
            PlanAccessSheet()
        }
        .sheet(isPresented: $showPaywall) {
            // „Zobacz plany" po wyczerpaniu puli prowadzi PROSTO do wyboru
            // planu — ten sam arkusz, który otwiera się z „Asystent i plan".
            PlansSheet()
        }
        .sheet(isPresented: $showConversations) {
            AssistantConversationsSheet(store: store)
        }
        .sheet(isPresented: $showMemory) {
            AssistantMemorySheet(store: store)
        }
        .sheet(isPresented: $showConsentReview) {
            if let consents = sessionStore.consentStore {
                AssistantConsentGateView(
                    consents: consents,
                    source: "IOS_ASSISTANT_MENU",
                    presentation: .sheet,
                    // Zgoda włączona z menu (np. po cofnięciu) musi zdjąć
                    // blokadę 403 w store — inaczej zakładka dalej pokazywała
                    // bramkę mimo zapisanej zgody.
                    onGranted: {
                        showConsentReview = false
                        continueAfterConsent()
                    }
                )
            }
        }
        .sheet(isPresented: $showCapabilities) {
            AssistantCapabilitiesSheet(
                store: store,
                onAsk: { text in askFromSheet(text) },
                onCompose: { isComposerFocused = true }
            )
        }
        .sheet(isPresented: $showHowItWorks) {
            AssistantHowItWorksView(
                presentation: .sheet,
                onFinish: { onboardingSeen = true },
                onAsk: { text in askFromSheet(text) },
                onShowCapabilities: {
                    showHowItWorks = false
                    showCapabilities = true
                }
            )
        }
        .sheet(item: $reporting) { message in
            AssistantReportSheet(message: message) { reason, comment in
                await store.report(messageId: message.id, reason: reason, comment: comment)
            }
        }
        .alert("Usunąć historię rozmów?", isPresented: $showDeleteAlert) {
            Button("Usuń", role: .destructive) {
                Task { await store.deleteAllConversations() }
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Znikną wszystkie Twoje rozmowy z asystentem. Plan tygodnia i przepisy zostają.")
        }
    }

    // MARK: - Nagłówek

    /// Duży tytuł tylko na pustym ekranie.
    ///
    /// W trwającej rozmowie słowo „Asystent” nie niesie nic, czego nie widać
    /// z zakładki, a zjada wiersz treści. Kompaktowy pasek oddaje to miejsce
    /// wiadomościom i pokazuje tytuł rozmowy nadany przez serwer.
    private var header: some View {
        AssistantHeader(
            mode: headerMode,
            onNewConversation: { Task { await store.startNewConversation() } },
            accessory: quotaPips
        ) {
            // W przepływie startowym (przed zgodą albo w kartach) menu ma
            // tylko to, co wtedy działa — „Nowa rozmowa" czy „Usuń historię"
            // bez zgody kończyły się 403 albo pustym arkuszem.
            let inIntro = currentStep != nil
            if !inIntro {
                Button { Task { await store.startNewConversation() } } label: { Label("Nowa rozmowa", systemImage: "plus") }
                Button { showConversations = true } label: { Label("Historia rozmów", systemImage: "clock") }
            }
            Button { showCapabilities = true } label: { Label("Co potrafi asystent", systemImage: "sparkles") }
            Button { showHowItWorks = true } label: { Label("Jak działa asystent", systemImage: "questionmark.bubble") }
            if !inIntro {
                Button { showMemory = true } label: { Label("Pamięć domu", systemImage: "brain.head.profile") }
                Button { showUsage = true } label: { Label("Limity asystenta", systemImage: "chart.bar") }
            }
            Button { showConsentReview = true } label: { Label("Prywatność i zgoda", systemImage: "lock.shield") }
            if !inIntro {
                Divider()
                Button(role: .destructive) { showDeleteAlert = true } label: { Label("Usuń historię rozmów", systemImage: "trash") }
            }
        }
        // Pierwsza wiadomość przełącza nagłówek z dużego na kompaktowy —
        // bez tego tracił ~40 pt skokiem w tej samej klatce, w której
        // znikały chipy i pusty stan.
        .animation(.smooth(duration: 0.25), value: headerMode)
    }

    // MARK: - Przepływ startowy

    /// Krok do narysowania; `nil` = rozmowa. Krok „Zgoda" bez magazynu zgód
    /// nie ma czego pokazać — wtedy też rozmowa.
    private var activeIntroStep: IntroStep? {
        guard let step = currentStep else { return nil }
        if step == .consent, sessionStore.consentStore == nil { return nil }
        return step
    }

    @ViewBuilder
    private func introFlow(_ step: IntroStep) -> some View {
        ZStack {
            introContent(step)
                .id(step)
                .transition(.horizontalStep(direction: introDirection))
        }
        .animation(.easeInOut(duration: 0.34), value: step)

        introFooter(step)
    }

    @ViewBuilder
    private func introContent(_ step: IntroStep) -> some View {
        switch step {
        case .hero:
            AssistantWelcomeView()
        case .consent:
            if let consents = sessionStore.consentStore {
                AssistantConsentGateView(
                    consents: consents,
                    source: "IOS_ASSISTANT_GATE",
                    presentation: .inline,
                    draft: $consentDraft
                )
            }
        case .cards:
            AssistantHowItWorksView(
                presentation: .inline,
                step: $introCard,
                onFinish: { startConversation() },
                onSkip: { startConversation() },
                onAsk: { text in
                    finishIntro()
                    ask(text)
                },
                onShowCapabilities: { showCapabilities = true }
            )
        }
    }

    /// Jedna stopka na trzy kroki — ta sama geometria, zmienia się gniazdo,
    /// tytuł i obecność „Wstecz".
    @ViewBuilder
    private func introFooter(_ step: IntroStep) -> some View {
        switch step {
        case .hero:
            AssistantIntroFooter(
                slot: .link("Zobacz wszystko, co potrafi"),
                onSlotTap: { showCapabilities = true },
                primaryTitle: "Zaczynamy",
                primaryTrailingIcon: "arrow.right",
                onPrimary: { goToStep(.consent) { welcomeSeen = true } }
            )
        case .consent:
            let granted = sessionStore.consentStore?.assistantGranted == true
            let busy = sessionStore.consentStore?.isBusy == true
            let canGrant = AssistantConsentGateView.canGrant(consentDraft)
            AssistantIntroFooter(
                slot: .stepper(step: AssistantIntroSteps.consent, total: AssistantIntroSteps.total),
                notice: consentDraft.errorMessage,
                showsBack: true,
                onBack: { goToStep(.hero) },
                primaryTitle: granted ? "Dalej" : "Włącz asystenta",
                primaryLeadingIcon: granted ? nil : "sparkles",
                primaryTrailingIcon: granted ? "chevron.right" : nil,
                isPrimaryEnabled: granted || (canGrant && !busy),
                isPrimaryLoading: busy,
                primaryHint: granted || canGrant ? nil : "Najpierw zaznacz oba potwierdzenia",
                onPrimary: {
                    if granted { continueAfterConsent() } else { grantConsent() }
                }
            )
        case .cards:
            let isLast = introCard >= AssistantCapabilities.onboarding.count - 1
            AssistantIntroFooter(
                slot: .stepper(step: AssistantIntroSteps.card(introCard), total: AssistantIntroSteps.total),
                showsBack: true,
                onBack: {
                    if introCard > 0 {
                        withAnimation(.easeInOut(duration: 0.3)) { introCard -= 1 }
                    } else {
                        goToStep(.consent)
                    }
                },
                primaryTitle: isLast ? "Zaczynajmy" : "Dalej",
                primaryTrailingIcon: isLast ? nil : "chevron.right",
                onPrimary: {
                    if isLast {
                        startConversation()
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) { introCard += 1 }
                    }
                }
            )
        }
    }

    /// Zapis zgody z przycisku w stopce; po sukcesie — dalej w przepływie.
    private func grantConsent() {
        guard let consents = sessionStore.consentStore else { return }
        Task { @MainActor in
            if await AssistantConsentGateView.grant(consents: consents, source: "IOS_ASSISTANT_GATE", draft: $consentDraft) {
                continueAfterConsent()
            }
        }
    }

    /// Który krok przepływu startowego pokazać. Bez zgody zawsze hero albo
    /// zgoda (ręczny wybór tylko między nimi); ze zgodą — to, co user wybrał
    /// przyciskami, a bez wyboru: rozmowa. `nil` = rozmowa.
    ///
    /// ZGODA NA SERWERZE JEST DOWODEM PRZEJŚCIA PRZEPŁYWU. Karty „Poznaj"
    /// pokazują się raz, tuż po włączeniu zgody — wchodzi się w nie jawnie
    /// (`continueAfterConsent` → `goToStep(.cards)`), nigdy z tego miejsca.
    /// Wcześniej bez lokalnej flagi wracały tu karty, a flagi kasuje
    /// wylogowanie: każde ponowne logowanie pokazywało onboarding od nowa,
    /// choć zgoda była zapisana na serwerze.
    private var currentStep: IntroStep? {
        if gateActive {
            switch introStep {
            case .hero: return .hero
            case .consent: return .consent
            default: return welcomeSeen ? .consent : .hero
            }
        }
        return introStep
    }

    /// Kierunek trafia do drzewa widoków PRZED zmianą kroku, w osobnym
    /// obiegu pętli zdarzeń — razem ze zmianami stanu, od których zależy
    /// `currentStep` (`sideEffects`). Przejście wyjścia SwiftUI bierze
    /// z ostatniego renderu widoku, który znika: gdyby kierunek i krok
    /// zmieniły się w jednej transakcji, strona schodząca wyjeżdżałaby
    /// jeszcze w poprzednim kierunku i przy „Wstecz" obie spotykały się na
    /// tej samej krawędzi. Ta sama sztuczka w `FeatureTourView` i `WelcomeView`.
    private func goToStep(_ step: IntroStep, alongside sideEffects: (() -> Void)? = nil) {
        introDirection = step.order >= (currentStep?.order ?? 0) ? 1 : -1
        DispatchQueue.main.async {
            sideEffects?()
            introStep = step
        }
    }

    /// Po zgodzie: karty tylko za pierwszym razem. Kto cofnął zgodę i włącza
    /// ją ponownie (albo dostał 403 w środku rozmowy), wraca prosto do
    /// rozmowy — onboarding i „Od czego zaczniemy?" zostają pod menu ⋯.
    private func continueAfterConsent() {
        // Zdejmuje blokadę 403 (`needsConsent`) także wtedy, gdy zgoda była
        // już zapisana po stronie serwera, a store o tym nie wiedział.
        let unlock = {
            store.consentGranted()
            if store.retryText != nil { retry() }
        }
        if onboardingSeen {
            unlock()
            finishIntro()
        } else {
            // Odblokowanie zmienia `currentStep` — musi iść razem z krokiem,
            // po ustawieniu kierunku (patrz `goToStep`).
            goToStep(.cards, alongside: unlock)
        }
    }

    /// Przykład stuknięty w arkuszu z menu. Bez zgody nie ma czego wysyłać
    /// (serwer odpowie 403) — zamiast tego prowadzi do kroku „Zgoda";
    /// w trakcie kart kończy przepływ i wysyła.
    private func askFromSheet(_ text: String) {
        if gateActive {
            goToStep(.consent) { welcomeSeen = true }
            return
        }
        if currentStep != nil { finishIntro() }
        ask(text)
    }

    /// „Zaczynajmy" / „Pomiń": rozmowa z kursorem w polu.
    private func startConversation() {
        finishIntro()
        // Pole pojawia się razem z rozmową — fokus dopiero, gdy już jest
        // w hierarchii.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isComposerFocused = true }
    }

    /// Koniec przepływu: flagi na stałe, rozmowa. „Co potrafi" i „Jak działa"
    /// zostają pod menu ⋯.
    private func finishIntro() {
        withAnimation(.easeOut(duration: 0.28)) {
            introStep = nil
            welcomeSeen = true
            onboardingSeen = true
        }
    }

    /// Bez zgody (403 z serwera albo stan z `/me/consents`) zakładka pokazuje
    /// bramkę. Zanim stan zgód się wczyta, nie zgadujemy — pokazujemy rozmowę.
    private var gateActive: Bool {
        if store.needsConsent { return true }
        guard let consents = sessionStore.consentStore else { return false }
        // Bramka, dopóki NIE wiemy na pewno, że zgoda jest. Nowy użytkownik
        // widział rozmowę zamiast „Zanim zaczniemy", bo stan zgód wczytywał się
        // po pierwszym renderze, a starszy serwer bez pól wersji nie wczytywał
        // się wcale. Ktoś ze zgodą, którego stan chwilowo nie doszedł, widzi
        // bramkę jeszcze raz — jedno stuknięcie, bez szkody.
        return !(consents.isLoaded && consents.assistantGranted)
    }

    /// Bramka i onboarding to nie rozmowa — nagłówek zostaje duży, nawet
    /// gdy konto ma stare rozmowy (tytuł starej rozmowy nad „Zanim
    /// zaczniemy" wyglądał na błąd).
    private var headerMode: AssistantHeaderMode {
        (store.messages.isEmpty || currentStep != nil) ? .large : .compact(title: conversationTitle)
    }

    /// Plakietka puli w nagłówku — tylko na próbie. W planie miesięcznym
    /// pula jest na tyle duża, że licznik w nagłówku byłby szumem.
    /// W kompaktowym pasku bez etykiety — miejsce ma tytuł rozmowy.
    private var quotaPips: AnyView? {
        guard let usage = store.usage, usage.isTrial else { return nil }
        return AnyView(
            Button { showUsage = true } label: {
                AssistantQuotaPips(
                    remaining: usage.messages.remaining,
                    limit: usage.messages.limit,
                    showsLabel: headerMode == .large
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Otwiera limity asystenta")
        )
    }

    /// Ile wiadomości zostało z puli PRÓBNEJ; `nil` w planie miesięcznym
    /// albo gdy jeszcze nie znamy liczb.
    private var conversationTitle: String? {
        guard let id = store.conversationId else { return nil }
        return store.conversations.first { $0.id == id }?.title
    }

    // MARK: - Rozmowa

    /// Powitanie z tego, co aplikacja wie o tej chwili — patrz `AssistantWelcome`.
    private var welcome: AssistantWelcome {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        // Tydzień od poniedziałku, jak wszędzie w aplikacji (`PlanWeek`).
        let weekday = calendar.component(.weekday, from: today)
        let sinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -sinceMonday, to: today) ?? today
        let plan = sessionStore.mealCalendarStore
        func planned(_ date: Date) -> Int { plan?.plan(for: date).plannedSlots.count ?? 0 }
        func plannedDays(from start: Date) -> Int {
            (0..<7).reduce(0) { total, offset in
                let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                return total + (planned(day) > 0 ? 1 : 0)
            }
        }
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        return AssistantWelcome.compose(
            .init(
                now: now,
                calendar: calendar,
                displayName: UserDefaults.standard.string(forKey: "settings.user.displayName"),
                plannedToday: planned(today),
                plannedTomorrow: planned(tomorrow),
                plannedDaysThisWeek: plannedDays(from: monday),
                plannedDaysNextWeek: plannedDays(from: nextMonday)
            )
        )
    }

    /// Pusta rozmowa NIE jest listą: nie ma czego przewijać, więc nie ma
    /// przewijania ani odbicia. Powitanie stoi na środku wolnego miejsca
    /// między nagłówkiem a polem; lista z kotwicami i rozpórką wchodzi
    /// dopiero z pierwszym pytaniem.
    private var isConversationEmpty: Bool {
        store.messages.isEmpty && !store.isLoadingHistory && !store.isSending
    }

    @ViewBuilder
    private var conversation: some View {
        if isConversationEmpty {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, SCPageMetrics.horizontal)
            // Bez ScrollView nie działa `scrollDismissesKeyboard`, więc na
            // pustym ekranie klawiatury nie dało się schować niczym poza
            // wysłaniem. Całe wolne tło łapie stuknięcie i zdejmuje fokus.
            .contentShape(Rectangle())
            .onTapGesture { isComposerFocused = false }
            .transition(.opacity)
        } else {
            messageList
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.isLoadingHistory && store.messages.isEmpty {
                            ChatSkeleton()
                        }

                        // Wszystko PRZED ostatnim pytaniem — bez żadnej animacji.
                        ForEach(Array(store.messages.prefix(slotStart).enumerated()), id: \.element.id) { index, message in
                            bubble(at: index, message)
                        }

                        turnSlot

                        // Koniec TREŚCI — tu ląduje strzałka „na dół". Osobno
                        // od rozpórki niżej, bo przewinięcie do jej dołu
                        // wypychało ostatnią wiadomość o całą jej wysokość
                        // w górę i zostawiało pod nią pusty ekran.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.tailAnchor)

                        // Rozpórka: bez niej ScrollView nie ma dokąd przewinąć
                        // i początku długiej odpowiedzi nie da się wypchnąć pod
                        // górną krawędź. Tyle, ile trzeba na kartę i akcje —
                        // każdy piksel ponad to jest pustką, przez którą
                        // użytkownik musi przewijać z powrotem.
                        Color.clear
                            .frame(height: 120)
                            .id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, SCPageMetrics.horizontal)
                    .padding(.bottom, 12)
                    // BEZ `.animation(value: store.isSending)` na liście:
                    // `isSending` przełącza się ZAWSZE w jednej transakcji
                    // z dopisaniem pytania, pustego stanu, separatora „Dziś"
                    // albo całej odpowiedzi — i wszystko to dostawało animację
                    // układu. Jedyne animowane przejście siedzi w `turnSlot`.
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    // „Na końcu" liczy się od KOŃCA TREŚCI (`tailAnchor`), nie
                    // od końca rozpórki: próg 80 pt był mniejszy niż sama
                    // rozpórka (120 + 12), więc po stuknięciu strzałki
                    // rozmowa stawała na końcu treści, a strzałka wciąż
                    // wisiała, bo do dna zostawało 132 pt.
                    // Z żywym slotem dno treści leży o wysokość OKNA pod
                    // pytaniem, a przy klawiaturze okno jest krótsze — dno
                    // fizycznie nie wchodzi w widok, choć użytkownik stoi
                    // „na końcu". Liczymy więc wobec nieskróconego okna;
                    // inaczej pigułka zapalała się przy każdym stuknięciu
                    // w pole i mrugała, gdy klawiatura chowała się przy wysyłce.
                    let window = store.hasLiveTurnSlot
                        ? max(geometry.containerSize.height, viewportHeight)
                        : geometry.containerSize.height
                    return geometry.contentOffset.y + window
                        >= geometry.contentSize.height - Self.bottomSlack
                } action: { _, atBottom in
                    isPinnedToBottom = atBottom
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.containerSize.height
                } action: { _, height in
                    // Tylko rośnie: klawiatura nie ma prawa skracać slotu
                    // i „pompować" listy przy każdym fokusie pola.
                    if height > viewportHeight { viewportHeight = height }
                }
                .onChange(of: slotKey) { _, _ in
                    // Własne pytanie wypychamy POD GÓRNĄ KRAWĘDŹ (wzorzec
                    // ChatGPT): wskaźnik stoi 14 pt niżej, a odpowiedź wyłoni
                    // się w jego miejscu — bez przewijania. Zawieszone na
                    // TOŻSAMOŚCI pytania, nie na liczbie wiadomości: „Popraw
                    // pytanie" ostatniego pytania bez odpowiedzi (po „Stop",
                    // po błędzie tury) zdejmuje jedno i dopisuje jedno, więc
                    // liczba stoi w miejscu — a slot i tak dostaje nowy
                    // `ZStack` z minimalną wysokością. Bez przewinięcia pytanie
                    // zostawało tam, gdzie stało, pod nim wyrastał ekran pustki
                    // i zapalała się pigułka „na dół". Historia wczytana
                    // z serwera też zmienia tożsamość, ale bez żywego slotu.
                    guard store.isSending, store.hasLiveTurnSlot,
                          store.messages.last?.author == .user else { return }
                    scroll(proxy, to: Self.turnAnchor, anchor: .top)
                }
                .onChange(of: store.messages.count) { old, _ in
                    // Własne pytanie ma swoje przewinięcie wyżej (`slotKey`)
                    // — tu nie wolno go dublować ani przebijać „dołem"
                    // historii, gdy pierwsze pytanie w rozmowie robi 0 → 1.
                    // Odpowiedź tury NIE przewija nic: to jest ta sekunda, na
                    // którą się czekało, i ekran ma wtedy stać. Historia
                    // (0 → N) otwiera się na dole, jak dotąd.
                    if store.isSending, store.hasLiveTurnSlot, store.messages.last?.author == .user {
                        return
                    }
                    if old == 0 {
                        scroll(proxy, to: Self.tailAnchor, anchor: .bottom)
                    } else if old < store.messages.count,
                              let last = store.messages.last, last.author == .assistant,
                              last.thinking == nil || !store.hasLiveTurnSlot {
                        // Odpowiedź SPOZA żywego slotu nie ma pod pytaniem
                        // pustego pola, w którym mogłaby się wyłonić:
                        // potwierdzenie propozycji („Dodaj do planu"/„Cofnij",
                        // bez `thinking`) ląduje pod kartą, a odpowiedź tury
                        // podjętej z serwera rośnie od dolnej krawędzi w dół
                        // i widać z niej sam wiersz „Myślałem". Jak dotąd:
                        // początek pod górną krawędź. Odpowiedź tury z TEJ
                        // sesji zostaje bez przewinięcia — to jest ta sekunda,
                        // na którą się czekało, i ekran ma wtedy stać.
                        scroll(proxy, to: last.id, anchor: .top)
                    }
                }
                .onChange(of: store.isSending) { _, sending in
                    // Tura podjęta z serwera (powrót na zakładkę, relaunch):
                    // wskaźnik wchodzi pod ostatnią wiadomość historii, która
                    // stoi przy dolnej krawędzi — bez tego siedziałby tuż pod
                    // nią, poza ekranem. Własne pytanie ma swoje przewinięcie
                    // wyżej i slot z minimalną wysokością, więc tu go nie ma.
                    guard sending, !store.hasLiveTurnSlot else { return }
                    scroll(proxy, to: Self.tailAnchor, anchor: .bottom)
                }
                .onChange(of: store.errorMessage) { _, newValue in
                    // Notka stoi w slocie pod pytaniem, więc zwykle jest
                    // widoczna — przewijamy tylko, gdy ktoś odjechał w górę.
                    guard newValue != nil, !isPinnedToBottom else { return }
                    scroll(proxy, to: Self.errorAnchor, anchor: .bottom)
                }
                .onChange(of: isComposerFocused) { _, focused in
                    guard focused, let last = store.messages.last else { return }
                    if store.hasLiveTurnSlot {
                        // Pytanie zostaje pod górną krawędzią, a klawiatura
                        // zasłania pustkę slotu. Ostatnia odpowiedź „do dna"
                        // zostawiała pod krótką odpowiedzią pół ekranu pustki
                        // i zapalała pigułkę przy każdym stuknięciu w pole.
                        scroll(proxy, to: Self.turnAnchor, anchor: .top)
                    } else {
                        scroll(proxy, to: last.id, anchor: .bottom)
                    }
                }
                // Wibracja tylko przy ODPOWIEDZI — przy każdej wiadomości
                // (także własnej) byłaby szumem.
                .sensoryFeedback(.success, trigger: answerCount)
                .sensoryFeedback(.error, trigger: store.errorMessage)

                // Jak w ChatGPT: pojawia się i znika płynnie, a nie skokiem,
                // i tylko wtedy, gdy naprawdę jest dokąd zjechać.
                if !isPinnedToBottom && !isAutoScrolling && !store.messages.isEmpty {
                    scrollToBottomPill(proxy)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.22), value: isPinnedToBottom)
            .animation(.smooth(duration: 0.22), value: isAutoScrolling)
        }
    }

    private func scrollToBottomPill(_ proxy: ScrollViewProxy) -> some View {
        Button {
            scroll(proxy, to: Self.tailAnchor, anchor: .bottom)
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.scCardSurface(scheme)))
                .overlay(Circle().stroke(Color.scCardStroke(scheme), lineWidth: 1))
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
        .accessibilityLabel("Na koniec rozmowy")
    }

    private var emptyState: some View {
        AssistantEmptyState(welcome: welcome)
    }

    /// Podpowiedzi tuż nad polem, dosunięte do prawej jak dymki
    /// użytkownika. TYLKO na pustej rozmowie — pomagają zacząć. W trwającej
    /// rozmowie ich nie ma: „Podmień jedno danie" pod każdą odpowiedzią było
    /// szumem, a po błędzie czasu wystarczy komunikat z ponowieniem.
    private var composerHints: [String]? {
        guard !store.isSending, store.messages.isEmpty else { return nil }
        return welcome.quickStarts
    }

    // MARK: - Pole wiadomości

    private var composer: some View {
        VStack(spacing: 0) {
            // Podpowiedzi NAD kreską pola — należą do rozmowy, nie do
            // klawiatury; dosunięte do prawej jak dymki użytkownika.
            if let hints = composerHints {
                AssistantQuickReplies(items: hints, alignment: .trailing, onTap: ask)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }

            if editing != nil {
                editingBar
            }

            // Jedyny moment, w którym aplikacja sama zaczyna rozmowę o
            // pieniądzach — i mówi wtedy jedną linijką, bez kafla, bez ikony
            // i bez przycisku. Pole tekstowe zostaje na miejscu.
            if store.isLockedByTrialQuota {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Darmowe wiadomości wykorzystane.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                    Button { showPaywall = true } label: {
                        Text("Zobacz plany")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(SCPalette.terracotta)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
            }
            // Bez linijki „Zostały 2 wiadomości" nad polem: to samo mówią
            // kropki w nagłówku (5 z zaznaczonymi pozostałymi), a stuknięcie
            // w nie otwiera limity.

            // Pole i przycisk stoją ciaśniej niż reszta ekranu (8 pt zamiast
            // marginesu strony, 6 pt między nimi, przycisk 40 zamiast 44) —
            // każdy z tych punktów idzie na szerokość tekstu. Przy poprzednim
            // układzie dłuższe pytanie („zaplanuj mi obiady na cały tydzień
            // bez laktozy") mieściło w wierszu kilka słów i użytkownik nie
            // widział, co pisze.
            HStack(alignment: .bottom, spacing: 6) {
                TextField(
                    store.isUnavailable
                        ? "Asystent jest teraz niedostępny"
                        : (store.isLockedByTrialQuota
                            ? "Limit na próbę wykorzystany"
                            : (store.isLocked ? "Chwila przerwy — spróbuj za moment" : "Napisz do asystenta…")),
                    text: $draft,
                    axis: .vertical
                )
                // Do ośmiu wierszy: pytanie do asystenta bywa całym akapitem
                // („mamy gości w sobotę, dwie osoby bez glutenu…"), a przy
                // pięciu wierszach początek uciekał poza pole.
                .lineLimit(1...8)
                .font(.system(size: 15.5))
                .tracking(-0.25)
                .foregroundStyle(Color.scLabel(scheme))
                .focused($isComposerFocused)
                .disabled(store.isUnavailable || store.isLocked)
                // Jawne `maxWidth: .infinity`: bez tego pole brało szerokość
                // wpisanego tekstu i rosło dopiero z nim, zamiast od razu
                // zająć cały wiersz obok przycisku.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // Liquid Glass jak dolne menu tuż pod nim (precedens:
                // `PlanDayGoalBar`). Kapsuła, nie prostokąt: przy jednym
                // wierszu to dokładnie kształt pola wyszukiwania systemu,
                // a przy ośmiu wierszach `.capsule` zaokrągla rogi do
                // połowy wysokości i dalej wygląda jak pole, nie jak karta.
                // Warstwa tła POD szkłem przygasza przelatującą rozmowę —
                // samo szkło przepuszczało litery na tyle wyraźnie, że przy
                // krawędzi wyglądały jak artefakt.
                .glassEffect(
                    .regular.tint(Color.scPageBase(scheme).opacity(0.35)).interactive(),
                    in: .capsule
                )
                .background(Color.scPageBase(scheme).opacity(0.6), in: .capsule)

                // W trakcie tury strzałka zamienia się w „stop": po dziesięciu
                // sekundach widać już, że pytanie było źle zadane, a czekanie
                // do końca nie daje nic poza czekaniem.
                //
                // Wariant „soft" jak reszta akcji w aplikacji: terakota na
                // własnym tincie z obwódką, nie pełne koło — pełne było
                // jedynym nasyconym punktem na ekranie i ciągnęło wzrok
                // bardziej niż sama rozmowa.
                //
                // Po wciśnięciu „stop" przycisk WYGASA razem z wierszem
                // „Zatrzymuję…": `stopWaiting()` i tak ignoruje kolejne
                // stuknięcia (serwer domyka turę w swoim tempie, w środku
                // narzędzia planisty to bywa 30–60 s), a pełna terakota bez
                // reakcji czytała się jak zignorowany przycisk.
                Button {
                    if store.isSending { store.stopWaiting() } else { send() }
                } label: {
                    Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: store.isSending ? 13 : 16, weight: .bold))
                        .foregroundStyle(sendTint)
                        .frame(width: 44, height: 44)
                        // Ten sam materiał co pole obok — dwa kształty z jednego
                        // szkła czytają się jako jeden pasek, nie pole + guzik.
                        .glassEffect(
                            .regular.tint(sendTint.opacity(0.18)).interactive(),
                            in: .circle
                        )
                        .background(Color.scPageBase(scheme).opacity(0.6), in: .circle)
                }
                .buttonStyle(.plain)
                .disabled((!store.isSending && !canSend) || store.isStopping)
                .accessibilityLabel(sendAccessibilityLabel)
                .animation(.easeOut(duration: 0.2), value: store.isStopping)
            }
            // 20 pt = margines boczny pływającego paska zakładek z iOS 26
            // (zmierzone na 402-pt ekranie: pasek stoi od 20 do 382 pt).
            // Pole z przyciskiem ma być z nim w jednej linii, bo stoi tuż nad
            // nim i z tego samego szkła — inna szerokość czyta się jak dwa
            // elementy z dwóch różnych ekranów.
            .padding(.horizontal, 20)
            .padding(.top, 8)
            // 8 nad dolnym menu: pole ma wisieć tuż nad szkłem menu, tak jak
            // pasek celu dnia na Planie — nie na własnej półce.
            .padding(.bottom, 8)
        }
        // Chipy nad polem znikają przy pierwszym pytaniu — composer kurczył
        // się wtedy o ~46 pt skokiem, razem z nagłówkiem i pustym stanem.
        .animation(.easeInOut(duration: 0.2), value: composerHints == nil)
    }

    /// Pasek „Poprawiasz pytanie".
    ///
    /// Bez niego pole z wpisanym starym tekstem wygląda jak zwykłe pole,
    /// a wysłanie kasuje pół rozmowy bez ostrzeżenia. Pasek mówi, co się
    /// stanie, i daje drogę odwrotu.
    private var editingBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SCPalette.butter)

            VStack(alignment: .leading, spacing: 1) {
                Text("Poprawiasz pytanie")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))
                Text("Odpowiedzi po nim znikną z rozmowy")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.scFaint(scheme))
            }

            Spacer(minLength: 0)

            Button {
                draft = ""
                editing = nil
                isComposerFocused = false
            } label: {
                Text("Anuluj")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.scButterTint(scheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.scRule(scheme)).frame(height: 1)
        }
    }

    private var canSend: Bool {
        store.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Akcent przycisku wysyłania. Nieaktywny schodzi na przygaszony
    /// neutralny — tint i obwódka liczą się z tego samego koloru, więc
    /// przycisk wygasa w całości, a nie tylko glifem.
    private var sendTint: Color {
        // „Zatrzymuję…" gasi przycisk jak każdy nieaktywny — stop już
        // poszedł i drugi nic nie zrobi.
        if store.isStopping { return Color.scMuted(scheme).opacity(0.55) }
        if store.isSending { return SCPalette.terracotta }
        return canSend ? SCPalette.terracotta : Color.scMuted(scheme).opacity(0.55)
    }

    private var sendAccessibilityLabel: String {
        if store.isStopping { return "Zatrzymuję" }
        return store.isSending ? "Zatrzymaj turę" : "Wyślij"
    }

    private var answerCount: Int {
        store.messages.filter { $0.author == .assistant }.count
    }

    // MARK: - Akcje

    /// Zdjęcie bez pytania to też pytanie.
    ///
    /// Serwer wymaga treści wiadomości, a użytkownik, który zrobił zdjęcie
    /// lodówki, powiedział już wszystko. Zamiast blokować wysyłkę pustym
    /// polem, wpisujemy za niego to jedno zdanie, o które i tak by chodziło.
    /// Poprawiana wiadomość: co poprawiamy i od czego zaczęliśmy.
    private struct EditingMessage: Equatable {
        let id: String
        let originalText: String
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, store.canSend else { return }

        let edited = editing
        draft = ""
        editing = nil
        isComposerFocused = false
        Task {
            if let edited {
                await store.editMessage(
                    messageId: edited.id,
                    text: text,
                    weekStart: datesViewModel.weekStartISO
                )
            } else {
                await store.send(
                    text: text,
                    weekStart: datesViewModel.weekStartISO
                )
            }
        }
    }

    /// Wejście w tryb poprawki: pytanie wraca do pola, gotowe do zmiany.
    private func beginEditing(_ message: AgentChatMessage) {
        editing = EditingMessage(id: message.id, originalText: message.text)
        draft = message.text
        isComposerFocused = true
    }

    /// Kręciołek siedzi w TEJ karcie, której przycisk został naciśnięty.
    private func isBusy(_ message: AgentChatMessage) -> Bool {
        guard let proposalId = message.card?.proposalId else { return false }
        return store.busyProposalId == proposalId
    }

    /// „Zmień" nie wysyła nic samo z siebie.
    ///
    /// Tura kosztuje pieniądze i pół minuty, a „zmień coś" nie mówi modelowi
    /// nic. Zamiast tego otwieramy klawiaturę z początkiem zdania — użytkownik
    /// dopowiada, CO zmienić, i dopiero to jedzie na serwer.
    private func revise() {
        draft = "Zmień w tej propozycji: "
        isComposerFocused = true
    }

    /// „Poproś o nową” z karty STALE/EXPIRED — gotowe zdanie, bez zapisu.
    private func askForFreshProposal() {
        ask("Przelicz tę propozycję na nowo na aktualnym planie")
    }

    private func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, store.canSend else { return }
        draft = ""
        isComposerFocused = false
        // Tekst, który nie doszedł, wraca przyciskiem „Spróbuj ponownie" przy
        // komunikacie błędu — z tym samym kluczem idempotencji. Oddawanie go
        // JEDNOCZEŚNIE do pola dawało dwie drogi wysyłki tego samego pytania
        // i realny podwójny rachunek.
        Task {
            await store.send(text: trimmed, weekStart: datesViewModel.weekStartISO)
        }
    }

    private func retry() {
        Task {
            await store.retry(weekStart: datesViewModel.weekStartISO)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String?, anchor: UnitPoint) {
        guard let id else { return }
        // Numer pokolenia, nie flaga: dwa przewinięcia pod rząd (pytanie,
        // potem błąd) nie mogą odsłonić pigułki, zanim skończy się drugie.
        autoScrollGeneration += 1
        let generation = autoScrollGeneration
        isAutoScrolling = true
        if reduceMotion {
            proxy.scrollTo(id, anchor: anchor)
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
        Task {
            // Dłużej niż samo przewinięcie (0,25 s): ostatni odczyt geometrii
            // przychodzi klatkę po jego końcu.
            try? await Task.sleep(for: .seconds(0.4))
            if autoScrollGeneration == generation { isAutoScrolling = false }
        }
    }

    /// Rozwinięcie po id wiadomości jako `Binding<Bool>` dla wiersza — stan
    /// mieszka w ekranie, więc przeżywa przeprowadzkę wiersza ze slotu do
    /// części przed slotem (patrz `expandedCards`).
    private func expansion(of id: String, in keys: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { keys.wrappedValue.contains(id) },
            set: { expanded in
                if expanded {
                    keys.wrappedValue.insert(id)
                } else {
                    keys.wrappedValue.remove(id)
                }
            }
        )
    }

    // MARK: - Slot ostatniej tury

    /// Indeks ostatniego pytania — od niego zaczyna się slot ostatniej tury.
    private var lastUserIndex: Int? { store.messages.lastIndex { $0.author == .user } }
    private var slotStart: Int { lastUserIndex ?? store.messages.count }

    /// Tożsamość slotu = ostatnie pytanie. Nowe pytanie dostaje NOWY `ZStack`
    /// zamiast animowanego przełączenia starego: inaczej odpowiedzi poprzedniej
    /// tury gasłyby przez 0,28 s pod nowym pytaniem (duch), podczas gdy te
    /// same odpowiedzi już stoją wyżej, w części przed slotem.
    private var slotKey: String {
        guard let index = lastUserIndex else { return "assistant.turn.none" }
        // Własna przestrzeń nazw: sam `message.id` wisi już na dymku pytania
        // tuż wyżej, a `scrollTo(last.id)` przy fokusie pola trafiałoby
        // w dwa widoki naraz i stawało raz na dymku, raz na slocie.
        return "assistant.slot." + store.messages[index].id
    }

    /// Wzorzec ChatGPT: ostatnia tura ma co najmniej wysokość okna, żeby pytanie
    /// dało się wypchnąć pod górną krawędź, a odpowiedź wyłaniała się w pustym
    /// polu pod nim — bez przewijania i bez ruchu czegokolwiek nad nią.
    private var slotMinHeight: CGFloat {
        store.hasLiveTurnSlot ? max(0, viewportHeight - Self.belowSlot) : 0
    }

    /// Jawna właściwość zamiast `reduceMotion ? nil : …` w argumencie (SE-0418).
    private var slotAnimation: Animation? {
        if reduceMotion { return nil }
        return .easeInOut(duration: 0.28)
    }

    /// Jeden wiersz rozmowy — wspólny dla części przed slotem i dla slotu,
    /// żeby oba rysowały identycznie. Indeks jest GLOBALNY (separator dnia
    /// i odpowiedź na kartę pytania patrzą na sąsiadów).
    @ViewBuilder
    private func bubble(at index: Int, _ message: AgentChatMessage) -> some View {
        if let separator = daySeparator(at: index) {
            DaySeparator(text: separator)
        }

        MessageBubble(
            message: message,
            isBusy: isBusy(message),
            // Odpowiedź użytkownika, która nastąpiła po tej wiadomości —
            // karta pytania zaznacza nią wybraną opcję zamiast domyślnej
            // z serwera.
            reply: reply(after: index),
            isCardExpanded: expansion(of: message.id, in: $expandedCards),
            isThoughtExpanded: expansion(of: message.id, in: $expandedThoughts),
            onOpenPlan: { sessionStore.dashboardTab = .plan },
            onOpenShopping: {
                // Lista zakupów jest arkuszem w Planie, więc sama zakładka
                // to za mało.
                sessionStore.opensShoppingList = true
                sessionStore.dashboardTab = .plan
            },
            onAskAgain: { ask(message.text) },
            onApply: { id, force in
                Task { await store.applyProposal(id: id, force: force) }
            },
            onUndo: { id in
                Task { await store.undoProposal(id: id) }
            },
            onRevise: { revise() },
            onAskNew: { askForFreshProposal() },
            onAsk: { prompt in ask(prompt) },
            onEdit: { beginEditing(message) },
            onReport: { reporting = message }
        )
        .id(message.id)
    }

    /// Slot ostatniej tury: pytanie + ALBO wskaźnik, ALBO odpowiedzi tej tury
    /// (i ewentualna notka błędu). Insert/remove dzieje się w zwykłym `ZStack`,
    /// nie na poziomie `LazyVStack` — tam przejścia są przewidywalne, a tu
    /// `apply(finished:)` i `defer` w `followTurn` przełączają obie strony
    /// w jednej transakcji, więc to czysty crossfade w miejscu: glif tury
    /// staje się glifem „Myślałem", tekst kroku — czasem, treść wyrasta pod nim.
    private var turnSlot: some View {
        VStack(alignment: .leading, spacing: 14) {
            if slotStart < store.messages.count {
                bubble(at: slotStart, store.messages[slotStart])
            }
            ZStack(alignment: .topLeading) {
                if store.isSending {
                    VStack(alignment: .leading, spacing: 12) {
                        AssistantThinkingLine(
                            steps: store.progress,
                            // `.distantPast` nie ma prawa wejść: `send()`,
                            // `editMessage()` i start `followTurn` ustawiają epokę
                            // razem z `isSending`.
                            startedAt: store.turnStartedAt ?? .distantPast,
                            isStopping: store.isStopping
                        )
                        // Odpowiedź pisze się POD wierszem, zanim tura się
                        // domknie — a po domknięciu ten sam tekst zostaje
                        // w miejscu jako `AssistantAnswer`, więc crossfade
                        // niżej podmienia identyczne piksele.
                        if !store.draftText.isEmpty {
                            AssistantDraftAnswer(text: store.draftText)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: store.draftText.isEmpty)
                    // Wyjście (wiersz → odpowiedź) animuje ten `ZStack`; wejście
                    // pod NOWYM pytaniem robi sam wiersz (`appeared`), bo
                    // `.id(slotKey)` niżej stawia go w nieanimowanej transakcji.
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(store.messages.enumerated().dropFirst(slotStart + 1)), id: \.element.id) { index, message in
                            bubble(at: index, message)
                        }
                        if let errorMessage = store.errorMessage {
                            ErrorNote(
                                text: errorMessage,
                                // Domknięcie, a nie referencja `retry`: pod
                                // `InferSendableFromCaptures` (SE-0418, włączone
                                // w tym projekcie) referencja do metody obok `nil`
                                // w wyrażeniu warunkowym daje dwa równorzędne
                                // rozwiązania typu i CAŁY `ScrollView` przestaje
                                // się kompilować („ambiguous use of 'init'"),
                                // ze wskazaniem na linię 60 wierszy wyżej.
                                // Jawny typ tu nie pomaga — tylko domknięcie.
                                onRetry: store.retryText == nil ? nil : { retry() }
                            )
                            .id(Self.errorAnchor)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(slotAnimation, value: store.isSending)
            .id(slotKey)
        }
        .frame(minHeight: slotMinHeight, alignment: .top)
        .id(Self.turnAnchor)
    }

    /// Pierwsza wiadomość użytkownika PO danej pozycji — to nią odpowiedział
    /// na pytanie asystenta. Zatrzymujemy się na kolejnej odpowiedzi
    /// asystenta: pytanie bez odpowiedzi przed nią zostało pominięte.
    private func reply(after index: Int) -> String? {
        guard store.messages[index].card?.isClarify == true else { return nil }
        for next in store.messages[(index + 1)...] {
            if next.author == .user { return next.text }
            return nil
        }
        return nil
    }

    /// Napis separatora, gdy wiadomość zaczyna nowy dzień.
    private func daySeparator(at index: Int) -> String? {
        guard let date = store.messages[index].createdAt else { return nil }
        if index == 0 { return Self.dayLabel(date) }
        guard let previous = store.messages[index - 1].createdAt else {
            return Self.dayLabel(date)
        }
        guard !Calendar.current.isDate(previous, inSameDayAs: date) else { return nil }
        return Self.dayLabel(date)
    }

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Dziś" }
        if calendar.isDateInYesterday(date) { return "Wczoraj" }
        return dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }()

    private static let turnAnchor = "assistant.turn"
    private static let errorAnchor = "assistant.error"
    /// Co stoi pod slotem ostatniej tury: spacing 14 + tail 1 + spacing 14
    /// + rozpórka 120 + padding 12. Slot o wysokości `okno − belowSlot`
    /// stawia dno treści dokładnie na dolnej krawędzi, gdy pytanie jest u góry.
    private static let belowSlot: CGFloat = 161
    private static let bottomAnchor = "assistant.bottom"
    private static let tailAnchor = "assistant.tail"
    /// Ile od dna treści liczy się jeszcze jako „na końcu": rozpórka
    /// (120) + dolny padding (12) + luz na jeden gest.
    private static let bottomSlack: CGFloat = 120 + 12 + 48
}

/// Zakładka asystenta, zanim sesja postawi store'y (zimny start, brak
/// gospodarstwa). Pusta zakładka wyglądałaby na awarię aplikacji.
struct AssistantUnavailableView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                EditorialPageHeader("Asystent")

                Text("Asystent będzie dostępny, gdy wczyta się gospodarstwo.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.scMuted(scheme))

                Spacer()
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.top, SCPageMetrics.top)
            // Ten sam warunek co w `AssistantView` — inaczej tytuł podskakuje
            // o wysokość paska statusu w chwili, gdy gospodarstwo się wczyta.
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

// MARK: - Separator dnia

private struct DaySeparator: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.scMuted(scheme))
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }
}

// MARK: - Dymek

/// Wiadomość w rozmowie.
///
/// Dwa różne kształty, bo to dwie różne treści: pytanie użytkownika to jedno
/// zdanie i zachowuje się jak dymek, a odpowiedź asystenta bywa całym
/// tygodniem — dostaje więc pełną szerokość i strukturę (nagłówki, kafelki
/// dni) zamiast ściany tekstu wciśniętej w dymek.
private struct MessageBubble: View {
    let message: AgentChatMessage
    let isBusy: Bool
    /// Treść następnej wiadomości użytkownika; `nil`, gdy jeszcze nie
    /// odpowiedział. Tylko karta pytania z tego korzysta.
    var reply: String? = nil
    /// Rozwinięcia trzyma ekran (po id wiadomości), nie wiersz — wiersz
    /// zmienia miejsce w drzewie między slotem a częścią przed nim.
    @Binding var isCardExpanded: Bool
    @Binding var isThoughtExpanded: Bool
    let onOpenPlan: () -> Void
    let onOpenShopping: () -> Void
    let onAskAgain: () -> Void
    /// `force` = „Zapisz mimo to”.
    let onApply: (String, Bool) -> Void
    let onUndo: (String) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    let onAsk: (String) -> Void
    let onEdit: () -> Void
    let onReport: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if message.author == .user {
            userBubble
                .contextMenu { menuItems }
                .accessibilityLabel("Ty: \(message.text)")
        } else {
            assistantCard
                .contextMenu { menuItems }
                .accessibilityLabel("Asystent: \(message.text)")
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("Kopiuj", systemImage: "doc.on.doc")
        }

        ShareLink(item: message.text) {
            Label("Udostępnij", systemImage: "square.and.arrow.up")
        }

        if message.author == .user {
            Button(action: onEdit) {
                Label("Popraw pytanie", systemImage: "pencil")
            }

            Button(action: onAskAgain) {
                Label("Zapytaj jeszcze raz", systemImage: "arrow.clockwise")
            }
        } else {
            // Obiecane w FAQ i w regulaminie („Zgłoś odpowiedź”) — idzie na
            // `POST /agent/messages/:id/report`, nie zmienia rozmowy.
            Button(role: .destructive, action: onReport) {
                Label("Zgłoś odpowiedź", systemImage: "flag")
            }
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)

            VStack(alignment: .trailing, spacing: 0) {
                Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.scAccentTint(scheme))
                )
            }
            // Wysłana, jeszcze niepotwierdzona — subtelnie, bo w 99 %
            // przypadków potwierdzenie przychodzi zanim ktokolwiek zdąży
            // to zauważyć.
            .opacity(message.isPending ? 0.6 : 1)
            // Potwierdzenie przychodzi w osobnej transakcji, po powrocie
            // POST — bez tego dymek mrugał z 60 % na 100 % skokiem.
            .animation(.easeOut(duration: 0.2), value: message.isPending)
        }
    }

    /// Odpowiedź asystenta NIE dostaje dymka.
    ///
    /// Dymek jest gestem konwersacyjnym dobrym dla jednego zdania, a odpowiedź
    /// bywa całym tygodniem — w wąskiej bańce zamienia się w ścianę tekstu.
    /// Pełna szerokość daje treści (a wkrótce kartom) miejsce, którego dymek
    /// nie ma jak dać; rozmowę czyta się po stronie ekranu, nie po ramce.
    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pierwszy wiersz ma geometrię wskaźnika tury — to w niego
            // wskaźnik się zamienia. Tylko dla odpowiedzi z tej sesji.
            if let thinking = message.thinking {
                AssistantThoughtSummary(summary: thinking, isExpanded: $isThoughtExpanded)
            }

            if message.savedPlan {
                AssistantSavedPlanCard(onOpenPlan: onOpenPlan)
            }

            // Karta pytania NIESIE treść wypowiedzi, więc pokazanie obok niej
            // jeszcze `text` znaczyłoby to samo pytanie dwa razy pod rząd.
            if !message.text.isEmpty, message.card?.replacesText != true {
                AssistantAnswer(text: message.text)
            }

            card

            // Po fakcie: z czym asystent to policzył. Pod kartą, żeby nie
            // rozdzielać zdania od tego, co ono opisuje.
            if !message.usedContext.isEmpty {
                AssistantUsedContextLine(items: message.usedContext)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    /// Karta pod odpowiedzią. Nieznany rodzaj znika bez śladu — zostaje samo
    /// zdanie, które i tak niesie sens. To jest cała zgodność wstecz: serwer
    /// może dorzucić nowy rodzaj karty, nie czekając na wydanie aplikacji.
    @ViewBuilder
    private var card: some View {
        switch message.card {
        case .planWeek(let planWeek):
            AssistantPlanWeekCard(
                card: planWeek,
                isBusy: isBusy,
                isExpanded: $isCardExpanded,
                onApply: { force in onApply(planWeek.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: { onUndo(planWeek.proposalId) }
            )
        case .planDay(let planDay):
            AssistantPlanDayCard(
                card: planDay,
                isBusy: isBusy,
                onApply: { force in onApply(planDay.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: { onUndo(planDay.proposalId) }
            )
        case .options(let options):
            AssistantOptionsCard(card: options, onAsk: onAsk)
        case .swap(let swap):
            AssistantSwapCard(
                card: swap,
                isBusy: isBusy,
                onApply: { force in onApply(swap.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: { onUndo(swap.proposalId) }
            )
        case .removeMeal(let removal):
            AssistantRemoveMealCard(
                card: removal,
                isBusy: isBusy,
                onApply: { force in onApply(removal.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: { onUndo(removal.proposalId) }
            )
        case .householdSplit(let split):
            AssistantHouseholdSplitCard(
                card: split,
                isBusy: isBusy,
                onApply: { force in onApply(split.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: { onUndo(split.proposalId) }
            )
        case .macroGap(let macro):
            AssistantMacroGapCard(card: macro, onAsk: onAsk)
        case .shoppingList(let shopping):
            AssistantShoppingListCard(card: shopping, onOpenShopping: onOpenShopping)
        case .clarify(let clarify):
            AssistantClarifyCard(card: clarify, reply: reply, onAsk: onAsk)
        case .applied(let applied):
            AssistantAppliedCard(
                card: applied,
                isBusy: isBusy,
                onUndo: { onUndo(applied.proposalId) },
                onOpenPlan: onOpenPlan
            )
        case .unknown, .none:
            EmptyView()
        }
    }
}

// MARK: - Szkielet ładowania

/// Zaślepki dymków na czas pobierania historii. Bez tego wejście na zakładkę
/// w słabej sieci wygląda jak rozmowa, która zniknęła.
private struct ChatSkeleton: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            skeletonBubble(width: 0.55, isMine: true)
            skeletonBubble(width: 0.9, isMine: false, height: 96)
            skeletonBubble(width: 0.45, isMine: true)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    private func skeletonBubble(
        width: CGFloat,
        isMine: Bool,
        height: CGFloat = 44
    ) -> some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.scTileBg(scheme))
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: width, anchor: isMine ? .trailing : .leading)

            if !isMine { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Błąd

private struct ErrorNote: View {
    let text: String
    /// `nil`, gdy nie ma czego ponawiać — tura, która ruszyła i się nie
    /// domknęła, przy ponowieniu kosztowałaby drugi raz to samo.
    var onRetry: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.top, 1)

                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.scLabel(scheme))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }

            if let onRetry {
                Button(action: onRetry) {
                    Text("Spróbuj ponownie")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.scTileBg(scheme)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scAccentTint(scheme))
        )
    }
}
