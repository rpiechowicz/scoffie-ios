import SwiftUI

/// „15 · Rozmowy” — 1:1 z makietą: nagłówek `Asystent · Rozmowy` z krążkiem
/// „nowa rozmowa” i X, grupy Dziś / Wczoraj / W tym tygodniu / Wcześniej,
/// wiersz = tytuł, podgląd ostatniej odpowiedzi, godzina po prawej;
/// rozmowa z biegnącą turą ma plakietkę „W toku”. Szukanie przypięte do
/// dołu. Usuwanie przez przytrzymanie wiersza.
struct AssistantConversationsSheet: View {
    let store: AgentStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var pendingDeletion: AgentConversationDTO?
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            AssistantSheetScaffold(
                title: "Rozmowy",
                onClose: { dismiss() },
                action: {
                    // Ten sam krążek, co krzyżyk obok (`SCSheetIconButton`) —
                    // dwa przyciski w nagłówku to jeden komplet.
                    SCSheetIconButton(
                        systemName: "square.and.pencil",
                        tint: SCPalette.terracotta,
                        accessibilityLabel: "Nowa rozmowa"
                    ) {
                        Task {
                            await store.startNewConversation()
                            dismiss()
                        }
                    }
                },
                footer: { searchBar }
            ) {
                if store.historyConversations.isEmpty && !store.isLoadingConversations {
                    emptyState
                } else if groups.isEmpty && !query.isEmpty {
                    noResults
                } else {
                    ForEach(groups, id: \.label) { group in
                        AssistantGroup(title: group.label) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, conversation in
                                row(conversation, first: index == 0)
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(
                "Usunąć tę rozmowę?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                )
            ) {
                Button("Usuń", role: .destructive) {
                    guard let conversation = pendingDeletion else { return }
                    pendingDeletion = nil
                    Task { await store.deleteConversation(id: conversation.id) }
                }
                Button("Anuluj", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Rozmowa zniknie razem z wiadomościami. Plan tygodnia i przepisy zostają.")
            }
        }
        .presentationDragIndicator(.visible)
        .task { await store.refreshConversations() }
    }

    // MARK: - Szukanie

    /// `SearchBar`: pigułka 48 na dole, jak w aplikacji.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AssistantLook.faint(scheme))
            TextField("Szukaj w rozmowach", text: $query)
                .font(.system(size: 16))
                .tracking(-0.2)
                .foregroundStyle(AssistantLook.ink(scheme))
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(AssistantLook.faint(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść szukanie")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Capsule().fill(AssistantLook.input(scheme)))
        .overlay(Capsule().stroke(AssistantLook.cardStroke(scheme), lineWidth: 1))
        .shadow(color: Color.black.opacity(scheme == .dark ? 0 : 0.04), radius: 1, y: 1)
        .shadow(color: Color(red: 90 / 255, green: 50 / 255, blue: 30 / 255).opacity(scheme == .dark ? 0 : 0.10), radius: 12, y: 8)
    }

    // MARK: - Grupy

    private struct ConversationGroup {
        let label: String
        let items: [AgentConversationDTO]
    }

    /// Rozmowy pogrupowane po tym, KIEDY się wydarzyły.
    private var groups: [ConversationGroup] {
        let matching = store.historyConversations.filter(matches)
        let calendar = Calendar.current
        let now = Date()

        var buckets: [(String, [AgentConversationDTO])] = [
            ("Dziś", []), ("Wczoraj", []), ("W tym tygodniu", []), ("Wcześniej", [])
        ]

        for conversation in matching {
            let stamp = AgentStore.parseTimestamp(conversation.lastMessageAt ?? conversation.createdAt)
            let index: Int
            if let stamp {
                if calendar.isDateInToday(stamp) {
                    index = 0
                } else if calendar.isDateInYesterday(stamp) {
                    index = 1
                } else if let days = calendar.dateComponents([.day], from: stamp, to: now).day, days < 7 {
                    index = 2
                } else {
                    index = 3
                }
            } else {
                index = 3
            }
            buckets[index].1.append(conversation)
        }

        return buckets
            .filter { !$0.1.isEmpty }
            .map { ConversationGroup(label: $0.0, items: $0.1) }
    }

    /// Szukanie bez znaków diakrytycznych i wielkości liter.
    private func matches(_ conversation: AgentConversationDTO) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let haystack = [conversation.title, conversation.preview]
            .compactMap { $0 }
            .joined(separator: " ")
        return haystack.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    /// `HistRow`: tytuł · podgląd ostatniej odpowiedzi · godzina i „W toku”.
    private func row(_ conversation: AgentConversationDTO, first: Bool) -> some View {
        let isRunning = conversation.activeTurnId != nil
        let isEmpty = conversation.title == nil
        let preview = conversation.preview.flatMap { text -> String? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != conversation.title else { return nil }
            return trimmed
        }
        return Button {
            Task {
                await store.select(conversationId: conversation.id)
                dismiss()
            }
        } label: {
            AssistantRow(
                title: conversation.title ?? "Nowa rozmowa",
                subtitle: preview ?? (isEmpty ? "Bez wiadomości" : nil),
                first: first,
                titleWeight: isEmpty ? .medium : .semibold,
                titleColor: isEmpty ? AssistantLook.muted(scheme) : nil,
                verticalPadding: 12,
                alignment: .top,
                leading: { EmptyView() },
                trailing: {
                    VStack(alignment: .trailing, spacing: 6) {
                        if let stamp = Self.stamp(conversation) {
                            Text(stamp)
                                .font(.system(size: 12.5))
                                .monospacedDigit()
                                .foregroundStyle(AssistantLook.faint(scheme))
                        }
                        if isRunning {
                            AssistantWorkingChip()
                        }
                    }
                    .fixedSize()
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = conversation
            } label: {
                Label("Usuń rozmowę", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(conversation.id == store.conversationId ? "bieżąca" : (isRunning ? "w toku" : ""))
        .accessibilityHint("Otwiera rozmowę. Przytrzymaj, żeby usunąć.")
    }

    // MARK: - Puste stany

    private var emptyState: some View {
        VStack(spacing: 14) {
            SCMarkShape()
                .fill(AssistantLook.ink(scheme).opacity(0.28))
                .frame(width: 30, height: 30)
                .padding(.top, 36)
                .accessibilityHidden(true)

            Text("Nie ma jeszcze żadnej rozmowy")
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AssistantLook.ink(scheme))

            Text("Zapytaj asystenta o plan tygodnia — rozmowa zapisze się tutaj i będzie można do niej wrócić.")
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(AssistantLook.muted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
    }

    private var noResults: some View {
        VStack(spacing: 6) {
            Text("Nic nie pasuje do „\(query)”")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AssistantLook.ink(scheme))
            Text("Szukam w tytułach i ostatnich wiadomościach.")
                .font(.system(size: 13))
                .foregroundStyle(AssistantLook.muted(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 38)
        .accessibilityElement(children: .combine)
    }

    private static func stamp(_ conversation: AgentConversationDTO) -> String? {
        let raw = conversation.lastMessageAt ?? conversation.createdAt
        guard let date = AgentStore.parseTimestamp(raw) else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) || calendar.isDateInYesterday(date) {
            return timeFormatter.string(from: date)
        }
        return dateFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
