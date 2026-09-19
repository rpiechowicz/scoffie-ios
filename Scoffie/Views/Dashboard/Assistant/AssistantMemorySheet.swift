import SwiftUI

/// Co asystent pamięta o gospodarstwie.
///
/// Pamięć, o której użytkownik wie tylko stąd, że asystent nagle coś „wie",
/// jest nie do sprawdzenia i nie do cofnięcia. Ten ekran pokazuje ją wprost,
/// w trzech grupach (preferencje, ograniczenia, zwyczaje), i pozwala skasować
/// każdą notatkę z osobna. Limit stoi w stopce jako cicha metadana — nie
/// w nagłówku, bo „6 z 30” nad listą czytało się jak licznik do wypełnienia.
///
/// Notatki są WSPÓLNE dla domu — tak samo jak plan tygodnia i lista zakupów.
struct AssistantMemorySheet: View {
    let store: AgentStore

    /// Tyle notatek trzyma serwer — kontrakt `MEMORY_LIMIT`.
    private static let memoryLimit = 30

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showsForgetAllAlert = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                SCPageBackground(scheme: scheme).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        EditorialSheetHeader(eyebrow: "Asystent", title: "Pamięć domu") {
                            dismiss()
                        }

                        if store.memory.isEmpty && !store.isLoadingMemory {
                            emptyState
                        } else {
                            Text("Notatki z rozmów, których asystent używa przy każdej odpowiedzi. Usuń to, co nieaktualne — nowe dopisuje sam.")
                                .font(.system(size: 13.5))
                                .lineSpacing(2)
                                .foregroundStyle(Color.scMuted(scheme))
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(grouped) { section in
                                groupCard(section)
                            }

                            footerMeta
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refreshMemory() }
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

    private func accent(for group: AgentMemoryGroup) -> Color {
        switch group {
        case .preference: return SCPalette.terracotta
        case .constraint: return SCPalette.indigo
        case .habit: return SCPalette.sage
        }
    }

    private func groupCard(_ section: GroupSection) -> some View {
        AssistantSurfaceCard {
            AssistantSectionLabel(text: section.group.title, color: accent(for: section.group))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

            ForEach(Array(section.notes.enumerated()), id: \.element.id) { index, note in
                noteRow(note, first: index == 0)
            }
        }
    }

    private func noteRow(_ note: AgentMemoryNoteDTO, first: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.text)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let date = AgentStore.parseTimestamp(note.createdAt) {
                    Text("Zapamiętane \(Self.dayFormatter.string(from: date))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.scFaint(scheme))
                }
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.forgetMemory(noteId: note.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.scChipBg(scheme)))
                    .scTapTarget(44, drawn: 28)
            }
            .buttonStyle(PlanPressStyle(scale: 0.9))
            .accessibilityLabel("Zapomnij: \(note.text)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.scRule(scheme)).frame(height: 1).padding(.leading, 16) }
        }
    }

    /// Limit i „usuń wszystko” — u dołu, ściszone.
    private var footerMeta: some View {
        VStack(spacing: 10) {
            Text("\(store.memory.count) z \(Self.memoryLimit) notatek · wspólne dla domu")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
                .frame(maxWidth: .infinity)

            AssistantTextButton(title: "Usuń wszystkie notatki", role: .destructive) {
                showsForgetAllAlert = true
            }
        }
        .padding(.top, 8)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private var emptyState: some View {
        VStack(spacing: 12) {
            AssistantMarkBadge(size: 56)
                .padding(.top, 24)

            Text("Na razie nic")
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(Color.scLabel(scheme))

            Text("Gdy powiesz asystentowi coś trwałego o Waszym domu — „w środy jemy u teściów”, „Kuba nie je ryb” — zapisze to tutaj i będzie o tym wiedział w kolejnych rozmowach.")
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
}
