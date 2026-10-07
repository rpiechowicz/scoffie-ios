import SwiftUI

/// Ustawienia → Powiadomienia: na górze arkusza podgląd powiadomienia, tak
/// jak przyjdzie na ekran blokady (6.10.2026 — Rafał: „ciut ładniejsze”).
///
/// Zamiast opisywać kanał słowami — pokazuje go. Stuknięcie w wiersz kanału
/// albo jego włączenie podmienia podgląd (tytuł i treść rolują się,
/// `SCMotion.textRoll`); przy wyciszonych powiadomieniach podgląd gaśnie
/// i mówi „Wyciszone”. Treści są przykładowe, ale w tonie prawdziwych
/// (`MealReminderService`), żeby podgląd nie obiecywał czegoś, czego
/// aplikacja nie wysyła.
struct NotificationPreviewCard: View {
    enum Kind: String, CaseIterable {
        case morning, meals, dayWrapUp, plan, shopping

        var title: String {
            switch self {
            case .morning:   return "Dzień dobry"
            case .meals:     return "Za 40 minut obiad"
            case .dayWrapUp: return "Jutro w planie"
            case .plan:      return "Ania zmieniła plan"
            case .shopping:  return "Zakupy zrobione"
            }
        }

        var body: String {
            switch self {
            case .morning:   return "Dziś 3 posiłki i 1850 kcal. Na start o 8:00: owsianka z malinami."
            case .meals:     return "Kurczak curry z ryżem — czas zacząć gotować."
            case .dayWrapUp: return "Śniadanie, obiad i kolacja czekają. Lista zakupów gotowa."
            case .plan:      return "Środa: nowy obiad — leczo z cukinią."
            case .shopping:  return "Marek odhaczył 12 produktów z listy."
            }
        }

        /// Kolor kanału — ten sam co kafelek jego wiersza.
        var accent: Color {
            switch self {
            case .morning:   return SCPalette.butter
            case .meals:     return SCPalette.sage
            case .dayWrapUp: return SCPalette.indigo
            case .plan:      return SCPalette.terracotta
            case .shopping:  return SCPalette.teal
            }
        }
    }

    let kind: Kind
    /// Czy powiadomienia w ogóle dojdą (zgoda systemu + główny przełącznik
    /// + kanał). Inaczej podgląd gaśnie.
    let isActive: Bool

    @Environment(\.colorScheme) private var scheme

    private static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SCScoffieMark(size: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .saturation(isActive ? 1 : 0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("SCOFFIE")
                        .font(.sc(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.scMuted(scheme))

                    Spacer(minLength: 0)

                    Text(isActive ? "teraz" : "Wyciszone")
                        .font(.sc(size: 12, weight: .medium))
                        .foregroundStyle(isActive ? Color.scFaint(scheme) : SCPalette.terracotta)
                        .contentTransition(.numericText())
                }

                Text(kind.title)
                    .font(.sc(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .contentTransition(.numericText())

                Text(kind.body)
                    .font(.sc(size: 14))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            ZStack {
                Self.shape.fill(Color.scTileBg(scheme))
                // Delikatna poświata w kolorze kanału z lewego górnego rogu —
                // kolor płynie przy zmianie kanału.
                Self.shape.fill(
                    RadialGradient(
                        colors: [kind.accent.opacity(isActive ? (scheme == .dark ? 0.22 : 0.16) : 0), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
            }
        }
        .overlay(Self.shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
        .opacity(isActive ? 1 : 0.6)
        .animation(SCMotion.textRoll, value: kind)
        .animation(SCMotion.textRoll, value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isActive
                ? "Przykładowe powiadomienie: \(kind.title). \(kind.body)"
                : "Powiadomienia wyciszone"
        )
    }
}
