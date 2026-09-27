import SwiftUI

/// Odpowiedź asystenta rozłożona na kawałki, które da się pokazać jak
/// interfejs, a nie jak zrzut tekstu.
///
/// Model pisze markdownem, a `Text` markdownu blokowego nie rozumie — na
/// ekranie lądowały dosłowne gwiazdki („\*\*Obiady (LUNCH):\*\*") i ściana
/// myślników. Tu ten sam tekst zamienia się w nagłówki sekcji i wiersze dni,
/// które renderują się jak reszta aplikacji.
///
/// Każdy kawałek zna swój zakres w SUROWYM tekście (`raw`, w znakach) — po nim
/// odpowiedź, która jeszcze się pisze, wie, ile z danego kawałka już widać
/// (`AssistantAnswer(revealed:)`).
enum AssistantBlock {
    case heading(String, raw: Range<Int>)
    case paragraph(String, raw: Range<Int>)
    case list([AssistantListItem])

    /// Zakres całego kawałka w surowym tekście.
    var raw: Range<Int> {
        switch self {
        case let .heading(_, raw), let .paragraph(_, raw): return raw
        case let .list(items):
            let start = items.first?.raw.lowerBound ?? 0
            return start..<(items.last?.raw.upperBound ?? start)
        }
    }
}

struct AssistantListItem {
    /// Skrót dnia („PN"), gdy pozycja zaczyna się od dnia tygodnia.
    let day: String?
    /// Numer z listy numerowanej („1."). Kroki przepisu bez numeru przestają
    /// być krokami — zostaje z nich zbiór czynności w przypadkowej kolejności.
    let ordinal: Int?
    /// Poziom wcięcia (0 = najwyższy). Liczony PRZED przycięciem linii, bo po
    /// nim cała hierarchia odpowiedzi znika.
    let depth: Int
    let text: String
    /// Zakres pozycji w surowym tekście.
    var raw: Range<Int> = 0..<0
}

enum AssistantAnswerParser {
    /// Kolejne linie tekstu to JEDEN akapit (łamanie wiersza w środku), pusta
    /// linia go zamyka. Do 27.09.2026 każda linia była osobnym blokiem
    /// z tym samym odstępem 14 pt, co prawdziwy akapit — przerwa między
    /// akapitami nie różniła się od złamania linii i odpowiedź czytała się
    /// jak ściśnięty słup zdań.
    static func blocks(from raw: String) -> [AssistantBlock] {
        var blocks: [AssistantBlock] = []
        var pending: [AssistantListItem] = []
        var paragraph: [String] = []
        var paragraphRaw: Range<Int>?

        func flushList() {
            guard !pending.isEmpty else { return }
            blocks.append(.list(pending))
            pending = []
        }

        func flushParagraph() {
            guard !paragraph.isEmpty, let range = paragraphRaw else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n"), raw: range))
            paragraph = []
            paragraphRaw = nil
        }

        var offset = 0
        for line in raw.components(separatedBy: "\n") {
            let range = offset..<(offset + line.count)
            // `components(separatedBy:)` zjada znak nowej linii — liczymy go.
            offset += line.count + 1

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushList()
                flushParagraph()
                continue
            }

            // Wcięcie liczymy z SUROWEJ linii — po przycięciu podpunkt
            // („  - bez laktozy") wygląda identycznie jak pozycja nadrzędna.
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            if var item = listItem(from: trimmed, depth: min(indent / 2, 3)) {
                flushParagraph()
                item.raw = range
                pending.append(item)
                continue
            }

            flushList()
            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(heading, raw: range))
            } else {
                paragraph.append(clean(trimmed))
                paragraphRaw = (paragraphRaw?.lowerBound ?? range.lowerBound)..<range.upperBound
            }
        }

        flushList()
        flushParagraph()
        return blocks
    }

    // MARK: - Rozpoznawanie

    private static func heading(from line: String) -> String? {
        if line.hasPrefix("#") {
            let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : clean(text)
        }
        if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
            return clean(String(line.dropFirst(2).dropLast(2)))
        }
        // Krótka linia zakończona dwukropkiem to w praktyce nagłówek sekcji
        // („Obiady:"). Długa nie — to zdanie wprowadzające listę.
        if line.hasSuffix(":"), line.count <= 40 {
            return clean(String(line.dropLast()))
        }
        return nil
    }

    private static func listItem(from line: String, depth: Int) -> AssistantListItem? {
        guard let parsed = listContent(of: line) else { return nil }
        guard let (day, rest) = splitDay(parsed.content) else {
            return AssistantListItem(
                day: nil,
                ordinal: parsed.ordinal,
                depth: depth,
                text: clean(parsed.content)
            )
        }
        return AssistantListItem(
            day: day,
            ordinal: parsed.ordinal,
            depth: depth,
            text: clean(rest)
        )
    }

    private static func listContent(
        of line: String
    ) -> (content: String, ordinal: Int?)? {
        for marker in ["- ", "– ", "— ", "* ", "• "] where line.hasPrefix(marker) {
            return (String(line.dropFirst(marker.count)), nil)
        }
        // „1. Coś tam" — numerowana lista. Numer zostaje: to on niesie
        // kolejność kroków przepisu.
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2, parts[0].count <= 3,
           let last = parts[0].last, last == "." || last == ")",
           parts[0].dropLast().allSatisfy({ $0.isNumber }),
           let ordinal = Int(parts[0].dropLast()) {
            return (String(parts[1]), ordinal)
        }
        return nil
    }

    /// Dzieli „PN: Kurczak…" na skrót dnia i resztę. `nil`, gdy pozycja nie
    /// zaczyna się od dnia — wtedy zostaje zwykłym punktem listy.
    private static func splitDay(_ content: String) -> (String, String)? {
        for separator in [": ", " – ", " — ", " - "] {
            guard let range = content.range(of: separator) else { continue }
            let head = content[content.startIndex..<range.lowerBound]
            // Dzień to jedno krótkie słowo. Bez tego „Uwaga: brakuje białka"
            // wyglądałoby na wiersz dnia.
            guard head.count <= 14 else { continue }
            let token = head
                .replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespaces)
                .uppercased()
            guard let badge = dayBadges[token] else { continue }
            return (badge, String(content[range.upperBound...]))
        }
        return nil
    }

    private static let dayBadges: [String: String] = [
        "PN": "PN", "PON": "PN", "PONIEDZIALEK": "PN", "PONIEDZIAŁEK": "PN",
        "WT": "WT", "WTOREK": "WT",
        "SR": "ŚR", "ŚR": "ŚR", "SRODA": "ŚR", "ŚRODA": "ŚR",
        "CZ": "CZW", "CZW": "CZW", "CZWARTEK": "CZW",
        "PT": "PT", "PIA": "PT", "PIATEK": "PT", "PIĄTEK": "PT",
        "SB": "SOB", "SOB": "SOB", "SOBOTA": "SOB",
        "ND": "ND", "NDZ": "ND", "NIEDZIELA": "ND",
    ]

    /// Zdejmuje z tekstu to, czego użytkownik nie ma prawa oglądać: kody
    /// slotów z bazy i resztki markdownu. Prompt każe modelowi ich nie pisać,
    /// ale stare rozmowy zostały z nimi w historii.
    private static func clean(_ text: String) -> String {
        var result = text
        for code in ["(BREAKFAST)", "(LUNCH)", "(DINNER)", "(SNACK)", "(SUPPER)"] {
            result = result.replacingOccurrences(of: code, with: "")
        }
        result = result.trimmingCharacters(in: .whitespaces)
        if result.hasSuffix(":") {
            result = String(result.dropLast())
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Markdown liniowy (`**pogrubienie**`) na `AttributedString`. Gdy tekst
    /// nie da się sparsować, wraca goły — lepszy niż pusty dymek.
    ///
    /// LINKI SĄ ZDEJMOWANE (audyt 12.09.2026). Parser markdownu zachowuje
    /// atrybut `.link`, a `Text` renderuje go jako dotykalny i otwiera
    /// środowiskowym `openURL` — czyli, przy braku nadpisania, dowolny adres
    /// i dowolny schemat, także cudzej aplikacji. Treść odpowiedzi pochodzi
    /// od modelu, a model czyta tytuły przepisów gospodarstwa, które wpisuje
    /// domownik: to gotowa droga na podsunięcie komuś „Odnów subskrypcję”
    /// prowadzącego na obcą stronę. Serwer takiej składni już nie zapisuje,
    /// ale stare rozmowy w historii mają ją nadal, a klient nie ma prawa
    /// polegać na tym, że druga strona zawsze posprząta.
    ///
    /// Formatowanie zostaje, znika sama klikalność.
    static func inline(_ text: String) -> AttributedString {
        var parsed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        for run in parsed.runs where run.link != nil {
            parsed[run.range].link = nil
        }
        return parsed
    }
}

// MARK: - Pisanie

/// Ile kawałka widać, gdy odpowiedź jeszcze się pisze.
///
/// Tekst jest ZŁOŻONY od pierwszej klatki (cały znany tekst), a nienapisana
/// część ma przezroczysty kolor — jak `SCTypedText` w powitaniu. Wiersze
/// łamią się więc tak samo na początku i na końcu pisania: słowo nie
/// przeskakuje do następnej linii w chwili, gdy się dopisze, i odpowiedź nie
/// rośnie linijka po linijce pod okiem. Ostatnie znaki przed „kursorem”
/// wchodzą rampą krycia — tekst wpływa, zamiast wskakiwać literami.
struct AssistantReveal {
    /// Napisane znaki SUROWEGO tekstu.
    let count: Int

    /// Ile znaków rampy przed kursorem.
    static let ramp = 14

    /// Kawałek w całości przed kursorem — rysuje się zwyczajnie.
    func isComplete(_ raw: Range<Int>) -> Bool { count >= raw.upperBound }

    /// Kawałek w całości za kursorem — jeszcze go nie ma.
    func isPending(_ raw: Range<Int>) -> Bool { count <= raw.lowerBound }

    /// Tekst kawałka z kryciem wg pozycji kursora. Znaki surowego tekstu
    /// i wyrenderowanego różnią się o znaczniki (`**`, „- ”), więc pozycja
    /// w kawałku liczy się proporcją — na długości zdania różnica to znak.
    func styled(_ text: AttributedString, raw: Range<Int>, color: Color) -> AttributedString {
        guard !isComplete(raw) else { return text }
        var result = text
        let rendered = result.characters.count
        guard rendered > 0 else { return result }
        let rawLength = max(1, raw.count)
        let written = Double(max(0, count - raw.lowerBound)) / Double(rawLength)
        let cursor = min(rendered, max(0, Int((written * Double(rendered)).rounded())))

        // Od razu do początku rampy — bez przechodzenia całego akapitu
        // w każdej klatce.
        let rampStart = max(0, cursor - Self.ramp)
        var index = result.characters.index(result.characters.startIndex, offsetBy: rampStart)
        var position = rampStart
        while position < cursor, index < result.characters.endIndex {
            let next = result.characters.index(after: index)
            // 1 = ostatni napisany znak: ledwie widać; czternasty wstecz —
            // prawie w pełni.
            let distance = cursor - position
            let alpha = 0.3 + 0.7 * Double(distance - 1) / Double(Self.ramp)
            result[index..<next].foregroundColor = color.opacity(alpha)
            index = next
            position += 1
        }
        // Reszta kawałka jednym zakresem — stoi w układzie, niewidoczna.
        if index < result.characters.endIndex {
            result[index..<result.characters.endIndex].foregroundColor = color.opacity(0)
        }
        return result
    }
}

// MARK: - Widok

/// Odpowiedź asystenta: nagłówki sekcji, akapity i listy dni w kafelkach.
///
/// Typografia (27.09.2026, „odpowiedzi są ściśnięte”): akapit 16 pt z interlinią
/// 6 i bez ścieśniania liter (było −0,3), odstęp 16 pt między kawałkami,
/// nagłówek sekcji jak zdanie (15/600) zamiast wersalików 11 pt, pozycje listy
/// 15 pt z interlinią.
struct AssistantAnswer: View {
    let text: String
    /// Ile znaków `text` jest już napisanych — `nil` = całość (historia,
    /// odpowiedź odsłonięta).
    var revealed: Int? = nil

    @Environment(\.colorScheme) private var scheme

    static let blockSpacing: CGFloat = 16

    private var blocks: [AssistantBlock] {
        AssistantAnswerParser.blocks(from: text)
    }

    private var reveal: AssistantReveal? {
        guard let revealed, revealed < text.count else { return nil }
        return AssistantReveal(count: revealed)
    }

    var body: some View {
        let reveal = self.reveal
        VStack(alignment: .leading, spacing: Self.blockSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, index: index, reveal: reveal)
                    // Kawałek, do którego kursor jeszcze nie doszedł, stoi
                    // w układzie (miejsce zarezerwowane), ale go nie widać —
                    // także ramki listy i plakietek dni.
                    .opacity(reveal?.isPending(block.raw) == true ? 0 : 1)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: AssistantBlock, index: Int, reveal: AssistantReveal?) -> some View {
        switch block {
        case let .heading(title, raw):
            Text(styled(AssistantAnswerParser.inline(title), raw: raw, reveal: reveal))
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
                // Nagłówek rozdziela sekcje, więc potrzebuje powietrza
                // NAD sobą — ale nie wtedy, gdy stoi na samej górze.
                .padding(.top, index == 0 ? 0 : 4)

        case let .paragraph(paragraph, raw):
            Text(styled(AssistantAnswerParser.inline(paragraph), raw: raw, reveal: reveal))
                .font(.system(size: 16))
                .lineSpacing(6)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)

        case let .list(items):
            AssistantListCard(items: items, reveal: reveal)
        }
    }

    private func styled(_ text: AttributedString, raw: Range<Int>, reveal: AssistantReveal?) -> AttributedString {
        guard let reveal else { return text }
        return reveal.styled(text, raw: raw, color: Color.scLabel(scheme))
    }
}

/// Lista pozycji w jednym kafelku. Dni dostają plakietkę, żeby dało się
/// przelecieć tydzień wzrokiem zamiast czytać go zdanie po zdaniu.
private struct AssistantListCard: View {
    let items: [AssistantListItem]
    var reveal: AssistantReveal? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 0) {
                    if index > 0 {
                        Rectangle()
                            .fill(Color.scRule(scheme))
                            .frame(height: 0.5)
                            .padding(
                                .leading,
                                item.day == nil && item.ordinal == nil ? 14 : 60
                            )
                    }
                    row(item)
                }
                .opacity(reveal?.isPending(item.raw) == true ? 0 : 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private func row(_ item: AssistantListItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let badge = item.day ?? item.ordinal.map({ "\($0)." }) {
                Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SCPalette.terracotta)
                    .frame(width: 36, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.scAccentTint(scheme))
                    )
            } else {
                Circle()
                    .fill(Color.scMuted(scheme).opacity(0.5))
                    .frame(width: 4, height: 4)
                    .padding(.top, 9)
            }

            Text(styledText(item))
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12 + CGFloat(item.depth) * 14)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
    }

    private func styledText(_ item: AssistantListItem) -> AttributedString {
        let text = AssistantAnswerParser.inline(item.text)
        guard let reveal else { return text }
        return reveal.styled(text, raw: item.raw, color: Color.scLabel(scheme))
    }
}

/// Skrót do planu po turze, która NAPRAWDĘ coś zapisała.
///
/// Bez tego jedynym śladem zapisu było zdanie w odpowiedzi, a plan trzeba
/// było znaleźć samemu w innej zakładce.
struct AssistantSavedPlanCard: View {
    let onOpenPlan: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SCPalette.sage)

            Text("Plan tygodnia zapisany")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))

            Spacer(minLength: 8)

            Button(action: onOpenPlan) {
                Text("Otwórz")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SCPalette.terracotta)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.scAccentTint(scheme))
                    )
                    // Pigułka ma ~28 pt; cel dotyku 44 bez podnoszenia wiersza.
                    .scTapHeight(drawn: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }
}
