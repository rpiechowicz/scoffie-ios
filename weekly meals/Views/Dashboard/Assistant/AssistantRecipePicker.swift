import SwiftUI

/// Wskazanie przepisu, o który chodzi.
///
/// Nazwę dania można wpisać ręcznie, ale asystent musi ją wtedy odnaleźć
/// w katalogu — a „placki” pasują do czterech przepisów naraz. Wybór z listy
/// wkleja pełny, jednoznaczny tytuł, więc pytanie zaczyna się od zgody co do
/// tego, o czym rozmawiamy.
///
/// Świadomie wkleja TEKST do pola, a nie „załącznik”: zdanie z tytułem czyta
/// się tak samo w rozmowie jak wszystko inne, a użytkownik może je jeszcze
/// dopisać albo poprawić przed wysłaniem.
struct AssistantRecipePicker: View {
    let recipes: [Recipe]
    let onPick: (Recipe) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var matches: [Recipe] {
        let needle = Self.fold(query)
        guard !needle.isEmpty else { return recipes }
        return recipes.filter { Self.fold($0.name).contains(needle) }
    }

    var body: some View {
        NavigationStack {
            List(matches, id: \.id) { recipe in
                Button {
                    onPick(recipe)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recipe.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.wmLabel(scheme))
                            .multilineTextAlignment(.leading)
                        if recipe.prepTimeMinutes > 0 {
                            Text("\(recipe.prepTimeMinutes) min")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.wmMuted(scheme))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Szukaj przepisu")
            .navigationTitle("Który przepis?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
            }
            .overlay {
                if matches.isEmpty {
                    ContentUnavailableView(
                        "Nic nie pasuje",
                        systemImage: "magnifyingglass",
                        description: Text("Spróbuj innego słowa albo opisz danie asystentowi własnymi słowami.")
                    )
                }
            }
        }
    }

    /// Porównanie bez znaków diakrytycznych i wielkości liter: „zurek”
    /// ma znaleźć „Żurek”.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
