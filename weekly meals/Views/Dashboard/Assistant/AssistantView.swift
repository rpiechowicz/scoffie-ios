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
    @Environment(\.colorScheme) private var scheme

    @State private var draft = ""
    @State private var showDeleteAlert = false
    @State private var showConversations = false
    @State private var showMemory = false
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
                conversation
                composer
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
        .sheet(isPresented: $showConversations) {
            AssistantConversationsSheet(store: store)
        }
        .sheet(isPresented: $showMemory) {
            AssistantMemorySheet(store: store)
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

    private var header: some View {
        EditorialPageHeader(title: "Asystent") {
            HStack(spacing: 8) {
                EditorialIconButton(icon: "clock.arrow.circlepath") {
                    showConversations = true
                }
                .accessibilityLabel("Historia rozmów")

                Menu {
                    Button {
                        Task { await store.startNewConversation() }
                    } label: {
                        Label("Nowa rozmowa", systemImage: "square.and.pencil")
                    }
                    Button {
                        showMemory = true
                    } label: {
                        Label("Co asystent pamięta", systemImage: "brain")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Usuń historię rozmów", systemImage: "trash")
                    }
                } label: {
                    // Ten sam rozmiar co `EditorialIconButton` (38 pt), żeby akcje
                    // nagłówka wyglądały tak samo na każdej zakładce.
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.wmLabel(scheme))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.wmTileBg(scheme)))
                        .overlay(Circle().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
                }
                .accessibilityLabel("Więcej opcji asystenta")
            }
        }
        .padding(.horizontal, WMPageMetrics.horizontal)
        .padding(.top, WMPageMetrics.top)
        .padding(.bottom, 12)
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
                                onOpenPlan: { sessionStore.dashboardTab = .plan },
                                onAskAgain: { ask(message.text) }
                            )
                            .id(message.id)
                        }

                        if store.isSending {
                            ProgressTrail(
                                steps: store.progress,
                                startedAt: store.turnStartedAt
                            )
                            .id(Self.progressAnchor)
                        }

                        if let errorMessage = store.errorMessage {
                            ErrorNote(
                                text: errorMessage,
                                onRetry: store.retryText == nil ? nil : retry
                            )
                            .id(Self.errorAnchor)
                        }

                        if showsFollowUps {
                            followUps
                        }

                        // Rozpórka: bez niej ScrollView nie ma dokąd przewinąć
                        // i początek krótkiej odpowiedzi nie da się wypchnąć
                        // pod górę ekranu.
                        Color.clear
                            .frame(height: 280)
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
            scroll(proxy, to: Self.bottomAnchor, anchor: .bottom)
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
        VStack(alignment: .leading, spacing: 14) {
            Text("O co zapytać")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.wmLabel(scheme))

            Text("Asystent zna Wasz plan tygodnia, przepisy i cele domowników. Może ułożyć tydzień, podmienić jedno danie albo dopisać przepis.")
                .font(.system(size: 14))
                .foregroundStyle(Color.wmMuted(scheme))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    // Jedno dotknięcie zamiast dwóch: podpowiedź wysyła się od
                    // razu, zamiast wypełniać pole i czekać na drugi ruch.
                    Button { ask(suggestion) } label: {
                        Text(suggestion)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.wmLabel(scheme))
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.wmTileBg(scheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 8)
    }

    /// Podpowiedzi kolejnego ruchu pod ostatnią odpowiedzią — jak w dojrzałych
    /// czatach: rozmowa nie kończy się ścianą tekstu i pustką.
    private var followUps: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Self.followUpSuggestions, id: \.self) { suggestion in
                    Button { ask(suggestion) } label: {
                        Text(suggestion)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WMPalette.terracotta)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.wmAccentTint(scheme)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var showsFollowUps: Bool {
        !store.isSending
            && store.errorMessage == nil
            && store.messages.last?.author == .assistant
    }

    // MARK: - Pole wiadomości

    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.wmRule(scheme))

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    store.isUnavailable ? "Asystent jest teraz niedostępny" : "Napisz do asystenta…",
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .font(.system(size: 15))
                .foregroundStyle(Color.wmLabel(scheme))
                .focused($isComposerFocused)
                .disabled(store.isUnavailable)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.wmInsetSurface(scheme))
                )

                // W trakcie tury strzałka zamienia się w „stop": po dziesięciu
                // sekundach widać już, że pytanie było źle zadane, a czekanie
                // do końca nie daje nic poza czekaniem.
                Button {
                    if store.isSending { store.stopWaiting() } else { send() }
                } label: {
                    Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: store.isSending ? 13 : 16, weight: .bold))
                        .foregroundStyle(Color.wmCanvas(scheme))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(sendTint))
                }
                .buttonStyle(.plain)
                .disabled(!store.isSending && !canSend)
                .accessibilityLabel(store.isSending ? "Przestań czekać" : "Wyślij")
            }
            .padding(.horizontal, WMPageMetrics.horizontal)
            .padding(.vertical, 12)
        }
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

    private func send() {
        ask(draft)
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

    private static let suggestions = [
        "Zaplanuj mi obiady i kolacje na ten tydzień",
        "Podmień kolację we wtorek na coś do 30 minut",
        "Czego brakuje w planie, żeby wyrobić się z białkiem?",
    ]

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
    let onOpenPlan: () -> Void
    let onAskAgain: () -> Void

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
            Button(action: onAskAgain) {
                Label("Zapytaj jeszcze raz", systemImage: "arrow.clockwise")
            }
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)

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
                // Wysłana, jeszcze niepotwierdzona — subtelnie, bo w 99 %
                // przypadków potwierdzenie przychodzi zanim ktokolwiek zdąży
                // to zauważyć.
                .opacity(message.isPending ? 0.6 : 1)
        }
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.savedPlan {
                AssistantSavedPlanCard(onOpenPlan: onOpenPlan)
            }

            AssistantAnswer(text: message.text)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.wmCardSurface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.wmCardStroke(scheme), lineWidth: 1)
        )
        .textSelection(.enabled)
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

// MARK: - Postęp

/// Kroki tury. Ostatni jest wyróżniony, poprzednie zostają jako ślad — widać,
/// ile już się wydarzyło, zamiast jednego migającego napisu.
private struct ProgressTrail: View {
    let steps: [AgentProgressStepDTO]
    let startedAt: Date?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                if steps.isEmpty {
                    Text("Zastanawiam się…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.wmMuted(scheme))
                } else {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        Text(step.label)
                            .font(.system(size: 14, weight: index == steps.count - 1 ? .medium : .regular))
                            .foregroundStyle(
                                index == steps.count - 1
                                ? Color.wmLabel(scheme)
                                : Color.wmMuted(scheme)
                            )
                    }
                }

                if let startedAt {
                    elapsed(from: startedAt)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// Między krokami bywa kilkanaście sekund ciszy. Licznik mówi, że
    /// aplikacja żyje, a po minucie wprost proponuje odejście — tura przeżywa
    /// zmianę zakładki.
    private func elapsed(from startedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(startedAt)))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(seconds) s")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wmMuted(scheme))

                if seconds >= 45 {
                    Text("Układanie całego tygodnia trwa nawet minutę — możesz przejść na inną zakładkę, odpowiedź poczeka.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(scheme))
                }
            }
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
