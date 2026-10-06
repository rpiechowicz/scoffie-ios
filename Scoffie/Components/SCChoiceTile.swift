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
    /// Miniatura W KARCIE (nie na całą wysokość — Rafał 27.09.2026: „jako
    /// card było zdecydowanie lepsze”), tak duża, żeby odstęp od góry, dołu
    /// i lewej był ten sam: (70 − 54) / 2 = 8 = `leading`.
    static let media: CGFloat = 54
    static let mediaRadius: CGFloat = 14
    /// Odstęp miniatury od lewej krawędzi — równy odstępowi od góry i dołu.
    static let leading: CGFloat = 8
    /// Jedna czcionka nazwy we WSZYSTKICH kafelkach — bez zmniejszania długich
    /// słów („Wysokobiałkowe” było mniejsze od „Mało soli”, Rafał: „wszystko
    /// takie samo, nie może się to różnić”).
    static let titleSize: CGFloat = 14
    /// JEDNA wysokość dla każdego kafelka w każdej siatce — mieści dwie linie
    /// nazwy i dopowiedzenie. Wcześniej wysokość brała się z treści i siatka
    /// z jedną dwuwierszową nazwą („Ryby i owoce morza”) była wyższa od
    /// sąsiedniej (27.09.2026, Rafał: „znów się rozpycha 2-liniowe title od
    /// 1-liniowego… zrób takie wszystkie, by było jednakowo”).
    static let height: CGFloat = 70
    static let badge: CGFloat = 18
    /// Wcięcie treści z prawej.
    static let inset: CGFloat = 10
    /// Od miniatury do nazwy — mieści znaczek wystający 6 pt z miniatury.
    static let mediaGap: CGFloat = 11
}

/// Kafelek wyboru w siatce 2 × N: miniatura z lewej, obok nazwa i pod nią
/// jedna linijka dopowiedzenia (w filtrach — ile przepisów zostanie po
/// zaznaczeniu).
///
/// Nazwa stoi OBOK miniatury, w jednej linii z nią. Wersja z nazwą pod
/// miniaturą (23.09) wyrównywała krój, ale każdy kafelek zrobił się
/// dwupiętrowy i siatka urosła dwukrotnie — Rafał, 24.09.2026: „podobało mi
/// się bardziej, jak jest w 1 linii”. Długie jedno słowo („Niskotłuszczowe”)
/// zostaje w jednej linii i lekko maleje, kilka słów schodzi do drugiej.
/// Każdy kafelek ma tę samą wysokość (`SCChoiceTileMetrics.height`, 70 pt)
/// z miniaturą 46 pt, więc dwuwierszowa nazwa niczego nie rozpycha, a siatki
/// w różnych arkuszach mają ten sam rytm. Siatka (`RecipeFilterTileGrid`)
/// dalej wyrównuje do najwyższego — przy dużym Dynamic Type.
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
    /// Treść miniatury — kafelek przycina ją do zaokrąglonego kwadratu 46 pt.
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

    /// Długie pojedyncze słowo dostaje miękkie dzielenie (U+00AD) — łamie się
    /// z dywizem („Wysoko-/białkowe”) zamiast maleć albo pękać w przypadkowym
    /// miejscu. Najpierw znane przedrostki, potem granica sylaby w połowie.
    static func hyphenated(_ title: String) -> String {
        title.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let text = String(word)
            guard text.count > 10 else { return text }
            let lower = text.lowercased()
            for prefix in ["wysoko", "nisko", "bez", "wege", "pesce", "mało", "pełno", "dużo"]
            where lower.hasPrefix(prefix) && text.count - prefix.count >= 4 {
                let index = text.index(text.startIndex, offsetBy: prefix.count)
                return String(text[..<index]) + "\u{00AD}" + String(text[index...])
            }
            let vowels = Set("aąeęioóuy")
            let characters = Array(text)
            var cut = characters.count / 2
            while cut < characters.count - 3, !vowels.contains(Character(characters[cut - 1].lowercased())) {
                cut += 1
            }
            return String(characters[..<cut]) + "\u{00AD}" + String(characters[cut...])
        }
        .joined(separator: " ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SCChoiceTileMetrics.mediaGap) {
                mediaView

                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.hyphenated(title))
                        .font(.sc(size: SCChoiceTileMetrics.titleSize, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    detail()
                        .font(.sc(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .padding(.leading, SCChoiceTileMetrics.leading)
            .padding(.trailing, SCChoiceTileMetrics.inset)
            // Elastyczny w obu osiach: siatka daje każdemu kafelkowi tę samą
            // szerokość kolumny i wysokość najwyższego kafelka w siatce.
            .frame(maxWidth: .infinity, minHeight: SCChoiceTileMetrics.height, maxHeight: .infinity, alignment: .leading)
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

    /// Miniatura w karcie — kwadrat 54 pt z odstępem 8 pt od lewej, góry
    /// i dołu. Zaznaczony: obwódka akcentu wokół miniatury i znaczek na rogu.
    private var mediaView: some View {
        let size = SCChoiceTileMetrics.media
        let radius = SCChoiceTileMetrics.mediaRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        // Stała ramka: siatka mierzy kafelek bez wysokości, a `scaledToFill`
        // zgłosiłby naturalną wysokość zdjęcia.
        return media()
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
            .overlay {
                RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                    .strokeBorder(accent, lineWidth: 1.5)
                    .padding(-3)
                    .opacity(mark == .on ? 1 : 0)
                    .scaleEffect(mark == .on ? 1 : 0.92)
            }
            .overlay(alignment: .bottomTrailing) {
                badge
                    .offset(x: 5, y: 5)
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
                        .font(.sc(size: mark == .locked ? 8.5 : 9.5, weight: .heavy))
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
