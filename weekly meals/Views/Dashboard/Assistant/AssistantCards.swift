import SwiftUI

// Karty asystenta — propozycja tygodnia, propozycja dnia, pytanie
// i potwierdzenie zapisu.
//
// Cała treść przychodzi z serwera GOTOWA: nazwy dni, etykiety posiłków,
// napisy na przyciskach, liczby, zdania o celu. Ten plik jej nie liczy
// i nie tłumaczy — układa ją i decyduje, co się dzieje po dotknięciu.
// Dzięki temu nowy rodzaj karty po stronie serwera nie wymaga wydania
// aplikacji, a stary build nie pokaże nigdy liczby, której serwer już nie uznaje.

// MARK: - Wspólne atomy kart

/// Nadtytuł karty. Gdy serwer go nie przysłał (starszy build kontraktu),
/// zostaje wartość zapasowa — karta bez nadtytułu wygląda na niedokończoną.
private struct CardEyebrowFallback {
    static let planWeek = "Propozycja planu"
    static let planDay = "Propozycja dnia"
}

/// Wiersz posiłku: etykieta slotu w stałej kolumnie, nazwa dania obok.
///
/// Stała szerokość kolumny jest tu informacją, nie ozdobą: siedem dni
/// czyta się w pionie i nazwy dań muszą zaczynać się w jednej linii,
/// inaczej wzrok szuka ich od nowa przy każdym wierszu.
private struct MealLine: View {
    let slot: String
    let title: String
    var imageUrl: String?
    var dimmed: Bool = false

    /// Szerokość kolumny slotu.
    ///
    /// Stała, bo nazwy dań mają zaczynać się w jednej linii — inaczej wzrok
    /// szuka ich od nowa przy każdym wierszu. Musi zmieścić najdłuższą
    /// etykietę („II ŚNIADANIE”) bez łamania: złamane „ŚNIADANI/E” wyglądało
    /// jak błąd, a nie jak etykieta.
    private static let slotColumn: CGFloat = 84

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            thumbnail

            Text(slot)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.wmFaint(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: Self.slotColumn, alignment: .leading)

            // Dwie linie, bo „Dorsz pieczony z ziemniakami i surówką" ucięty
            // w połowie nie mówi, co się je — a to jedyne, po co ten wiersz jest.
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(dimmed ? Color.wmMuted(scheme) : Color.wmLabel(scheme))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    /// Miniatura dania — wzrokowy skrót do „co to właściwie jest".
    ///
    /// 28 px: tyle, żeby rozpoznać kolor i kształt potrawy, i nie tyle, żeby
    /// wiersz przestał być wierszem. Bez zdjęcia zostaje sam znak sztućców —
    /// puste miejsce rozjeżdżałoby kolumnę z nazwami.
    private var thumbnail: some View {
        let url = imageUrl.flatMap(URL.init(string:))
        return CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                ZStack {
                    Color.wmInsetSurface(scheme)
                    Image(systemName: "fork.knife")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.wmFaint(scheme))
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .opacity(dimmed ? 0.55 : 1)
    }
}

/// Pasek celu: gdzie plan ląduje wobec normy.
///
/// Kreska celu jest częścią informacji — bez niej pasek mówi „ile", ale nie
/// „ile powinno", a to jest cała treść tego elementu.
private struct TargetBar: View {
    let label: String
    let value: Int
    let target: Int?
    let note: String?

    /// Ile ponad cel jeszcze mieści się w pasku. 1,25× zostawia miejsce na
    /// przekroczenie i nie spłaszcza typowego wyniku do połowy szerokości.
    private static let headroom = 1.25

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12.5))
                    .tracking(-0.15)
                    .foregroundStyle(Color.wmMuted(scheme))
                Spacer(minLength: 8)
                Text("\(value)")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(Color.wmLabel(scheme))
            }

            if let target, target > 0 {
                GeometryReader { geometry in
                    let full = Double(target) * Self.headroom
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.wmBarTrack(scheme))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [WMPalette.terracottaDeep, WMPalette.terracotta],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * min(Double(value) / full, 1))
                        Rectangle()
                            .fill(Color.wmLabel(scheme).opacity(0.85))
                            .frame(width: 2)
                            .offset(x: geometry.size.width / Self.headroom)
                    }
                }
                .frame(height: 7)

                HStack {
                    Text("Twój cel \(target) kcal")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmFaint(scheme))
                    Spacer(minLength: 8)
                    if let note {
                        Text(note)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WMPalette.sage)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }
}

/// „Zniknie z planu” — zmiana planu nigdy nie jest cicha.
private struct RemovalsSection: View {
    let removals: [PlanWeekCardRemovalDTO]
    /// Karta dnia mówi o jednym dniu, więc powtarzanie w niej nazwy dnia
    /// przy każdej pozycji jest szumem.
    var showsDay: Bool = true

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                Text("Zniknie z planu · \(removals.count)")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.1)
                    .textCase(.uppercase)
            }
            .foregroundStyle(WMPalette.terracotta)

            // Powód po prawej („powtórka”, „ponad cel”) to jedno słowo od
            // modelu — bez niego zniknięcie dania wygląda na przypadek.
            ForEach(removals) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line(for: item))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .strikethrough(true, color: Color.wmStrike(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let reason = item.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.wmFaint(scheme))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(WMPalette.terracotta.opacity(scheme == .dark ? 0.08 : 0.05))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }

    private func line(for item: PlanWeekCardRemovalDTO) -> String {
        showsDay
            ? "\(item.dayLabel), \(item.mealLabel.lowercased()): \(item.title)"
            : "\(item.mealLabel): \(item.title)"
    }
}

/// Karta, w której nie ma już czego kliknąć — z powodem.
///
/// Sam wyszarzony przycisk mówiłby „nie da się" i nic więcej. Tydzień
/// zmieniony przez kogoś w domu, wygaśnięcie i zapis to trzy różne historie
/// i tylko po nazwie tej właściwej wiadomo, co zrobić dalej.
struct AssistantCardStatusFooter: View {
    let state: AgentCardStateDTO

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.wmMuted(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }

    private var icon: String {
        switch state.status {
        case "APPLIED": return "checkmark.circle.fill"
        case "UNDONE": return "arrow.uturn.backward.circle"
        default: return "clock.badge.exclamationmark"
        }
    }

    private var tint: Color {
        switch state.status {
        case "APPLIED": return WMPalette.sage
        case "UNDONE": return Color.wmFaint(scheme)
        default: return WMPalette.butter
        }
    }

    private var text: String {
        switch state.status {
        case "APPLIED": return "Ta propozycja jest już w planie."
        case "UNDONE": return "Zapis został cofnięty."
        case "STALE": return "Plan zmienił się od czasu tej propozycji."
        case "EXPIRED": return "Ta propozycja jest już nieaktualna."
        case "FAILED": return "Tej propozycji nie udało się zapisać."
        default: return "Tej propozycji nie da się już zatwierdzić."
        }
    }
}

// MARK: - Propozycja tygodnia

/// Propozycja planu — tydzień do obejrzenia, zanim cokolwiek się zapisze.
///
/// Przycisk jest W KARCIE, a nie na dole ekranu: użytkownik zatwierdza TO,
/// na co właśnie patrzy, i po tygodniu w historii dalej widać, co dokładnie
/// zostało zatwierdzone.
struct AssistantPlanWeekCard: View {
    let card: PlanWeekCardDTO
    let isBusy: Bool
    /// `force` = „Zapisz mimo to” przy propozycji nieaktualnej.
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil

    /// Ile dni widać przed rozwinięciem. Trzy, bo tyle mieści się na ekranie
    /// bez przewijania — a karta ma być do ogarnięcia jednym spojrzeniem.
    private static let previewDays = 3

    @State private var isExpanded = false
    @Environment(\.colorScheme) private var scheme

    private var visibleDays: [PlanWeekCardDayDTO] {
        isExpanded ? card.days : Array(card.days.prefix(Self.previewDays))
    }

    private var hiddenDaysCount: Int {
        max(0, card.days.count - Self.previewDays)
    }

    var body: some View {
        AssistantCard(tone: .neutral) {
            AssistantCardHead(
                eyebrow: card.eyebrow ?? CardEyebrowFallback.planWeek,
                eyebrowDetail: card.eyebrowDetail,
                title: card.title
            ) {
                mealsBadge
            }

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                ForEach(visibleDays) { day in
                    DayBlock(day: day)
                        .overlay(alignment: .top) {
                            if day.id != visibleDays.first?.id {
                                Rectangle()
                                    .fill(Color.wmRule(scheme))
                                    .frame(height: 1)
                                    .padding(.leading, 16)
                            }
                        }
                }
            }

            if hiddenDaysCount > 0 {
                expandButton
            }

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed)
            }

            TargetBar(
                label: "Średnio dziennie",
                value: card.summary.averageKcalPerDay,
                target: card.summary.targetKcalPerDay,
                note: card.summary.goalNote
            )

            footer
        }
    }

    private var mealsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "fork.knife")
                .font(.system(size: 10, weight: .semibold))
            Text("\(card.summary.meals)")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(Color.wmMuted(scheme))
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(Color.wmChipBg(scheme)))
    }

    private var expandButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(isExpanded ? "Pokaż mniej" : "Pokaż pozostałe dni")
                    .font(.system(size: 13.5, weight: .semibold))
                    .tracking(-0.2)
                if !isExpanded {
                    Text("\(hiddenDaysCount)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .opacity(0.7)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(WMPalette.terracotta)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        AssistantProposalFooter(
            state: card.state,
            applyLabel: applyLabel,
            reviseLabel: "Zmień",
            isBusy: isBusy,
            onApply: onApply,
            onRevise: onRevise,
            onAskNew: onAskNew,
            onUndo: onUndo
        )
    }

    private var applyLabel: String {
        card.actions.first { $0.kind == .apply }?.label ?? "Dodaj do planu"
    }

    private struct DayBlock: View {
        let day: PlanWeekCardDayDTO

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(day.shortName)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(-0.1)
                        .foregroundStyle(Color.wmLabel(scheme))
                    if let dateLabel = day.dateLabel {
                        Text(dateLabel)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.wmFaint(scheme))
                    }
                    Spacer(minLength: 8)
                    if day.kcalTotal > 0 {
                        Text("\(day.kcalTotal) kcal")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Color.wmFaint(scheme))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(day.slots) { slot in
                        MealLine(
                            slot: slot.mealLabel,
                            title: slot.title,
                            imageUrl: slot.imageUrl,
                            // Wyszarzone jest to, co ZOSTAJE — wzrok ma
                            // trafiać w to, co propozycja naprawdę zmienia.
                            dimmed: !slot.isNew
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 9)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Propozycja dnia

/// Jeden dzień: posiłek po posiłku, z sumą wobec celu.
///
/// Tydzień pokazuje układ, dzień pokazuje talerz — dlatego to osobna karta,
/// a nie tydzień z jednym wierszem.
struct AssistantPlanDayCard: View {
    let card: PlanDayCardDTO
    let isBusy: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil

    /// Kolory pasków przy posiłkach — kolejność dnia, nie znaczenie.
    /// Poranek jest ciepły, wieczór chłodny; to jedyna treść tego koloru.
    private static let rails: [Color] = [
        WMPalette.butter, WMPalette.terracotta, WMPalette.indigo, WMPalette.sage,
    ]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard(tone: .neutral) {
            AssistantCardHead(
                eyebrow: card.eyebrow ?? CardEyebrowFallback.planDay,
                eyebrowDetail: card.eyebrowDetail,
                title: card.title
            ) {
                EmptyView()
            }

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.wmMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 0) {
                ForEach(Array(card.slots.enumerated()), id: \.element.id) { index, slot in
                    MealRow(
                        slot: slot,
                        rail: Self.rails[index % Self.rails.count]
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.wmRule(scheme))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }

            if !card.removed.isEmpty {
                RemovalsSection(removals: card.removed, showsDay: false)
            }

            total

            footer
        }
    }

    /// „Razem 1 872 z 2 100 kcal” — jedna linia, która odpowiada na pytanie,
    /// po które użytkownik otworzył tę kartę.
    private var total: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(totalLabel)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmMuted(scheme))

                if let target = card.summary.targetKcalPerDay, target > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.wmBarTrack(scheme))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [WMPalette.terracottaDeep, WMPalette.terracotta],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geometry.size.width
                                        * min(Double(card.summary.kcalTotal) / Double(target), 1)
                                )
                        }
                    }
                    .frame(height: 7)
                }
            }

            if let note = card.summary.goalNote {
                Text(note)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(WMPalette.sage)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.wmSageTint(scheme)))
                    .overlay(Capsule().stroke(WMPalette.sage.opacity(0.24), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }

    private var totalLabel: String {
        guard let target = card.summary.targetKcalPerDay, target > 0 else {
            return "Razem \(card.summary.kcalTotal) kcal"
        }
        return "Razem \(card.summary.kcalTotal) z \(target) kcal"
    }

    private var footer: some View {
        AssistantProposalFooter(
            state: card.state,
            applyLabel: applyLabel,
            reviseLabel: "Inny zestaw",
            reviseIcon: "arrow.triangle.2.circlepath",
            isBusy: isBusy,
            onApply: onApply,
            onRevise: onRevise,
            onAskNew: onAskNew,
            onUndo: onUndo
        )
    }

    private var applyLabel: String {
        card.actions.first { $0.kind == .apply }?.label ?? "Zapisz dzień"
    }

    private struct MealRow: View {
        let slot: PlanWeekCardSlotDTO
        let rail: Color

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Capsule()
                    .fill(rail.opacity(0.85))
                    .frame(width: 3)

                CachedAsyncImage(url: slot.imageUrl.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            Color.wmInsetSurface(scheme)
                            Image(systemName: "fork.knife")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.wmFaint(scheme))
                        }
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.mealLabel)
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.7)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.wmFaint(scheme))

                    Text(slot.title)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.25)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if slot.prepTimeMinutes > 0 {
                        Text("\(slot.prepTimeMinutes) min")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.wmMuted(scheme))
                    }
                }

                Spacer(minLength: 8)

                if slot.kcalPerServing > 0 {
                    Text("\(slot.kcalPerServing)")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmLabel(scheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pytanie z gotowymi odpowiedziami

/// Pytanie, które da się odpowiedzieć dotknięciem.
///
/// Nie jest kartą w ramce, tylko wiadomością z pionową kreską — bo to wciąż
/// wypowiedź asystenta, a nie zestawienie danych. Odpowiedzi wysyłają się jak
/// zwykłe wiadomości, więc w historii zostaje to, co użytkownik „powiedział".
struct AssistantClarifyCard: View {
    let card: ClarifyCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(WMPalette.butter.opacity(0.8))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.question)
                        .font(.system(size: 15.5))
                        .foregroundStyle(Color.wmLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)

                    if let hint = card.hint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 13))
                            .tracking(-0.15)
                            .foregroundStyle(Color.wmMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            AssistantAnswerChips(actions: card.actions, onAsk: onAsk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Gotowe odpowiedzi jako przyciski. Pierwsza jest wyróżniona, bo model
/// wymienia je od najbardziej prawdopodobnej — cztery równorzędne przyciski
/// oddawałyby decyzję z powrotem użytkownikowi.
struct AssistantAnswerChips: View {
    let actions: [AgentCardActionDTO]
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AllergenChipFlow(spacing: 7) {
            ForEach(actions) { action in
                Button {
                    onAsk(action.prompt ?? action.label)
                } label: {
                    Text(action.label)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(
                            action.isPrimary ? WMPalette.butter : Color.wmLabel(scheme)
                        )
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(
                            Capsule().fill(
                                action.isPrimary
                                    ? Color.wmButterTint(scheme)
                                    : Color.wmTileBg(scheme)
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                action.isPrimary
                                    ? WMPalette.butter.opacity(0.34)
                                    : Color.wmTileStroke(scheme),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Potwierdzenie zapisu

/// „Zapisano" z „Cofnij" — w WIADOMOŚCI, nie w toaście.
///
/// Toast znika po trzech sekundach i zabiera ze sobą jedyną drogę odwrotu.
/// Wiadomość zostaje w rozmowie, więc cofnięcie jest tam, gdzie użytkownik
/// będzie go szukał: przy zmianie, która go zaskoczyła.
struct AssistantAppliedCard: View {
    let card: AppliedCardDTO
    let isBusy: Bool
    let onUndo: () -> Void
    let onOpenPlan: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var undoAction: AgentCardActionDTO? {
        card.actions.first { $0.kind == .undo }
    }

    var body: some View {
        AssistantCard(tone: .sage) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(WMPalette.sage.opacity(0.22))
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(WMPalette.sage)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))

                    if let subtitle = card.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .tracking(-0.15)
                            .foregroundStyle(Color.wmMuted(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            ForEach(card.notes, id: \.self) { note in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmFaint(scheme))
                        .padding(.top, 1)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            actions
        }
    }

    /// Przyciski karty zapisu są SPOKOJNE — pełny terakotowy guzik krzyczałby
    /// o coś, co już się stało. „Cofnij" jest obok, ale nie wyżej: cofanie ma
    /// być łatwe do znalezienia, nie łatwiejsze niż otwarcie planu.
    private var actions: some View {
        HStack(spacing: 8) {
            if card.state.canUndo, let undoAction {
                Button(action: onUndo) {
                    HStack(spacing: 6) {
                        if isBusy {
                            ProgressView().controlSize(.small).tint(Color.wmMuted(scheme))
                        } else {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.wmMuted(scheme))
                        }
                        Text(undoAction.label)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.wmLabel(scheme))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.wmTileBg(scheme)))
                    .overlay(Capsule().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            Button(action: onOpenPlan) {
                HStack(spacing: 6) {
                    Text(openPlanLabel)
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(WMPalette.sage)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(WMPalette.sage.opacity(0.18)))
                .overlay(Capsule().stroke(WMPalette.sage.opacity(0.34), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var openPlanLabel: String {
        card.actions.first { $0.kind == .openPlan }?.label ?? "Otwórz Plan tygodnia"
    }
}

// MARK: - Dania do wyboru

/// Kilka dań jako kafelki — pytanie zadane obrazkami.
///
/// Karuzela, a nie lista: wybór z trzech zdjęć trwa sekundę, a ta sama treść
/// w pionie zajmuje pół ekranu i zmusza do czytania. Karta nie ma stanu —
/// dotknięcie wysyła wiadomość, a nie zapisuje plan.
struct AssistantOptionsCard: View {
    let card: OptionsCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.eyebrow)
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(WMPalette.terracotta)

                Text(card.title)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.35)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(card.options) { option in
                        OptionTile(option: option) { onAsk(option.prompt) }
                    }
                }
                // Karuzela sięga poza margines rozmowy, żeby ostatni kafelek
                // był ucięty krawędzią ekranu — to jedyny sygnał, że da się
                // przewinąć, jaki działa bez paska przewijania.
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()

            if !card.actions.isEmpty {
                AssistantAnswerChips(actions: card.actions, onAsk: onAsk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct OptionTile: View {
        let option: OptionsCardItemDTO
        let onTap: () -> Void

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    cover

                    VStack(alignment: .leading, spacing: 7) {
                        Text(option.title)
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.wmLabel(scheme))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .frame(height: 34, alignment: .top)

                        HStack(spacing: 8) {
                            Label {
                                Text("\(option.kcalPerServing)")
                                    .monospacedDigit()
                            } icon: {
                                Image(systemName: "flame")
                                    .foregroundStyle(WMPalette.terracotta)
                            }

                            if option.prepTimeMinutes > 0 {
                                Label {
                                    Text("\(option.prepTimeMinutes)′")
                                        .monospacedDigit()
                                } icon: {
                                    Image(systemName: "clock")
                                        .foregroundStyle(Color.wmMuted(scheme))
                                }
                            }
                        }
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.wmMuted(scheme))

                        if let tag = option.tag, !tag.isEmpty {
                            Text(tag)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(WMPalette.sage)
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(Capsule().fill(Color.wmSageTint(scheme)))
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.top, 9)
                    .padding(.bottom, 11)
                }
                .frame(width: 152, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.wmCardSurface(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.wmCardStroke(scheme), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }

        @ViewBuilder
        private var cover: some View {
            let url = option.imageUrl.flatMap(URL.init(string:))
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    // Bez zdjęcia kafelek nie zapada się do samego tekstu:
                    // wysokość zostaje, żeby karuzela nie skakała w pionie.
                    ZStack {
                        Color.wmInsetSurface(scheme)
                        Image(systemName: "fork.knife")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.wmFaint(scheme))
                    }
                }
            }
            .frame(width: 152, height: 92)
            .clipped()
        }
    }
}

// MARK: - Podmiana

/// Co znika i co wchodzi — z różnicą, dla której o podmianę poproszono.
struct AssistantSwapCard: View {
    let card: SwapCardDTO
    let isBusy: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard(tone: .neutral) {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title) {
                EmptyView()
            }

            VStack(spacing: 0) {
                if let from = card.from {
                    SideRow(side: from, isOutgoing: true)
                }
                SideRow(side: card.to, isOutgoing: false)
            }
            .padding(.horizontal, 16)

            if !card.deltas.isEmpty {
                deltas
            }

            footer
        }
    }

    private var deltas: some View {
        AllergenChipFlow(spacing: 6) {
            ForEach(card.deltas) { delta in
                HStack(spacing: 5) {
                    Text(delta.value)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(delta.good ? WMPalette.sage : Color.wmMuted(scheme))
                    Text(delta.label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(
                            delta.good ? WMPalette.sage.opacity(0.8) : Color.wmFaint(scheme)
                        )
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    Capsule().fill(
                        delta.good ? Color.wmSageTint(scheme) : Color.wmChipBg(scheme)
                    )
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        AssistantProposalFooter(
            state: card.state,
            applyLabel: applyLabel,
            applyIcon: "arrow.triangle.2.circlepath",
            reviseLabel: "Inne",
            reviseIcon: "ellipsis",
            isBusy: isBusy,
            onApply: onApply,
            onRevise: onRevise,
            onAskNew: onAskNew,
            onUndo: onUndo
        )
    }

    private var applyLabel: String {
        card.actions.first { $0.kind == .apply }?.label ?? "Podmień"
    }

    /// Wiersz jednej strony podmiany. To, co znika, jest przekreślone
    /// i wyszarzone — inaczej obie linie wyglądają jak dwa dania do wyboru.
    private struct SideRow: View {
        let side: SwapCardSideDTO
        let isOutgoing: Bool

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isOutgoing ? "xmark" : "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOutgoing ? Color.wmFaint(scheme) : WMPalette.sage)
                    .frame(width: 16)

                Text(side.title)
                    .font(.system(size: 14, weight: isOutgoing ? .regular : .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(isOutgoing ? Color.wmFaint(scheme) : Color.wmLabel(scheme))
                    .strikethrough(isOutgoing, color: Color.wmStrike(scheme))
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text(detail)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(isOutgoing ? Color.wmFaint(scheme) : Color.wmLabel(scheme))
            }
            .padding(.vertical, 10)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
            }
        }

        private var detail: String {
            side.prepTimeMinutes > 0
                ? "\(side.kcalPerServing) · \(side.prepTimeMinutes)′"
                : "\(side.kcalPerServing)"
        }
    }
}

// MARK: - Jedno danie, kilka talerzy

/// Podział wspólnego dania na porcje.
///
/// Karta odpowiada na pytanie, którego nie da się zadać planowi tygodnia:
/// „ugotuję jedno, ale jak to podać czterem osobom z czterema różnymi celami".
/// Cel obok imienia pochodzi z profilu — to jedyna rzecz, po której użytkownik
/// pozna, że asystent naprawdę je przeczytał.
struct AssistantHouseholdSplitCard: View {
    let card: HouseholdSplitCardDTO
    let isBusy: Bool
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    let onAskNew: () -> Void
    var onUndo: (() -> Void)? = nil

    /// Kolor osoby jest STAŁY w obrębie karty i bierze się z pozycji na
    /// liście — nie niesie znaczenia, tylko pozwala odróżnić wiersze wzrokiem.
    private static let avatarColors: [Color] = [
        WMPalette.terracotta, WMPalette.indigo, WMPalette.sage, WMPalette.butter,
    ]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard(tone: .neutral) {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title) {
                if card.prepTimeMinutes > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(card.prepTimeMinutes)′")
                            .font(.system(size: 11.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color.wmMuted(scheme))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.wmChipBg(scheme)))
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(card.portions.enumerated()), id: \.element.id) { index, portion in
                    PortionRow(
                        portion: portion,
                        tint: Self.avatarColors[index % Self.avatarColors.count]
                    )
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.wmRule(scheme))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }

            footer
        }
    }

    private var footer: some View {
        AssistantProposalFooter(
            state: card.state,
            applyLabel: card.actions.first { $0.kind == .apply }?.label ?? "Zapisz",
            reviseLabel: "Zmień",
            isBusy: isBusy,
            onApply: onApply,
            onRevise: onRevise,
            onAskNew: onAskNew,
            onUndo: onUndo
        )
    }

    private struct PortionRow: View {
        let portion: HouseholdSplitPortionDTO
        let tint: Color

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    Circle().fill(tint.opacity(0.15))
                    Circle().stroke(tint.opacity(0.33), lineWidth: 1)
                    Text(portion.initial)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(portion.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.25)
                            .foregroundStyle(Color.wmLabel(scheme))
                        Text(portion.goalLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let note = portion.note, !note.isEmpty {
                        Text(note)
                            .font(.system(size: 12.5))
                            .tracking(-0.15)
                            .foregroundStyle(Color.wmMuted(scheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                if portion.kcal > 0 {
                    Text("\(portion.kcal)")
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmLabel(scheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Luka makro

/// Ile brakuje do celu — i co to domknie.
///
/// Indygo, nie terakota: to jest analiza, a nie propozycja do zatwierdzenia.
/// Kolor odróżnia karty, po których coś się dzieje, od tych, które tłumaczą.
struct AssistantMacroGapCard: View {
    let card: MacroGapCardDTO
    let onAsk: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard(tone: .indigo) {
            AssistantCardHead(
                eyebrow: card.eyebrow,
                eyebrowColor: WMPalette.indigo,
                title: card.title
            ) {
                ZStack {
                    Circle().fill(WMPalette.indigo.opacity(0.2))
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(WMPalette.indigo)
                }
                .frame(width: 34, height: 34)
            }

            progress

            if !card.boosters.isEmpty {
                boosters
                boosterNote
            }

            if let action = card.actions.first, let prompt = action.prompt {
                AssistantCardActions(
                    primaryTitle: action.label,
                    primaryIcon: "checkmark",
                    onPrimary: { onAsk(prompt) }
                )
            }
        }
    }

    /// Strzałka wysyła pytanie, nic nie zapisuje — stopka mówi to wprost,
    /// żeby nikt nie szukał w planie zmiany, której nie ma.
    private var boosterNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.wmFaint(scheme))
            Text("Każda strzałka wysyła pytanie — nic nie zapisuje się samo")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.wmFaint(scheme))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.wmBarTrack(scheme))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    WMPalette.indigo.opacity(0.65), WMPalette.indigo,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * card.progress)
                }
            }
            .frame(height: 10)

            HStack {
                Text("\(card.current) \(card.unit) z planu")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmLabel(scheme))
                Spacer(minLength: 8)
                Text("cel \(card.target) \(card.unit)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmMuted(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    private var boosters: some View {
        VStack(spacing: 0) {
            Text("Zapytaj o zmianę")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Color.wmFaint(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 11)
                .padding(.bottom, 4)

            ForEach(Array(card.boosters.enumerated()), id: \.element.id) { index, booster in
                Button { onAsk(booster.askPrompt) } label: {
                    HStack(alignment: .center, spacing: 11) {
                        Text(booster.text)
                            .font(.system(size: 13.5))
                            .tracking(-0.2)
                            .foregroundStyle(Color.wmLabel(scheme))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        Text(booster.amountLabel(unit: card.unit))
                            .font(.system(size: 12.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WMPalette.indigo)

                        ZStack {
                            Circle().fill(WMPalette.indigo.opacity(0.14))
                            Circle().stroke(WMPalette.indigo.opacity(0.28), lineWidth: 1)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(WMPalette.indigo)
                        }
                        .frame(width: 30, height: 30)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    if index > 0 {
                        Rectangle()
                            .fill(Color.wmRule(scheme))
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }
}

// MARK: - Lista zakupów

/// Co trzeba kupić, po działach sklepu.
///
/// Działy nie są ozdobą: listę czyta się chodząc alejkami, a nie w kolejności,
/// w jakiej przepisy trafiły do planu.
struct AssistantShoppingListCard: View {
    let card: ShoppingListCardDTO
    let onOpenShopping: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AssistantCard(tone: .neutral) {
            AssistantCardHead(eyebrow: card.eyebrow, title: card.title) {
                ZStack {
                    Circle().fill(WMPalette.terracotta.opacity(0.16))
                    Image(systemName: "cart")
                        .font(.system(size: 15))
                        .foregroundStyle(WMPalette.terracotta)
                }
                .frame(width: 34, height: 34)
            }

            VStack(spacing: 0) {
                ForEach(card.groups) { group in
                    GroupBlock(group: group)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
                        }
                }
            }
            .padding(.horizontal, 16)

            if let note = card.checkedNote {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WMPalette.sage)
                    Text(note)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.wmMuted(scheme))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 2)
            }

            if let empty = card.emptyDepartments, empty > 0 {
                Text("+ \(empty) \(Self.departmentsWord(empty)) bez pozycji")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wmFaint(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            }

            AssistantCardActions(
                primaryTitle: card.actions.first?.label ?? "Otwórz listę zakupów",
                primaryIcon: "cart",
                onPrimary: onOpenShopping
            )
        }
    }

    static func departmentsWord(_ count: Int) -> String {
        if count == 1 { return "dział" }
        let mod100 = count % 100
        if (12...14).contains(mod100) { return "działów" }
        return (2...4).contains(count % 10) ? "działy" : "działów"
    }

    private struct GroupBlock: View {
        let group: ShoppingListCardGroupDTO

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(group.department)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.wmMuted(scheme))
                    // „2/4” — do kupienia z wszystkich; odhaczone są tłem.
                    Text("\(group.remainingCount)/\(group.rows.count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Color.wmFaint(scheme))
                    Spacer(minLength: 0)
                }

                AllergenChipFlow(spacing: 6) {
                    ForEach(group.rows) { entry in
                        HStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(
                                        entry.isChecked ? WMPalette.sage : Color.wmFaint(scheme).opacity(0.6),
                                        lineWidth: 1.5
                                    )
                                if entry.isChecked {
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(WMPalette.sage)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundStyle(Color.wmPageBase(scheme))
                                }
                            }
                            .frame(width: 13, height: 13)

                            Text(entry.label)
                                .font(.system(size: 12.5))
                                .tracking(-0.15)
                                .foregroundStyle(entry.isChecked ? Color.wmFaint(scheme) : Color.wmLabel(scheme))
                                .strikethrough(entry.isChecked, color: Color.wmStrike(scheme))
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(entry.isChecked ? Color.clear : Color.wmInsetSurface(scheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    entry.isChecked ? Color.wmRule(scheme) : Color.wmCardStroke(scheme),
                                    lineWidth: 1
                                )
                        )
                    }
                }

                if let hidden = group.hidden, hidden > 0 {
                    Text("+ \(hidden) więcej w Liście zakupów")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.wmFaint(scheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }
}
