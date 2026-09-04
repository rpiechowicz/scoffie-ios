import SwiftUI

/// Co asystent wie o gospodarstwie — dane pod pusty stan zakładki.
///
/// Widok nie sięga po store'y sam: dostaje policzone fakty, żeby dało się go
/// obejrzeć w podglądzie i żeby liczenie („ile z ilu posiłków”) żyło w jednym
/// miejscu, a nie w środku layoutu.
struct AssistantKnowledge: Equatable {
    struct Member: Equatable, Identifiable {
        let id: String
        let name: String
        let calorieGoal: Int?
        /// Dieta i alergeny sklejone w jedno zdanie („bez laktozy”, „wegetariańska”).
        let restrictions: String?
    }

    var weekLabel: String
    var plannedMeals: Int
    var totalMealSlots: Int
    var calorieGoal: Int
    var proteinTargetG: Int?
    var recipeCount: Int
    var favouriteCount: Int
    var members: [Member]

    var isWeekEmpty: Bool { plannedMeals == 0 }

    /// Zdanie pod hero: konkret zamiast zachęty. Wymienia to, co naprawdę
    /// zawęzi propozycję — cel i pierwsze ograniczenie w domu.
    var heroSubtitle: String {
        var parts: [String] = []
        if recipeCount > 0 {
            parts.append("Ułożę obiady i kolacje z Waszych \(recipeCount) przepisów")
        } else {
            parts.append("Ułożę obiady i kolacje z Waszego katalogu")
        }
        parts.append("pod cel \(calorieGoal) kcal")
        if let restriction = members.compactMap(\.restrictions).first {
            parts.append("i z ograniczeniem: \(restriction.lowercased())")
        }
        return parts.joined(separator: " ") + "."
    }
}

/// Pusty ekran asystenta.
///
/// Makieta wychodzi z założenia, że pusty tydzień to nie pytanie „o co zapytać”,
/// tylko zadanie do wykonania — stąd jedna propozycja wynikająca ze STANU planu
/// zamiast trzech ogólnych podpowiedzi.
struct AssistantEmptyState: View {
    let knowledge: AssistantKnowledge
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isKnowledgeExpanded = false

    var body: some View {
        // Projekt „Asystent Zgoda" (3.09.2026): pusta rozmowa to jeden
        // wyśrodkowany kafel i zdanie, a cztery szybkie starty siedzą nad
        // chipami zakresu przy polu — nie w treści. Karta „Co wiem o Was"
        // i skróty zostają w kodzie na wypadek powrotu, ale nie renderują się.
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.scAccentTint(scheme))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(SCPalette.terracotta)
                )
            VStack(spacing: 4) {
                Text("Co dziś planujemy?")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.45)
                    .foregroundStyle(Color.scLabel(scheme))
                Text("Zacznij od jednego z poleceń nad polem albo napisz własne. Zakres ustawisz chipami nad polem.")
                    .font(.system(size: 14))
                    .tracking(-0.15)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(maxWidth: 270)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Zacznijmy od tego")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                }
                .foregroundStyle(SCPalette.terracotta)

                Text(heroTitle)
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.45)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text(knowledge.heroSubtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 14)

            Button { onAsk(heroPrompt) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                    Text(heroAction)
                        .font(.system(size: 15.5, weight: .bold))
                        .tracking(-0.3)
                }
                .foregroundStyle(Color.scPageBase(scheme))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(SCPalette.terracotta))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.scAccentTint(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(SCPalette.terracotta.opacity(0.26), lineWidth: 1)
        )
    }

    private var heroTitle: String {
        if knowledge.isWeekEmpty {
            return "Plan na \(knowledge.weekLabel) jest pusty"
        }
        return "W planie na \(knowledge.weekLabel) jest \(knowledge.plannedMeals) z \(knowledge.totalMealSlots) posiłków"
    }

    private var heroAction: String {
        knowledge.isWeekEmpty ? "Ułóż mi cały tydzień" : "Uzupełnij brakujące posiłki"
    }

    private var heroPrompt: String {
        knowledge.isWeekEmpty
            ? "Zaplanuj mi obiady i kolacje na ten tydzień"
            : "Uzupełnij brakujące posiłki w tym tygodniu"
    }

    // MARK: - Skróty

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Albo szybciej")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Color.scFaint(scheme))
                .padding(.leading, 2)

            // Trzy skróty, które asystent UMIE dziś wykonać. Makieta ma w tym
            // miejscu zdjęcie lodówki — wchodzi dopiero z załącznikami, a skrót
            // do funkcji, której nie ma, byłby obietnicą bez pokrycia.
            row(
                icon: "clock",
                color: SCPalette.indigo,
                title: "Co zjeść jutro, mam 15 minut",
                meta: "Z Waszych przepisów",
                prompt: "Co mogę zjeść jutro, jeśli mam 15 minut na przygotowanie?"
            )
            row(
                icon: "chart.line.uptrend.xyaxis",
                color: SCPalette.sage,
                title: "Czego brakuje, żeby wyrobić się z białkiem",
                meta: "Analiza tygodnia",
                prompt: "Czego brakuje w planie, żeby wyrobić się z białkiem?"
            )
            row(
                icon: "arrow.triangle.2.circlepath",
                color: SCPalette.butter,
                title: "Podmień jedno danie w tym tygodniu",
                meta: "Zmiana w planie",
                prompt: "Podmień jedno danie w tym tygodniu na coś szybszego"
            )
        }
    }

    private func row(
        icon: String,
        color: Color,
        title: String,
        meta: String,
        prompt: String
    ) -> some View {
        Button { onAsk(prompt) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(color.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.25)
                        .foregroundStyle(Color.scLabel(scheme))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(meta)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.scFaint(scheme))
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.scTileBg(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.scTileStroke(scheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Co wiem o Was

    private var knowledgeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.22)) { isKnowledgeExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.scMuted(scheme))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Co wiem o Was")
                            .font(.system(size: 13.5, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.scLabel(scheme))

                        if !isKnowledgeExpanded {
                            Text(summaryLine)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.scFaint(scheme))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isKnowledgeExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.scFaint(scheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            if isKnowledgeExpanded {
                VStack(spacing: 0) {
                    factRow(icon: "target", color: SCPalette.terracotta, key: "Twój cel", value: goalValue)
                    factRow(
                        icon: "person.2",
                        color: SCPalette.indigo,
                        key: "Domownicy",
                        value: membersValue
                    )
                    if let restrictions = restrictionsValue {
                        factRow(icon: "leaf", color: SCPalette.sage, key: "Ograniczenia", value: restrictions)
                    }
                    factRow(
                        icon: "calendar",
                        color: SCPalette.butter,
                        key: "Plan \(knowledge.weekLabel)",
                        value: "\(knowledge.plannedMeals) z \(knowledge.totalMealSlots) posiłków"
                    )
                    factRow(
                        icon: "book",
                        color: SCPalette.terracotta,
                        key: "Wasze przepisy",
                        value: "\(knowledge.recipeCount) w katalogu, \(knowledge.favouriteCount) ulubionych"
                    )
                }
                .padding(.bottom, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.scInsetSurface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private func factRow(icon: String, color: Color, key: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)

            Text(key)
                .font(.system(size: 12))
                .foregroundStyle(Color.scMuted(scheme))
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.scRule(scheme)).frame(height: 1)
        }
    }

    private var summaryLine: String {
        var parts = ["Cel \(knowledge.calorieGoal) kcal"]
        if !knowledge.members.isEmpty {
            parts.append(
                "\(knowledge.members.count) " + PolishPlural.form(
                    knowledge.members.count,
                    one: "domownik",
                    few: "domownicy",
                    many: "domowników"
                )
            )
        }
        if knowledge.recipeCount > 0 {
            parts.append("\(knowledge.recipeCount) przepisów")
        }
        return parts.joined(separator: " · ")
    }

    private var goalValue: String {
        guard let protein = knowledge.proteinTargetG else {
            return "\(knowledge.calorieGoal) kcal"
        }
        return "\(knowledge.calorieGoal) kcal · \(protein) g białka"
    }

    private var membersValue: String {
        guard !knowledge.members.isEmpty else { return "Tylko Ty" }
        return knowledge.members
            .map { member in
                guard let goal = member.calorieGoal else { return member.name }
                return "\(member.name) \(goal)"
            }
            .joined(separator: " · ")
    }

    private var restrictionsValue: String? {
        let described = knowledge.members.compactMap { member -> String? in
            guard let restrictions = member.restrictions else { return nil }
            return "\(member.name) — \(restrictions)"
        }
        return described.isEmpty ? nil : described.joined(separator: ", ")
    }
}
