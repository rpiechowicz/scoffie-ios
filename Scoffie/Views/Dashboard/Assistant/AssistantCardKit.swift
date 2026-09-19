import SwiftUI

// Wspólne atomy kart asystenta — JEDNA rodzina.
//
// Każda karta w rozmowie (propozycja tygodnia, podmiana, lista zakupów,
// briefing na pustym ekranie, wynik nieudanej tury) składa się z tych samych
// klocków w tej samej kolejności: nadtytuł → tytuł → podtytuł → treść →
// podsumowanie → akcje → stan. Liczby (promień, wcięcia, wysokość przycisku)
// stoją w jednym miejscu, więc karta zakupów i karta tygodnia nie mogą się
// od siebie odjechać o dwa punkty.
//
// Reguły akcji:
//   A. jedna akcja — na całą szerokość;
//   B. dwie akcje — wtórna po lewej, główna po prawej, obie 44 pt;
//   C. nawigacja — wiersz z chevronem, bez wypełnienia;
//   D. cofnięcie — akcja wtórna W karcie, nigdy toast.
// Główna akcja marki jest terakotowa; zapis niesie szałwię, analiza indygo,
// stan nieaktualny — przygaszony neutral. Bez czerwieni.

// MARK: - Liczby

enum AssistantCardMetrics {
    static let radius: CGFloat = 20
    /// Wcięcie treści od krawędzi karty.
    static let inset: CGFloat = 16
    static let headTop: CGFloat = 14
    /// Odstęp między sekcjami karty.
    static let section: CGFloat = 12
    static let ctaHeight: CGFloat = 44
    /// Wcięcie paska akcji — mniejsze niż treści, żeby przyciski były szersze.
    static let footerInset: CGFloat = 12
    /// Promień kafli WEWNĄTRZ karty (miniatury, wiersze, paski).
    static let innerRadius: CGFloat = 12
}

// MARK: - Ton

/// Ton karty: neutral = propozycja, sage = zapisane / sukces, indigo =
/// analiza / planowanie, muted = nieaktualne / wygasłe.
enum AssistantTone: Equatable {
    case neutral, sage, indigo, muted

    var accent: Color {
        switch self {
        case .neutral: return SCPalette.terracotta
        case .sage: return SCPalette.sage
        case .indigo: return SCPalette.indigo
        case .muted: return SCPalette.terracotta
        }
    }

    func fill(_ scheme: ColorScheme) -> Color {
        switch self {
        case .neutral: return Color.scCardSurface(scheme)
        case .sage: return Color.scSageTint(scheme)
        case .indigo: return Color.scIndigoTint(scheme)
        case .muted: return Color.scTileBg(scheme)
        }
    }

    func stroke(_ scheme: ColorScheme) -> Color {
        switch self {
        case .neutral: return Color.scCardStroke(scheme)
        case .sage: return SCPalette.sage.opacity(0.24)
        case .indigo: return SCPalette.indigo.opacity(0.26)
        case .muted: return Color.scTileStroke(scheme)
        }
    }
}

// MARK: - Kontener

/// Kontener karty: powierzchnia, obrys, przycięcie. Ton PRZENIKA — zmiana
/// stanu propozycji (czeka → zapisane) nie podmienia karty, tylko jej barwę.
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
            .overlay(shape.stroke(tone.stroke(scheme), lineWidth: 1))
            .clipShape(shape)
            .animation(.easeInOut(duration: 0.25), value: tone)
    }
}

// MARK: - Stan propozycji

/// Stan karty jako TEKST, nie tylko kolor — VoiceOver i osoby nierozróżniające
/// barw dostają to samo, co wszyscy. Liczone z `AgentCardStateDTO` PRZY ODCZYCIE.
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

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .applied: return "checkmark"
        case .undone: return "arrow.uturn.backward"
        case .stale: return "arrow.triangle.2.circlepath"
        case .expired: return "hourglass"
        case .failed: return "exclamationmark"
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
        case .pending: return Color.scMuted(scheme)
        case .applied: return SCPalette.sage
        case .undone, .stale, .expired: return Color.scMuted(scheme)
        case .failed: return SCPalette.terracotta
        }
    }

    /// Zdanie pod stanem: termin, okno cofnięcia, co dalej.
    func note(until: String?) -> String? {
        switch self {
        case .pending:
            return Self.deadline(until).map { "Ważna do \($0)" }
        case .applied:
            return Self.remaining(until).map { "Cofnij możliwe jeszcze \($0)" }
        case .undone:
            return "Możesz zastosować ponownie."
        case .stale:
            return "Plan zmienił się od tej propozycji."
        case .expired:
            return "Poproś o nową — asystent policzy od nowa."
        case .failed:
            return "Plan bez zmian."
        }
    }

    /// „piątku 5.09, 14:20” z ISO; `nil`, gdy serwer nie dał terminu.
    private static func deadline(_ until: String?) -> String? {
        guard let date = AgentStore.parseTimestamp(until) else { return nil }
        return deadlineFormatter.string(from: date)
    }

    /// „52 min” / „2 h” do końca okna cofnięcia; `nil` po jego upływie.
    private static func remaining(_ until: String?) -> String? {
        guard let date = AgentStore.parseTimestamp(until) else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        if seconds < 3600 { return "\(max(1, seconds / 60)) min" }
        return "\(seconds / 3600) h"
    }

    private static let deadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = "EEEE d.MM, HH:mm"
        return formatter
    }()
}

/// Pigułka stanu w nagłówku karty: ikona + słowo.
struct AssistantStatusChip: View {
    let status: AssistantCardStatus

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint = status.tint(scheme)
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 9.5, weight: .bold))
            Text(status.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(-0.1)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(tint.opacity(scheme == .dark ? 0.16 : 0.12)))
        .fixedSize()
        .accessibilityLabel("Stan: \(status.title)")
    }
}

// MARK: - Nagłówek

/// Nadtytuł (co to jest) → tytuł (co z tego wynika) → opcjonalny podtytuł
/// (dlaczego). Po prawej miejsce na pigułkę stanu albo plakietkę.
struct AssistantCardHead<Right: View>: View {
    let eyebrow: String
    /// Drugi wiersz nadtytułu — data albo zakres. Osobno, nie doklejone
    /// kropką: „PROPOZYCJA PLANU · 31 SIERPNIA – 6 WRZEŚNIA” łamie się
    /// w środku nazwy miesiąca.
    var eyebrowDetail: String?
    var eyebrowColor: Color = SCPalette.terracotta
    let title: String
    var subtitle: String?
    @ViewBuilder var right: () -> Right

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(eyebrowColor)
                        .lineLimit(1)

                    if let eyebrowDetail, !eyebrowDetail.isEmpty {
                        Text(eyebrowDetail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.scMuted(scheme))
                            .lineLimit(1)
                    }

                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.35)
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                right()
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .tracking(-0.15)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AssistantCardMetrics.inset)
        .padding(.top, AssistantCardMetrics.headTop)
        .padding(.bottom, AssistantCardMetrics.section)
    }
}

extension AssistantCardHead where Right == EmptyView {
    init(
        eyebrow: String,
        eyebrowDetail: String? = nil,
        eyebrowColor: Color = SCPalette.terracotta,
        title: String,
        subtitle: String? = nil
    ) {
        self.init(
            eyebrow: eyebrow,
            eyebrowDetail: eyebrowDetail,
            eyebrowColor: eyebrowColor,
            title: title,
            subtitle: subtitle
        ) { EmptyView() }
    }
}

extension AssistantCardHead where Right == AssistantStatusChip {
    /// Nagłówek z pigułką stanu po prawej — dla każdej propozycji.
    init(
        eyebrow: String,
        eyebrowDetail: String? = nil,
        eyebrowColor: Color = SCPalette.terracotta,
        title: String,
        subtitle: String? = nil,
        status: AssistantCardStatus
    ) {
        self.init(
            eyebrow: eyebrow,
            eyebrowDetail: eyebrowDetail,
            eyebrowColor: eyebrowColor,
            title: title,
            subtitle: subtitle
        ) { AssistantStatusChip(status: status) }
    }
}

// MARK: - Sekcje

/// Kreska oddzielająca sekcje karty — jedna grubość, jeden kolor.
struct AssistantCardRule: View {
    var leadingInset: CGFloat = 0

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(Color.scRule(scheme))
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}

/// Etykieta sekcji wewnątrz karty: „POWÓD PROPOZYCJI”, „TERAZ”.
struct AssistantCardLabel: View {
    let text: String
    var color: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color ?? Color.scFaint(scheme))
            .lineLimit(1)
    }
}

/// Wiersz podsumowania: opis po lewej, wartość po prawej.
struct AssistantCardSummaryRow: View {
    let label: String
    let value: String
    var valueColor: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12.5))
                .tracking(-0.15)
                .foregroundStyle(Color.scMuted(scheme))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? Color.scLabel(scheme))
        }
    }
}

/// Miniatura dania w wierszu — 28…52 pt, z tym samym zapasem bez zdjęcia.
struct AssistantThumbnail: View {
    let url: URL?
    var size: CGFloat = 32
    var dimmed: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    Color.scInsetSurface(scheme)
                    Image(systemName: "fork.knife")
                        .font(.system(size: size * 0.36))
                        .foregroundStyle(Color.scFaint(scheme))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.25), style: .continuous))
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityHidden(true)
    }
}

/// Pasek postępu z kreską celu — jedna geometria dla kalorii i makr.
///
/// Kreska celu jest częścią informacji: bez niej pasek mówi „ile”, ale nie
/// „ile powinno”. Zapas 1,25× zostawia miejsce na przekroczenie.
struct AssistantTargetBar: View {
    let value: Int
    let target: Int?
    var color: Color = SCPalette.terracotta
    var height: CGFloat = 7

    private static let headroom = 1.25

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            let full = target.map { Double($0) * Self.headroom } ?? Double(max(value, 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.scBarTrack(scheme))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(Double(value) / max(full, 1), 1))
                if target != nil {
                    Rectangle()
                        .fill(Color.scLabel(scheme).opacity(0.85))
                        .frame(width: 2)
                        .offset(x: geometry.size.width / Self.headroom - 1)
                }
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

/// Pasek akcji karty. Jedna akcja = pełna szerokość; dwie = wtórna po lewej,
/// główna po prawej; nawigacja = wiersz z chevronem.
struct AssistantCardActions: View {
    enum Style: Equatable {
        /// Wypełnione kapsuły.
        case buttons
        /// Wiersz nawigacyjny: tytuł + chevron, bez wypełnienia.
        case navigation
    }

    let primary: AssistantCardAction
    var secondary: AssistantCardAction? = nil
    var tone: AssistantTone = .neutral
    var style: Style = .buttons
    var isBusy: Bool = false
    /// Kreska nad akcjami — wyłączana, gdy sekcja wyżej sama ją rysuje.
    var showsRule: Bool = true
    /// Akcja główna WYPEŁNIONA akcentem z białym tekstem — dla jedynej akcji
    /// na ekranie (briefing). W rozmowie zostaje wariant „soft”, bo pełna
    /// terakota pod każdą odpowiedzią byłaby jedynym nasyconym punktem ekranu.
    var filledPrimary: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            switch style {
            case .buttons: buttons
            case .navigation: navigation
            }
        }
        .overlay(alignment: .top) {
            if showsRule { AssistantCardRule() }
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if let secondary {
                secondaryButton(secondary)
            }
            primaryButton
        }
        .padding(AssistantCardMetrics.footerInset)
    }

    private var navigation: some View {
        Button(action: primary.action) {
            HStack(spacing: 8) {
                if let icon = primary.icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone.accent)
                }
                Text(primary.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Color.scLabel(scheme))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.scFaint(scheme))
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .disabled(isBusy)
    }

    private var primaryButton: some View {
        Button(action: primary.action) {
            HStack(spacing: 7) {
                if isBusy {
                    ProgressView().controlSize(.small).tint(filledPrimary ? .white : tone.accent)
                } else if let icon = primary.icon, !filledPrimary {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
                Text(primary.title)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.25)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if filledPrimary, let icon = primary.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(filledPrimary ? Color.white : tone.accent)
            .frame(maxWidth: .infinity)
            .frame(height: filledPrimary ? 52 : AssistantCardMetrics.ctaHeight)
            .background {
                if filledPrimary {
                    Capsule(style: .continuous)
                        .fill(SCPalette.terracottaDeep)
                        .shadow(color: SCPalette.terracotta.opacity(0.28), radius: 10, y: 5)
                }
            }
            .modifier(SoftUnlessFilled(filled: filledPrimary, accent: tone.accent))
        }
        .buttonStyle(PlanPressStyle(scale: 0.985))
        .disabled(isBusy)
    }

    /// Kapsuła „soft” tylko dla wariantu niewypełnionego.
    private struct SoftUnlessFilled: ViewModifier {
        let filled: Bool
        let accent: Color

        func body(content: Content) -> some View {
            if filled {
                content
            } else {
                content.scSoftCapsule(accent)
            }
        }
    }

    private func secondaryButton(_ action: AssistantCardAction) -> some View {
        Button(action: action.action) {
            HStack(spacing: 6) {
                if let icon = action.icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.scMuted(scheme))
                }
                Text(action.title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Color.scLabel(scheme))
            }
            .padding(.horizontal, 16)
            .frame(height: AssistantCardMetrics.ctaHeight)
            .background(Capsule().fill(Color.scTileBg(scheme)))
            .overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

/// Zdanie o stanie nad akcjami — tylko, gdy stan coś zmienia w tym, co da
/// się zrobić (termin, okno cofnięcia, „plan się zmienił”).
struct AssistantStateNote: View {
    let status: AssistantCardStatus
    let until: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let note = status.note(until: until) {
            HStack(spacing: 7) {
                Image(systemName: status.icon)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(status.tint(scheme))
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AssistantCardMetrics.inset)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .overlay(alignment: .top) { AssistantCardRule() }
        }
    }
}

/// Stopka propozycji: notka stanu + akcje zależne od stanu.
///
/// Karta w historii jest STEROWNIKIEM, nie zdjęciem — ten sam korpus, a stan
/// z serwera decyduje, co da się kliknąć:
///   PENDING  → „Zmień coś” | „Dodaj do planu”
///   APPLIED  → „Cofnij”    | „Otwórz plan”
///   UNDONE   → „Zastosuj ponownie”
///   FAILED   → „Spróbuj ponownie”
///   STALE    → „Zapisz mimo to” | „Odśwież propozycję”
///   EXPIRED  → „Odśwież propozycję”
struct AssistantProposalFooter: View {
    let state: AgentCardStateDTO
    let applyLabel: String
    var applyIcon: String? = "checkmark"
    var reviseLabel: String = "Zmień coś"
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
                secondary: AssistantCardAction(title: reviseLabel, action: onRevise),
                tone: .neutral,
                isBusy: isBusy
            )
        case .applied where state.canUndo:
            if let onUndo {
                AssistantCardActions(
                    primary: AssistantCardAction(
                        title: "Otwórz plan",
                        icon: "arrow.right",
                        action: onOpenPlan ?? onUndo
                    ),
                    secondary: AssistantCardAction(title: "Cofnij", icon: "arrow.uturn.backward", action: onUndo),
                    tone: .sage,
                    isBusy: isBusy
                )
            }
        case .undone where state.canApply:
            AssistantCardActions(
                primary: AssistantCardAction(title: "Zastosuj ponownie", icon: "checkmark") { onApply(false) },
                isBusy: isBusy
            )
        case .failed where state.canApply:
            AssistantCardActions(
                primary: AssistantCardAction(title: "Spróbuj ponownie", icon: "arrow.clockwise") { onApply(false) },
                isBusy: isBusy
            )
        case .stale where state.canApply:
            AssistantCardActions(
                primary: AssistantCardAction(title: "Odśwież propozycję", icon: "arrow.triangle.2.circlepath", action: onAskNew),
                secondary: AssistantCardAction(title: "Zapisz mimo to") { onApply(true) },
                isBusy: isBusy
            )
        case .stale, .expired:
            AssistantCardActions(
                primary: AssistantCardAction(title: "Odśwież propozycję", icon: "arrow.triangle.2.circlepath", action: onAskNew),
                isBusy: isBusy
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - Szybkie odpowiedzi

/// Podpowiedzi kolejnego ruchu — chipy w kolorze marki.
struct AssistantQuickReplies: View {
    let items: [String]
    var alignment: HorizontalAlignment = .leading
    let onTap: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AllergenChipFlow(spacing: 7, alignment: alignment) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.system(size: 13.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(SCPalette.terracotta)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.scAccentTint(scheme).opacity(0.5)))
                        .overlay(Capsule().stroke(SCPalette.terracotta.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
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
                    eyebrow: "Propozycja planu",
                    eyebrowDetail: "22–28 września",
                    title: "Obiad i kolacja na tydzień",
                    subtitle: "Nic się nie powtarza, a wtorek jest szybki.",
                    status: .pending
                )
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Dodaj do planu", icon: "checkmark") {},
                    secondary: AssistantCardAction(title: "Zmień coś") {}
                )
            }
            AssistantCard(tone: .sage) {
                AssistantCardHead(eyebrow: "Zapisane", title: "Plan tygodnia zapisany", status: .applied)
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Otwórz plan", icon: "arrow.right") {},
                    secondary: AssistantCardAction(title: "Cofnij", icon: "arrow.uturn.backward") {},
                    tone: .sage
                )
            }
            AssistantCard(tone: .muted) {
                AssistantCardHead(eyebrow: "Propozycja planu", title: "Obiady na tydzień", status: .stale)
                AssistantStateNote(status: .stale, until: nil)
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Odśwież propozycję", icon: "arrow.triangle.2.circlepath") {},
                    secondary: AssistantCardAction(title: "Zapisz mimo to") {},
                    showsRule: false
                )
            }
            AssistantCard {
                AssistantCardHead(eyebrow: "Lista zakupów", title: "4 rzeczy do kupienia")
                AssistantCardActions(
                    primary: AssistantCardAction(title: "Otwórz listę", icon: "cart") {},
                    style: .navigation
                )
            }
        }
        .padding(20)
    }
    .background(SCPageBackground(scheme: .light).ignoresSafeArea())
}
#endif
