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
    /// Wcięcie treści ze wszystkich stron.
    static let inset: CGFloat = 10
    /// Od miniatury do nazwy — mieści znaczek wystający 8 pt pod miniaturę.
    static let mediaGap: CGFloat = 10
}

/// Kafelek wyboru w siatce 2 × N: miniatura u góry, pod nią nazwa i jedna
/// linijka dopowiedzenia (w filtrach — ile przepisów zostanie po zaznaczeniu).
///
/// Nazwa stoi POD miniaturą, na całej szerokości kafelka, a nie obok niej.
/// Obok miniatury zostawało na tekst 96 pt (iPhone 375 pt), a
/// „Niskotłuszczowe” i „Wysokobiałkowe” w 14,5 pt semibold mają ~118 pt —
/// malały do 80 % i stały mniejszym krojem niż „Mało soli”, a „Bogate
/// w błonnik” schodziło do drugiej linii i podnosiło swój rząd (Rafał,
/// 23.09.2026: „nie są wszystkie takiej samej wielkości”). Pod miniaturą jest
/// 143 pt przy 375 i 152 przy 393, więc każda nazwa filtrów i aspektów
/// kategorii (najdłuższa „Makaron, ryż, kasze”, ~138 pt) mieści się w jednej
/// linii jednym krojem. Wysokość kafelków wyrównuje siatka
/// (`RecipeFilterTileGrid`): każdy dostaje wysokość najwyższego w CAŁEJ siatce.
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

    /// Kilka słów („Ryby i owoce morza”) może zejść do drugiej linii — łamie
    /// się tylko na spacji, bo każdy wyraz z osobna ma najwyżej ~86 pt.
    /// Jedno słowo zostaje w jednej linii: w dwóch złamałoby się w pół wyrazu.
    private var isSingleWord: Bool { !title.contains(" ") }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                mediaView
                    .padding(.bottom, SCChoiceTileMetrics.mediaGap)

                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .tracking(-0.25)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(isSingleWord ? 1 : 2)
                    // Bezpiecznik na ekran 320 pt (iPhone z powiększonym
                    // ekranem): tam jedno długie słowo zmaleje o włos, zamiast
                    // złamać się w pół. Od 375 pt nie działa — wszystkie nazwy
                    // stoją tym samym krojem 14,5 pt.
                    .minimumScaleFactor(isSingleWord ? 0.9 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Kafelek wyższy od swojej treści (sąsiad z nazwą w dwóch
                // liniach) oddaje nadmiar TU: miniatura i nazwa trzymają górę,
                // liczba przepisów — dół, w jednej linii na każdym kafelku.
                Spacer(minLength: 2)

                detail()
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(SCChoiceTileMetrics.inset)
            // Elastyczny w obu osiach: siatka daje każdemu kafelkowi tę samą
            // szerokość kolumny i wysokość najwyższego kafelka w siatce.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
