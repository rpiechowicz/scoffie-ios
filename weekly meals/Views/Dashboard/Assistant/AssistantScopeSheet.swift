import SwiftUI

/// Wybór, kogo dotyczy pytanie.
///
/// Zakres można powiedzieć słowami („zaplanuj tylko dla mnie i Ani”), ale
/// wtedy model musi dopasować imiona do wierszy w bazie i czasem trafia obok.
/// Wybór na liście daje mu gotowe identyfikatory, więc uczestnicy posiłków
/// w propozycji są poprawni bez zgadywania.
struct AssistantScopeSheet: View {
    let members: [HouseholdMemberSnapshot]
    @Binding var selection: Set<String>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selection.removeAll()
                    } label: {
                        row(
                            title: "Cały dom",
                            subtitle: "\(members.count) \(Self.peopleWord(members.count))",
                            isSelected: selection.isEmpty
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section("Tylko wybrane osoby") {
                    ForEach(members) { member in
                        Button {
                            toggle(member.id)
                        } label: {
                            row(
                                title: member.displayName,
                                subtitle: nil,
                                isSelected: selection.contains(member.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Dla kogo?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
        // Wybranie wszystkich to to samo, co „cały dom” — trzymanie tego jako
        // listy czterech identyfikatorów kazałoby modelowi udowadniać, że
        // nikogo nie pominął.
        if selection.count == members.count { selection.removeAll() }
    }

    private func row(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.wmLabel(scheme))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(scheme))
                }
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WMPalette.terracotta)
            }
        }
        .contentShape(Rectangle())
    }

    static func peopleWord(_ count: Int) -> String {
        if count == 1 { return "osoba" }
        let mod100 = count % 100
        if (12...14).contains(mod100) { return "osób" }
        return (2...4).contains(count % 10) ? "osoby" : "osób"
    }
}
