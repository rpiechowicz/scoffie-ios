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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.wmCanvas(scheme).ignoresSafeArea()

                if store.conversations.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Rozmowy")
            .navigationBarTitleDisplayMode(.inline)
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
            ForEach(store.conversations) { conversation in
                Button {
                    Task {
                        await store.select(conversationId: conversation.id)
                        dismiss()
                    }
                } label: {
                    row(conversation)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.wmCanvas(scheme))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDeletion = conversation
                    } label: {
                        Label("Usuń", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refreshConversations()
        }
    }

    private func row(_ conversation: AgentConversationDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(conversation.title ?? "Nowa rozmowa")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)

                    // Rozmowa z turą w biegu — bez tego znaku wygląda jak
                    // każda inna, a właśnie do niej warto wrócić najpierw.
                    if conversation.activeTurnId != nil {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WMPalette.terracotta)
                    }
                }

                if let preview = conversation.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if let stamp = Self.stamp(conversation) {
                    Text(stamp)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.wmMuted(scheme))
                }
            }

            Spacer(minLength: 0)

            if conversation.id == store.conversationId {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WMPalette.terracotta)
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
                .foregroundStyle(Color.wmMuted(scheme))

            Text("Nie ma jeszcze żadnej rozmowy")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.wmLabel(scheme))

            Text("Zapytaj asystenta o plan tygodnia — rozmowa zapisze się tutaj i będziesz mógł do niej wrócić.")
                .font(.system(size: 14))
                .foregroundStyle(Color.wmMuted(scheme))
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
