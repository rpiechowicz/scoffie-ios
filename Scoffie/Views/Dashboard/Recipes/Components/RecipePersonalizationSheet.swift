import SwiftUI

// Arkusz „Dopasowanie przepisów” otwierany różdżką obok tytułu na Przepisach.
//
// Zastąpił baner, który siedział nad listą. Baner mieścił jedno zdanie
// i przełącznik, a najważniejszej rzeczy — że dieta i alergeny UKRYWAJĄ,
// a cel tylko PRZESTAWIA KOLEJNOŚĆ — nie dało się w nim powiedzieć.
//
// Arkusz ma cztery bloki i ani jednego więcej: zdanie z zasadą, przełącznik
// z licznikiem, co jest ustawione, gdzie to zmienić. Wszystko, co tłumaczyłoby
// zasadę drugi raz (osobna sekcja „jak to działa”, plakietki stanu przy każdym
// mechanizmie), zostało wycięte — powtarzało lead innymi słowami.
struct RecipePersonalizationSheet: View {
    let personalization: RecipePersonalization

    /// Cały katalog, nie wynik wyszukiwania. Arkusz mówi o ustawieniu
    /// globalnym, więc jego liczby nie mogą skakać, gdy ktoś coś wpisze
    /// w wyszukiwarkę na ekranie pod spodem.
    let catalog: [Recipe]

    let canEvaluateDiet: Bool

    @Binding var isEnabled: Bool

    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Personalizacja z ŻYWYM przełącznikiem. `personalization` to zdjęcie
    /// stanu z chwili otwarcia arkusza, a `hiddenCount(in:)` zaczyna się od
    /// `guard isEnabled` — bez tej podmiany licznik nie zjechałby do zera po
    /// stuknięciu przełącznika tutaj.
    private var effective: RecipePersonalization {
        var copy = personalization
        copy.isEnabled = isEnabled
        return copy
    }

    private var hiddenCount: Int { effective.hiddenCount(in: catalog) }

    var body: some View {
        ZStack {
            SCPageBackground(scheme: scheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    EditorialSheetHeader(
                        eyebrow: "Personalizacja",
                        title: "Dopasowanie przepisów"
                    ) {
                        onClose()
                    }

                    lead
                    switchCard

                    if !personalization.chips.isEmpty {
                        chips
                    }

                    settingsHint
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Zasada

    /// Jedno zdanie, które tłumaczy całość. Musi zostać literałem w `Text(_:)`,
    /// żeby rozwinąć się do `LocalizedStringKey` i pogrubić `**…**` —
    /// wyciągnięte do `let` wypisałoby gwiazdki.
    private var lead: some View {
        Text("Tę listę układają Twoje ustawienia. **Dieta i alergeny ukrywają** dania, których nie zjesz, a **cel tylko przestawia kolejność** — niczego nie chowa.")
            .font(.system(size: 13.5, weight: .regular))
            .foregroundStyle(Color.scMuted(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Przełącznik

    /// Cały wiersz jest przyciskiem — natywny `Toggle` łapałby gest jako drugi
    /// target. Ten sam układ co „Tylko ulubione” w arkuszu filtrów.
    private var switchCard: some View {
        Button {
            withAnimation(.smooth(duration: 0.22)) {
                isEnabled.toggle()
            }
        } label: {
            HStack(spacing: 14) {
                switchIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(isEnabled ? "Dopasowanie włączone" : "Dopasowanie wyłączone")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(Color.scLabel(scheme))

                    Text(statusLine)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RecipeFilterToggleIndicator(isOn: isEnabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isEnabled
                      ? SCPalette.sage.opacity(scheme == .dark ? 0.16 : 0.09)
                      : Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isEnabled
                        ? SCPalette.sage.opacity(scheme == .dark ? 0.30 : 0.42)
                        : Color.scTileStroke(scheme), lineWidth: 1)
        )
        .accessibilityLabel("Dopasowanie przepisów")
        .accessibilityValue(isEnabled ? "Włączone" : "Wyłączone")
        .accessibilityHint(isEnabled
                           ? "Stuknij, aby wyłączyć i zobaczyć cały katalog"
                           : "Stuknij, aby włączyć dopasowanie")
    }

    /// Ta sama różdżka co na przycisku w nagłówku — zmienia się tylko kafelek
    /// pod nią. Podmiana glifu czytałaby się jak inna funkcja.
    @ViewBuilder
    private var switchIcon: some View {
        if isEnabled {
            EditorialSettingsTileIcon(
                icon: "wand.and.stars",
                color: SCPalette.sage,
                size: 38,
                radius: 11
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.scChipBg(scheme))

                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)

                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .frame(width: 38, height: 38)
        }
    }

    /// Jedna linia stanu zamiast osobnego bloku z licznikami. Pierwsze
    /// trafienie wygrywa. Gałąź bez składników jest tu, a nie w osobnej
    /// karcie ostrzegawczej — to ta sama informacja, tylko krócej.
    private var statusLine: String {
        if !isEnabled {
            return "Widzisz cały katalog, także dania spoza Twojej diety."
        }
        if !personalization.hasAnyPreference {
            return "Nie masz nic ustawionego, więc nie ma czego dopasowywać."
        }
        if personalization.restrictsCatalog, !canEvaluateDiet {
            return "Katalog nie przysłał składników, więc dieta i alergeny na razie nic nie odsiewają."
        }
        if personalization.restrictsCatalog, hiddenCount > 0 {
            return "Ukryto \(hiddenCount) z \(catalog.count) \(RecipeCountNoun.label(for: catalog.count))."
        }
        if personalization.restrictsCatalog {
            return "Wszystko w katalogu mieści się w Twoich ustawieniach."
        }
        return "Nic nie znika z listy — zmienia się tylko kolejność."
    }

    // MARK: - Co jest ustawione

    /// Same chipy, bez karty i bez nagłówka sekcji — to podpis pod
    /// przełącznikiem, a nie osobny rozdział.
    private var chips: some View {
        RecipeFilterChipFlow(spacing: 8) {
            ForEach(personalization.chips) { chip in
                PersonalizationChipLabel(chip: chip)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Twoje preferencje")
    }

    /// Świadomie zwykły tekst, nie przycisk — Ustawienia to inna zakładka
    /// `TabView`, a wiersz, który wygląda na klikalny i nic nie robi, jest
    /// gorszy niż zdanie.
    private var settingsHint: some View {
        Text("Dietę, alergeny i cel zmienisz w Ustawieniach → Dieta i alergeny.")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.scFaint(scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Chip preferencji

/// Plakietka preferencji — tylko do czytania. Celowo nie `RecipeFilterChip`,
/// bo tamten jest przyciskiem i wyglądałby na klikalny.
private struct PersonalizationChipLabel: View {
    let chip: RecipePersonalization.Chip

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: chip.icon)
                .font(.system(size: 10.5, weight: .bold))

            Text(chip.title)
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(-0.1)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                // `AllergenChipFlow` mierzy każde dziecko przez
                // `sizeThatFits(.unspecified)`, więc chip zgłasza pełną
                // szerokość jednej linii i wychodziłby poza ekran. Limit na
                // TEKŚCIE (nie na kapsule) zmusza go do zawinięcia.
                .frame(maxWidth: 260, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(chip.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(chip.accent.opacity(scheme == .dark ? 0.20 : 0.12)))
        .overlay(Capsule().stroke(chip.accent.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - Odmiana rzeczownika

/// Polska odmiana „przepis” po liczebniku: 1 → „przepis”, 2–4 (poza 12–14) →
/// „przepisy”, reszta → „przepisów”. Nie prywatne, bo korzysta z tego również
/// plakietka dostępności przycisku w `EditorialRecipesHeader`.
enum RecipeCountNoun {
    static func label(for count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if count == 1 { return "przepis" }
        if (2...4).contains(last), !(12...14).contains(lastTwo) { return "przepisy" }
        return "przepisów"
    }
}
