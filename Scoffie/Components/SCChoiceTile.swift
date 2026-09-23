import SwiftUI

/// Stan kafelka wyboru. Osobny typ, a nie zagnieżdżony w `SCChoiceTile`:
/// typ zagnieżdżony w typie generycznym jest sam generyczny, więc
/// `SCChoiceTile<Text, Text>.Mark` i `SCChoiceTile<Image, Group<…>>.Mark`
/// byłyby dla kompilatora dwoma różnymi wyliczeniami.
enum SCChoiceMark: Equatable {
    case off
    case on
    /// Przyszło z profilu — kłódka w szałwii, stuknięcie nic nie robi.
    case locked
}

/// Wymiary kafelka — poza typem generycznym, który nie może mieć stałych
/// statycznych.
private enum SCChoiceTileMetrics {
    static let media: CGFloat = 38
    static let mediaRadius: CGFloat = 11
    static let badge: CGFloat = 18
}

/// Kafelek wyboru w siatce 2 × N: miniatura, nazwa, pod nią jedna linijka
/// dopowiedzenia (w filtrach — ile przepisów zostanie po zaznaczeniu).
///
/// Miniatura to zwykle zdjęcie dania z tą cechą („Z rybą” — dorsz, „Zupy” —
/// zupa), a bez zdjęcia glif w tincie akcentu. Pierwsza wersja miała w tym
/// miejscu samo pole wyboru i szary kafelek: dwanaście takich pod rząd
/// czytało się jak formularz („wygląda to trochę smutno” — Rafał, 23.09.2026).
///
/// Zaznaczenie mówi trzy rzeczy naraz, żeby nie zależało od samego koloru:
/// tint kafelka z obwódką akcentu, obwódka wokół miniatury i znaczek
/// z ptaszkiem na jej rogu. Kafelek z profilu — tint szałwii i kłódka.
struct SCChoiceTile<Media: View, Detail: View>: View {
    let title: String
    let mark: SCChoiceMark
    var accent: Color = SCPalette.terracotta
    /// Kafelek, który nic by nie dał (np. zero wyników) — gaśnie, ale zostaje
    /// na miejscu, żeby siatka nie przeskakiwała przy stuknięciu obok.
    var isDimmed: Bool = false
    /// Co VoiceOver czyta po nazwie. Dopowiedzenie z ekranu tu nie trafia
    /// samo, bo kafelek jest jednym elementem (`children: .ignore`).
    var accessibilityValue: String? = nil
    let action: () -> Void
    /// Treść miniatury — kafelek przycina ją do zaokrąglonego kwadratu 38 pt.
    @ViewBuilder var media: () -> Media
    @ViewBuilder var detail: () -> Detail

    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    private var fill: Color {
        switch mark {
        case .on:     return accent.opacity(scheme == .dark ? 0.12 : 0.09)
        case .locked: return SCPalette.sage.opacity(scheme == .dark ? 0.12 : 0.09)
        case .off:    return Color.scTileBg(scheme)
        }
    }

    private var stroke: Color {
        switch mark {
        case .on:     return accent.opacity(0.45)
        case .locked: return .clear
        case .off:    return Color.scTileStroke(scheme)
        }
    }

    /// Jedno słowo („Niskotłuszczowe”) nie zawinie się ładnie — złamałoby
    /// się w pół wyrazu. Zostaje w jednej linii i najwyżej lekko maleje.
    /// Kilka słów („Ryby i owoce morza”) schodzi do drugiej linii.
    private var titleLines: Int { title.contains(" ") ? 2 : 1 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                mediaView

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .tracking(-0.25)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(titleLines)
                        .minimumScaleFactor(0.8)

                    detail()
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 9)
            // Elastyczny w pionie: w `Grid` sąsiad z nazwą w dwóch liniach
            // wyznacza wysokość wiersza, a ten kafelek się do niej rozciąga.
            .frame(maxWidth: .infinity, minHeight: 58, maxHeight: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: mark == .on ? 1.2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
        .disabled(mark == .locked || isDimmed)
        .opacity(isDimmed ? 0.4 : 1)
        .animation(.smooth(duration: 0.2), value: mark)
        .animation(.smooth(duration: 0.18), value: isDimmed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(accessibilityValue ?? ""))
        .accessibilityAddTraits(mark == .off ? .isButton : [.isButton, .isSelected])
    }

    private var mediaView: some View {
        let size = SCChoiceTileMetrics.media
        let radius = SCChoiceTileMetrics.mediaRadius

        return media()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.scTileStroke(scheme), lineWidth: 1)
            )
            // Zaznaczony: obwódka akcentu 2 pt od miniatury.
            .overlay {
                RoundedRectangle(cornerRadius: radius + 3.5, style: .continuous)
                    .strokeBorder(accent, lineWidth: 1.5)
                    .padding(-3.5)
                    .opacity(mark == .on ? 1 : 0)
                    .scaleEffect(mark == .on ? 1 : 0.92)
            }
            .overlay(alignment: .bottomTrailing) {
                badge
                    .offset(x: 6, y: 6)
            }
    }

    @ViewBuilder
    private var badge: some View {
        if mark != .off {
            let size = SCChoiceTileMetrics.badge
            Circle()
                .fill(mark == .locked ? SCPalette.sage : accent)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: mark == .locked ? "lock.fill" : "checkmark")
                        .font(.system(size: mark == .locked ? 8.5 : 9.5, weight: .heavy))
                        // Akcenty w ciemnym motywie są jasne (masło, szałwia) —
                        // biały glif ginął na nich. Ciemny czyta się na każdym.
                        .foregroundStyle(scheme == .dark ? Color.scPageBase(scheme) : Color.white)
                )
                // Wycięcie w kolorze tła odkleja znaczek od zdjęcia.
                .overlay(
                    Circle()
                        .strokeBorder(Color.scPageBase(scheme), lineWidth: 2)
                        .padding(-2)
                )
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }
}
