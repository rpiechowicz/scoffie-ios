import SwiftUI

// Wspólne atomy kart asystenta — JEDNA rodzina, 1:1 z makietą
// „Scoffie — Asystent v4” (`cards-main.jsx`, `kit.jsx`).
//
// Anatomia karty: 1 eyebrow (typ) · 2 tytuł · 3 podtytuł · 4 treść ·
// 5 podsumowanie · 6 akcje · 7 stan (plakietka). Promienie: karta 24 /
// lista 20 / wnętrze 16 / miniatura 11 / pigułka 99. Padding poziomy 18.
// Separator: włoskowaty. Stopka 12/14/14 z przyciskami 42 (pole dotyku 44).
//
// Reguła akcji: główna = pigułka „soft” (tint terakoty, obwódka i tekst
// w tym samym kolorze — `scSoftCapsule`, jak w reszcie aplikacji), ZAWSZE
// terakota; poboczna = neutralna pigułka o ton ciemniejsza od karty. Makieta
// ma tu pełne wypełnienie — świadomie odchodzimy od niej na rzecz stylu
// aplikacji. Jedna akcja → pełna szerokość; dwie → RÓWNE połówki, poboczna
// po lewej, główna po prawej, a gdy któraś nie mieści się w połówce — jedna
// pod drugą, główna na dole (`AssistantActionPair`). Główna stoi więc zawsze
// na końcu. Nawigacja informacyjna → wiersz z chevronem. Cofnij po zapisie
// = poboczna w karcie, nigdy toast.
// Stan → kolor: propozycja terakota, planowanie indygo, zapisane szałwia,
// nieaktualna / przerwane wyciszona neutralność, nigdy czerwień.

// MARK: - Barwy makiety

/// Tokeny z `kit.jsx` (`L`). Jasny motyw = liczby z makiety co do wartości;
/// ciemny = te same role na palecie aplikacji, bo makieta ciemnego nie ma.
///
/// WYJĄTEK: powierzchnie. Karta, jej obrys i pola na karcie biorą żetony
/// aplikacji (`scTileBg`, `scTileStroke`, `scChipBg`) w OBU motywach.
/// Makieta miała w jasnym motywie białe karty z cieniem — obok kafli
/// Ustawień, Planu i Przepisów wyglądały jak wklejka z innej aplikacji
/// (arkusz „Asystent i plan” w Ustawieniach był jedynym białym ekranem
/// wśród beżowych). Decyzja Rafała z 23.09.2026: wszystkie karty w tym
/// samym kolorze.
enum AssistantLook {
    private static let inkLight = Color(red: 30 / 255, green: 22 / 255, blue: 18 / 255)        // #1E1612
    private static let warmLight = Color(red: 58 / 255, green: 42 / 255, blue: 34 / 255)       // rgba(58,42,34,…)
    private static let inkDark = SCPalette.labelDark

    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark : inkLight }
    static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.72) : warmLight.opacity(0.76) }
    static func faint(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.55) : warmLight.opacity(0.66) }
    static func hair(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.12) : warmLight.opacity(0.10) }
    static func wash(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.04) : warmLight.opacity(0.04) }
    /// Kreskowany obrys pustego kafelka / kółka.
    static func dash(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.28) : warmLight.opacity(0.22) }

    static func card(_ scheme: ColorScheme) -> Color { Color.scTileBg(scheme) }
    static func cardStroke(_ scheme: ColorScheme) -> Color { Color.scTileStroke(scheme) }
    /// Pola na karcie (kafelek ikony, składnik wiersza) — ciemniejsze od
    /// karty o jeden stopień, jak pola tekstowe w arkuszach Ustawień.
    static func field(_ scheme: ColorScheme) -> Color { Color.scChipBg(scheme) }
    /// Pole nad przewijaną treścią (composer, pasek edycji, szukanie):
    /// NIEPRZEZROCZYSTE, bo rozmowa przelatuje pod nim — w ciemnym motywie
    /// półprzezroczysty tint pokazywał litery przez pole.
    static func input(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 38 / 255, green: 30 / 255, blue: 26 / 255)
            : Color(red: 253 / 255, green: 250 / 255, blue: 246 / 255)
    }

    static func terra(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.terracotta : Color(red: 168 / 255, green: 80 / 255, blue: 47 / 255)   // #A8502F
    }
    static func terraFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.terracotta : Color(red: 194 / 255, green: 100 / 255, blue: 62 / 255)  // #C2643E
    }
    static func terraTint(_ scheme: ColorScheme) -> Color { terraFill(scheme).opacity(scheme == .dark ? 0.18 : 0.12) }
    static func terraTint2(_ scheme: ColorScheme) -> Color { terraFill(scheme).opacity(scheme == .dark ? 0.28 : 0.22) }

    static func indigo(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.indigo : Color(red: 90 / 255, green: 97 / 255, blue: 174 / 255)      // #5A61AE
    }
    static func indigoTint(_ scheme: ColorScheme) -> Color { indigo(scheme).opacity(scheme == .dark ? 0.16 : 0.10) }

    static func sage(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.sage : Color(red: 58 / 255, green: 115 / 255, blue: 84 / 255)        // #3A7354
    }
    static func sageTint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.sage.opacity(0.16) : Color(red: 79 / 255, green: 143 / 255, blue: 108 / 255).opacity(0.14)
    }

    static func butter(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.butter : Color(red: 138 / 255, green: 101 / 255, blue: 18 / 255)     // #8A6512
    }
    static func butterTint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? SCPalette.butter.opacity(0.16) : Color(red: 214 / 255, green: 170 / 255, blue: 60 / 255).opacity(0.18)
    }

    /// Neutralne tło plakietki „Nieaktualna” / „Przerwane”.
    static func quietTint(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.09) : warmLight.opacity(0.07) }
}

/// Cień karty z makiety (`0 1px 2px .04, 0 10px 30px -14px rgba(90,50,30,.18)`)
/// był potrzebny białej karcie na kremowym tle, żeby się od niego odkleiła.
/// Karta stoi teraz na żetonach kafla — jak w Ustawieniach, bez cienia —
/// więc modyfikator zostaje pusty, a miejsce użycia nie musi się zmieniać.
private struct AssistantCardShadow: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content
    }
}

// MARK: - Liczby

enum AssistantCardMetrics {
    static let radius: CGFloat = 24
    /// Promień zgrupowanej listy (arkusze).
    static let listRadius: CGFloat = 20
    /// Wcięcie treści od krawędzi karty.
    static let inset: CGFloat = 18
    static let headTop: CGFloat = 16
    /// Odstęp między sekcjami karty.
    static let section: CGFloat = 14
    /// Wysokość przycisku w stopce karty (`AssistantButtonSize.compact`).
    static let ctaHeight: CGFloat = 42
    /// Wcięcie paska akcji — mniejsze niż treści, żeby przyciski były szersze.
    static let footerInset: CGFloat = 14
    /// Promień kafli WEWNĄTRZ karty (wnętrze 16, miniatura 11).
    static let innerRadius: CGFloat = 16
    static let thumbRadius: CGFloat = 11
}

// MARK: - Ton

/// Ton karty: neutral = propozycja, sage = zapisane, indigo = analiza,
/// muted = nieaktualne / przerwane (przygaszona, bez cienia).
enum AssistantTone: Equatable {
    case neutral, sage, indigo, muted

    func accent(_ scheme: ColorScheme) -> Color {
        switch self {
        case .neutral: return AssistantLook.terra(scheme)
        case .sage: return AssistantLook.sage(scheme)
        case .indigo: return AssistantLook.indigo(scheme)
        case .muted: return AssistantLook.faint(scheme)
        }
    }

    func fill(_ scheme: ColorScheme) -> Color {
        switch self {
        case .neutral, .indigo, .sage: return AssistantLook.card(scheme)
        // Przygaszona: ta sama karta, tylko cieńsza — nieaktualne ma się
        // cofnąć, a nie zmienić materiał.
        case .muted: return AssistantLook.card(scheme).opacity(0.6)
        }
    }

    func stroke(_ scheme: ColorScheme) -> Color {
        switch self {
        case .neutral, .indigo: return AssistantLook.cardStroke(scheme)
        case .sage: return AssistantLook.sage(scheme).opacity(0.30)
        case .muted: return AssistantLook.cardStroke(scheme).opacity(0.9)
        }
    }

    var hasShadow: Bool { self != .muted }
}

// MARK: - Kontener

/// Kontener karty: powierzchnia, obrys, cień, przycięcie. Ton PRZENIKA —
/// zmiana stanu propozycji (czeka → zapisane) nie podmienia karty.
struct AssistantCard<Content: View>: View {
    var tone: AssistantTone = .neutral
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AssistantCardMetrics.radius, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(tone.fill(scheme)))
            .clipShape(shape)
            .overlay(shape.stroke(tone.stroke(scheme), lineWidth: 1))
            .modifier(AssistantCardShadow(enabled: tone.hasShadow))
            .animation(.easeInOut(duration: 0.25), value: tone)
    }
}

// MARK: - Stan propozycji

/// Stan karty jako TEKST, nie tylko kolor. Liczone z `AgentCardStateDTO`
/// PRZY ODCZYCIE.
enum AssistantCardStatus: Equatable {
    case pending, applied, undone, stale, expired, failed

    init(_ state: AgentCardStateDTO) {
        switch state.status {
        case "APPLIED": self = .applied
        case "UNDONE": self = .undone
        case "STALE": self = .stale
        case "EXPIRED": self = .expired
        case "FAILED": self = .failed
        default: self = .pending
        }
    }

    var title: String {
        switch self {
        case .pending: return "Do zatwierdzenia"
        case .applied: return "Zapisane"
        case .undone: return "Cofnięte"
        case .stale: return "Nieaktualna"
        case .expired: return "Wygasła"
        case .failed: return "Nie zapisano"
        }
    }

    /// Ton całej karty w tym stanie.
    var tone: AssistantTone {
        switch self {
        case .pending, .failed: return .neutral
        case .applied: return .sage
        case .undone, .stale, .expired: return .muted
        }
    }

    func tint(_ scheme: ColorScheme) -> Color {
        switch self {
        case .pending, .failed: return AssistantLook.terra(scheme)
        case .applied: return AssistantLook.sage(scheme)
        case .undone, .stale, .expired: return AssistantLook.faint(scheme)
        }
    }

    func chipFill(_ scheme: ColorScheme) -> Color {
        switch self {
        case .pending, .failed: return AssistantLook.terraTint(scheme)
        case .applied: return AssistantLook.sageTint(scheme)
        case .undone, .stale, .expired: return AssistantLook.quietTint(scheme)
        }
    }

    /// Zdanie tuż nad decyzją — tylko, gdy stan zmienia to, co da się zrobić.
    /// Propozycja i zapis nie dostają notki (makieta ich nie ma).
    func note(until: String?) -> String? {
        switch self {
        case .pending, .applied: return nil
        case .undone: return "Możesz zastosować ponownie."
        case .stale: return "Plan zmienił się od tej propozycji."
        case .expired: return "Poproś o nową — asystent policzy od nowa."
        case .failed: return "Plan bez zmian."
        }
    }
}

/// Plakietka stanu w prawym górnym rogu karty: samo słowo, 11/700.
struct AssistantStatusChip: View {
    let status: AssistantCardStatus

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(status.title)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.3)
            .lineLimit(1)
            .foregroundStyle(status.tint(scheme))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(status.chipFill(scheme)))
            .fixedSize()
            .accessibilityLabel("Stan: \(status.title)")
    }
}

/// Plakietka „W toku” (indygo) — dla rozmowy z biegnącą turą.
struct AssistantWorkingChip: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 5) {
            AssistantSpinningMark(size: 10)
            Text("W toku")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(AssistantLook.indigo(scheme))
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(AssistantLook.indigoTint(scheme)))
        .fixedSize()
        .accessibilityLabel("W toku")
    }
}

/// Znak marki, który orbituje (`kesOrbit` 5,5 s) — w stanie pracy
/// i w plakietce „W toku”. Przy Reduce Motion stoi.
struct AssistantSpinningMark: View {
    var size: CGFloat = 26
    var color: Color? = nil
    var spinning: Bool = true

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !spinning)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            SCMarkShape()
                .fill(color ?? AssistantLook.terraFill(scheme))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(reduceMotion || !spinning ? 0 : Self.orbit(t) * 360))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// `cubic-bezier(.45,.05,.55,.95)` na okresie 5,5 s.
    private static func orbit(_ t: TimeInterval) -> Double {
        let phase = t.truncatingRemainder(dividingBy: 5.5) / 5.5
        return phase < 0.5 ? 2 * phase * phase : 1 - pow(-2 * phase + 2, 2) / 2
    }
}

// MARK: - Nagłówek

/// Eyebrow (typ) „· meta” · plakietka po prawej → tytuł 21/700 → podtytuł 14.
/// Znak marki przy eyebrow tylko, gdy karta jest głosem asystenta
/// (briefing, zapisane) — `mark`.
struct AssistantCardHead<Right: View>: View {
    let eyebrow: String
    /// „22–28 wrz” — doklejone kropką po eyebrow, jak na makiecie.
    var eyebrowDetail: String?
    var eyebrowColor: Color? = nil
    var mark: Bool = false
    var tone: AssistantTone = .neutral
    let title: String?
    var subtitle: String?
    @ViewBuilder var right: () -> Right

    @Environment(\.colorScheme) private var scheme

    private var eyeColor: Color {
        if let eyebrowColor { return eyebrowColor }
        switch tone {
        case .sage: return AssistantLook.sage(scheme)
        case .muted: return AssistantLook.faint(scheme)
        case .indigo: return AssistantLook.indigo(scheme)
        case .neutral: return AssistantLook.terra(scheme)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    if mark {
                        SCMarkShape()
                            .fill(tone == .sage ? AssistantLook.sage(scheme) : (tone == .muted ? AssistantLook.faint(scheme) : AssistantLook.terraFill(scheme)))
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    }
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(eyeColor)
                        .lineLimit(1)
                    if let eyebrowDetail, !eyebrowDetail.isEmpty {
                        Text("· " + eyebrowDetail)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AssistantLook.faint(scheme))
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                right()
            }

            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.5)
                    .lineSpacing(1)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .opacity(tone == .muted ? 0.6 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .foregroundStyle(AssistantLook.muted(scheme))
                    .opacity(tone == .muted ? 0.7 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.top, AssistantCardMetrics.headTop)
    }
}

extension AssistantCardHead where Right == EmptyView {
    init(
        eyebrow: String,
        eyebrowDetail: String? = nil,
        eyebrowColor: Color? = nil,
        mark: Bool = false,
        tone: AssistantTone = .neutral,
        title: String?,
        subtitle: String? = nil
    ) {
        self.init(
            eyebrow: eyebrow,
            eyebrowDetail: eyebrowDetail,
            eyebrowColor: eyebrowColor,
            mark: mark,
            tone: tone,
            title: title,
            subtitle: subtitle
        ) { EmptyView() }
    }
}

extension AssistantCardHead where Right == AssistantStatusChip {
    /// Nagłówek z plakietką stanu po prawej — dla każdej propozycji.
    init(
        eyebrow: String,
        eyebrowDetail: String? = nil,
        eyebrowColor: Color? = nil,
        mark: Bool = false,
        title: String?,
        subtitle: String? = nil,
        status: AssistantCardStatus
    ) {
        self.init(
            eyebrow: eyebrow,
            eyebrowDetail: eyebrowDetail,
            eyebrowColor: eyebrowColor,
            mark: mark,
            tone: status.tone,
            title: title,
            subtitle: subtitle
        ) { AssistantStatusChip(status: status) }
    }
}

// MARK: - Sekcje

/// Włoskowata kreska między sekcjami karty.
struct AssistantCardRule: View {
    var leadingInset: CGFloat = 0

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(AssistantLook.hair(scheme))
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// Etykieta sekcji wewnątrz karty: „POWÓD PROPOZYCJI”, „CO SIĘ ZMIENI” — 11.5/600.
struct AssistantCardLabel: View {
    let text: String
    var color: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(color ?? AssistantLook.faint(scheme))
            .lineLimit(1)
    }
}

/// 5 · Podsumowanie — jeden wiersz faktów rozdzielonych kropką.
struct AssistantCardSummary: View {
    let items: [String]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Text("·").foregroundStyle(AssistantLook.ink(scheme).opacity(0.3))
                    }
                    Text(item).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .foregroundStyle(AssistantLook.muted(scheme))
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { AssistantCardRule() }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Wiersz podsumowania: opis po lewej, wartość po prawej (stare karty).
struct AssistantCardSummaryRow: View {
    let label: String
    let value: String
    var valueColor: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(AssistantLook.muted(scheme))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? AssistantLook.ink(scheme))
        }
    }
}

/// Miniatura dania — promień 0,3 boku (36 → 11), z tym samym zapasem bez zdjęcia.
struct AssistantThumbnail: View {
    let url: URL?
    var size: CGFloat = 36
    var dimmed: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    AssistantLook.wash(scheme)
                    Image(systemName: "fork.knife")
                        .font(.system(size: size * 0.36))
                        .foregroundStyle(AssistantLook.faint(scheme))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: (size * 0.3).rounded(), style: .continuous))
        .shadow(color: Color.black.opacity(dimmed ? 0 : 0.12), radius: 1, y: 1)
        .saturation(dimmed ? 0.4 : 1)
        .opacity(dimmed ? 0.6 : 1)
        .accessibilityHidden(true)
    }
}

/// Wiersz posiłku z makiety: miniatura 36 · PORA (11/600) nad nazwą (15/500)
/// · kcal po prawej (13/600). `muted` = to, co zostaje (nieaktualne).
struct AssistantMealRow: View {
    let slot: String?
    let title: String
    var imageUrl: String? = nil
    var kcal: Int = 0
    var size: CGFloat = 36
    var muted: Bool = false
    var titleWeight: Font.Weight = .medium

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AssistantThumbnail(url: imageUrl.flatMap(URL.init(string:)), size: size, dimmed: muted)

            VStack(alignment: .leading, spacing: 3) {
                if let slot, !slot.isEmpty {
                    Text(slot)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(AssistantLook.faint(scheme))
                        .lineLimit(1)
                }
                Text(title)
                    .font(.system(size: 15, weight: titleWeight))
                    .tracking(-0.25)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if kcal > 0 {
                HStack(spacing: 3) {
                    CountingNumber(target: kcal)
                    Text("kcal")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AssistantLook.muted(scheme))
                .fixedSize()
            }
        }
        .opacity(muted ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Cienka linia „średnio vs cel” — 3 pt, akcent tylko jako kolor.
struct AssistantTargetBar: View {
    let value: Int
    let target: Int?
    var color: Color = SCPalette.indigo
    var height: CGFloat = 3

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            let full = Double(max(target ?? value, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(AssistantLook.ink(scheme).opacity(0.08))
                Capsule()
                    .fill(color.opacity(0.7))
                    .frame(width: geometry.size.width * min(Double(value) / full, 1))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Akcje

struct AssistantCardAction {
    let title: String
    var icon: String? = nil
    let action: () -> Void
}

/// Dwa rozmiary JEDNEGO przycisku asystenta.
///
/// Wcześniej każdy przycisk miał 48 pt i tekst 15,5 — w stopce karty para
/// takich pigułek była cięższa od samej treści karty („za duże”). Teraz:
/// w karcie w rozmowie `compact` (42 pt rysowane, pole dotyku 44 przez
/// `scTapHeight`, tekst 14), a samodzielne CTA — arkusz wyboru posiłku,
/// stopki arkuszy, karta planów — `regular` (46 pt, tekst 15), czyli tyle,
/// ile `EditorialPrimaryActionButton` w arkuszach Ustawień.
enum AssistantButtonSize: Equatable {
    case compact
    case regular

    var height: CGFloat {
        switch self {
        case .compact: return AssistantCardMetrics.ctaHeight
        case .regular: return 46
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .compact: return 14
        case .regular: return 15
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .compact: return 12
        case .regular: return 13
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: return 14
        case .regular: return 18
        }
    }

    /// Ściśnięcie pod palcem — mniejszy przycisk ściska się odrobinę mocniej,
    /// żeby reakcja była tak samo widoczna.
    var pressScale: CGFloat {
        switch self {
        case .compact: return 0.96
        case .regular: return 0.97
        }
    }
}

/// Para akcji karty: [poboczna, główna] (albo jedna z nich).
///
/// Obok siebie w RÓWNYCH połówkach, gdy obie mieszczą się w połówce bez
/// ściskania tekstu — para czyta się jako wybór „albo–albo”, a kolor mówi,
/// która jest główna. Gdy któraś się nie mieści (długa etykieta z serwera,
/// „Napisz, na co masz ochotę”), obie stają jedna pod drugą na pełną
/// szerokość, główna NA DOLE — tam, gdzie stoi pojedyncza akcja, więc
/// w arkuszu wyboru posiłku główna nie skacze między stronami. Zamiast
/// dawnych wag 1 : 1,4, przy których dłuższa poboczna zjeżdżała skalą albo
/// urywała się wielokropkiem.
struct AssistantActionPair: Layout {
    var spacing: CGFloat = 8

    /// Obie akcje mieszczą się w połówce szerokości w swoim naturalnym rozmiarze.
    private func fitsSideBySide(width: CGFloat, subviews: Subviews) -> Bool {
        guard subviews.count == 2 else { return false }
        let half = max(0, (width - spacing) / 2)
        return subviews.allSatisfy { $0.sizeThatFits(.unspecified).width <= half }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        // Sonda bez szerokości — obok siebie w szerokościach własnych, NIGDY
        // nieskończoność (nieskończony wymiar ramki wywraca aplikację).
        guard let width = proposal.width, width.isFinite else {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let widest = sizes.map(\.width).max() ?? 0
            let count = CGFloat(sizes.count)
            return CGSize(
                width: widest * count + spacing * (count - 1),
                height: sizes.map(\.height).max() ?? 0
            )
        }
        if fitsSideBySide(width: width, subviews: subviews) {
            let half = max(0, (width - spacing) / 2)
            let height = subviews
                .map { $0.sizeThatFits(ProposedViewSize(width: half, height: nil)).height }
                .max() ?? 0
            return CGSize(width: width, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(
            width: width,
            height: heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if fitsSideBySide(width: bounds.width, subviews: subviews) {
            let half = max(0, (bounds.width - spacing) / 2)
            var x = bounds.minX
            for subview in subviews {
                subview.place(
                    at: CGPoint(x: x, y: bounds.minY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: half, height: bounds.height)
                )
                x += half + spacing
            }
            return
        }
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: height)
            )
            y += height + spacing
        }
    }
}

/// Rząd o RÓWNYCH kolumnach: każde dziecko dostaje dokładnie
/// `(szerokość − odstępy) / n`, a wysokość rzędu to najwyższe dziecko
/// zmierzone przy TEJ szerokości (nie przy nieskończonej — tytuł na dwie
/// linie musi się zmieścić). Kafelki w karcie opcji stoją na tym, bo
/// `HStack` rozdawał szerokość po długości tekstu i rząd wychodził krzywy.
struct AssistantEqualColumns: Layout {
    var spacing: CGFloat = 10

    private func columnWidth(_ total: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(0, (total - spacing * CGFloat(count - 1)) / CGFloat(count))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let width = proposal.width, width.isFinite else {
            // Sonda bez szerokości — suma szerokości własnych, nigdy nieskończoność.
            let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
            let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            return CGSize(width: ideal + spacing * CGFloat(max(0, subviews.count - 1)), height: height)
        }
        let column = columnWidth(width, count: subviews.count)
        let height = subviews
            .map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(bounds.width, count: subviews.count)
        var x = bounds.minX
        for subview in subviews {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: column, height: bounds.height)
            )
            x += column + spacing
        }
    }
}

/// Pasek akcji karty. Główna = „soft” terakota, poboczna = neutralna
/// pigułka, obie w rozmiarze `compact`, ułożone przez `AssistantActionPair`.
/// Nawigacja = wiersz z chevronem.
///
/// Kręciołek pracy stoi na przycisku, który STUKNIĘTO („Cofnij” kręci się
/// na „Cofnij”, a nie na „Otwórz plan” obok); druga akcja w tym czasie
/// przygasa. Gdy praca przyszła z innego miejsca (zapis z arkusza wyboru
/// posiłku), kręci się główna.
struct AssistantCardActions: View {
    enum Style: Equatable {
        case buttons
        case navigation
    }

    /// Który przycisk stuknięto — tylko po to, żeby wiedzieć, gdzie postawić
    /// kręciołek. Stan widoku, nie logika akcji.
    private enum Slot: Equatable {
        case primary, secondary
    }

    let primary: AssistantCardAction?
    var secondary: AssistantCardAction? = nil
    var tone: AssistantTone = .neutral
    var style: Style = .buttons
    var isBusy: Bool = false
    /// Kreska nad stopką — wyłączana, gdy sekcja wyżej sama ją rysuje.
    var showsRule: Bool = true
    /// Zostało dla zgodności wywołań; główna akcja jest zawsze wypełniona.
    var filledPrimary: Bool = true

    @Environment(\.colorScheme) private var scheme
    @State private var tapped: Slot?
    /// Lustro `isBusy` czytane z zadania, które sprząta `tapped`.
    @State private var busyNow = false

    init(
        primary: AssistantCardAction? = nil,
        secondary: AssistantCardAction? = nil,
        tone: AssistantTone = .neutral,
        style: Style = .buttons,
        isBusy: Bool = false,
        showsRule: Bool = true,
        filledPrimary: Bool = true
    ) {
        self.primary = primary
        self.secondary = secondary
        self.tone = tone
        self.style = style
        self.isBusy = isBusy
        self.showsRule = showsRule
        self.filledPrimary = filledPrimary
    }

    /// Przycisk z kręciołkiem: stuknięty, a bez stuknięcia — główny (albo
    /// jedyny, gdy głównego nie ma).
    private var busySlot: Slot? {
        guard isBusy else { return nil }
        if let tapped { return tapped }
        return primary != nil ? .primary : .secondary
    }

    var body: some View {
        Group {
            switch style {
            case .buttons: buttons
            case .navigation: navigation
            }
        }
        .background(style == .buttons ? AssistantLook.wash(scheme) : Color.clear)
        .overlay(alignment: .top) {
            if showsRule { AssistantCardRule() }
        }
        .onChange(of: isBusy, initial: true) { _, busy in
            busyNow = busy
            if !busy { tapped = nil }
        }
        // Stuknięcie, po którym praca nie ruszyła (nawigacja, wiadomość do
        // asystenta), nie może zostawić znacznika na później — inaczej
        // następny zapis kręciłby się na tamtym przycisku.
        .task(id: tapped) {
            guard tapped != nil else { return }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, !busyNow else { return }
            tapped = nil
        }
    }

    private func marked(_ action: AssistantCardAction, as slot: Slot) -> AssistantCardAction {
        AssistantCardAction(title: action.title, icon: action.icon) {
            tapped = slot
            action.action()
        }
    }

    @ViewBuilder
    private var buttons: some View {
        AssistantActionPair(spacing: 8) {
            if let secondary {
                AssistantGhostButton(
                    action: marked(secondary, as: .secondary),
                    isBusy: busySlot == .secondary,
                    size: .compact
                )
                .disabled(isBusy)
                .opacity(isBusy && busySlot != .secondary ? 0.5 : 1)
            }
            if let primary {
                AssistantPrimaryButton(
                    action: marked(primary, as: .primary),
                    isBusy: busySlot == .primary,
                    size: .compact
                )
                .disabled(isBusy)
                .opacity(isBusy && busySlot != .primary ? 0.5 : 1)
            }
        }
        .animation(.smooth(duration: 0.2), value: isBusy)
        .padding(.top, 12)
        .padding(.horizontal, AssistantCardMetrics.footerInset)
        .padding(.bottom, AssistantCardMetrics.footerInset)
    }

    @ViewBuilder
    private var navigation: some View {
        if let primary {
            Button(action: primary.action) {
                HStack(spacing: 12) {
                    Text(primary.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(AssistantLook.ink(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AssistantLook.ink(scheme).opacity(0.35))
                }
                .padding(.horizontal, AssistantCardMetrics.inset)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlanPressStyle(scale: 0.985))
            .disabled(isBusy)
        }
    }
}

/// Wnętrze przycisku asystenta: tytuł i glif. Glif „dalej” (strzałka
/// w prawo, chevron) stoi PO tytule, każdy inny (cofnij, odśwież, ptaszek,
/// ołówek) PRZED nim — ta sama reguła w głównej i pobocznej.
///
/// Stan pracy nie zmienia szerokości: kręciołek zajmuje miejsce glifu,
/// a bez glifu staje zamiast tytułu. Inaczej para przeskakiwałaby
/// z połówek w stos w chwili stuknięcia.
private struct AssistantButtonLabel: View {
    let title: String
    let icon: String?
    let isBusy: Bool
    let size: AssistantButtonSize
    let tint: Color

    private var trailsIcon: Bool {
        guard let icon else { return false }
        return icon.hasPrefix("arrow.right") || icon.hasPrefix("chevron.right") || icon == "arrow.up.right"
    }

    private var glyphSide: CGFloat { size.iconSize + 4 }

    var body: some View {
        HStack(spacing: 6) {
            if !trailsIcon { glyph }
            Text(title)
                .font(.system(size: size.fontSize, weight: .semibold))
                .tracking(-0.2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                // Tytuł zmieniony w animowanej transakcji roluje się literami
                // (jak w `EditorialPrimaryActionButton`), zamiast podmienić się
                // w jednej klatce.
                .contentTransition(.numericText())
                .opacity(isBusy && icon == nil ? 0 : 1)
            if trailsIcon { glyph }
        }
        .overlay {
            if isBusy && icon == nil { spinner }
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if let icon {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: size.iconSize, weight: .bold))
                    .opacity(isBusy ? 0 : 1)
                if isBusy { spinner }
            }
            .frame(width: glyphSide, height: glyphSide)
        }
    }

    private var spinner: some View {
        ProgressView()
            .controlSize(.small)
            .tint(tint)
            .scaleEffect(0.8)
            .frame(width: glyphSide, height: glyphSide)
            .transition(.opacity)
    }
}

/// Główna akcja: pigułka „soft” (`scSoftCapsule`) — tint i obwódka terakoty,
/// tekst w tym samym kolorze. `size: .compact` w stopce karty, `.regular`
/// (domyślny) jako samodzielne CTA.
struct AssistantPrimaryButton: View {
    let action: AssistantCardAction
    var isBusy: Bool = false
    var size: AssistantButtonSize = .regular

    @Environment(\.colorScheme) private var scheme

    private var tint: Color { AssistantLook.terra(scheme) }

    var body: some View {
        Button(action: action.action) {
            AssistantButtonLabel(title: action.title, icon: action.icon, isBusy: isBusy, size: size, tint: tint)
                .foregroundStyle(tint)
                .padding(.horizontal, size.horizontalPadding)
                .frame(maxWidth: .infinity)
                .frame(height: size.height)
                .scSoftCapsule(tint)
                .scTapHeight(44, drawn: size.height)
        }
        .buttonStyle(PlanPressStyle(scale: size.pressScale))
        .disabled(isBusy)
        .animation(.smooth(duration: 0.2), value: isBusy)
    }
}

/// Poboczna akcja: neutralny towarzysz „soft” — tło o ton ciemniejsze od
/// karty (`field`, jak „Odrzuć” przy zaproszeniu w Ustawieniach) i cienka
/// obwódka kafla, tekst w kolorze treści. Na tle samej karty (`scTileBg`)
/// był tylko obrysem i ginął obok terakotowej.
struct AssistantGhostButton: View {
    let action: AssistantCardAction
    var isBusy: Bool = false
    var size: AssistantButtonSize = .regular

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action.action) {
            AssistantButtonLabel(
                title: action.title,
                icon: action.icon,
                isBusy: isBusy,
                size: size,
                tint: AssistantLook.muted(scheme)
            )
            .foregroundStyle(AssistantLook.ink(scheme))
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: .infinity)
            .frame(height: size.height)
            .background(Capsule(style: .continuous).fill(AssistantLook.field(scheme)))
            .overlay(Capsule(style: .continuous).strokeBorder(AssistantLook.cardStroke(scheme), lineWidth: 1.2))
            .scTapHeight(44, drawn: size.height)
        }
        .buttonStyle(PlanPressStyle(scale: size.pressScale))
        .disabled(isBusy)
        .animation(.smooth(duration: 0.2), value: isBusy)
    }
}

/// Zdanie o stanie tuż nad decyzją: ikona zegara + zdanie 14/500.
struct AssistantStateNote: View {
    let status: AssistantCardStatus
    let until: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let note = status.note(until: until) {
            HStack(spacing: 9) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AssistantLook.faint(scheme))
                Text(note)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { AssistantCardRule() }
        }
    }
}

/// Stopka propozycji: notka stanu + akcje zależne od stanu.
///
///   PENDING  → „Zmień coś” | „Dodaj do planu”
///   APPLIED  → „Cofnij”    | „Otwórz plan →”
///   UNDONE   → „Zastosuj ponownie”
///   FAILED   → „Spróbuj ponownie”
///   STALE    → „Zapisz mimo to” | „Odśwież propozycję”
///   EXPIRED  → „Odśwież propozycję”
struct AssistantProposalFooter: View {
    let state: AgentCardStateDTO
    let applyLabel: String
    var applyIcon: String? = nil
    var reviseLabel: String = "Zmień coś"
    var reviseIcon: String? = nil
    let isBusy: Bool
    /// `force` = „Zapisz mimo to” przy propozycji nieaktualnej.
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    /// Odświeżenie — gotowe zdanie do asystenta, bez zapisu.
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil
    var onOpenPlan: (() -> Void)? = nil

    private var status: AssistantCardStatus { AssistantCardStatus(state) }

    var body: some View {
        VStack(spacing: 0) {
            AssistantStateNote(status: status, until: state.until)
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .pending where state.canApply:
            AssistantCardActions(
                primary: AssistantCardAction(title: applyLabel, icon: applyIcon) { onApply(false) },
                secondary: AssistantCardAction(title: reviseLabel, icon: reviseIcon, action: onRevise),
                isBusy: isBusy
            )
        case .applied where state.canUndo:
            if let onUndo {
                // Bez `onOpenPlan` zostaje samo „Cofnij” — dawniej „Otwórz plan”
                // dostawało wtedy cofnięcie jako zapas i robiło coś innego,
                // niż mówił napis.
                AssistantCardActions(
                    primary: onOpenPlan.map { open in
                        AssistantCardAction(title: "Otwórz plan", icon: "arrow.right", action: open)
                    },
                    secondary: AssistantCardAction(title: "Cofnij", icon: "arrow.uturn.backward", action: onUndo),
                    tone: .sage,
                    isBusy: isBusy
                )
            }
        case .applied:
            if let onOpenPlan {
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Otwórz plan", icon: "arrow.right", action: onOpenPlan),
                    tone: .sage,
                    isBusy: isBusy
                )
            }
        case .undone where state.canApply:
            AssistantCardActions(
                primary: AssistantCardAction(title: "Zastosuj ponownie") { onApply(false) },
                isBusy: isBusy
            )
        case .failed where state.canApply:
            AssistantCardActions(
                primary: AssistantCardAction(title: "Spróbuj ponownie") { onApply(false) },
                isBusy: isBusy
            )
        case .stale where state.canApply:
            AssistantCardActions(
                primary: AssistantCardAction(title: "Odśwież propozycję", action: onAskNew),
                secondary: AssistantCardAction(title: "Zapisz mimo to") { onApply(true) },
                isBusy: isBusy
            )
        case .stale, .expired:
            AssistantCardActions(
                primary: AssistantCardAction(title: "Odśwież propozycję", action: onAskNew),
                isBusy: isBusy
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - Szybkie odpowiedzi

/// Pigułka szybkiej odpowiedzi albo sugestii (nie przycisk tekstowy):
/// 38 pt rysowane, pole dotyku 44, 14,5/600. Neutralna ma strój pobocznej
/// akcji (`AssistantGhostButton`: pole o ton od karty + obwódka kafla),
/// wyróżniona (wybrana odpowiedź) — strój głównej, „soft” terakota. Dawne
/// 40 pt z tekstem 15 i obwódką 1,5 stało w karcie pytania ciężej niż
/// samo pytanie.
struct AssistantChip: View {
    let title: String
    var icon: String? = nil
    var highlighted: Bool = false
    var dimmed: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    private static let height: CGFloat = 38

    private var shape: Capsule { Capsule(style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 14.5, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(highlighted ? AssistantLook.terra(scheme) : AssistantLook.ink(scheme))
            .padding(.horizontal, 15)
            .frame(height: Self.height)
            .background {
                if highlighted {
                    shape.fill(Color.clear).scSoftCapsule(AssistantLook.terra(scheme))
                } else {
                    shape
                        .fill(AssistantLook.field(scheme))
                        .overlay(shape.strokeBorder(AssistantLook.cardStroke(scheme), lineWidth: 1.2))
                }
            }
            .opacity(dimmed ? 0.45 : 1)
            .scTapHeight(44, drawn: Self.height)
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
        .animation(.smooth(duration: 0.2), value: highlighted)
        .animation(.smooth(duration: 0.2), value: dimmed)
    }
}

/// Podpowiedzi kolejnego ruchu — pigułki, zawijane.
struct AssistantQuickReplies: View {
    let items: [String]
    var alignment: HorizontalAlignment = .leading
    let onTap: (String) -> Void

    var body: some View {
        AllergenChipFlow(spacing: 8, alignment: alignment) {
            ForEach(items, id: \.self) { item in
                AssistantChip(title: item) { onTap(item) }
            }
        }
    }
}

#if DEBUG
#Preview("Atomy kart") {
    ScrollView {
        VStack(spacing: 16) {
            AssistantCard {
                AssistantCardHead(
                    eyebrow: "Propozycja",
                    eyebrowDetail: "22–28 wrz",
                    title: "Plan tygodnia",
                    subtitle: "21 posiłków z Twoich przepisów, bez powtórek.",
                    status: .pending
                )
                AssistantCardSummary(items: ["Śr. 2 080 kcal dziennie", "Jedna lista zakupów"])
                    .padding(.top, 14)
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Dodaj do planu") {},
                    secondary: AssistantCardAction(title: "Zmień coś") {}
                )
            }
            AssistantCard(tone: .sage) {
                AssistantCardHead(eyebrow: "Propozycja", eyebrowDetail: "22–28 wrz", mark: true, title: "Plan tygodnia zapisany", subtitle: "21 posiłków · 22–28 września", status: .applied)
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Otwórz plan", icon: "arrow.right") {},
                    secondary: AssistantCardAction(title: "Cofnij", icon: "arrow.uturn.backward") {},
                    tone: .sage
                )
                .padding(.top, 16)
            }
            AssistantCard(tone: .muted) {
                AssistantCardHead(eyebrow: "Propozycja", eyebrowDetail: "Śr 24", title: "Plan dnia", subtitle: "3 posiłki · 1 520 kcal", status: .stale)
                AssistantStateNote(status: .stale, until: nil)
                    .padding(.top, 14)
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Odśwież propozycję") {},
                    secondary: AssistantCardAction(title: "Zapisz mimo to") {}
                )
            }
            AssistantCard {
                AssistantCardHead(eyebrow: "Zakupy", title: "Lista zakupów")
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Otwórz listę", icon: "arrow.right") {}
                )
                .padding(.top, 16)
            }
        }
        .padding(20)
    }
    .background(SCPageBackground(scheme: .light).ignoresSafeArea())
}

#Preview("Przyciski — pary, stos, praca") {
    ScrollView {
        VStack(spacing: 16) {
            // Para w połówkach.
            AssistantCard {
                AssistantCardHead(eyebrow: "Propozycja", title: "Plan dnia", status: .pending)
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Zapisz dzień") {},
                    secondary: AssistantCardAction(title: "Inny zestaw") {}
                )
                .padding(.top, 16)
            }
            // Za długie na połówki — stos, główna na dole.
            AssistantCard {
                AssistantCardHead(eyebrow: "Propozycja", title: "Plan tygodnia", status: .pending)
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Zapisz cały tydzień w planie") {},
                    secondary: AssistantCardAction(title: "Zmień coś w propozycji") {}
                )
                .padding(.top, 16)
            }
            // Praca: kręciołek w miejscu glifu, druga akcja przygasa.
            AssistantCard(tone: .sage) {
                AssistantCardHead(eyebrow: "Propozycja", mark: true, title: "Zapisane", status: .applied)
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Otwórz plan", icon: "arrow.right") {},
                    secondary: AssistantCardAction(title: "Cofnij", icon: "arrow.uturn.backward") {},
                    tone: .sage,
                    isBusy: true
                )
                .padding(.top, 16)
            }
            // Sama poboczna (wynik tury) i szybkie odpowiedzi.
            AssistantCard {
                AssistantQuickReplies(items: ["Tylko obiady", "Na jutro", "Dla dwóch"]) { _ in }
                    .padding(AssistantCardMetrics.inset)
                AssistantCardActions(
                    secondary: AssistantCardAction(title: "Spróbuj ponownie", icon: "arrow.clockwise") {}
                )
            }
            // Samodzielne CTA (arkusze).
            AssistantPrimaryButton(action: AssistantCardAction(title: "Wstaw na środę", icon: "arrow.right") {})
            AssistantGhostButton(action: AssistantCardAction(title: "Napisz, na co masz ochotę", icon: "square.and.pencil") {})
        }
        .padding(20)
    }
    .background(SCPageBackground(scheme: .light).ignoresSafeArea())
}
#endif
