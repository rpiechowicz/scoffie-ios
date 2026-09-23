import SwiftUI

/// Odpowiedź asystenta rozłożona na kawałki, które da się pokazać jak
/// interfejs, a nie jak zrzut tekstu.
///
/// Model pisze markdownem, a `Text` markdownu blokowego nie rozumie — na
/// ekranie lądowały dosłowne gwiazdki („\*\*Obiady (LUNCH):\*\*") i ściana
/// myślników. Tu ten sam tekst zamienia się w nagłówki sekcji i wiersze dni,
/// które renderują się jak reszta aplikacji.
enum AssistantBlock {
    case heading(String)
    case paragraph(String)
    case list([AssistantListItem])
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
}

enum AssistantAnswerParser {
    static func blocks(from raw: String) -> [AssistantBlock] {
        var blocks: [AssistantBlock] = []
        var pending: [AssistantListItem] = []

        func flushList() {
            guard !pending.isEmpty else { return }
            blocks.append(.list(pending))
            pending = []
        }

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushList()
                continue
            }

            // Wcięcie liczymy z SUROWEJ linii — po przycięciu podpunkt
            // („  - bez laktozy") wygląda identycznie jak pozycja nadrzędna.
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            if let item = listItem(from: trimmed, depth: min(indent / 2, 3)) {
                pending.append(item)
                continue
            }

            flushList()
            if let heading = heading(from: trimmed) {
                blocks.append(.heading(heading))
            } else {
                blocks.append(.paragraph(clean(trimmed)))
            }
        }

        flushList()
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

// MARK: - Widok

/// Odpowiedź asystenta: nagłówki sekcji, akapity i listy dni w kafelkach.
struct AssistantAnswer: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    private var blocks: [AssistantBlock] {
        AssistantAnswerParser.blocks(from: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case let .heading(title):
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.scMuted(scheme))
                        // Nagłówek rozdziela sekcje, więc potrzebuje powietrza
                        // NAD sobą — ale nie wtedy, gdy stoi na samej górze.
                        .padding(.top, index == 0 ? 0 : 8)

                case let .paragraph(paragraph):
                    Text(AssistantAnswerParser.inline(paragraph))
                        .font(.system(size: 16))
                        .tracking(-0.3)
                        .lineSpacing(4)
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                case let .list(items):
                    AssistantListCard(items: items)
                }
            }
        }
    }
}

/// Lista pozycji w jednym kafelku. Dni dostają plakietkę, żeby dało się
/// przelecieć tydzień wzrokiem zamiast czytać go zdanie po zdaniu.
private struct AssistantListCard: View {
    let items: [AssistantListItem]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 0.5)
                        .padding(
                            .leading,
                            item.day == nil && item.ordinal == nil ? 14 : 60
                        )
                }

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
                            .padding(.top, 8)
                    }

                    Text(AssistantAnswerParser.inline(item.text))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 12 + CGFloat(item.depth) * 14)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
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
