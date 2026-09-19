import SwiftUI

// Wspólne atomy kart asystenta — JEDNA rodzina, 1:1 z makietą
// „Scoffie — Asystent v4” (`cards-main.jsx`, `kit.jsx`).
//
// Anatomia karty: 1 eyebrow (typ) · 2 tytuł · 3 podtytuł · 4 treść ·
// 5 podsumowanie · 6 akcje · 7 stan (plakietka). Promienie: karta 24 /
// lista 20 / wnętrze 16 / miniatura 11 / pigułka 99. Padding poziomy 18.
// Separator: włoskowaty. Stopka 12/14/14 z przyciskami 48.
//
// Reguła akcji: główna = pełna pigułka, ZAWSZE terakota, biały tekst;
// poboczna = obrys. Jedna akcja → pełna szerokość; dwie → poboczna po
// lewej (1), główna po prawej (1,4). Nawigacja informacyjna → wiersz
// z chevronem. Cofnij po zapisie = poboczna w karcie, nigdy toast.
// Stan → kolor: propozycja terakota, planowanie indygo, zapisane szałwia,
// nieaktualna / przerwane wyciszona neutralność, nigdy czerwień.

// MARK: - Barwy makiety

/// Tokeny z `kit.jsx` (`L`). Jasny motyw = liczby z makiety co do wartości;
/// ciemny = te same role na palecie aplikacji, bo makieta ciemnego nie ma.
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

    static func card(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.05) : Color.white.opacity(0.80) }
    static func cardStroke(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.08) : warmLight.opacity(0.08) }
    /// Białe pola na karcie (kafelek ikony, składnik wiersza).
    static func field(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkDark.opacity(0.06) : Color.white.opacity(0.85) }
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

/// Cień karty z makiety: `0 1px 2px .04, 0 10px 30px -14px rgba(90,50,30,.18)`.
private struct AssistantCardShadow: ViewModifier {
    let enabled: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if enabled, scheme == .light {
            content
                .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
                .shadow(color: Color(red: 90 / 255, green: 50 / 255, blue: 30 / 255).opacity(0.10), radius: 12, y: 8)
        } else {
            content
        }
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
    static let ctaHeight: CGFloat = 48
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
        case .neutral, .indigo: return AssistantLook.card(scheme)
        case .sage: return scheme == .dark ? AssistantLook.card(scheme) : Color.white.opacity(0.86)
        case .muted: return scheme == .dark ? SCPalette.labelDark.opacity(0.03) : Color.white.opacity(0.45)
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

/// Dwie kolumny w stosunku wag — „poboczna 1 : główna 1,4” z makiety.
struct AssistantWeightedRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        // Propozycja bywa `nil` albo nieskończona (sonda „ile chcesz”) —
        // wtedy oddajemy sumę szerokości własnych, NIGDY nieskończoność:
        // nieskończony wymiar ramki wywraca aplikację.
        if let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: height)
        }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
        return CGSize(width: ideal + spacing * CGFloat(max(0, subviews.count - 1)), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let total = weights.prefix(subviews.count).reduce(0, +)
        let free = max(0, bounds.width - spacing * CGFloat(max(0, subviews.count - 1)))
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let weight = index < weights.count ? weights[index] : 1
            let width = total > 0 ? free * weight / total : free / CGFloat(subviews.count)
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }
}

/// Pasek akcji karty. Główna = pełna terakota z białym tekstem (ikona po
/// prawej tylko, gdy podana); poboczna = obrys. Nawigacja = wiersz z chevronem.
struct AssistantCardActions: View {
    enum Style: Equatable {
        case buttons
        case navigation
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
    }

    @ViewBuilder
    private var buttons: some View {
        Group {
            if let primary, let secondary {
                AssistantWeightedRow(weights: [1, 1.4], spacing: 8) {
                    AssistantGhostButton(action: secondary, isBusy: isBusy)
                    AssistantPrimaryButton(action: primary, isBusy: isBusy)
                }
            } else if let primary {
                AssistantPrimaryButton(action: primary, isBusy: isBusy)
            } else if let secondary {
                AssistantGhostButton(action: secondary, isBusy: isBusy)
            }
        }
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

/// Główna akcja: pigułka 48, terakota, biały tekst 15,5/600, ikona po prawej.
struct AssistantPrimaryButton: View {
    let action: AssistantCardAction
    var isBusy: Bool = false
    var height: CGFloat = AssistantCardMetrics.ctaHeight

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action.action) {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(action.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if !isBusy, let icon = action.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule(style: .continuous).fill(AssistantLook.terra(scheme)))
            .shadow(color: AssistantLook.terra(scheme).opacity(scheme == .dark ? 0 : 0.35), radius: 10, y: 6)
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .disabled(isBusy)
    }
}

/// Poboczna akcja: pigułka 48 z obrysem 1,5, ikona po lewej.
struct AssistantGhostButton: View {
    let action: AssistantCardAction
    var isBusy: Bool = false
    var height: CGFloat = AssistantCardMetrics.ctaHeight

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action.action) {
            HStack(spacing: 7) {
                if let icon = action.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(action.title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .tracking(-0.3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(AssistantLook.ink(scheme))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(Capsule(style: .continuous).stroke(AssistantLook.ink(scheme).opacity(0.14), lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .disabled(isBusy)
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
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Otwórz plan", icon: "arrow.right", action: onOpenPlan ?? onUndo),
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

/// Pigułki 40 pt, 15/600 — szybka odpowiedź albo sugestia (nie przycisk
/// tekstowy). `tone: terra` = wyróżniona.
struct AssistantChip: View {
    let title: String
    var icon: String? = nil
    var highlighted: Bool = false
    var dimmed: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.system(size: 15, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(highlighted ? AssistantLook.terra(scheme) : AssistantLook.ink(scheme))
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule().fill(highlighted ? AssistantLook.terraTint(scheme) : AssistantLook.field(scheme).opacity(0.85)))
            .overlay(Capsule().stroke(highlighted ? Color.clear : AssistantLook.ink(scheme).opacity(0.14), lineWidth: 1.5))
            .opacity(dimmed ? 0.45 : 1)
        }
        .buttonStyle(PlanPressStyle(scale: 0.97))
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
#endif
