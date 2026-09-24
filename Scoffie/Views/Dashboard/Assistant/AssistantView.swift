import Combine
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
    // Reszta profilu pod dzienny cel makro — te same klucze, co Plan
    // i Kalendarz, bo briefing „brakuje Ci białka” ma mówić o TYM SAMYM celu,
    // który pokazuje pigułka „Cel dnia”.
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
    @Environment(\.scTabIsActive) private var isActiveTab
    @FocusState private var isComposerFocused: Bool
    /// Powitanie w trybie pisania (akcje i kontekst zgaszone).
    ///
    /// DLACZEGO NIE SAM FOKUS: powitanie stoi przyklejone do pola, a pole
    /// jedzie z klawiaturą. Fokus przełączał się klatkę PRZED ruchem
    /// klawiatury i zwijał blok własną animacją (`.smooth(0.3)`), a klawiatura
    /// podnosiła go swoją krzywą — otwarcie najpierw opadało o wysokość akcji,
    /// a potem wjeżdżało w górę („przeskakuje, jak zaczynam pisać”). Przy
    /// chowaniu odwrotnie: akcje wracały, zanim klawiatura zjechała, blok
    /// nie mieścił się nad nią, stawał od góry i dopiero potem opadał.
    /// Teraz ten stan zmienia się w powiadomieniu klawiatury, w JEJ krzywej
    /// i w tej samej chwili (`keyboardMoved`) — zwinięcie bloku i ruch pola to
    /// jeden ciągły ruch. Fokus bez klawiatury ekranowej (klawiatura
    /// sprzętowa) przełącza go sam, po chwili (`focusChanged`).
    @State private var greetingComposing = false
    /// Klawiatura ekranowa zasłania dół ekranu.
    @State private var keyboardUp = false
    /// Czas ostatniego ruchu klawiatury (z powiadomienia) — zapasowe
    /// przełączenie w `focusChanged` jedzie w tym samym tempie.
    @State private var keyboardDuration: Double = 0.3
    /// Podbicie = pierwsza litera w polu — znak powitania skinie.
    @State private var typingNudge = 0
    /// Podbicie = tura skończyła się odpowiedzią — znak w nagłówku podskakuje.
    @State private var answerCheer = 0

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
            // Miejsce pod własnym paskiem zakładek: pole wiadomości siada
            // nad nim, a przy klawiaturze rezerwa schodzi do zera.
            .scReservesTabBarSpace()
        }
        .task {
            await store.openIfNeeded()
            // Plakietka puli w nagłówku potrzebuje liczb od razu, nie dopiero
            // po pierwszym 429. Bez zgody to żądanie po prostu nic nie zwraca.
            _ = await store.loadUsage()
        }
        // Zakładki żyją wszystkie naraz, więc „widać rozmowę" znaczy
        // „wybrana zakładka", nie `onAppear` — ten odpala się raz, pod
        // loaderem startowym.
        .onChange(of: isActiveTab, initial: true) { _, active in
            store.setVisible(active)
            // Powrót na zakładkę po przerwie: czysta kartka zamiast
            // dopisywania do rozmowy sprzed pół dnia.
            if active { rotateIfStale() }
            // Przerwa techniczna: każde wejście na zakładkę sprawdza po cichu,
            // czy asystent już wrócił — nikt nie musi pamiętać o przycisku.
            if active, store.isUnavailable { Task { await store.recheckAvailability() } }
            // Pula znana, zanim ktoś stuknie w akcję powitania: pusta =
            // powitanie od razu w stanie limitu, bez wysyłki i skoku.
            if active { Task { await store.refreshUsageIfStale() } }
        }
        .onDisappear { store.setVisible(false) }
        .onChange(of: scenePhase) { _, phase in
            // Ten sam próg dla powrotu z tła: aplikacja zminimalizowana
            // w sklepie i otwarta w kuchni to dwie różne rozmowy.
            if phase == .active { rotateIfStale() }
            if phase == .background { store.noteWentToBackground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            keyboardMoved(covers: Self.keyboardCoversBottom(note), duration: Self.animationDuration(of: note))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
            keyboardMoved(covers: false, duration: Self.animationDuration(of: note), hiding: true)
        }
        .onChange(of: isComposerFocused) { _, focused in focusChanged(focused) }
        .onChange(of: draft.isEmpty) { wasEmpty, isEmpty in
            if wasEmpty, !isEmpty { typingNudge += 1 }
        }
        .onChange(of: store.isSending) { wasSending, isSending in
            // Tura domknęła się odpowiedzią (nie błędem, nie „stop”).
            if wasSending, !isSending, store.errorMessage == nil { answerCheer += 1 }
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

    /// Czysta kartka po przerwie to NOWA wiadomość asystenta — powitanie
    /// pisze się od nowa, nawet gdy ta sama sytuacja grała przed chwilą.
    /// Pamięć czyścimy w tej samej aktualizacji, w której znika rozmowa,
    /// więc `AssistantEmptyState` rodzi się już jako „do odtworzenia”.
    private func rotateIfStale() {
        if store.rotateIfStale() { AssistantGreetingMemory.forget() }
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
            accessory: quotaPips,
            markMood: store.isSending ? .thinking : .idle,
            markCheer: answerCheer
        ) {
            // W przepływie startowym (przed zgodą albo w kartach) menu ma
            // tylko to, co wtedy działa — „Nowa rozmowa" czy „Usuń historię"
            // bez zgody kończyły się 403 albo pustym arkuszem.
            let inIntro = currentStep != nil
            if !inIntro {
                Button { Task { await store.startNewConversation() } } label: { Label("Nowa rozmowa", systemImage: "plus") }
                Button { showConversations = true } label: { Label("Historia rozmów", systemImage: "clock") }
            }
            Button { showCapabilities = true } label: { Label("Co potrafi asystent", systemImage: "rectangle.stack") }
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
    /// tej samej krawędzi. Ta sama sztuczka w `WelcomeView`.
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
        // Przy zerze kapsułki nie ma — zera nie trzeba pokazywać dwa razy
        // (briefing i karta zamiast pola już o tym mówią).
        guard let usage = store.usage, usage.isTrial, usage.messages.remaining > 0 else { return nil }
        return AnyView(
            Button { showUsage = true } label: {
                AssistantQuotaPill(
                    remaining: usage.messages.remaining,
                    limit: usage.messages.limit,
                    compact: headerMode != .large
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

    /// Briefing pustej rozmowy — z tego, co aplikacja WIE o tej chwili:
    /// plan tego i przyszłego tygodnia, godziny posiłków, bilans, pula.
    /// Priorytety liczy `AssistantBriefingResolver`; tu tylko zbieramy fakty.
    private var briefing: AssistantBriefing {
        AssistantBriefingResolver.resolve(briefingContext)
    }

    private var briefingContext: AssistantBriefingContext {
        let calendar = Calendar.current
        let now = Date()
        let monday = PlanWeek.monday(of: now)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        let thisWeek = (0..<7).map { offset in
            briefingDay(calendar.date(byAdding: .day, value: offset, to: monday) ?? monday)
        }
        let nextWeek = (0..<7).map { offset in
            briefingDay(calendar.date(byAdding: .day, value: offset, to: nextMonday) ?? nextMonday)
        }
        var slotMinutes: [AssistantBriefingSlot: Int] = [:]
        for slot in MealSlot.allCases {
            if let briefingSlot = AssistantBriefingSlot(rawValue: slot.rawValue),
               let minutes = sessionStore.mealSlotSchedule.minutes(for: slot) {
                slotMinutes[briefingSlot] = minutes
            }
        }
        // Nowe konto: żadnego planu w pamięci i żadnej rozmowy. Cokolwiek
        // z tych dwóch znaczy, że Scoffie ten dom już zna.
        let plan = sessionStore.mealCalendarStore
        let isNewUser = (plan?.plans.isEmpty ?? true) && store.historyConversations.isEmpty
        return AssistantBriefingContext(
            now: now,
            calendar: calendar,
            displayName: UserDefaults.standard.string(forKey: "settings.user.displayName"),
            trialExhausted: store.isLockedByTrialQuota,
            isNewUser: isNewUser,
            thisWeek: thisWeek,
            nextWeek: nextWeek,
            slotMinutes: slotMinutes,
            balance: weeklyProteinBalance(thisWeek: thisWeek.map(\.date))
        )
    }

    /// Jeden dzień planu w słowniku briefingu — soczewka bieżącego użytkownika
    /// (jego danie bije wspólne), pory włączone w domu plus te, w których
    /// coś stoi.
    private func briefingDay(_ date: Date) -> AssistantBriefingDay {
        let plan = sessionStore.mealCalendarStore
        let planned = plan?.plan(for: date).plannedSlots ?? []
        let slots = sessionStore.mealSlots.visibleSlots(planned: planned)
        let memberCount = knownHouseholdMemberCount
        var meals: [AssistantBriefingDay.Meal] = []
        for slot in slots {
            guard let briefingSlot = AssistantBriefingSlot(rawValue: slot.rawValue) else { continue }
            let visible = visibleMeals(on: date, slot: slot)
            guard let meal = visible.first else { continue }
            let nutrition = meal.nutritionPerPerson(knownHouseholdMemberCount: memberCount)
            meals.append(
                AssistantBriefingDay.Meal(
                    slot: briefingSlot,
                    title: meal.recipe.name,
                    kcal: Int(nutrition.kcal.rounded()),
                    imageURL: meal.recipe.imageURL,
                    minutes: meal.recipe.prepTimeMinutes
                )
            )
        }
        return AssistantBriefingDay(
            date: date,
            enabledSlots: slots.compactMap { AssistantBriefingSlot(rawValue: $0.rawValue) },
            meals: meals
        )
    }

    /// Posiłki slotu widziane przez zalogowaną osobę — jak w Planie tygodnia.
    private func visibleMeals(on date: Date, slot: MealSlot) -> [PlanMeal] {
        let all = sessionStore.mealCalendarStore?.meals(for: date, slot: slot) ?? []
        guard let memberId = sessionStore.currentUserId else { return all }
        return all.visibleTo(memberId: memberId)
    }

    /// Ilu domowników dzieli się porcjami — `nil`, dopóki lista nie doszła.
    private var knownHouseholdMemberCount: Int? {
        guard sessionStore.didLoadHouseholdMembers else { return nil }
        return max(1, sessionStore.householdMembers.count)
    }

    /// Średnie białko z ZAPLANOWANYCH dni tygodnia wobec celu z profilu.
    /// `nil`, gdy nie ma celu makro (brak sylwetki) albo nie ma czego liczyć —
    /// briefing nie zmyśla liczb.
    private func weeklyProteinBalance(thisWeek dates: [Date]) -> AssistantBriefingBalance? {
        let targets = DailyNutritionTargets.resolve(
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
        guard let proteinTarget = targets.macros?.proteinG, proteinTarget > 0 else { return nil }
        let memberCount = knownHouseholdMemberCount
        var total = 0.0
        var counted = 0
        var below = 0
        for date in dates {
            let planned = sessionStore.mealCalendarStore?.plan(for: date).plannedSlots ?? []
            guard !planned.isEmpty else { continue }
            let slots = sessionStore.mealSlots.visibleSlots(planned: planned)
            let day = PlanDayNutrition.make(
                slots: slots,
                meals: { visibleMeals(on: date, slot: $0) },
                knownHouseholdMemberCount: memberCount
            )
            guard !day.isEmpty else { continue }
            total += day.total.protein
            counted += 1
            if day.total.protein < Double(proteinTarget) { below += 1 }
        }
        guard counted > 0 else { return nil }
        return AssistantBriefingBalance(
            macroGenitive: "białka",
            macroAccusative: "białko",
            unit: "g",
            averagePerDay: Int((total / Double(counted)).rounded()),
            target: proteinTarget,
            daysCounted: counted,
            daysBelowTarget: below
        )
    }

    /// Akcja z powitania.
    private func perform(_ action: AssistantBriefing.Action) {
        switch action.kind {
        case let .ask(prompt): ask(prompt)
        // „Mam inny pomysł” tylko ustawia fokus — akcje gasną, otwarcie
        // zostaje nad polem jako temat rozmowy.
        case .compose: isComposerFocused = true
        case .openPlans: showPaywall = true
        case .openHistory: showConversations = true
        case .openPlan: sessionStore.dashboardTab = .plan
        case .openShopping:
            // Lista zakupów jest arkuszem w Planie, więc sama zakładka to za mało.
            sessionStore.opensShoppingList = true
            sessionStore.dashboardTab = .plan
        }
    }

    /// Pusta rozmowa NIE jest listą: nie ma czego przewijać, więc nie ma
    /// przewijania ani odbicia. Powitanie stoi na środku wolnego miejsca
    /// między nagłówkiem a polem; lista z kotwicami i rozpórką wchodzi
    /// dopiero z pierwszym pytaniem.
    private var isConversationEmpty: Bool {
        store.messages.isEmpty && !store.isLoadingHistory && !store.isSending
    }

    /// Pusty stan i lista przechodzą w siebie kryciem — w JEDNEJ transakcji
    /// z nagłówkiem (duży ↔ kompaktowy) i podpowiedziami nad polem, które
    /// mają własne odciski na tę samą chwilę. „Nowa rozmowa" była dotąd
    /// cięciem: lista znikała w klatce, powitanie wskakiwało w następnej.
    private var conversationSwitch: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.3)
    }

    private var conversation: some View {
        ZStack {
            if store.isUnavailable {
                // Asystent wyłączony na serwerze (`AI_DISABLED`): przerwa
                // techniczna zamiast rozmowy i pola. Historia zostaje
                // w menu („Historia rozmów”), a po powrocie wszystko wraca samo.
                GeometryReader { geometry in
                    ScrollView {
                        AssistantMaintenanceView(
                            isChecking: store.isCheckingAvailability,
                            onRecheck: { await store.recheckAvailability() }
                        )
                        .padding(.horizontal, SCPageMetrics.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 28)
                        .frame(minHeight: geometry.size.height, alignment: .bottom)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else if isConversationEmpty {
                // Powitanie stoi PRZY POLU, nie pod nagłówkiem (makieta
                // „Empty state v2”, wariant A): pytanie i odpowiedzi pod
                // kciukiem, tam, gdzie zacznie się rozmowa. Wolne miejsce
                // zostaje NAD blokiem. Gdy blok jest wyższy niż ekran
                // (Dynamic Type, iPhone SE), startuje od otwarcia i przewija
                // się — czytamy od początku, nie od środka.
                GeometryReader { geometry in
                    ScrollView {
                        emptyState
                            .padding(.horizontal, SCPageMetrics.horizontal)
                            .padding(.top, 4)
                            .padding(.bottom, 20)
                            .frame(minHeight: geometry.size.height, alignment: .bottom)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Bez ScrollView nie działa `scrollDismissesKeyboard`, więc na
                // pustym ekranie klawiatury nie dało się schować niczym poza
                // wysłaniem. Całe wolne tło łapie stuknięcie i zdejmuje fokus.
                .contentShape(Rectangle())
                .onTapGesture { isComposerFocused = false }
                // Powitanie wyrasta lekko od środka; schodzi samym kryciem,
                // żeby nie „uciekało" spod pierwszego pytania.
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    )
                )
            } else {
                messageList
                    .transition(.opacity)
            }
        }
        .animation(conversationSwitch, value: isConversationEmpty)
        .animation(conversationSwitch, value: store.isUnavailable)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                messageScroll(proxy)

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

    // Rozbite na osobne funkcje: jako jedno wyrażenie (reader → ZStack →
    // ScrollView → kilkanaście modyfikatorów) kompilator nie dawał rady
    // go otypować w rozsądnym czasie.
    private func messageScroll(_ proxy: ScrollViewProxy) -> some View {
        let scroll = ScrollView {
            messageStack
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // Rozmowa NIE zwija dolnego menu: zwinięty pasek jest węższy od
        // pola wiadomości nad nim i dwa elementy przestawały się zgadzać.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            // „Na końcu" liczy się od KOŃCA TREŚCI (`tailAnchor`), nie
            // od końca rozpórki: próg 80 pt był mniejszy niż sama
            // rozpórka (120 + 12), więc po stuknięciu strzałki
            // rozmowa stawała na końcu treści, a strzałka wciąż
            // wisiała, bo do dna zostawało 132 pt.
            let visibleBottom: CGFloat = geometry.contentOffset.y + geometry.containerSize.height
            return visibleBottom >= geometry.contentSize.height - Self.bottomSlack
        } action: { _, atBottom in
            isPinnedToBottom = atBottom
        }

        let triggered = withScrollTriggers(scroll, proxy: proxy)
        // Wibracja tylko przy NOWEJ odpowiedzi i przy NOWYM błędzie.
        // Wyzwalacz po samej zmianie wartości odzywał się też, gdy
        // liczba odpowiedzi SPADAŁA (nowa rozmowa, wybór z historii,
        // poprawka pytania) i gdy błąd ZNIKAŁ — „sukces" i „błąd"
        // pod palcem w chwili, w której nic takiego się nie stało.
        // Typy domknięć jawnie: `.success : nil` bez nich zjadało
        // kompilatorowi limit czasu na całe wyrażenie.
        let onAnswer: (Int, Int) -> SensoryFeedback? = { old, new in
            new > old ? SensoryFeedback.success : nil
        }
        let onError: (String?, String?) -> SensoryFeedback? = { old, new in
            old == nil && new != nil ? SensoryFeedback.error : nil
        }
        return triggered
            .sensoryFeedback(trigger: answerCount, onAnswer)
            .sensoryFeedback(trigger: store.errorMessage, onError)
    }

    /// Odstęp między wiadomościami. Odpowiedź z kartą pod pytaniem i kolejne
    /// pytanie pod kartą stały po 14 pt — wszystko zlewało się w jeden słup.
    /// Ta sama wartość w historii i w slocie ostatniej tury, inaczej slot
    /// przeskoczyłby przy przejściu do historii.
    static let messageGap: CGFloat = 22

    private var messageStack: some View {
        LazyVStack(alignment: .leading, spacing: Self.messageGap) {
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

    /// Przewinięcia reagujące na zmiany w rozmowie — osobno, żeby odciążyć
    /// typowanie `messageScroll`.
    private func withScrollTriggers<Content: View>(_ content: Content, proxy: ScrollViewProxy) -> some View {
        content
            .onChange(of: slotKey) { _, _ in
                // Własne pytanie i wiersz „myślę" pod nim jadą na dół
                // rozmowy. Wzorzec ChatGPT (pytanie pod górną krawędzią,
                // pod nim pusty ekran na odpowiedź) wyglądał tu jak błąd:
                // po jednym zdaniu z arkusza „Co potrafi” zostawała
                // strona pustki, a krótka odpowiedź wisiała nad nią.
                // Zawieszone na TOŻSAMOŚCI pytania, nie na liczbie
                // wiadomości: „Popraw pytanie" zdejmuje jedno i dopisuje
                // jedno, więc liczba stoi w miejscu.
                guard store.isSending, store.hasLiveTurnSlot,
                      store.messages.last?.author == .user else { return }
                scroll(proxy, to: Self.tailAnchor, anchor: .bottom)
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
                          let last = store.messages.last, last.author == .assistant {
                    // Nowa odpowiedź rośnie od dolnej krawędzi w dół
                    // (dopisuje się znak po znaku), więc jej początek
                    // idzie pod górną krawędź — `scrollTo` i tak zatrzyma
                    // się na końcu treści, gdy odpowiedź jest krótka.
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
                scroll(proxy, to: last.id, anchor: .bottom)
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
        AssistantEmptyState(
            briefing: briefing,
            // Przy wyczerpanej puli miesięcznej akcje powitania i tak nic nie
            // wyślą — zostaje samo otwarcie, a pod nim karta z datą powrotu.
            composing: greetingComposing || isLockedByMonthlyQuota,
            nudge: typingNudge,
            quota: quotaFacts,
            sleeping: isLockedByMonthlyQuota,
            onAction: perform
        )
    }

    /// Liczby puli dla widoków „wykorzystane” — z serwera; plan polecany
    /// tylko, gdy znamy liczbę domowników.
    private var quotaFacts: AssistantQuotaFacts? {
        AssistantQuotaFacts.make(
            usage: store.usage,
            householdSize: sessionStore.didLoadHouseholdMembers ? sessionStore.householdMembers.count : 0,
            subscriptions: sessionStore.subscriptionStore
        )
    }

    /// Wyczerpana pula planu MIESIĘCZNEGO. Tylko gdy serwer już powiedział,
    /// że to nie próba — inaczej próba zobaczyłaby na chwilę „wraca …”.
    /// Dotąd pole stało wtedy wyszarzone z „Chwila przerwy — spróbuj za
    /// moment”, choć przerwa trwała do odnowienia puli.
    private var isLockedByMonthlyQuota: Bool {
        store.isLocked && store.lockReason == .quota && store.usage?.isTrial == false
    }

    // MARK: - Klawiatura a powitanie

    /// Klawiatura rusza: powitanie zwija się / rozwija w tej samej chwili
    /// i w tej samej krzywej co pole nad klawiaturą (patrz `greetingComposing`).
    private func keyboardMoved(covers: Bool, duration: Double, hiding: Bool = false) {
        let target: Bool
        if covers {
            target = true
        } else if hiding {
            // Klawiatura ZJEŻDŻA: powitanie rozwija się w tym samym ruchu,
            // nawet jeśli fokus zejdzie dopiero za chwilę (zamknięcie
            // przeciągnięciem). Dawniej czekało na `focusChanged` i ruszało
            // PO klawiaturze — drugi ruch, który wyglądał jak przeskok.
            target = false
        } else if isComposerFocused {
            // Klawiatura zjeżdża, a fokus jeszcze nie zszedł (schował ją
            // system) — rozwinięcie odda `focusChanged` za chwilę.
            target = greetingComposing
        } else {
            target = false
        }
        guard keyboardUp != covers || greetingComposing != target else { return }
        keyboardDuration = duration
        withAnimation(reduceMotion ? nil : Self.keyboardCurve(duration: duration)) {
            keyboardUp = covers
            greetingComposing = target
        }
    }

    /// Fokus pola. Z klawiaturą ekranową stan przełącza jej powiadomienie
    /// (`keyboardMoved`); tu tylko zapas: klawiatura sprzętowa nie zasłania
    /// ekranu, a fokus zdjęty przez system przychodzi już po powiadomieniu.
    private func focusChanged(_ focused: Bool) {
        if !focused {
            guard !keyboardUp, greetingComposing else { return }
            withAnimation(reduceMotion ? nil : Self.keyboardCurve(duration: keyboardDuration)) { greetingComposing = false }
            return
        }
        guard !greetingComposing else { return }
        Task { @MainActor in
            // Do tej chwili klawiatura ekranowa na pewno już ruszyła; jeśli
            // nie — jest sprzętowa i powitanie zwija się samo.
            try? await Task.sleep(for: .milliseconds(350))
            guard isComposerFocused, !greetingComposing else { return }
            withAnimation(reduceMotion ? nil : Self.keyboardCurve(duration: keyboardDuration)) { greetingComposing = true }
        }
    }

    /// Krzywa klawiatury — ta sama co rezerwa pod dolnym menu.
    private static func keyboardCurve(duration: Double) -> Animation {
        SCTabBarChrome.keyboardCurve(duration: duration)
    }

    /// Czas ruchu klawiatury z powiadomienia.
    private static func animationDuration(of note: Notification) -> Double {
        (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
    }

    /// Czy klawiatura po zmianie ramki zasłoni dół ekranu. Pasek skrótów
    /// klawiatury sprzętowej ma ~55–70 pt, prawdziwa klawiatura ponad 250 —
    /// ten sam próg co rezerwa pod dolnym menu (`NavigationMenu`).
    private static func keyboardCoversBottom(_ note: Notification) -> Bool {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return false }
        let overlap = max(0, UIScreen.main.bounds.height - frame.minY)
        return overlap > 120
    }

    /// Przykład w polu: na pustym ekranie pasuje do sytuacji z powitania
    /// („Np. mam kurczaka i paprykę”), w rozmowie — zwykłe zaproszenie.
    private var composerPrompt: String {
        if store.isUnavailable { return "Asystent jest teraz niedostępny" }
        if store.isLocked { return "Chwila przerwy — spróbuj za moment" }
        if isConversationEmpty, editing == nil {
            let example = briefing.placeholder
            if !example.isEmpty { return example }
        }
        return "Napisz do asystenta…"
    }

    // MARK: - Pole wiadomości

    private var composer: some View {
        VStack(spacing: 0) {
            if editing != nil {
                editingBar
                    .transition(.opacity)
            }

            // Wykorzystana pula na próbę: pole, w które nie da się pisać, jest
            // wyłącznie frustracją. W rozmowie stoi zamiast niego karta
            // z jednym przyciskiem, który coś zmienia; na pustym ekranie
            // to samo mówi briefing, więc composera nie ma wcale.
            if store.isUnavailable {
                // Przerwa techniczna: ekran mówi to sam i ma własne
                // „Sprawdź ponownie” — wyszarzone pole byłoby tylko szumem.
                EmptyView()
            } else if store.isLockedByTrialQuota {
                if !isConversationEmpty {
                    quotaSpentCard(isTrial: true)
                }
            } else if isLockedByMonthlyQuota {
                // Pula miesięczna: pole, w które nie da się pisać do
                // odnowienia, zastępuje karta z datą powrotu — także na
                // pustym ekranie, bo powitanie o puli nie mówi.
                quotaSpentCard(isTrial: false)
            } else {
                composerField
            }
        }
        // Zasłona pod polem i dolnym menu: rozmowa przewijała się pod nimi
        // w pełnej ostrości i jej litery mieszały się z polem i ikonami.
        // Treść gaśnie w tło strony na 28 pt nad polem, a niżej — aż do
        // krawędzi ekranu, także pod menu — tła już nie widać.
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color.scPageBase(scheme).opacity(0), location: 0),
                    .init(color: Color.scPageBase(scheme).opacity(0.94), location: 0.22),
                    .init(color: Color.scPageBase(scheme), location: 0.45),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -28)
            .ignoresSafeArea(.container, edges: .bottom)
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: editing != nil)
        .animation(.easeInOut(duration: 0.2), value: store.isLockedByTrialQuota)
        .animation(.easeInOut(duration: 0.2), value: isLockedByMonthlyQuota)
        .animation(.easeInOut(duration: 0.2), value: store.isUnavailable)
    }

    /// `LComposer` z makiety: pole 50 pt w pigułce z włoskowatym obrysem,
    /// obok krążek 50 — w terakocie wariantu „soft”, gdy jest co wysłać albo
    /// tura biegnie (wtedy strzałka staje się stopem); przy poprawce pytania
    /// pole dostaje obrys terakoty i poświatę.
    private var composerField: some View {
        let active = store.isSending || editing != nil || canSend
        return HStack(alignment: .bottom, spacing: 10) {
            TextField(composerPrompt, text: $draft, axis: .vertical)
            // Do ośmiu wierszy: pytanie bywa całym akapitem („mamy gości
            // w sobotę, dwie osoby bez glutenu…"). PUSTE pole ma jeden
            // wiersz: przykład z powitania („Np. obiady do 30 minut przez
            // cały tydzień”) łamał się na dwa, a pierwsza litera zwijała pole
            // do jednego — powitanie nad nim opadało skokiem o wiersz.
            .lineLimit(draft.isEmpty ? 1...1 : 1...8)
            .font(.system(size: 16.5))
            .tracking(-0.3)
            .foregroundStyle(AssistantLook.ink(scheme))
            .focused($isComposerFocused)
            .disabled(store.isUnavailable || store.isLocked)
            .submitLabel(.send)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .frame(minHeight: 50)
            .background(Capsule(style: .continuous).fill(AssistantLook.input(scheme)))
            .overlay(
                Capsule(style: .continuous).stroke(
                    editing == nil ? AssistantLook.cardStroke(scheme) : AssistantLook.terraFill(scheme).opacity(0.5),
                    lineWidth: 1
                )
            )
            .background(
                Capsule(style: .continuous)
                    .stroke(AssistantLook.terraFill(scheme).opacity(editing == nil ? 0 : 0.12), lineWidth: 3)
                    .padding(-2)
            )
            .animation(.easeOut(duration: 0.2), value: editing != nil)
            .accessibilityLabel(editing == nil ? "Wiadomość do asystenta" : "Poprawiana wiadomość")

            // W trakcie tury strzałka zamienia się w „stop"; po „stop"
            // przycisk WYGASA razem ze statusem „Zatrzymuję…", bo drugi stop
            // nic nie zrobi.
            Button {
                if store.isSending { store.stopWaiting() } else { send() }
            } label: {
                ZStack {
                    // Wygaszony: krążek jak pole obok.
                    Group {
                        Circle().fill(AssistantLook.input(scheme))
                        Circle().stroke(AssistantLook.cardStroke(scheme), lineWidth: 1)
                    }
                    .opacity(active ? 0 : 1)

                    // Aktywny: wariant „soft” (`scSoftSurface`), jak każda
                    // akcja główna — pełna terakotowa tarcza z białą strzałką
                    // była jedyną taką plamą koloru na ekranie.
                    Color.clear
                        .scSoftSurface(Circle())
                        .opacity(active ? 1 : 0)

                    Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: store.isSending ? 18 : 19, weight: .bold))
                        .foregroundStyle(active ? SCPalette.terracotta : AssistantLook.ink(scheme).opacity(0.45))
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 50, height: 50)
                .opacity(store.isStopping ? 0.5 : 1)
            }
            .buttonStyle(PlanPressStyle(scale: 0.92))
            .disabled((!store.isSending && !canSend) || store.isStopping)
            .accessibilityLabel(sendAccessibilityLabel)
            .animation(.easeOut(duration: 0.2), value: active)
            .animation(.easeOut(duration: 0.2), value: store.isStopping)
            .animation(.easeOut(duration: 0.2), value: store.isSending)
        }
        // Ten sam margines co dolne menu — pole i pasek mają jedną szerokość.
        .padding(.horizontal, SCFloatingTabBar.sideMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Karta zamiast pola po wykorzystaniu puli (`AssistantQuotaSpentCard`):
    /// próba prowadzi do planów, plan miesięczny — do limitów z datą powrotu.
    private func quotaSpentCard(isTrial: Bool) -> some View {
        AssistantQuotaSpentCard(
            facts: quotaFacts,
            isTrial: isTrial,
            action: {
                if isTrial { showPaywall = true } else { showUsage = true }
            }
        )
        .background(RoundedRectangle(cornerRadius: AssistantCardMetrics.radius, style: .continuous).fill(AssistantLook.input(scheme)))
        // Ten sam margines co dolne menu — pole i pasek mają jedną szerokość.
        .padding(.horizontal, SCFloatingTabBar.sideMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// `LEditBar`: pasek 36 pt nad polem — „Edytujesz wiadomość” i „Anuluj”.
    /// Zatwierdzenie to strzałka w polu; bez osobnego przycisku, jak na makiecie.
    private var editingBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "pencil")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AssistantLook.terra(scheme))
            Text("Edytujesz wiadomość")
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(AssistantLook.ink(scheme))

            Spacer(minLength: 0)

            Button {
                draft = ""
                editing = nil
                isComposerFocused = false
            } label: {
                Text("Anuluj")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AssistantLook.terra(scheme))
                    .frame(height: 36)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AssistantLook.input(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AssistantLook.cardStroke(scheme), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var canSend: Bool {
        store.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    /// Treść ostatniego pytania — „Spróbuj ponownie” po nieudanej turze
    /// zadaje je jeszcze raz jako NOWĄ turę (tamta już się domknęła).
    private var lastUserText: String? {
        store.messages.last { $0.author == .user }?.text
    }

    private func askAgain() {
        guard let text = lastUserText else { return }
        ask(text)
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

    /// Jawna właściwość zamiast `reduceMotion ? nil : …` w argumencie (SE-0418).
    private var slotAnimation: Animation? {
        if reduceMotion { return nil }
        return .easeInOut(duration: 0.28)
    }

    /// Jeden wiersz rozmowy — wspólny dla części przed slotem i dla slotu,
    /// żeby oba rysowały identycznie. Indeks jest GLOBALNY (separator dnia
    /// i odpowiedź na kartę pytania patrzą na sąsiadów).
    @ViewBuilder
    private func bubble(at index: Int, _ message: AgentChatMessage, showsThinking: Bool = true) -> some View {
        // Indeks z domknięcia wiersza bywa NIEAKTUALNY: leniwa lista potrafi
        // przeliczyć stary wiersz już po tym, jak rozmowa się skróciła
        // (poprawione pytanie, nowa rozmowa, wycofana wiadomość) — a sąsiadów
        // czytamy wprost z `store.messages`. Stąd pozycja liczona na żywo.
        let index = liveIndex(of: message, hint: index)

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
            showsThinking: showsThinking,
            isEditing: editing?.id == message.id,
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
            onReport: { reporting = message },
            onRevealed: { store.markRevealed(id: message.id) },
            onCompose: { isComposerFocused = true }
        )
        .id(message.id)
    }

    /// Pierwsza odpowiedź asystenta w slocie, jeśli niesie ślad tury — to
    /// nad nią stoi wiersz „myślę", który przeżył turę.
    private var slotThinkingAnswer: AgentChatMessage? {
        let index = slotStart + 1
        guard index < store.messages.count else { return nil }
        let answer = store.messages[index]
        guard answer.author == .assistant, answer.thinking != nil else { return nil }
        return answer
    }

    /// Faza wiersza „myślę" w slocie: praca, dopóki tura biegnie; osiadła,
    /// dopóki odpowiedź z tej sesji stoi w slocie; `nil` = wiersza nie ma
    /// (historia z serwera, błąd tury bez odpowiedzi).
    private var thoughtPhase: AssistantThoughtLine.Phase? {
        if store.isSending {
            // `.distantPast` nie ma prawa wejść: `send()`, `editMessage()`
            // i start `followTurn` ustawiają epokę razem z `isSending`.
            return .working(startedAt: store.turnStartedAt ?? .distantPast, isStopping: store.isStopping)
        }
        if let thinking = slotThinkingAnswer?.thinking {
            return .settled(duration: thinking.duration)
        }
        return nil
    }

    /// Nowy krok postępu zmienia wysokość śladu pod wierszem „myślę" — całe
    /// wnętrze slotu (szkic odpowiedzi niżej) ma zjechać razem z nim, a nie
    /// skoczyć. Modyfikator siedzi na slocie, bo animacja na samym śladzie
    /// nie obejmuje ruchu sąsiadów.
    private var stepAnimation: Animation? {
        if reduceMotion { return nil }
        return .easeOut(duration: 0.25)
    }

    /// Slot ostatniej tury: pytanie + wiersz „myślę" + ALBO szkic odpowiedzi,
    /// ALBO odpowiedzi tej tury (i ewentualna notka błędu). Insert/remove
    /// dzieje się w zwykłym `ZStack`, nie na poziomie `LazyVStack` — tam
    /// przejścia są przewidywalne, a tu `apply(finished:)` i `defer`
    /// w `followTurn` przełączają obie strony w jednej transakcji: wiersz
    /// osiada w miejscu, szkic przenika w odpowiedź, treść wyrasta pod nim.
    private var turnSlot: some View {
        VStack(alignment: .leading, spacing: Self.messageGap) {
            if slotStart < store.messages.count {
                bubble(at: slotStart, store.messages[slotStart])
            }
            VStack(alignment: .leading, spacing: 16) {
                // JEDEN wiersz na całe życie tury: ten sam widok w tym samym
                // miejscu drzewa od pierwszej klatki do końca życia odpowiedzi
                // w slocie. Domknięcie tury nie podmienia go na inny widok,
                // tylko przełącza fazę — dlatego etykieta rozmywa się
                // w „Myślałem", licznik zjeżdża, ślad zwija się pod chevron,
                // a odpowiedź wyrasta pod nim. Odpowiedź w slocie NIE rysuje
                // własnego wiersza (`showsThinking: false`); dostaje go
                // z powrotem od `MessageBubble`, gdy po następnym pytaniu
                // przejdzie do części przed slotem.
                if store.isSending, let phase = thoughtPhase {
                    AssistantThoughtLine(
                        phase: phase,
                        steps: store.progress,
                        isExpanded: expansion(of: Self.liveThoughtKey, in: $expandedThoughts)
                    )
                    // Bez poziomego wcięcia: kolumna ikon wiersza stoi w linii
                    // znaku marki przy odpowiedziach.
                    .padding(.vertical, 4)
                    .transition(.opacity)
                }

                ZStack(alignment: .topLeading) {
                    if store.isSending {
                        // Odpowiedź pisze się POD wierszem, zanim tura się
                        // domknie — a po domknięciu ten sam tekst zostaje
                        // w miejscu jako `AssistantAnswer`, więc crossfade
                        // niżej podmienia identyczne piksele.
                        Group {
                            if !store.draftText.isEmpty {
                                AssistantDraftAnswer(text: store.draftText, clock: store.draftReveal)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: store.draftText.isEmpty)
                        // Wyjście (szkic → odpowiedź) animuje ten `ZStack`;
                        // wejście pod NOWYM pytaniem robi sam wiersz
                        // (`appeared`), bo `.id(slotKey)` niżej stawia go
                        // w nieanimowanej transakcji.
                        .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: Self.messageGap) {
                            ForEach(Array(store.messages.enumerated().dropFirst(slotStart + 1)), id: \.element.id) { index, message in
                                bubble(at: index, message)
                            }
                            if let errorMessage = store.errorMessage {
                                AssistantOutcomeCard(
                                    code: store.lastTurnErrorCode,
                                    message: errorMessage,
                                    wrote: store.lastTurnWrote,
                                    suggestions: store.suggestions,
                                    onAsk: { prompt in ask(prompt) },
                                    // Domknięcia, nie referencje do metod: pod
                                    // `InferSendableFromCaptures` (SE-0418) referencja
                                    // obok `nil` w wyrażeniu warunkowym wywraca typowanie
                                    // CAŁEGO `ScrollView` („ambiguous use of 'init'").
                                    onRetry: store.retryText == nil ? nil : { retry() },
                                    onAskAgain: lastUserText == nil ? nil : { askAgain() }
                                )
                                .id(Self.errorAnchor)
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
            // Osiadanie tury to JEDNA transakcja na całym wnętrzu slotu:
            // wiersz „myślę" przechodzi w „Myślałem", ślad się zwija,
            // szkic przenika w odpowiedź — i wszystko to zjeżdża razem.
            .animation(slotAnimation, value: store.isSending)
            .animation(stepAnimation, value: store.progress.count)
            .id(slotKey)
        }
        .id(Self.turnAnchor)
    }

    /// Bieżąca pozycja wiadomości w rozmowie; `nil`, gdy już jej tam nie ma
    /// (wiersz dogorywa po skróceniu rozmowy i nie ma sąsiadów do czytania).
    private func liveIndex(of message: AgentChatMessage, hint: Int) -> Int? {
        if store.messages.indices.contains(hint), store.messages[hint].id == message.id { return hint }
        return store.messages.firstIndex { $0.id == message.id }
    }

    /// Pierwsza wiadomość użytkownika PO danej pozycji — to nią odpowiedział
    /// na pytanie asystenta. Zatrzymujemy się na kolejnej odpowiedzi
    /// asystenta: pytanie bez odpowiedzi przed nią zostało pominięte.
    private func reply(after index: Int?) -> String? {
        guard let index, store.messages[index].card?.marksReply == true else { return nil }
        for next in store.messages[(index + 1)...] {
            if next.author == .user { return next.text }
            return nil
        }
        return nil
    }

    /// Napis separatora, gdy wiadomość zaczyna nowy dzień.
    private func daySeparator(at index: Int?) -> String? {
        guard let index, let date = store.messages[index].createdAt else { return nil }
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
    /// Klucz rozwinięcia wiersza „myślę" w TRAKCIE tury — nieużywany (ślad na
    /// żywo ma własny stan), ale `Binding` musi na coś wskazywać.
    private static let liveThoughtKey = "assistant.thought.live"
    private static let errorAnchor = "assistant.error"
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
    /// Czy rysować wiersz „Myślałem" nad odpowiedzią. `false` dla odpowiedzi
    /// w slocie ostatniej tury — tam wiersz stoi NAD dymkiem, jako ten sam
    /// widok, który pracował przez całą turę (`AssistantView.turnSlot`).
    var showsThinking: Bool = true
    /// Pytanie właśnie poprawiane — dymek dostaje obrys terakoty.
    var isEditing: Bool = false
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
    /// Odpowiedź dopisała się do końca — sklep zdejmuje `revealFrom`.
    let onRevealed: () -> Void
    /// Fokus na polu rozmowy (arkusz wyboru: „Napisz, na co masz ochotę”).
    var onCompose: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Wiadomość przyszła w tej sesji (a nie z historii) — karta wyboru
    /// otwiera wtedy arkusz sama. `revealFrom` znika po dopisaniu tekstu,
    /// czyli zanim karta się pokaże, więc zapamiętujemy go przy wejściu.
    @State private var arrivedLive = false

    /// Czy tekst jeszcze się dopisuje — reszta (karta, ślad, „Uwzględniłem”)
    /// czeka pod nim i wchodzi dopiero po ostatnim znaku.
    private var isRevealing: Bool {
        message.author == .assistant && message.revealFrom != nil && !message.text.isEmpty
            && message.card?.replacesText != true
    }

    /// Jawna właściwość zamiast `reduceMotion ? nil : …` w argumencie (SE-0418).
    private var revealAnimation: Animation? {
        if reduceMotion { return nil }
        return .easeOut(duration: 0.35)
    }

    var body: some View {
        if message.author == .user {
            userBubble
                .contextMenu { menuItems }
                .accessibilityLabel("Ty: \(message.text)")
        } else {
            assistantCard
                .contextMenu { menuItems }
                .accessibilityLabel("Asystent: \(message.text)")
                .onAppear {
                    if message.revealFrom != nil { arrivedLive = true }
                }
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
        AssistantUserBubble(text: message.text, editing: isEditing, pending: message.isPending)
    }

    /// Odpowiedź asystenta NIE dostaje dymka.
    ///
    /// Dymek jest gestem konwersacyjnym dobrym dla jednego zdania, a odpowiedź
    /// bywa całym tygodniem — w wąskiej bańce zamienia się w ścianę tekstu.
    /// Pełna szerokość daje treści (a wkrótce kartom) miejsce, którego dymek
    /// nie ma jak dać; rozmowę czyta się po stronie ekranu, nie po ramce.
    private var assistantCard: some View {
        // 20 pt między tekstem a kartą: karta to osobna rzecz do obejrzenia,
        // nie dalszy ciąg akapitu.
        VStack(alignment: .leading, spacing: 20) {
            // `LAsstMsg` + `LThought`: znak marki obok treści, a POD nią
            // „Myślałem 42 s” wcięte pod tekst. Karta pytania NIESIE treść
            // wypowiedzi, więc obok niej nie ma `text`.
            if !message.text.isEmpty, message.card?.replacesText != true {
                VStack(alignment: .leading, spacing: 10) {
                    // Świeża odpowiedź: znak przy niej raz podskakuje.
                    AssistantVoice(greets: message.revealFrom != nil) {
                        if let from = message.revealFrom {
                            AssistantRevealedAnswer(text: message.text, from: from, onDone: onRevealed)
                        } else {
                            AssistantAnswer(text: message.text)
                        }
                    }
                    if !isRevealing, showsThinking, let thinking = message.thinking {
                        AssistantThoughtLine(
                            phase: .settled(duration: thinking.duration),
                            steps: thinking.steps,
                            isExpanded: $isThoughtExpanded
                        )
                    }
                }
            } else if showsThinking, let thinking = message.thinking {
                AssistantThoughtLine(
                    phase: .settled(duration: thinking.duration),
                    steps: thinking.steps,
                    isExpanded: $isThoughtExpanded
                )
            }

            if !isRevealing {
                Group {
                    if message.savedPlan {
                        AssistantSavedPlanCard(onOpenPlan: onOpenPlan)
                    }

                    card
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
        }
        // Wejście reszty pod dopisanym tekstem — jedno łagodne przejście.
        .animation(revealAnimation, value: isRevealing)
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
                onUndo: { onUndo(planWeek.proposalId) },
                onOpenPlan: onOpenPlan,
                onAsk: onAsk,
                onCompose: onCompose,
                autoPresentID: arrivedLive ? message.id : nil
            )
        case .planDay(let planDay):
            AssistantPlanDayCard(
                card: planDay,
                isBusy: isBusy,
                onApply: { force in onApply(planDay.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: { onUndo(planDay.proposalId) },
                onOpenPlan: onOpenPlan,
                onAsk: onAsk,
                onCompose: onCompose,
                autoPresentID: arrivedLive ? message.id : nil
            )
        case .options(let options):
            AssistantOptionsCard(
                card: options,
                reply: reply,
                autoPresentID: arrivedLive ? message.id : nil,
                onAsk: onAsk,
                onCompose: onCompose
            )
        case .swap(let swap):
            AssistantSwapCard(
                card: swap,
                isBusy: isBusy,
                onApply: { force in onApply(swap.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onAsk: onAsk,
                onUndo: { onUndo(swap.proposalId) },
                onOpenPlan: onOpenPlan
            )
        case .removeMeal(let removal):
            AssistantRemoveMealCard(
                card: removal,
                isBusy: isBusy,
                onApply: { force in onApply(removal.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onAsk: onAsk,
                onUndo: { onUndo(removal.proposalId) },
                onOpenPlan: onOpenPlan
            )
        case .householdSplit(let split):
            AssistantHouseholdSplitCard(
                card: split,
                isBusy: isBusy,
                onApply: { force in onApply(split.proposalId, force) },
                onRevise: onRevise,
                onAskNew: onAskNew,
                onUndo: { onUndo(split.proposalId) },
                onOpenPlan: onOpenPlan
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
