import SwiftUI

/// „16 · Co o Was pamięta” — trzy grupy (preferencje, ograniczenia,
/// zwyczaje), każda notatka ze źródłem. Stuknięcie w notatkę pyta, czy ją
/// zapomnieć.
///
/// Notatki są WSPÓLNE dla domu — tak samo jak plan tygodnia i lista zakupów.
///
/// 7.10.2026 (nowy język arkuszy, jak Ustawienia → Gospodarstwo): podtytuł
/// to samo „6 z 30 notatek” (bez zdania objaśnień i bez liczenia od zera),
/// grupy = etykieta + karta Ustawień, notatka = `EditorialSettingsRow`
/// z kafelkiem grupy i pełnym tekstem, pusty stan `RecipeListEmptyState`,
/// a „Usuń wszystkie notatki” to `SCDestructiveButton` przypięty na dole
/// (jak „Opuść gospodarstwo”) zamiast terakotowego napisu pod licznikiem.
struct AssistantMemorySheet: View {
    let store: AgentStore

    /// Tyle notatek trzyma serwer — kontrakt `MEMORY_LIMIT`.
    private static let memoryLimit = 30

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showsForgetAllAlert = false
    @State private var pendingForget: AgentMemoryNoteDTO?

    var body: some View {
        NavigationStack {
            AssistantSheetScaffold(
                title: "Co o Was pamięta",
                subtitle: store.memory.isEmpty ? nil : "\(store.memory.count) z \(Self.memoryLimit) notatek",
                // Glif „Pamięci domu” z menu ⋯.
                icon: "brain.head.profile.fill",
                onClose: { dismiss() },
                footer: {
                    if !store.memory.isEmpty {
                        SCDestructiveButton(title: "Usuń wszystkie notatki", icon: "trash") {
                            showsForgetAllAlert = true
                        }
                    }
                }
            ) {
                if store.memory.isEmpty && !store.isLoadingMemory {
                    emptyState
                        .padding(.top, 14)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(grouped.enumerated()), id: \.element.id) { index, section in
                            EditorialSheetSectionLabel(title: section.group.title)
                                .padding(.top, index == 0 ? 14 : 20)
                            EditorialSettingsCardGroup {
                                ForEach(Array(section.notes.enumerated()), id: \.element.id) { noteIndex, note in
                                    noteRow(note, group: section.group, isLast: noteIndex == section.notes.count - 1)
                                }
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Usunąć wszystkie notatki?", isPresented: $showsForgetAllAlert) {
                Button("Usuń", role: .destructive) {
                    Task { await store.forgetAllMemory() }
                }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Nieodwracalne. Plan tygodnia i przepisy zostają; rozmowy kasujesz osobno w menu asystenta.")
            }
            .alert(
                "Zapomnieć tę notatkę?",
                isPresented: Binding(
                    get: { pendingForget != nil },
                    set: { if !$0 { pendingForget = nil } }
                )
            ) {
                Button("Zapomnij", role: .destructive) {
                    guard let note = pendingForget else { return }
                    pendingForget = nil
                    Task { await store.forgetMemory(noteId: note.id) }
                }
                Button("Anuluj", role: .cancel) { pendingForget = nil }
            } message: {
                Text(pendingForget?.text ?? "")
            }
        }
        .presentationDragIndicator(.visible)
        .task { await store.refreshMemory() }
    }

    private struct GroupSection: Identifiable {
        let group: AgentMemoryGroup
        let notes: [AgentMemoryNoteDTO]
        var id: String { group.id }
    }

    /// Grupy w stałej kolejności: preferencje, ograniczenia, zwyczaje.
    private var grouped: [GroupSection] {
        AgentMemoryGroup.allCases.compactMap { group in
            let notes = store.memory.filter { $0.group == group }
            return notes.isEmpty ? nil : GroupSection(group: group, notes: notes)
        }
    }

    /// Wiersz notatki: kafelek grupy · CAŁA treść (notatka to sama treść,
    /// nie nazwa — łamie się zamiast ucinać) · źródło „Z rozmowy · 14 wrz”.
    private func noteRow(_ note: AgentMemoryNoteDTO, group: AgentMemoryGroup, isLast: Bool) -> some View {
        let look = Self.look(group)
        return EditorialSettingsRow(
            icon: look.icon,
            iconColor: look.color,
            title: note.text,
            subtitle: source(note),
            isLast: isLast,
            wrapsText: true,
            action: { pendingForget = note }
        )
        .accessibilityHint("Pyta, czy zapomnieć tę notatkę")
    }

    /// Kafelek grupy — kolor i glif mówią rodzaj notatki bez czytania
    /// nagłówka sekcji.
    private static func look(_ group: AgentMemoryGroup) -> (icon: String, color: Color) {
        switch group {
        case .preference: return ("heart.fill", SCPalette.rose)
        case .constraint: return ("nosign", SettingsAccent.coral)
        case .habit: return ("repeat", SCPalette.indigo)
        }
    }

    private func source(_ note: AgentMemoryNoteDTO) -> String {
        guard let date = AgentStore.parseTimestamp(note.createdAt) else { return "Z rozmowy" }
        return "Z rozmowy · \(Self.dayFormatter.string(from: date))"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    /// Pusty stan list aplikacji (`RecipeListEmptyState`) zamiast szarego
    /// znaku z własnym krojem.
    private var emptyState: some View {
        RecipeListEmptyState(
            icon: "brain.head.profile.fill",
            title: "Na razie nic",
            message: "Gdy powiesz Asystentowi coś trwałego o swoim domu — „w środy jemy u teściów”, „Kuba nie je ryb” — zapisze to tutaj i będzie o tym wiedział w kolejnych rozmowach."
        )
    }
}
