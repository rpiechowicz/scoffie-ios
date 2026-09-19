import SwiftUI

/// „16 · Co o Was pamięta” — 1:1 z makietą: nagłówek o treści, nie
/// o limicie; trzy grupy (preferencje, ograniczenia, zwyczaje), każda
/// notatka ze źródłem; „6 z 30 notatek” w stopce jako cicha metadana.
/// Stuknięcie w notatkę pyta, czy ją zapomnieć.
///
/// Notatki są WSPÓLNE dla domu — tak samo jak plan tygodnia i lista zakupów.
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
                subtitle: "Trwałe rzeczy o Waszym domu, zapamiętane z rozmów. Każdą możesz poprawić albo usunąć.",
                onClose: { dismiss() },
                footer: { footerMeta }
            ) {
                if store.memory.isEmpty && !store.isLoadingMemory {
                    AssistantGroup {
                        emptyState
                    }
                } else {
                    ForEach(grouped) { section in
                        AssistantGroup(title: section.group.title) {
                            ForEach(Array(section.notes.enumerated()), id: \.element.id) { index, note in
                                noteRow(note, first: index == 0)
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

    /// Wiersz notatki: treść 15/500, źródło „Z rozmowy · 14 wrz”, chevron.
    private func noteRow(_ note: AgentMemoryNoteDTO, first: Bool) -> some View {
        Button {
            pendingForget = note
        } label: {
            AssistantRow(
                title: note.text,
                subtitle: source(note),
                chevron: true,
                first: first,
                titleSize: 15,
                titleWeight: .medium
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .accessibilityHint("Pyta, czy zapomnieć tę notatkę")
    }

    private func source(_ note: AgentMemoryNoteDTO) -> String {
        guard let date = AgentStore.parseTimestamp(note.createdAt) else { return "Z rozmowy" }
        return "Z rozmowy · \(Self.dayFormatter.string(from: date))"
    }

    /// Limit jako cicha metadana; „usuń wszystko” tuż pod nim.
    private var footerMeta: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                CountingNumber(target: store.memory.count)
                Text("z \(Self.memoryLimit) notatek")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(AssistantLook.faint(scheme))
            .frame(maxWidth: .infinity)

            if !store.memory.isEmpty {
                Button {
                    showsForgetAllAlert = true
                } label: {
                    Text("Usuń wszystkie notatki")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AssistantLook.terra(scheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    /// `MemoryEmpty`: znak w szarości, „Na razie nic” i jedno zdanie.
    private var emptyState: some View {
        VStack(spacing: 0) {
            SCMarkShape()
                .fill(AssistantLook.ink(scheme).opacity(0.28))
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            Text("Na razie nic")
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(AssistantLook.ink(scheme))
                .padding(.top, 14)

            Text("Gdy powiesz asystentowi coś trwałego o swoim domu — „w środy jemy u teściów”, „Kuba nie je ryb” — zapisze to tutaj i będzie o tym wiedział w kolejnych rozmowach.")
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(AssistantLook.muted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 36)
        .padding(.bottom, 32)
        .accessibilityElement(children: .combine)
    }
}
