import SwiftUI

/// Historia rozmów z asystentem.
///
/// Rozmowa z asystentem nie jest jednorazowa: wraca się do niej, żeby
/// sprawdzić, co ustaliliśmy w poniedziałek, i zaczyna nową, gdy temat jest
/// inny. Bez tej listy istniała dokładnie jedna rozmowa — najnowsza — a
/// wszystkie starsze były na serwerze i nikt nie mógł ich zobaczyć.
struct AssistantConversationsSheet: View {
    let store: AgentStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var pendingDeletion: AgentConversationDTO?
    @State private var query = ""


    var body: some View {
        NavigationStack {
            ZStack {
                Color.scCanvas(scheme).ignoresSafeArea()

                if store.conversations.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Rozmowy")
            .navigationBarTitleDisplayMode(.inline)
            // Rozmów przybywa po jednej dziennie i po miesiącu lista jest
            // dłuższa niż ekran — szukanie po treści jest wtedy szybsze niż
            // przewijanie po datach.
            .searchable(text: $query, prompt: "Szukaj w rozmowach")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await store.startNewConversation()
                            dismiss()
                        }
                    } label: {
                        Label("Nowa rozmowa", systemImage: "square.and.pencil")
                    }
                }
            }
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
        .task {
            await store.refreshConversations()
        }
    }

    private var list: some View {
        List {
            ForEach(groups, id: \.label) { group in
                Section {
                    ForEach(group.items) { conversation in
                        Button {
                            Task {
                                await store.select(conversationId: conversation.id)
                                dismiss()
                            }
                        } label: {
                            row(conversation)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.scCanvas(scheme))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = conversation
                            } label: {
                                Label("Usuń", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(group.label)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.scFaint(scheme))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if groups.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .refreshable {
            await store.refreshConversations()
        }
    }

    private struct ConversationGroup {
        let label: String
        let items: [AgentConversationDTO]
    }

    /// Rozmowy pogrupowane po tym, KIEDY się wydarzyły.
    ///
    /// Płaska lista dat odpowiada na pytanie „która to była”, dopiero gdy pamięta
    /// się datę. Grupy odpowiadają na to, jak ludzie o tym myślą: dzisiejsza,
    /// wczorajsza, „gdzieś w tym tygodniu”.
    private var groups: [ConversationGroup] {
        let matching = store.conversations.filter(matches)
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

    /// Szukanie bez znaków diakrytycznych i wielkości liter — „zurek” ma
    /// znaleźć „Żurek”.
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

    private func row(_ conversation: AgentConversationDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.title ?? "Nowa rozmowa")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)

                    // Rozmowa z turą w biegu — bez tego znaku wygląda jak
                    // każda inna, a właśnie do niej warto wrócić najpierw.
                    if conversation.activeTurnId != nil {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SCPalette.terracotta)
                    }
                }

                if let preview = conversation.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if let stamp = Self.stamp(conversation) {
                    Text(stamp)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }

            Spacer(minLength: 0)

            if conversation.id == store.conversationId {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.scMuted(scheme))

            Text("Nie ma jeszcze żadnej rozmowy")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))

            Text("Zapytaj asystenta o plan tygodnia — rozmowa zapisze się tutaj i będziesz mógł do niej wrócić.")
                .font(.system(size: 14))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    private static func stamp(_ conversation: AgentConversationDTO) -> String? {
        let raw = conversation.lastMessageAt ?? conversation.createdAt
        guard let date = AgentStore.parseTimestamp(raw) else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "Wczoraj \(timeFormatter.string(from: date))"
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
        formatter.dateFormat = "d MMMM"
        return formatter
    }()
}
