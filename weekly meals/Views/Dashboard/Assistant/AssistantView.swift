import SwiftUI

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
/// tygodnia", „Zapisuję plan tygodnia").
struct AssistantView: View {
    let store: AgentStore

    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.colorScheme) private var scheme

    @State private var draft = ""
    @State private var showDeleteAlert = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack {
            WMPageBackground(scheme: scheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                conversation
                composer
            }
        }
        .task {
            await store.openIfNeeded()
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
            Menu {
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
        .padding(.horizontal, WMPageMetrics.horizontal)
        .padding(.top, WMPageMetrics.top)
        .padding(.bottom, 12)
    }

    // MARK: - Rozmowa

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if store.messages.isEmpty && !store.isLoadingHistory {
                        emptyState
                    }

                    ForEach(store.messages) { message in
                        MessageBubble(message: message) {
                            sessionStore.dashboardTab = .plan
                        }
                        .id(message.id)
                    }

                    if store.isSending {
                        ProgressTrail(steps: store.progress)
                            .id(Self.progressAnchor)
                    }

                    if let errorMessage = store.errorMessage {
                        ErrorNote(text: errorMessage)
                            .id(Self.errorAnchor)
                    }
                }
                .padding(.horizontal, WMPageMetrics.horizontal)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.count) { _, _ in
                scroll(proxy, to: store.messages.last?.id)
            }
            .onChange(of: store.progress.count) { _, _ in
                scroll(proxy, to: Self.progressAnchor)
            }
            .onChange(of: store.errorMessage) { _, newValue in
                guard newValue != nil else { return }
                scroll(proxy, to: Self.errorAnchor)
            }
        }
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
                    Button {
                        draft = suggestion
                        isComposerFocused = true
                    } label: {
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

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.wmCanvas(scheme))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(sendTint))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Wyślij")
            }
            .padding(.horizontal, WMPageMetrics.horizontal)
            .padding(.vertical, 12)
        }
    }

    private var canSend: Bool {
        store.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendTint: Color {
        canSend ? WMPalette.terracotta : Color.wmMuted(scheme).opacity(0.4)
    }

    private func send() {
        let text = draft
        draft = ""
        Task {
            await store.send(text: text, weekStart: datesViewModel.weekStartISO)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String?) {
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private static let progressAnchor = "assistant.progress"
    private static let errorAnchor = "assistant.error"

    private static let suggestions = [
        "Zaplanuj mi obiady i kolacje na ten tydzień",
        "Podmień kolację we wtorek na coś do 30 minut",
        "Czego brakuje w planie, żeby wyrobić się z białkiem?",
    ]
}

/// Zakładka asystenta, zanim sesja postawi store'y (zimny start, brak
/// gospodarstwa). Pusta zakładka wyglądałaby na awarię aplikacji.
struct AssistantUnavailableView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
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
        }
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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if message.author == .user {
            userBubble
        } else {
            assistantCard
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

// MARK: - Postęp

/// Kroki tury. Ostatni jest wyróżniony, poprzednie zostają jako ślad — widać,
/// ile już się wydarzyło, zamiast jednego migającego napisu.
private struct ProgressTrail: View {
    let steps: [AgentProgressStepDTO]

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
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Błąd

private struct ErrorNote: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.wmAccentTint(scheme))
        )
    }
}
