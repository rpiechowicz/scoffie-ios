import SwiftUI

/// Czego ten domownik nie je — wybór ze składników, nie z klawiatury.
///
/// Wykluczenia trzymamy jako IDENTYFIKATORY, bo walidator planu porównuje je
/// ze składem przepisu. Wpisana z ręki nazwa („pieczarki") nie miałaby jak
/// w ten skład trafić: baza zna „pieczarka", a jutro może znać „pieczarki
/// brązowe". Dlatego to jest lista wyszukiwania, a nie pole tekstowe.
///
/// To NIE są alergeny. Alergen wynika ze składu i dotyczy zdrowia; tu chodzi
/// o zwykłą niechęć. Skutek dla planu jest ten sam — serwer odrzuci posiłek —
/// ale komunikat i miejsce w ustawieniach są osobne, żeby nikt nie wpisał
/// tu uczulenia w przekonaniu, że jest chroniony.
struct ExcludedIngredientsSheet: View {
    @Binding var selected: [BackendIngredientHitDTO]

    @Environment(\.sessionStore) private var sessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @State private var hits: [BackendIngredientHitDTO] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                if !selected.isEmpty {
                    Section("Nie jem") {
                        ForEach(selected) { item in
                            Button {
                                selected.removeAll { $0.id == item.id }
                            } label: {
                                row(item, isSelected: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section(query.isEmpty ? "Wyszukaj składnik" : "Wyniki") {
                    if isSearching {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Szukam…")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.scMuted(scheme))
                        }
                    } else if hits.isEmpty {
                        Text(
                            query.isEmpty
                                ? "Wpisz nazwę, np. „pieczarki”."
                                : "Nic nie pasuje. Spróbuj innego słowa."
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(Color.scMuted(scheme))
                    } else {
                        ForEach(hits) { item in
                            Button {
                                toggle(item)
                            } label: {
                                row(item, isSelected: selected.contains { $0.id == item.id })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Nazwa składnika")
            .navigationTitle("Czego nie jem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
            // Odpytujemy po chwili ciszy, nie po każdej literze: „pieczarki"
            // to osiem zapytań do serwera, z których siedem nikogo nie
            // interesuje.
            .task(id: query) {
                let szukane = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard szukane.count >= 2 else {
                    hits = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearching = true
                defer { isSearching = false }
                hits = await sessionStore.searchIngredients(query: szukane)
            }
        }
    }

    private func toggle(_ item: BackendIngredientHitDTO) {
        if let index = selected.firstIndex(where: { $0.id == item.id }) {
            selected.remove(at: index)
        } else {
            selected.append(item)
        }
    }

    private func row(_ item: BackendIngredientHitDTO, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.scLabel(scheme))
                Text(item.category)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 18))
                .foregroundStyle(isSelected ? SCPalette.terracotta : Color.scFaint(scheme))
        }
        .contentShape(Rectangle())
    }
}
