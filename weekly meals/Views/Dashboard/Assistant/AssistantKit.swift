import SwiftUI

// Powłoka ekranu asystenta — nagłówek, chipy kontekstu, ślad kroków tury
// i atomy kart. Wydzielone z `AssistantView`, bo od tej zmiany odpowiedź
// asystenta przestaje być jednym akapitem: te same kafle, pigułki i paski
// obsłużą kolejne rodzaje wiadomości (propozycja planu, podmiana, analiza),
// a widok rozmowy ma zostać czytelny.

// MARK: - Nagłówek

/// Nagłówek zakładki w dwóch rozmiarach.
///
/// Duży tytuł ma sens wyłącznie na pustym ekranie — w trwającej rozmowie
/// zjada wiersz treści, a tytuł rozmowy niesie więcej informacji niż słowo
/// „Asystent”. Kompaktowy pasek oddaje te ~40 pt strumieniowi wiadomości.
struct AssistantHeader: View {
    enum Mode: Equatable {
        case large
        /// Tytuł nadaje serwer z pierwszej wiadomości; `nil` = jeszcze nie doszedł.
        case compact(title: String?)
    }

    let mode: Mode
    var onNewConversation: () -> Void
    var onHistory: () -> Void
    var onMore: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch mode {
        case .large:
            HStack(alignment: .top, spacing: 12) {
                Text("Asystent")
                    .font(.system(size: 32, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 8)

                actions(compact: false)
            }
            .padding(.horizontal, WMPageMetrics.horizontal)
            .padding(.top, WMPageMetrics.top)
            .padding(.bottom, 12)

        case let .compact(title):
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Asystent")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(WMPalette.terracotta)

                    Text(title ?? "Nowa rozmowa")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.wmLabel(scheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                actions(compact: true)
            }
            .padding(.horizontal, WMPageMetrics.horizontal)
            .padding(.top, 58)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func actions(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact {
                // W rozmowie „nowa” jest częstsza niż menu — i to ona wygrywa
                // miejsce przy krawędzi, bo menu zostaje pod tym samym gestem
                // w pustym stanie.
                EditorialIconButton(icon: "square.and.pencil", action: onNewConversation)
                EditorialIconButton(icon: "clock.arrow.circlepath", action: onHistory)
            } else {
                EditorialIconButton(icon: "clock.arrow.circlepath", action: onHistory)
                EditorialIconButton(icon: "ellipsis", action: onMore)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Chipy kontekstu

/// Jeden chip nad polem wiadomości.
struct AssistantContextChip: Identifiable, Equatable {
    let id: String
    let icon: String
    let label: String
    /// Chip, który da się zmienić — chevron jest wtedy obietnicą, nie ozdobą.
    var adjustable: Bool = false
    /// Zawężony przez użytkownika: wyróżniony, bo zmienia wynik odpowiedzi.
    var isActive: Bool = false
}

/// Pasek „z czym asystent policzy odpowiedź”, zanim ją policzy.
///
/// Bez tego zakres jest domysłem: użytkownik pisze „zaplanuj tydzień” i dopiero
/// z odpowiedzi dowiaduje się, o który tydzień i o kogo chodziło. W trakcie
/// tury pasek gaśnie — zakres jest już zamknięty i klikanie w niego nic nie da.
struct AssistantContextChips: View {
    let items: [AssistantContextChip]
    var isMuted: Bool = false
    /// Dotknięcie chipa, który da się zmienić. `nil` = chipy są etykietami.
    var onTap: ((AssistantContextChip) -> Void)?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(items) { chip in
                    Button {
                        guard chip.adjustable else { return }
                        onTap?(chip)
                    } label: {
                        chipBody(chip)
                    }
                    .buttonStyle(.plain)
                    .disabled(!chip.adjustable || onTap == nil)
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
        .opacity(isMuted ? 0.5 : 1)
        .animation(.smooth(duration: 0.2), value: isMuted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Zakres odpowiedzi: \(items.map(\.label).joined(separator: ", "))")
    }

    private func chipBody(_ chip: AssistantContextChip) -> some View {
        HStack(spacing: 5) {
            Image(systemName: chip.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    chip.isActive ? WMPalette.terracotta : Color.wmMuted(scheme)
                )

            Text(chip.label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.1)
                .foregroundStyle(Color.wmLabel(scheme))
                .lineLimit(1)

            if chip.adjustable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.wmFaint(scheme))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            Capsule().fill(
                chip.isActive ? Color.wmAccentTint(scheme) : Color.wmChipBg(scheme)
            )
        )
        .overlay(
            Capsule().stroke(
                chip.isActive
                    ? WMPalette.terracotta.opacity(0.4)
                    : Color.wmTileStroke(scheme),
                lineWidth: 1
            )
        )
    }
}

// MARK: - Ślad kroków tury

/// Kroki tury zamiast kręciołka.
///
/// Tura trwa 25–60 s i jedyne, co o niej wiadomo, to kroki przysyłane przez
/// serwer (`progress[].label`). Zrobione zostają na ekranie wyszarzone —
/// dzięki temu widać PRZEBYTĄ drogę, a nie jeden migający napis, przy którym
/// nie sposób ocenić, czy cokolwiek się dzieje.
struct AssistantProgressTrail: View {
    let steps: [AgentProgressStepDTO]
    let startedAt: Date?

    /// Po tylu sekundach czekanie przestaje być chwilą i warto powiedzieć,
    /// że nie trzeba przy nim siedzieć. Wcześniej ta sama informacja jest
    /// szumem pod każdym pytaniem — i tak właśnie była odbierana.
    private static let patienceAfter: TimeInterval = 18

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if steps.isEmpty {
                row(label: "Zastanawiam się…", isCurrent: true)
                    .transition(.opacity)
            } else {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    row(label: step.label, isCurrent: index == steps.count - 1)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity
                            )
                        )
                }
            }

            if let startedAt {
                footer(from: startedAt)
            }
        }
        .padding(.vertical, 4)
        // Kroki dochodzą po jednym co kilka sekund — bez tego lista skacze,
        // a wiersz, który właśnie się skończył, zmienia się w ptaszek bez
        // żadnego przejścia.
        .animation(.smooth(duration: 0.3), value: steps.count)
    }

    @ViewBuilder
    private func row(label: String, isCurrent: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            StepIcon(isCurrent: isCurrent)

            Text(label)
                .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                .tracking(-0.15)
                .foregroundStyle(isCurrent ? Color.wmLabel(scheme) : Color.wmFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            Spacer(minLength: 0)
        }
    }

    /// Licznik sekund plus — dopiero po chwili — zdanie o tym, że nie trzeba
    /// tu siedzieć.
    private func footer(from startedAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let seconds = Int(elapsed)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(seconds) s")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.wmFaint(scheme))
                    // Ta sama animacja liczby co przy kaloriach w szczegółach
                    // przepisu: cyfra przewija się, zamiast podmieniać skokiem.
                    .contentTransition(.numericText(value: Double(seconds)))
                    .animation(.snappy(duration: 0.25), value: seconds)

                if elapsed >= Self.patienceAfter {
                    Text("Możesz wyjść — wrócę z odpowiedzią.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.wmFaint(scheme))
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .padding(.leading, 28)
            .animation(.smooth(duration: 0.35), value: elapsed >= Self.patienceAfter)
        }
    }

    /// Znacznik kroku: kręciołek albo ptaszek, ZAWSZE tej samej wielkości.
    ///
    /// Wcześniej kółko postępu było obrysem, a znacznik zrobionego kroku
    /// wypełnionym kołem tej samej ramki — obrys ma pół grubości linii poza
    /// promieniem, więc oba wyglądały na różne. Teraz obrys jest wsunięty
    /// o tę grubość i oba kończą się na tej samej średnicy.
    private struct StepIcon: View {
        let isCurrent: Bool

        private static let diameter: CGFloat = 18
        private static let lineWidth: CGFloat = 2

        @Environment(\.colorScheme) private var scheme

        var body: some View {
            ZStack {
                if isCurrent {
                    Spinner(lineWidth: Self.lineWidth)
                        .padding(Self.lineWidth / 2)
                } else {
                    Circle().fill(Color.wmSageTint(scheme))
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(WMPalette.sage)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }

    /// Kręciołek liczony z ZEGARA, nie ze stanu.
    ///
    /// Wersja na `@State` + `repeatForever` zatrzymywała się w połowie tury:
    /// każdy nowy krok postępu tworzył NOWY widok kółka, którego stan był już
    /// ustawiony na „po animacji" — `value:` nigdy się nie zmieniało, więc
    /// animacja nie ruszała i kółko zastygało pod kątem 360°. Kąt liczony
    /// z czasu nie ma stanu, który dałoby się zgubić przy przebudowie widoku.
    private struct Spinner: View {
        let lineWidth: CGFloat

        /// Pełny obrót; 0,9 s to tempo, przy którym oko widzi ruch, a nie miga.
        private static let period: TimeInterval = 0.9

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: Self.period)
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        WMPalette.terracotta,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(phase / Self.period * 360))
            }
        }
    }
}

// MARK: - Atomy kart

/// Kontener karty w rozmowie. `tone` steruje tłem i obrysem: sage = zapisane,
/// indigo = analiza, `nil` = zwykła karta.
struct AssistantCard<Content: View>: View {
    enum Tone { case neutral, sage, indigo }

    var tone: Tone = .neutral
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var fill: Color {
        switch tone {
        case .neutral: return Color.wmCardSurface(scheme)
        case .sage: return Color.wmSageTint(scheme)
        case .indigo: return Color.wmIndigoTint(scheme)
        }
    }

    private var stroke: Color {
        switch tone {
        case .neutral: return Color.wmCardStroke(scheme)
        case .sage: return WMPalette.sage.opacity(0.24)
        case .indigo: return WMPalette.indigo.opacity(0.26)
        }
    }
}

/// Nagłówek karty: nadtytuł (co to jest) + tytuł (co z tego wynika).
struct AssistantCardHead<Right: View>: View {
    let eyebrow: String
    /// Drugi wiersz nadtytułu — data albo zakres.
    ///
    /// Osobno, a nie doklejone kropką do `eyebrow`: „PROPOZYCJA PLANU ·
    /// 31 SIERPNIA – 6 WRZEŚNIA" nie mieści się w wierszu karty i łamie się
    /// w środku nazwy miesiąca, czyli w najgorszym możliwym miejscu.
    var eyebrowDetail: String?
    var eyebrowColor: Color = WMPalette.terracotta
    let title: String
    @ViewBuilder var right: () -> Right

    @Environment(\.colorScheme) private var scheme

    var body: some View {
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
                        .foregroundStyle(Color.wmMuted(scheme))
                        .lineLimit(1)
                }

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.35)
                    .foregroundStyle(Color.wmLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            right()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

extension AssistantCardHead where Right == EmptyView {
    init(eyebrow: String, eyebrowColor: Color = WMPalette.terracotta, title: String) {
        self.init(eyebrow: eyebrow, eyebrowColor: eyebrowColor, title: title) { EmptyView() }
    }
}

/// Pasek akcji karty — akcja główna zawsze po prawej, wtórna jako duch.
///
/// Akcje siedzą W KARCIE, nie w composerze: karta jest propozycją, a decyzja
/// dotyczy tej jednej propozycji, nie całej rozmowy.
struct AssistantCardActions: View {
    let primaryTitle: String
    var primaryIcon: String = "checkmark"
    var primaryTone: AssistantCard<EmptyView>.Tone = .neutral
    var isBusy: Bool = false
    var secondaryTitle: String?
    var secondaryIcon: String?
    var onSecondary: (() -> Void)?
    let onPrimary: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            if let secondaryTitle, let onSecondary {
                Button(action: onSecondary) {
                    HStack(spacing: 6) {
                        if let secondaryIcon {
                            Image(systemName: secondaryIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.wmMuted(scheme))
                        }
                        Text(secondaryTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.wmLabel(scheme))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.wmTileBg(scheme)))
                    .overlay(Capsule().stroke(Color.wmTileStroke(scheme), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            Button(action: onPrimary) {
                HStack(spacing: 7) {
                    if isBusy {
                        ProgressView().controlSize(.small).tint(Color.wmPageBase(scheme))
                    } else {
                        Image(systemName: primaryIcon)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(primaryTitle)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.25)
                }
                .foregroundStyle(Color.wmPageBase(scheme))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(primaryTone == .sage ? WMPalette.sage : WMPalette.terracotta))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(12)
        .background(Color.wmPageBase(scheme).opacity(scheme == .dark ? 0.14 : 0.04))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.wmRule(scheme)).frame(height: 1)
        }
    }
}

// MARK: - Szybkie odpowiedzi

/// Podpowiedzi kolejnego ruchu pod odpowiedzią — rozmowa nie kończy się ścianą
/// tekstu i pustym polem.
struct AssistantQuickReplies: View {
    let items: [String]
    let onTap: (String) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        AllergenChipFlow(spacing: 7) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.system(size: 13.5, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(WMPalette.terracotta)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(Color.wmAccentTint(scheme).opacity(0.5)))
                        .overlay(Capsule().stroke(WMPalette.terracotta.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
