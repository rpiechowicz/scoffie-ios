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
/// zamiast niego pokazujemy kroki przysyłane przez serwer („Czytam plan
/// tygodnia", „Zapisuję plan tygodnia") razem z upływem czasu.
struct AssistantView: View {
    let store: AgentStore

    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.weeklyMealStore) private var mealStore
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
    /// Kogo dotyczy pytanie; puste = całe gospodarstwo.
    @State private var scopeUserIds: Set<String> = []
    @State private var showsScopeSheet = false
    @State private var showsRecipePicker = false
    @State private var showDeleteAlert = false
    @State private var showConversations = false
    @State private var showMemory = false
    @State private var showUsage = false
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
    /// Ostatnio oglądana karta „Poznaj" i strona „Od czego zaczniemy?" —
    /// „Wstecz" wraca na nie, nie na pierwszą.
    @State private var introCard = 0
    @State private var introPage = 0

    enum IntroStep: Equatable { case hero, consent, cards, firstMessage }
    /// Odpowiedź asystenta w trakcie zgłaszania („Zgłoś odpowiedź").
    @State private var reporting: AgentChatMessage?
    /// Czy rozmowa stoi na końcu. Gdy użytkownik odjedzie w górę, żeby coś
    /// doczytać, automatyczne przewijanie MUSI przestać go szarpać.
    @State private var isPinnedToBottom = true
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                // Przepływ startowy to STAN ZAKŁADKI, nie arkusze: hero →
                // Zgoda → Poznaj → Start → rozmowa. Nagłówek i tab bar stoją,
                // wymienia się tylko treść — użytkownik czyta to jako ten sam
                // ekran w następnym kroku, nie nowy widok w stosie nawigacji.
                Group {
                    switch currentStep {
                    case .hero:
                        AssistantWelcomeView(
                            onStart: {
                                welcomeSeen = true
                                goToStep(.consent)
                            },
                            onShowCapabilities: { showCapabilities = true }
                        )
                    case .consent:
                        if let consents = sessionStore.consentStore {
                            AssistantConsentGateView(
                                consents: consents,
                                source: "IOS_ASSISTANT_GATE",
                                presentation: .inline,
                                onGranted: { continueAfterConsent() },
                                showsStepper: true,
                                onBack: { goToStep(.hero) },
                                onContinue: { continueAfterConsent() }
                            )
                        } else {
                            conversation
                            composer
                        }
                    case .cards:
                        AssistantHowItWorksView(
                            presentation: .inline,
                            showsStepBar: true,
                            startCard: introCard,
                            onFinish: {
                                introPage = 0
                                goToStep(.firstMessage)
                            },
                            onSkip: { finishIntro() },
                            onBack: { goToStep(.consent) },
                            onCardChange: { introCard = $0 }
                        )
                    case .firstMessage:
                        AssistantFirstMessageView(
                            onAsk: { text in
                                finishIntro()
                                ask(text)
                            },
                            onCompose: {
                                finishIntro()
                                // Pole pojawia się razem z rozmową — fokus dopiero,
                                // gdy już jest w hierarchii.
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { isComposerFocused = true }
                            },
                            onBack: {
                                introCard = AssistantCapabilities.onboarding.count - 1
                                goToStep(.cards)
                            },
                            startPage: introPage,
                            onPageChange: { introPage = $0 }
                        )
                    case nil:
                        conversation
                        composer
                    }
                }
                .transition(.assistantIntroStep)
                .animation(.easeOut(duration: 0.28), value: currentStep)
            }
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
        }
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
        .task {
            // Cele i ograniczenia domowników pod kartę „Co wiem o Was”.
            // Cicho i tylko raz na kwadrans — to karta poboczna.
            await sessionStore.refreshMemberContext()
        }
        .task(id: datesViewModel.weekStartISO) {
            // Chipy i arkusz „Dla kogo liczyć” biorą to samo, co serwer
            // wkłada do promptu — jedno źródło zamiast trzech cache'ów.
            await store.refreshContext(weekStart: datesViewModel.weekStartISO)
        }
        .task {
            // Stan zgód PRZED pierwszym renderem bramki — bez tego nowy
            // użytkownik widział rozmowę, dopóki serwer nie odpowiedział.
            await sessionStore.consentStore?.refresh()
        }
        .sheet(isPresented: $showsScopeSheet) {
            AssistantScopeSheet(
                members: sessionStore.householdMembers,
                context: store.context?.members ?? [],
                selection: $scopeUserIds
            )
        }
        .sheet(isPresented: $showUsage) {
            AssistantUsageSheet(store: store)
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
                onAsk: { text in ask(text) },
                onCompose: { isComposerFocused = true }
            )
        }
        .sheet(isPresented: $showHowItWorks) {
            AssistantHowItWorksView(
                presentation: .sheet,
                onFinish: { onboardingSeen = true },
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
            // Bramka i onboarding to nie rozmowa — nagłówek zostaje duży,
            // nawet gdy konto ma stare rozmowy (tytuł starej rozmowy nad
            // „Zanim zaczniemy" wyglądał na błąd).
            mode: (store.messages.isEmpty || currentStep != nil) ? .large : .compact(title: conversationTitle),
            onNewConversation: { Task { await store.startNewConversation() } },
        ) {
            Button { Task { await store.startNewConversation() } } label: { Label("Nowa rozmowa", systemImage: "plus") }
            Button { showConversations = true } label: { Label("Historia rozmów", systemImage: "clock") }
            Button { showCapabilities = true } label: { Label("Co potrafi asystent", systemImage: "sparkles") }
            Button { showHowItWorks = true } label: { Label("Jak działa asystent", systemImage: "questionmark.bubble") }
            Button { showMemory = true } label: { Label("Pamięć domu", systemImage: "brain.head.profile") }
            Button { showUsage = true } label: { Label("Limity asystenta", systemImage: "chart.bar") }
            Button { showConsentReview = true } label: { Label("Prywatność i zgoda", systemImage: "lock.shield") }
            Divider()
            Button(role: .destructive) { showDeleteAlert = true } label: { Label("Usuń historię rozmów", systemImage: "trash") }
        }
    }

    /// Który krok przepływu startowego pokazać. Bez zgody zawsze hero albo
    /// zgoda (ręczny wybór tylko między nimi); ze zgodą — to, co user wybrał
    /// przyciskami, a bez wyboru: karty, dopóki onboarding nie jest
    /// odhaczony. `nil` = rozmowa.
    private var currentStep: IntroStep? {
        if gateActive {
            switch introStep {
            case .hero: return .hero
            case .consent: return .consent
            default: return welcomeSeen ? .consent : .hero
            }
        }
        if let introStep { return introStep }
        return onboardingSeen ? nil : .cards
    }

    private func goToStep(_ step: IntroStep) {
        withAnimation(.easeOut(duration: 0.28)) { introStep = step }
    }

    /// Po zgodzie: karty tylko za pierwszym razem. Kto cofnął zgodę i włącza
    /// ją ponownie (albo dostał 403 w środku rozmowy), wraca prosto do
    /// rozmowy — onboarding i „Od czego zaczniemy?" zostają pod menu ⋯.
    private func continueAfterConsent() {
        // Zdejmuje blokadę 403 (`needsConsent`) także wtedy, gdy zgoda była
        // już zapisana po stronie serwera, a store o tym nie wiedział.
        store.consentGranted()
        if store.retryText != nil { retry() }
        if onboardingSeen {
            finishIntro()
        } else {
            goToStep(.cards)
        }
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

    private var conversationTitle: String? {
        guard let id = store.conversationId else { return nil }
        return store.conversations.first { $0.id == id }?.title
    }

    // MARK: - Rozmowa

    private var conversation: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.isLoadingHistory && store.messages.isEmpty {
                            ChatSkeleton()
                        } else if store.messages.isEmpty {
                            emptyState
                        }

                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                            if let separator = daySeparator(at: index) {
                                DaySeparator(text: separator)
                            }

                            MessageBubble(
                                message: message,
                                isBusy: isBusy(message),
                                onOpenPlan: { sessionStore.dashboardTab = .plan },
                                onOpenShopping: {
                                    // Lista zakupów jest arkuszem w Planie,
                                    // więc sama zakładka to za mało.
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

                        if store.isSending {
                            AssistantProgressTrail(
                                steps: store.progress,
                                startedAt: store.turnStartedAt
                            )
                            .id(Self.progressAnchor)
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
                    .padding(.horizontal, WMPageMetrics.horizontal)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.containerSize.height
                        >= geometry.contentSize.height - 80
                } action: { _, atBottom in
                    isPinnedToBottom = atBottom
                }
                .onChange(of: store.messages.count) { _, _ in
                    // Własne pytanie ciągniemy na sam dół; odpowiedź asystenta
                    // ustawiamy POCZĄTKIEM pod górną krawędzią, bo od góry się
                    // ją czyta — a plan tygodnia potrafi mieć ekran wysokości.
                    guard let last = store.messages.last else { return }
                    scroll(proxy, to: last.id, anchor: last.author == .user ? .bottom : .top)
                }
                .onChange(of: store.progress.count) { _, _ in
                    guard isPinnedToBottom else { return }
                    scroll(proxy, to: Self.progressAnchor, anchor: .bottom)
                }
                .onChange(of: store.errorMessage) { _, newValue in
                    guard newValue != nil else { return }
                    scroll(proxy, to: Self.errorAnchor, anchor: .bottom)
                }
                .onChange(of: isComposerFocused) { _, focused in
                    guard focused, let last = store.messages.last else { return }
                    scroll(proxy, to: last.id, anchor: .bottom)
                }
                // Wibracja tylko przy ODPOWIEDZI — przy każdej wiadomości
                // (także własnej) byłaby szumem.
                .sensoryFeedback(.success, trigger: answerCount)
                .sensoryFeedback(.error, trigger: store.errorMessage)

                if !isPinnedToBottom && !store.messages.isEmpty {
                    scrollToBottomPill(proxy)
                }
            }
        }
    }

    private func scrollToBottomPill(_ proxy: ScrollViewProxy) -> some View {
        Button {
            scroll(proxy, to: Self.tailAnchor, anchor: .bottom)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.wmLabel(scheme))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.wmCardSurface(scheme)))
                .overlay(Circle().stroke(Color.wmCardStroke(scheme), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
        .accessibilityLabel("Na koniec rozmowy")
    }

    private var emptyState: some View {
        AssistantEmptyState(knowledge: knowledge, onAsk: ask)
            .padding(.bottom, 8)
    }

    /// Fakty pod pusty stan — liczone tutaj, bo tylko ten widok ma naraz
    /// dostęp do planu, katalogu i składu gospodarstwa.
    private var knowledge: AssistantKnowledge {
        let dates = datesViewModel.dates
        let planned = dates.reduce(into: 0) { total, date in
            total += mealStore.plan(for: date).allMeals.count
        }
        let slotsPerDay = max(1, sessionStore.mealSlots.enabled.count)
        let recipes = recipeCatalogStore.recipes

        return AssistantKnowledge(
            weekLabel: Self.weekLabel(for: dates),
            plannedMeals: planned,
            totalMealSlots: slotsPerDay * max(1, dates.count),
            calorieGoal: calorieGoal,
            proteinTargetG: ownProteinTarget,
            recipeCount: recipes.count,
            favouriteCount: recipes.filter(\.favourite).count,
            members: otherMembers
        )
    }

    private var ownProteinTarget: Int? {
        let ownId = sessionStore.currentUserId
        let mine = sessionStore.memberContext.first { $0.userId == ownId }
        return mine?.targets?.macros?.proteinG
    }

    /// Domownicy poza mną — w karcie „Co wiem o Was” moje własne cele mają
    /// osobny wiersz, więc powtarzanie ich tutaj byłoby szumem.
    private var otherMembers: [AssistantKnowledge.Member] {
        let ownId = sessionStore.currentUserId
        return sessionStore.memberContext
            .filter { $0.userId != ownId }
            .map { context in
                AssistantKnowledge.Member(
                    id: context.userId,
                    name: HouseholdMemberStyle.shortName(context.displayName),
                    calorieGoal: context.targets?.calorieGoal,
                    restrictions: Self.restrictions(for: context)
                )
            }
    }

    /// „bez laktozy”, „wegetariańska” — to samo, czym asystent zawęża katalog.
    private static func restrictions(for context: BackendMemberContextDTO) -> String? {
        var parts: [String] = []

        let allergens = (context.allergens ?? [])
            .compactMap { Allergen(rawValue: $0)?.title.lowercased() }
        if !allergens.isEmpty {
            parts.append("bez " + allergens.joined(separator: ", "))
        }

        if let raw = context.dietPreference,
           let diet = DietPreference(backendValue: raw),
           diet != .none {
            parts.append(diet.title.lowercased())
        }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Etykieta zakresu: „Cały dom · 4”, „Ania i Zosia”, „3 osoby”.
    ///
    /// Do dwóch osób wypisujemy imiona — to jest cała informacja. Powyżej
    /// imiona nie mieszczą się w chipie, a sama liczba wystarczy, bo listę
    /// widać po dotknięciu.
    private static func scopeLabel(
        selected: [HouseholdMemberSnapshot],
        all: [HouseholdMemberSnapshot]
    ) -> String {
        if selected.isEmpty {
            return all.count > 1 ? "Cały dom · \(all.count)" : "Tylko Ty"
        }
        let names = selected.map(\.displayName)
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) i \(names[1])"
        default:
            return "\(names.count) \(AssistantScopeSheet.peopleWord(names.count))"
        }
    }

    /// „1–7 września” — zakres widocznego tygodnia jednym napisem.
    private static func weekLabel(for dates: [Date]) -> String {
        guard let first = dates.first, let last = dates.last else {
            return "ten tydzień"
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "pl_PL")
        day.dateFormat = "d"

        let full = DateFormatter()
        full.locale = Locale(identifier: "pl_PL")
        full.dateFormat = "d MMMM"

        return "\(day.string(from: first))–\(full.string(from: last))"
    }

    /// Podpowiedzi nad chipami zakresu, dosunięte do prawej jak dymki
    /// użytkownika. W rozmowie najwyżej dwie: po błędzie czasu — te
    /// z serwera (mniejszy zakres), po odpowiedzi — kolejny ruch. W scrollu
    /// pod ostatnią wiadomością zajmowały pół ekranu.
    private var composerHints: [String]? {
        guard !store.isSending else { return nil }
        if store.messages.isEmpty { return AssistantCapabilities.quickStarts }
        if !store.suggestions.isEmpty { return Array(store.suggestions.prefix(2)) }
        guard store.errorMessage == nil, store.messages.last?.author == .assistant else { return nil }
        return Array(Self.followUpSuggestions.prefix(2))
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
            }

            Divider().overlay(Color.wmRule(scheme))

            // Zakres widoczny PRZED odpowiedzią: bez tego użytkownik dowiaduje
            // się, o który tydzień i o kogo chodziło, dopiero z wyniku.
            AssistantContextChips(
                items: contextChips,
                isMuted: store.isSending,
                onTap: { chip in
                    guard chip.id == "household" else { return }
                    showsScopeSheet = true
                }
            )
                .padding(.top, 10)
                .padding(.bottom, 2)

            if editing != nil {
                editingBar
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    store.isUnavailable
                        ? "Asystent jest teraz niedostępny"
                        : (store.isLocked ? "Chwila przerwy — spróbuj za moment" : "Napisz do asystenta…"),
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .font(.system(size: 15.5))
                .tracking(-0.25)
                .foregroundStyle(Color.wmLabel(scheme))
                .focused($isComposerFocused)
                .disabled(store.isUnavailable || store.isLocked)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.wmInsetSurface(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isComposerFocused
                                ? WMPalette.terracotta.opacity(0.45)
                                : Color.wmTileStroke(scheme),
                            lineWidth: 1
                        )
                )

                // W trakcie tury strzałka zamienia się w „stop": po dziesięciu
                // sekundach widać już, że pytanie było źle zadane, a czekanie
                // do końca nie daje nic poza czekaniem.
                Button {
                    if store.isSending { store.stopWaiting() } else { send() }
                } label: {
                    Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: store.isSending ? 14 : 17, weight: .bold))
                        .foregroundStyle(store.isSending ? Color.wmLabel(scheme) : Color.wmPageBase(scheme))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(sendTint))
                }
                .buttonStyle(.plain)
                .disabled(!store.isSending && !canSend)
                .accessibilityLabel(store.isSending ? "Zatrzymaj turę" : "Wyślij")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
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
                .foregroundStyle(WMPalette.butter)

            VStack(alignment: .leading, spacing: 1) {
                Text("Poprawiasz pytanie")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.wmLabel(scheme))
                Text("Odpowiedzi po nim znikną z rozmowy")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.wmFaint(scheme))
            }

            Spacer(minLength: 0)

            Button {
                draft = ""
                editing = nil
                isComposerFocused = false
            } label: {
                Text("Anuluj")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.wmMuted(scheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.wmButterTint(scheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }

    /// Chipy mówią, z czym asystent policzy odpowiedź. Zakres domowników
    /// da się zmienić dotknięciem; pozostałe są etykietami i dlatego nie
    /// udają klikalnych chevronem.
    private var contextChips: [AssistantContextChip] {
        var chips: [AssistantContextChip] = [
            AssistantContextChip(
                id: "week",
                icon: "calendar",
                label: datesViewModel.isCurrentWeek
                    ? "Ten tydzień"
                    : Self.weekLabel(for: datesViewModel.dates)
            )
        ]

        let household = sessionStore.householdMembers
        let selected = household.filter { scopeUserIds.contains($0.id) }
        chips.append(
            AssistantContextChip(
                id: "household",
                icon: selected.isEmpty && household.count > 1 ? "person.2" : "person",
                label: Self.scopeLabel(selected: selected, all: household),
                adjustable: household.count > 1,
                isActive: !selected.isEmpty
            )
        )

        // Cel z serwera, gdy go dał — to nim liczą się paski celu na kartach;
        // cel z telefonu jest tylko zapasem na starszy serwer.
        let goal = store.context?.targetKcalPerDay ?? calorieGoal
        chips.append(
            AssistantContextChip(id: "goal", icon: "target", label: "Cel \(goal) kcal")
        )
        return chips
    }

    private var canSend: Bool {
        store.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendTint: Color {
        if store.isSending { return WMPalette.terracotta }
        return canSend ? WMPalette.terracotta : Color.wmMuted(scheme).opacity(0.4)
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

        let scope = scopeUserIds
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
                    weekStart: datesViewModel.weekStartISO,
                    scopeUserIds: Array(scope)
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
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: anchor)
        }
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

    private static let progressAnchor = "assistant.progress"
    private static let errorAnchor = "assistant.error"
    private static let bottomAnchor = "assistant.bottom"
    private static let tailAnchor = "assistant.tail"

    private static let followUpSuggestions = [
        "Podmień jedno danie",
        "Co z tego wyjdzie na liście zakupów?",
        "Zaplanuj resztę tygodnia",
    ]
}

/// Zakładka asystenta, zanim sesja postawi store'y (zimny start, brak
/// gospodarstwa). Pusta zakładka wyglądałaby na awarię aplikacji.
struct AssistantUnavailableView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                EditorialPageHeader("Asystent")

                Text("Asystent będzie dostępny, gdy wczyta się gospodarstwo.")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.wmMuted(scheme))

                Spacer()
            }
            .padding(.horizontal, WMPageMetrics.horizontal)
            .padding(.top, WMPageMetrics.top)
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
            .foregroundStyle(Color.wmMuted(scheme))
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
                .foregroundStyle(Color.wmLabel(scheme))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.wmAccentTint(scheme))
                )
            }
            // Wysłana, jeszcze niepotwierdzona — subtelnie, bo w 99 %
            // przypadków potwierdzenie przychodzi zanim ktokolwiek zdąży
            // to zauważyć.
            .opacity(message.isPending ? 0.6 : 1)
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
            AssistantClarifyCard(card: clarify, onAsk: onAsk)
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
                .fill(Color.wmTileBg(scheme))
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
                    .foregroundStyle(WMPalette.terracotta)
                    .padding(.top, 1)

                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wmLabel(scheme))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }

            if let onRetry {
                Button(action: onRetry) {
                    Text("Spróbuj ponownie")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WMPalette.terracotta)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.wmTileBg(scheme)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.wmAccentTint(scheme))
        )
    }
}
