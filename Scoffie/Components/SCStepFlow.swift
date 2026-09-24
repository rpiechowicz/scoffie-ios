import SwiftUI

// Klocki przepływów krok po kroku — JEDNE dla trzech miejsc: przewodnika
// „Poznaj aplikację” (`WelcomeView`), kreatora „Poznajmy się”
// (`WelcomeView`) i wprowadzenia Asystenta (`AssistantView.introFlow`,
// strony z `AssistantIntroPages.swift`, `AssistantConsentGateView`,
// arkusz `AssistantHowItWorksView`).
//
// Wcześniej każdy przepływ miał własną stopkę (`TourFooter`, `WelcomeFooter`,
// `AssistantIntroFooter`), pigułkowe kropki kroków (`WelcomeStepper`), własny
// nagłówek (kafel z gradientem i poświatą w kreatorze, 27 pt bold w asystencie,
// 32 pt w przewodniku) i trzy różne tła pod stopką. Rafał (23.09.2026):
// „Stepper oraz widoki zrób tak jak aktualnie działamy w aplikacji” i „użyj
// steppera z naszym shadow, aby było wszystko zgodne ze sobą” — stąd jeden
// pasek kroków, jedna stopka na `SCSheetFooter` (płyta + `SCEdgeShade`)
// i jeden nagłówek.

// MARK: - Pasek kroków

/// Wskaźnik kroków: odcinek na każdy krok na całą szerokość, jak segmenty
/// w arkuszu wyboru posiłku i pasek postępu Zakupów.
///
/// Przebyte kroki stoją w przygaszonym akcencie, bieżący w pełnym, reszta na
/// torze (`scBarTrack`). Przy „Dalej” następny odcinek NALEWA SIĘ od lewej
/// (szerokość, nie przenikanie), przy „Wstecz” — schodzi, więc ruch mówi,
/// w którą stronę się idzie. Pigułki z kreatora (bieżąca 28 pt, reszta
/// kropkami po 8 pt) nie mówiły, ile zostało, dopóki się ich nie policzyło.
struct SCStepProgress: View {
    /// Bieżący krok, liczony od 1.
    let step: Int
    let total: Int
    var accent: Color = SCPalette.terracotta

    static let height: CGFloat = 4
    private static let spacing: CGFloat = 5

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                segment(index)
            }
        }
        .frame(height: Self.height)
        // Sprężyna bez odbicia — odcinek dojeżdża do pełna miękko, jak
        // wypełnienie działu na pasku Zakupów.
        .animation(.spring(response: 0.5, dampingFraction: 0.92), value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Krok \(step) z \(total)")
    }

    private func segment(_ index: Int) -> some View {
        let reached = index < step
        let isCurrent = index == step - 1

        return Capsule(style: .continuous)
            .fill(Color.scBarTrack(scheme))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule(style: .continuous)
                        .fill(isCurrent ? accent : accent.opacity(0.45))
                        .frame(width: reached ? proxy.size.width : 0)
                }
            }
    }
}

// MARK: - Nagłówek kroku

/// Nagłówek strony w przepływie: kafelek z glifem w tincie akcentu
/// (`SCHeaderIconWell`, ten sam, co w nagłówkach arkuszy), eyebrow w kroju
/// `EditorialSheetHeader`, tytuł w kroju `EditorialPageHeader` i krótki
/// opis pod spodem (do dwóch–trzech zdań od 24.09.2026 — przewodnik
/// i kreator tłumaczą w nim, o co chodzi, zanim padnie pytanie).
///
/// Zastąpił nagłówek kreatora z pełnym kafelkiem w gradiencie i poświatą
/// (jedyny taki akcent w aplikacji) oraz ręcznie składane tytuły przewodnika
/// i asystenta, każdy w innym stopniu pisma.
struct SCStepHeader: View {
    var icon: String? = nil
    var accent: Color = SCPalette.terracotta
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    /// Tytuł i opis PISZĄ SIĘ na oczach — ta sama animacja co powitanie
    /// Asystenta (`SCTypedText`: nienapisana końcówka jest przezroczysta,
    /// więc układ nie skacze). Nowa wartość = pisze się od zera. `nil`
    /// (domyślnie) = zwykły tekst, jak w przewodniku i kreatorze.
    var typing: Int? = nil

    @Environment(\.colorScheme) private var scheme

    /// Tempo z powitania Asystenta: tytuł spokojnie, opis szybciej, razem
    /// najwyżej `typingBudget` — dłuższy tekst przyspiesza oba w tej samej
    /// proporcji, zamiast kazać czekać na ostatnie słowo.
    private static let titleRate: Double = 65
    private static let subtitleRate: Double = 170
    private static let typingBudget: Double = 0.9
    private static let typingLead: Double = 0.08

    private var rateScale: Double {
        let natural = Double(title.count) / Self.titleRate
            + Double(subtitle?.count ?? 0) / Self.subtitleRate
        return max(1, natural / Self.typingBudget)
    }

    private var subtitleDelay: Double {
        Self.typingLead + SCTypedText.duration(title, rate: Self.titleRate * rateScale) + 0.05
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let icon {
                SCHeaderIconWell(icon: icon, accent: accent, size: 48)
                    .padding(.bottom, 16)
            }

            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .padding(.bottom, 6)
            }

            titleText
                .font(.system(size: 28, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                subtitleText(subtitle)
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundStyle(Color.scMuted(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var titleText: some View {
        if let typing {
            SCTypedText(title, playKey: typing, rate: Self.titleRate * rateScale, delay: Self.typingLead)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    private func subtitleText(_ subtitle: String) -> some View {
        if let typing {
            SCTypedText(subtitle, playKey: typing, rate: Self.subtitleRate * rateScale, delay: subtitleDelay)
        } else {
            Text(subtitle)
        }
    }
}

// MARK: - Karta z funkcjami

/// Jeden wiersz karty z funkcjami: glif w tincie, tytuł i opcjonalny podpis.
struct SCStepFeature: Identifiable {
    let icon: String
    let accent: Color
    let title: String
    var subtitle: String? = nil

    var id: String { title }
}

/// Karta z listą funkcji — powitanie przewodnika, jego ekran domykający
/// i powitanie asystenta. Karta aplikacji (`scTileBg` + `scTileStroke`, bez
/// cienia), wiersze z kafelkiem w tincie i kreską wciętą pod tekst — jak
/// listy wyboru w Ustawieniach. Wcześniej te same wiersze stały luzem na
/// tle, a na powitaniu asystenta jako ptaszki w zielonych kółkach.
struct SCStepFeatureCard: View {
    let features: [SCStepFeature]

    @Environment(\.colorScheme) private var scheme

    private static let iconSize: CGFloat = 34
    private static let iconSpacing: CGFloat = 12
    private static let horizontalPadding: CGFloat = 16
    private static let radius: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                row(feature)
                if index < features.count - 1 {
                    Rectangle()
                        .fill(Color.scRule(scheme))
                        .frame(height: 1)
                        .padding(.leading, Self.horizontalPadding + Self.iconSize + Self.iconSpacing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(Color.scTileBg(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .stroke(Color.scTileStroke(scheme), lineWidth: 1)
        )
    }

    private func row(_ feature: SCStepFeature) -> some View {
        HStack(spacing: Self.iconSpacing) {
            SCHeaderIconWell(icon: feature.icon, accent: feature.accent, size: Self.iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = feature.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, feature.subtitle == nil ? 11 : 12)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stopka kroku

/// Stopka przepływu krok po kroku — JEDNA dla przewodnika, kreatora
/// i wprowadzenia asystenta. Stoi na `SCSheetFooter`: kryjąca płyta w kolorze
/// tła i nad nią cień krawędzi (`SCEdgeShade`), w którym treść gaśnie — ta
/// sama stopka, co w każdym arkuszu aplikacji.
///
/// Układ jest STAŁY między krokami, więc przycisk nie podskakuje:
/// - wiersz nawigacji o wysokości krążka: „Wstecz” po lewej (krążek
///   `SCSheetIconButton`, ten sam co krzyżyk arkusza), pośrodku gniazdo —
///   pasek kroków, odnośnik („Pomiń…”) albo nic — i licznik „2/5” po prawej;
///   „Wstecz” na pierwszym kroku GAŚNIE, ale trzyma miejsce, żeby pasek nie
///   przeskakiwał na bok;
/// - pod nim akcja główna na całą szerokość (`EditorialPrimaryActionButton`,
///   tytuł roluje się literami przy zmianie „Dalej” → „Utwórz gospodarstwo”).
///
/// Wstawia się ją jako OSTATNIE dziecko `VStack` pod treścią (albo nakładkę
/// na dole) — cień wystaje wtedy nad stopkę i leży na treści, więc przewijana
/// treść musi mieć na dole zapas `SCEdgeShade.bottomHeight`.
struct SCStepFooter: View {
    enum Slot: Equatable {
        case progress(step: Int, total: Int)
        case link(String)
        case empty

        /// Klucz przejścia gniazda: wszystkie kroki z paskiem dzielą jedną
        /// instancję, więc odcinki nalewają się w miejscu, zamiast wjeżdżać
        /// od nowa z każdą stroną.
        fileprivate var key: Int {
            switch self {
            case .progress: return 0
            case .link: return 1
            case .empty: return 2
            }
        }
    }

    /// Gdzie stoi „Wstecz”.
    enum BackPlacement {
        /// Krążek 36 pt na lewym końcu wiersza z paskiem kroków.
        case progressRow
        /// Krążek wysokości przycisku głównego, w jednej linii z nim, po lewej
        /// — przewodnik „Poznaj aplikację” i kreator (Rafał 24.09.2026: „ten
        /// button wstecz daj obok buttonu dalej”), od wprowadzenia Asystenta
        /// v2 także Asystent („taki sam jak na onboardingu aplikacji”). Pasek
        /// kroków dostaje wtedy cały wiersz nad nimi.
        case besidePrimary
    }

    let slot: Slot
    var onSlotTap: (() -> Void)? = nil
    /// Zdanie nad przyciskami (błąd zapisu) — przy akcji, która go wywołała,
    /// a nie w treści, którą trzeba by przewinąć.
    var notice: String? = nil
    var showsBack: Bool = false
    var onBack: (() -> Void)? = nil
    var backPlacement: BackPlacement = .progressRow
    let primaryTitle: String
    var primaryIcon: String = "arrow.right"
    var isPrimaryEnabled: Bool = true
    var isPrimaryLoading: Bool = false
    var primaryHint: String? = nil
    let onPrimary: () -> Void

    /// Wysokość wiersza nawigacji = średnica krążka „Wstecz”.
    static let rowHeight: CGFloat = 36

    /// Zmierzona wysokość przycisku głównego — średnica krążka „Wstecz”
    /// w układzie `.besidePrimary`. 48 do pierwszego pomiaru.
    @State private var primaryHeight: CGFloat = 48

    @Environment(\.colorScheme) private var scheme

    private var canGoBack: Bool { showsBack && onBack != nil }

    var body: some View {
        SCSheetFooter {
            if let notice {
                SCInlineErrorText(notice)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }

            navigationRow
                .padding(.bottom, 4)

            actionRow
        }
        .animation(.easeInOut(duration: 0.2), value: notice)
    }

    private var primaryButton: some View {
        EditorialPrimaryActionButton(
            title: primaryTitle,
            icon: primaryIcon,
            isEnabled: isPrimaryEnabled,
            isLoading: isPrimaryLoading,
            action: onPrimary
        )
        .accessibilityHint(primaryHint ?? "")
        // Animowana transakcja dla `numericText` w tytule — bez niej
        // „Dalej” → „Utwórz gospodarstwo” podmieniało się w jednej klatce.
        .animation(.smooth(duration: 0.32), value: primaryTitle)
    }

    @ViewBuilder
    private var actionRow: some View {
        switch backPlacement {
        case .progressRow:
            primaryButton
        case .besidePrimary:
            // Krążek bierze ZMIERZONĄ wysokość przycisku, więc oba stoją na
            // jednej linii bez stałej przepisanej z
            // `EditorialPrimaryActionButton` (i rosną razem z Dynamic Type).
            // Bez „Wstecz” (powitanie) przycisk rozjeżdża się na całą szerokość.
            HStack(spacing: 10) {
                if canGoBack {
                    Button {
                        onBack?()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.scMuted(scheme))
                            .frame(width: primaryHeight, height: primaryHeight)
                            .background(Circle().fill(Color.scChipBg(scheme)))
                            .overlay(Circle().stroke(Color.scTileStroke(scheme), lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(PlanPressStyle(scale: 0.92))
                    .accessibilityLabel("Wstecz")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                primaryButton
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        primaryHeight = height
                    }
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: canGoBack)
        }
    }

    private var navigationRow: some View {
        HStack(spacing: 12) {
            if backPlacement == .progressRow {
                SCSheetIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Wstecz",
                    action: { onBack?() }
                )
                .opacity(canGoBack ? 1 : 0)
                .scaleEffect(canGoBack ? 1 : 0.8)
                .allowsHitTesting(canGoBack)
                .accessibilityHidden(!canGoBack)
            }

            ZStack {
                slotContent
                    .id(slot.key)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.3), value: slot.key)

            // Przy „Wstecz” obok przycisku nie ma krążka, który równoważyłby
            // licznik z lewej — pusty licznik zjadałby 36 pt z prawej
            // i odnośnik „Pomiń…” stałby krzywo.
            if backPlacement == .progressRow || slot.key == Slot.progress(step: 0, total: 0).key {
                // Szerokość z treści, nie stałe 36 pt: przy dwucyfrowych
                // krokach („11/11” w przepływie przewodnik + kreator) licznik
                // łamał się na dwie linie. Minimum trzyma pasek w miejscu przy
                // „1/5” → „2/5”.
                counter
                    .fixedSize()
                    .frame(minWidth: Self.rowHeight, alignment: .trailing)
            }
        }
        .frame(height: Self.rowHeight)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: canGoBack)
    }

    @ViewBuilder
    private var slotContent: some View {
        switch slot {
        case let .progress(step, total):
            SCStepProgress(step: step, total: total)
        case let .link(title):
            Button {
                onSlotTap?()
            } label: {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .empty:
            Color.clear
        }
    }

    /// „2/5” — cyfra roluje się razem z nalewaniem odcinka. Czytelniej niż
    /// liczenie odcinków, a po prawej równoważy krążek „Wstecz”, więc pasek
    /// stoi na środku stopki.
    @ViewBuilder
    private var counter: some View {
        switch slot {
        case let .progress(step, total):
            Text("\(step)/\(total)")
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.scFaint(scheme))
                .contentTransition(.numericText(value: Double(step)))
                .animation(.smooth(duration: 0.3), value: step)
                .accessibilityHidden(true)
        case .link, .empty:
            Color.clear
        }
    }
}

#Preview("Stopka · krok 2") {
    ZStack(alignment: .bottom) {
        SCPageBackground(scheme: .dark).ignoresSafeArea()
        SCStepFooter(
            slot: .progress(step: 2, total: 5),
            showsBack: true,
            onBack: {},
            primaryTitle: "Dalej",
            onPrimary: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Stopka · odnośnik") {
    ZStack(alignment: .bottom) {
        SCPageBackground(scheme: .light).ignoresSafeArea()
        SCStepFooter(
            slot: .link("Pomiń i przejdź do konfiguracji"),
            onSlotTap: {},
            primaryTitle: "Poznaj aplikację",
            onPrimary: {}
        )
    }
    .preferredColorScheme(.light)
}

#Preview("Nagłówek i karta") {
    ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            SCStepHeader(
                icon: "person.fill",
                eyebrow: "Witaj w Scoffie",
                title: "Zacznijmy od Ciebie",
                subtitle: "Z tych danych policzymy Twój dzienny cel."
            )
            SCStepFeatureCard(features: [
                SCStepFeature(icon: "calendar", accent: SCPalette.terracotta, title: "Plan na cały tydzień", subtitle: "Widzi go cały dom"),
                SCStepFeature(icon: "basket.fill", accent: SCPalette.sage, title: "Lista zakupów z planu")
            ])
        }
        .padding(20)
    }
    .background(SCPageBackground(scheme: .dark).ignoresSafeArea())
    .preferredColorScheme(.dark)
}
