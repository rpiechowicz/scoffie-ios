import SwiftUI

/// „15 · Rozmowy” — nagłówek `Asystent · Rozmowy` z krążkiem „nowa rozmowa”
/// i X, grupy Dziś / Wczoraj / W tym tygodniu / Wcześniej, wiersz = tytuł,
/// podgląd ostatniej odpowiedzi, godzina po prawej; rozmowa z biegnącą turą
/// ma plakietkę „W toku”. Usuwanie przez przytrzymanie wiersza.
///
/// 7.10.2026 (Rafał: „popraw widoki i sheet dla asystenta zgodnie z nowym
/// design”): układ list arkuszy aplikacji — nagłówek i WSPÓLNE pole szukania
/// przypięte nad listą (`RecipeListSheetTop` + `SCSearchField`, jak „Wybierz
/// przepis”), grupy jako etykieta + karta Ustawień, wiersz
/// `EditorialSettingsRow` z kafelkiem i podglądem w podpisie, pusty stan
/// `RecipeListEmptyState`. Dawna własna pigułka szukania na dole (krem, dwa
/// cienie, `AssistantLook`) i wiersze `AssistantRow` odpadły.
struct AssistantConversationsSheet: View {
    let store: AgentStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var pendingDeletion: AgentConversationDTO?
    @State private var query = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                top

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.historyConversations.isEmpty && !store.isLoadingConversations {
                            emptyState
                                .padding(.top, 8)
                        } else if groups.isEmpty && !query.isEmpty {
                            noResults
                        } else {
                            ForEach(Array(groups.enumerated()), id: \.element.label) { index, group in
                                EditorialSheetSectionLabel(title: group.label)
                                    .padding(.top, index == 0 ? 8 : 20)
                                EditorialSettingsCardGroup {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { itemIndex, conversation in
                                        row(conversation, isLast: itemIndex == group.items.count - 1)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // Treść gaśnie pod przypiętym nagłówkiem zamiast kreski.
                .scScrollEdgeFade()
            }
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
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

    // MARK: - Nagłówek i szukanie

    /// Nagłówek i pole szukania przypięte nad listą — ten sam klocek, co
    /// w „Wybierz przepis” i liście kategorii. Bez rozmów pole nie ma czego
    /// szukać, więc stoi sam nagłówek.
    @ViewBuilder
    private var top: some View {
        if store.historyConversations.isEmpty {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 8)
        } else {
            RecipeListSheetTop(searchPrompt: "Szukaj w rozmowach", searchText: $query) {
                header
            }
        }
    }

    private var header: some View {
        EditorialSheetHeader(
            eyebrow: "Asystent",
            title: "Rozmowy",
            // Ten sam zegar, co „Historia rozmów” w menu ⋯.
            icon: "clock.fill",
            onClose: { dismiss() }
        ) {
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
        }
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

    /// Wiersz rozmowy: kafelek (terakota — kolor Asystenta z jego wiersza
    /// w Ustawieniach; pusta rozmowa szara) · tytuł · podgląd ostatniej
    /// odpowiedzi w podpisie · godzina i „W toku” po prawej.
    private func row(_ conversation: AgentConversationDTO, isLast: Bool) -> some View {
        let isRunning = conversation.activeTurnId != nil
        let isEmpty = conversation.title == nil
        let preview = conversation.preview.flatMap { text -> String? in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != conversation.title else { return nil }
            return trimmed
        }
        return EditorialSettingsRow(
            icon: isEmpty ? "bubble.left" : "bubble.left.fill",
            iconColor: isEmpty ? SettingsAccent.slate : SCPalette.terracotta,
            title: conversation.title ?? "Nowa rozmowa",
            subtitle: preview ?? (isEmpty ? "Bez wiadomości" : nil),
            isLast: isLast,
            action: {
                Task {
                    await store.select(conversationId: conversation.id)
                    dismiss()
                }
            }
        ) {
            VStack(alignment: .trailing, spacing: 6) {
                if let stamp = Self.stamp(conversation) {
                    Text(stamp)
                        .font(.sc(size: 12.5))
                        .monospacedDigit()
                        .foregroundStyle(Color.scFaint(scheme))
                }
                if isRunning {
                    AssistantWorkingChip()
                }
            }
            .fixedSize()
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = conversation
            } label: {
                Label("Usuń rozmowę", systemImage: "trash")
            }
        }
        .accessibilityValue(conversation.id == store.conversationId ? "bieżąca" : (isRunning ? "w toku" : ""))
        .accessibilityHint("Otwiera rozmowę. Przytrzymaj, żeby usunąć.")
    }

    // MARK: - Puste stany

    /// Pusty stan list aplikacji (`RecipeListEmptyState`: kafelek powodu,
    /// tytuł, zdanie) zamiast szarego znaku z własnym krojem.
    private var emptyState: some View {
        RecipeListEmptyState(
            icon: "bubble.left.and.bubble.right.fill",
            title: "Nie ma jeszcze żadnej rozmowy",
            message: "Zapytaj Asystenta o plan tygodnia — rozmowa zapisze się tutaj i będzie można do niej wrócić."
        )
    }

    private var noResults: some View {
        RecipeListEmptyState(
            icon: "magnifyingglass",
            title: "Nic nie pasuje do „\(query)”",
            message: "Szukam w tytułach i ostatnich wiadomościach.",
            actions: [
                RecipeListEmptyState.Action(title: "Wyczyść szukanie", icon: "xmark", run: { query = "" })
            ]
        )
        .padding(.top, 8)
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
