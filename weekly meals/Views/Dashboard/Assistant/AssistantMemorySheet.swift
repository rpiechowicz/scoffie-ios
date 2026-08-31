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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ZStack {
                Color.wmCanvas(scheme).ignoresSafeArea()

                if store.memory.isEmpty && !store.isLoadingMemory {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Co asystent pamięta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Zamknij") { dismiss() }
                }
            }
        }
        .task {
            await store.refreshMemory()
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(store.memory) { note in
                    Text(note.text)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.wmLabel(scheme))
                        .padding(.vertical, 4)
                        .listRowBackground(Color.wmCanvas(scheme))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await store.forgetMemory(noteId: note.id) }
                            } label: {
                                Label("Zapomnij", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("Asystent zapisuje tu tylko rzeczy trwałe — zwyczaje, niechęci, sprzęt w kuchni. Nie zapisuje planu ani niczego o wadze i zdrowiu.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .textCase(nil)
                    .padding(.bottom, 6)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await store.refreshMemory()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.wmMuted(scheme))

            Text("Na razie nic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.wmLabel(scheme))

            Text("Gdy powiesz asystentowi coś trwałego o swoim domu — „w środy jemy u teściów", „Kuba nie je ryb" — zapisze to tutaj i będzie o tym wiedział w kolejnych rozmowach.")
                .font(.system(size: 14))
                .foregroundStyle(Color.wmMuted(scheme))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
