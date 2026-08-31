import SwiftUI

/// Rozmowa z asystentem AI.
///
/// Arkusz, nie zakładka: asystent jest narzędziem DO planu, a nie osobnym
/// miejscem w aplikacji — wchodzi się w niego z Planu tygodnia i wraca do
/// tego samego tygodnia, o którym się rozmawiało.
///
/// Ekran świadomie nie ma „stanu ładowania" w środku dymka: tura trwa
/// dziesiątki sekund, więc zamiast kręciołka pokazujemy kroki, które
/// przysyła serwer („Czytam plan tygodnia", „Zapisuję plan tygodnia").
struct AssistantSheet: View {
    let store: AgentStore

    @Environment(\.datesViewModel) private var datesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var draft = ""
    @State private var showDeleteAlert = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.wmCanvas(scheme).ignoresSafeArea()

                VStack(spacing: 0) {
                    conversation
                    composer
                }
            }
            .navigationTitle("Asystent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Usuń historię rozmów", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Więcej opcji asystenta")
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
        .task {
            await store.openIfNeeded()
        }
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
                        MessageBubble(message: message)
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
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.wmCanvas(scheme))
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

// MARK: - Dymek

private struct MessageBubble: View {
    let message: AgentChatMessage

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            if message.author == .user { Spacer(minLength: 40) }

            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(Color.wmLabel(scheme))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            message.author == .user
                            ? Color.wmAccentTint(scheme)
                            : Color.wmCardSurface(scheme)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.wmCardStroke(scheme), lineWidth: 1)
                )
                // Wysłana, jeszcze niepotwierdzona — subtelnie, bo w 99 %
                // przypadków potwierdzenie przychodzi zanim ktokolwiek zdąży
                // to zauważyć.
                .opacity(message.isPending ? 0.6 : 1)

            if message.author == .assistant { Spacer(minLength: 40) }
        }
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
