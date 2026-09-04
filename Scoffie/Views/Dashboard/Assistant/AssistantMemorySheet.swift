import SwiftUI

/// Co asystent pamięta o gospodarstwie.
///
/// Pamięć, o której użytkownik wie tylko stąd, że asystent nagle coś „wie",
/// jest nie do sprawdzenia i nie do cofnięcia. Ten ekran pokazuje ją wprost
/// i pozwala skasować każdą notatkę z osobna.
///
/// Notatki są WSPÓLNE dla domu — tak samo jak plan tygodnia i lista zakupów —
/// więc widzi je każdy domownik.
struct AssistantMemorySheet: View {
    let store: AgentStore

    /// Tyle notatek trzyma serwer — kontrakt `MEMORY_LIMIT`.
    private static let memoryLimit = 30

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showsForgetAllAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.scCanvas(scheme).ignoresSafeArea()

                if store.memory.isEmpty && !store.isLoadingMemory {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Co o Was pamięta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zamknij") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(store.memory.count) z \(Self.memoryLimit)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                }
            }
            .alert("Usunąć wszystkie notatki?", isPresented: $showsForgetAllAlert) {
                Button("Usuń", role: .destructive) {
                    Task { await store.forgetAllMemory() }
                }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Nieodwracalne. Plan tygodnia i przepisy zostają; rozmowy kasujesz osobno w menu asystenta.")
            }
        }
        .task {
            await store.refreshMemory()
        }
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

    private var list: some View {
        List {
            Section {
                Text("Notatki z rozmów, których asystent używa przy każdej odpowiedzi. Usuń to, co nieaktualne — nowe dopisuje sam, do \(Self.memoryLimit).")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scMuted(scheme))
                    .listRowBackground(Color.scCanvas(scheme))
            }

            ForEach(grouped) { section in
                Section(section.group.title) {
                    ForEach(section.notes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.text)
                                .font(.system(size: 15))
                                .foregroundStyle(Color.scLabel(scheme))
                            if let date = AgentStore.parseTimestamp(note.createdAt) {
                                Text("Zapamiętane \(Self.dayFormatter.string(from: date))")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.scFaint(scheme))
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.scCanvas(scheme))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await store.forgetMemory(noteId: note.id) }
                            } label: {
                                Label("Zapomnij", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showsForgetAllAlert = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "trash")
                        Text("Usuń wszystkie notatki")
                            .font(.system(size: 14.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.scCanvas(scheme))
            } footer: {
                Text("Nieodwracalne · plan i przepisy zostają")
                    .font(.system(size: 11.5))
                    .frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refreshMemory()
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.scMuted(scheme))

            Text("Na razie nic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))

            Text("Gdy powiesz asystentowi coś trwałego o swoim domu — „w środy jemy u teściów”, „Kuba nie je ryb” — zapisze to tutaj i będzie o tym wiedział w kolejnych rozmowach.")
                .font(.system(size: 14))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
