import SwiftUI

/// Historia rozmów z asystentem — arkusz w tym samym języku co reszta
/// asystenta: redakcyjny nagłówek z krzyżykiem, własne pole szukania,
/// grupy „Dziś / Wczoraj / W tym tygodniu / Wcześniej” jako karty
/// z wierszami (tytuł, początek ostatniej wiadomości, godzina), plakietka
/// „W toku” przy rozmowie z turą w biegu i ptaszek przy bieżącej.
/// Usuwanie przez przytrzymanie wiersza — bez systemowej listy.
struct AssistantConversationsSheet: View {
    let store: AgentStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var pendingDeletion: AgentConversationDTO?
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialSheetHeader(eyebrow: "Asystent", title: "Rozmowy") {
                            dismiss()
                        }

                        searchField

                        newConversationRow

                        if store.conversations.isEmpty && !store.isLoadingConversations {
                            emptyState
                        } else if groups.isEmpty && !query.isEmpty {
                            noResults
                        } else {
                            ForEach(groups, id: \.label) { group in
                                groupCard(group)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await store.refreshConversations() }
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

    // MARK: - Szukanie i nowa rozmowa

    /// Własne pole zamiast `.searchable`: bez paska nawigacji systemowe pole
    /// nie ma gdzie się pokazać, a rozmów po miesiącu jest za dużo na
    /// przewijanie po datach.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scFaint(scheme))
            TextField("Szukaj w rozmowach", text: $query)
                .font(.system(size: 15))
                .foregroundStyle(Color.scLabel(scheme))
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść szukanie")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Capsule().fill(Color.scTileBg(scheme)))
        .overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
    }

    private var newConversationRow: some View {
        Button {
            Task {
                await store.startNewConversation()
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .bold))
                Text("Nowa rozmowa")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.25)
            }
            .foregroundStyle(SCPalette.terracotta)
            .frame(maxWidth: .infinity)
            .frame(height: AssistantCardMetrics.ctaHeight)
            .scSoftCapsule()
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
    }

    // MARK: - Grupy

    private struct ConversationGroup {
        let label: String
        let items: [AgentConversationDTO]
    }

    /// Rozmowy pogrupowane po tym, KIEDY się wydarzyły: dzisiejsza,
    /// wczorajsza, „gdzieś w tym tygodniu” — tak ludzie o tym myślą.
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

    private func groupCard(_ group: ConversationGroup) -> some View {
        AssistantSurfaceCard {
            AssistantSectionLabel(text: group.label)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 2)

            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, conversation in
                row(conversation, first: index == 0)
            }
        }
    }

    private func row(_ conversation: AgentConversationDTO, first: Bool) -> some View {
        let isCurrent = conversation.id == store.conversationId
        let isRunning = conversation.activeTurnId != nil
        // Podgląd, który powtarza tytuł, nic nie dodaje — wtedy zostaje sama godzina.
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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(conversation.title ?? "Nowa rozmowa")
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.25)
                            .foregroundStyle(Color.scLabel(scheme))
                            .lineLimit(1)
                        if isRunning {
                            runningChip
                        }
                    }

                    if let preview {
                        Text(preview)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.scMuted(scheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let stamp = Self.stamp(conversation) {
                        Text(stamp)
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(Color.scFaint(scheme))
                    }
                }

                Spacer(minLength: 0)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.scFaint(scheme))
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.scRule(scheme)).frame(height: 1).padding(.leading, 16) }
        }
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = conversation
            } label: {
                Label("Usuń rozmowę", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "bieżąca" : (isRunning ? "w toku" : ""))
        .accessibilityHint("Otwiera rozmowę. Przytrzymaj, żeby usunąć.")
    }

    /// Plakietka „W toku” — subtelna, w kolorze marki, bez kręciołka.
    private var runningChip: some View {
        HStack(spacing: 4) {
            SCMarkShape()
                .fill(SCPalette.terracotta)
                .frame(width: 9, height: 9)
            Text("W toku")
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(SCPalette.terracotta)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(Color.scAccentTint(scheme)))
        .fixedSize()
    }

    // MARK: - Puste stany

    private var emptyState: some View {
        VStack(spacing: 12) {
            AssistantMarkBadge(size: 56)
                .padding(.top, 24)

            Text("Nie ma jeszcze żadnej rozmowy")
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))

            Text("Zapytaj asystenta o plan tygodnia — rozmowa zapisze się tutaj i będzie można do niej wrócić.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private var noResults: some View {
        VStack(spacing: 6) {
            Text("Nic nie pasuje do „\(query)”")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
            Text("Szukam w tytułach i ostatnich wiadomościach.")
                .font(.system(size: 13))
                .foregroundStyle(Color.scMuted(scheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
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
        formatter.dateFormat = "d MMMM, HH:mm"
        return formatter
    }()
}
