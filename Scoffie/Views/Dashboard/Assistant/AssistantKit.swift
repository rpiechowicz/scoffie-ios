import SwiftUI

// Powłoka ekranu asystenta — nagłówek, wskaźnik tury (i to, w co zamienia
// się po odpowiedzi) oraz atomy kart. Wydzielone z `AssistantView`, bo od tej zmiany odpowiedź
// asystenta przestaje być jednym akapitem: te same kafle, pigułki i paski
// obsłużą kolejne rodzaje wiadomości (propozycja planu, podmiana, analiza),
// a widok rozmowy ma zostać czytelny.

// MARK: - Nagłówek

/// Nagłówek zakładki w dwóch rozmiarach.
///
/// Duży tytuł ma sens wyłącznie na pustym ekranie — w trwającej rozmowie
/// zjada wiersz treści, a tytuł rozmowy niesie więcej informacji niż słowo
/// „Asystent”. Kompaktowy pasek oddaje te ~40 pt strumieniowi wiadomości.
/// Poza generykiem, bo `AssistantHeader<…>.Mode` wymagałoby od wołającego
/// podania typu menu tylko po to, żeby nazwać tryb.
enum AssistantHeaderMode: Equatable {
    case large
    /// Tytuł nadaje serwer z pierwszej wiadomości; `nil` = jeszcze nie doszedł.
    case compact(title: String?)
}

struct AssistantHeader<MenuContent: View>: View {
    typealias Mode = AssistantHeaderMode

    let mode: Mode
    var onNewConversation: () -> Void
    /// Plakietka po lewej od akcji — stan puli w trakcie próby. Nagłówek to
    /// miejsce, do którego wzrok i tak wraca między odpowiedziami, więc stan
    /// jest widoczny bez otwierania czegokolwiek i nie wchodzi w treść.
    var accessory: AnyView?
    /// Pozycje menu ⋯ — systemowe `Menu` z ikonami (projekt „Asystent Zgoda"),
    /// nie arkusz z dołu: siedem pozycji czyta się szybciej przy przycisku.
    @ViewBuilder var menu: () -> MenuContent

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch mode {
        case .large:
            // `.center`, nie `.top`: plakietka (28 pt) i przycisk ⋯ (38 pt)
            // mają różne wysokości, więc wyrównane do góry plakietka wisiała
            // 5 pt nad osią przycisku.
            //
            // Bez `Spacer`a: HStack rozdaje miejsce dzieciom od najmniej
            // elastycznego i dzieli resztę PO RÓWNO między te, które zostały —
            // plakietka (tekst z `lineLimit(1)`) dostawała połowę wolnego
            // miejsca na spółkę ze Spacerem i ucinała się do „5 wiadom…",
            // choć obok zostawało 30 pt pustki. Teraz plakietka bierze swój
            // naturalny rozmiar, a to tytuł rozciąga się na resztę i w razie
            // czego schodzi do 0,9 skali.
            HStack(alignment: .center, spacing: 10) {
                Text("Asystent")
                    .font(.system(size: 32, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)

                accessory
                    .fixedSize(horizontal: true, vertical: false)
                actions(compact: false)
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.top, SCPageMetrics.top)
            .padding(.bottom, 12)

        case let .compact(title):
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Asystent")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(SCPalette.terracotta)

                    Text(title ?? "Nowa rozmowa")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.scLabel(scheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Jak wyżej: plakietka w naturalnym rozmiarze, ucina się
                // tytuł rozmowy — to on jest tu elementem elastycznym.
                accessory
                    .fixedSize(horizontal: true, vertical: false)
                actions(compact: true)
            }
            .padding(.horizontal, SCPageMetrics.horizontal)
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
                // Historia jest w menu — w kompaktowym pasku zostaje „nowa" i ⋯.
                EditorialIconButton(icon: "square.and.pencil", accessibilityTitle: "Nowa rozmowa", action: onNewConversation)
                menuButton
            } else {
                // Historia siedzi w menu ⋯ — drugi przycisk obok tylko dublował wejście.
                menuButton
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Ta sama pigułka co `EditorialIconButton`, ale jako etykieta `Menu`.
    private var menuButton: some View {
        Menu {
            menu()
        } label: {
            SCCircleIconLabel(icon: "ellipsis", size: 38)
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Więcej opcji asystenta")
    }
}

// MARK: - Wskaźnik tury

/// Wiersz „asystent pracuje": glif marki + jeden wiersz z połyskiem, zero
/// ramek, STAŁA wysokość 22 pt.
///
/// Tura trwa 25–240 s i jedyne, co o niej wiadomo, to kroki przysyłane przez
/// serwer (`progress[].label`). Poprzednik był kartą z obrysem, orbem
/// i rosnącą listą przebytych kroków — sześć wysokości w jednej turze,
/// tło skaczące między trzema tintami i orb, który przy każdej zmianie
/// etapu „eksplodował". Wzorzec ChatGPT/Claude jest odwrotny: SPOKÓJ —
/// jeden glif, jeden wiersz niskokontrastowego tekstu, a ruch niesie
/// połysk na tekście, nie kręciołek obok.
///
/// Ma tę samą geometrię co pierwszy wiersz odpowiedzi
/// (`AssistantThoughtSummary`): glif 14 pt w x = 0, tekst od 22 pt,
/// wiersz 22 pt. Dzięki temu odpowiedź WYŁANIA SIĘ w jego miejscu
/// (crossfade w slocie tury), a nie obok.
struct AssistantThinkingLine: View {
    let steps: [AgentProgressStepDTO]
    /// Epoka tury (`AgentStore.turnStartedAt`) — od niej liczy się oddech,
    /// połysk i moment „Możesz wyjść". Stała przez całą turę.
    let startedAt: Date
    var isStopping: Bool = false

    /// Po tylu sekundach czekanie przestaje być chwilą i warto powiedzieć,
    /// że nie trzeba przy nim siedzieć. Wcześniej ta sama informacja jest
    /// szumem pod każdym pytaniem — i tak właśnie była odbierana.
    private static let patienceAfter: TimeInterval = 18

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPatience = false
    /// Jednorazowe wejście wiersza. Nowe pytanie zmienia tożsamość slotu
    /// (`.id(slotKey)` w `AssistantView`) w tej samej, NIEANIMOWANEJ
    /// transakcji, w której `isSending` już jest `true` — SwiftUI stawia
    /// świeży `ZStack` z wierszem od razu i `.transition(.opacity)` na nim nie
    /// ma czego animować. W drugą stronę (wiersz → odpowiedź) `ZStack`
    /// istnieje i crossfade działa; to wejście domyka symetrię. Nie pętla,
    /// więc przebudowy przy krokach postępu go nie psują.
    @State private var appeared = false

    private var current: AgentProgressStepDTO? { steps.last }

    /// Planowanie trwa OD kroku z `phase` do końca tury — serwer znakuje
    /// tylko moment przekazania (`start_planning`), a droższa część zaczyna
    /// się właśnie wtedy. Liczenie z `steps.last` cofało ton po pierwszym
    /// narzędziu planisty i wskaźnik migotał kolorem tam i z powrotem.
    private var inPlanning: Bool { steps.contains { $0.isHandoff } }

    /// „Zapisano w tej turze" — fakt, który się nie cofa. Po zapisie model
    /// jeszcze 10–30 s pisze odpowiedź; powrót do indygo czytałby się jak
    /// cofnięcie zapisu.
    private var hasWritten: Bool { steps.contains { $0.writes == true } }

    /// Dwie kopie klienta są STATUSAMI, nie krokami. Etykiety kroków
    /// przychodzą wyłącznie z serwera.
    private var label: String {
        if isStopping { return "Zatrzymuję…" }
        return current?.label ?? "Zastanawiam się…"
    }

    /// Kolejność: zapis > planowanie > reszta. `contains` nigdy nie
    /// przechodzi z `true` na `false`, więc kolor idzie tylko w jedną stronę:
    /// terakota → indygo → szałwia.
    private var glyphColor: Color {
        if hasWritten { return SCPalette.sage }
        if inPlanning { return SCPalette.indigo }
        return SCPalette.terracotta
    }

    /// Jawne właściwości zamiast `reduceMotion ? nil : …` w argumencie —
    /// warunek z `nil` po jednej stronie daje dwa równorzędne rozwiązania
    /// typu (SE-0418) i kompilator zgłasza to przy najbliższym kontenerze.
    private var labelTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 5)),
            removal: .opacity.combined(with: .offset(y: -5))
        )
    }

    private var labelAnimation: Animation? {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return .easeInOut(duration: 0.3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Jeden zegar dla glifu i połysku — jedna epoka, zero rozjazdu faz.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let t = max(0, context.date.timeIntervalSince(startedAt))
                HStack(alignment: .center, spacing: 8) {
                    SCThinkingGlyph(t: t, color: glyphColor, size: 14, still: reduceMotion)

                    // Stary i nowy tekst nakładają się w tym samym miejscu
                    // zamiast przepychać układ; stała wysokość chroni resztę.
                    // Animujemy po ZMIANIE TEKSTU, nie po liczbie kroków —
                    // ten sam układ co `StartupLoaderView.statusLine`.
                    ZStack(alignment: .leading) {
                        SCShimmerText(text: label, t: t, still: reduceMotion)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .id(label)
                            .transition(labelTransition)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(labelAnimation, value: label)
                }
                .frame(height: 22)
            }

            if showsPatience {
                // 22 = glif 14 + odstęp 8: linia wyrównana do tekstu wyżej.
                Text("Możesz wyjść — wrócę z odpowiedzią.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.scFaint(scheme))
                    .padding(.leading, 22)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .onAppear { reveal() }
        // Raz na epokę tury, nie pętla — przebudowy przy krokach go nie psują,
        // a zmiana epoki (powrót na zakładkę, przyjęcie serwerowego startu)
        // liczy próg od nowa. Sam się anuluje, gdy wiersz znika.
        .task(id: startedAt) {
            showsPatience = false
            let wait = Self.patienceAfter - Date().timeIntervalSince(startedAt)
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.4)) { showsPatience = true }
        }
        // VoiceOver słyszy zmianę ETAPU (przekazanie planiście, zapis), nie
        // każdy krok — kroków bywa kilkanaście, a etapy dwa.
        .onChange(of: inPlanning) { _, now in
            if now { AccessibilityNotification.Announcement(label).post() }
        }
        .onChange(of: hasWritten) { _, now in
            if now { AccessibilityNotification.Announcement(label).post() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Zwykłe `if/else` zamiast `reduceMotion ? nil : …` w `withAnimation`
    /// (SE-0418). Ten sam czas co crossfade slotu, żeby wejście i wyjście
    /// wiersza czytały się jako jeden ruch.
    private func reveal() {
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(.easeOut(duration: 0.25)) { appeared = true }
        }
    }
}

/// To, w co zamienia się wskaźnik po turze: ta sama geometria (glif 14 pt
/// w x = 0, tekst od 22 pt, wiersz 22 pt), więc odpowiedź wyłania się
/// w miejscu, a nie obok. Jak „Thought for 12 s ›" u Claude'a: czas po
/// fakcie zamiast tykającego licznika, kroki pod chevronem. Rozwinięcie to
/// stan per wiadomość — nie animacja ciągła, więc nic tu nie zastyga.
struct AssistantThoughtSummary: View {
    let summary: AgentThinkingSummary
    /// Stan trzyma ekran rozmowy po id wiadomości — wiersz przenosi się ze
    /// slotu ostatniej tury do części przed nim i `@State` by nie przeżył.
    @Binding var isExpanded: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSteps: Bool { !summary.steps.isEmpty }
    private var title: String { Self.title(seconds: summary.seconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasSteps {
                Button { toggle() } label: {
                    row
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue("kroki: \(summary.steps.count)")
                .accessibilityHint("Pokazuje kroki")
            } else {
                // Tura bez kroków: wiersz nie jest przyciskiem — przycisk,
                // który nic nie rozwija, jest gorszy niż brak przycisku.
                row
                    .accessibilityLabel(title)
            }

            if isExpanded {
                // Lista po turze jest statyczna — `id: \.offset` nic tu nie przesuwa.
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(summary.steps.enumerated()), id: \.offset) { _, step in
                        Text(step.label)
                            .font(.system(size: 13))
                            .foregroundStyle(stepColor(step))
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 8) {
            SCMarkShape()
                .fill(Color.scFaint(scheme))
                .frame(width: 14, height: 14)
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color.scMuted(scheme))
                .lineLimit(1)
            if hasSteps {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.scFaint(scheme))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .contentShape(Rectangle())
    }

    /// `withAnimation`, nie `.animation(value:)`: rozwinięcie ZMIENIA układ
    /// sąsiadów w `LazyVStack`, a modyfikator na samym wierszu tego nie obejmie.
    private func toggle() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
        }
    }

    /// Cicha powtórka tonów z tury: szałwia = zapis, indygo = planista.
    private func stepColor(_ step: AgentProgressStepDTO) -> Color {
        if step.writes == true { return SCPalette.sage }
        if step.isHandoff { return SCPalette.indigo }
        return Color.scFaint(scheme)
    }

    /// Czas z pary serwerowej `startedAt`/`finishedAt`; `nil` = nie dało się
    /// policzyć i mówimy to ogólnie, zamiast pokazywać „0 s".
    static func title(seconds: Int?) -> String {
        guard let seconds, seconds >= 1 else { return "Myślałem chwilę" }
        if seconds < 60 { return "Myślałem \(seconds) s" }
        let minutes = seconds / 60
        let rest = seconds % 60
        if rest == 0 { return "Myślałem \(minutes) min" }
        return "Myślałem \(minutes) min \(rest) s"
    }
}

#Preview("Wskaźnik tury") {
    let search = AgentProgressStepDTO(tool: "search_recipes", label: "Szukam przepisów", at: "2026-09-18T10:00:01.000Z", writes: nil, phase: nil, transient: nil)
    let handoff = AgentProgressStepDTO(tool: "start_planning", label: "Biorę się za plan", at: "2026-09-18T10:00:05.000Z", writes: nil, phase: "PLANNING", transient: nil)
    let read = AgentProgressStepDTO(tool: "get_week_plan", label: "Czytam plan tygodnia", at: "2026-09-18T10:00:09.000Z", writes: nil, phase: nil, transient: nil)
    let write = AgentProgressStepDTO(tool: "apply_week_plan", label: "Zapisuję plan tygodnia", at: "2026-09-18T10:00:40.000Z", writes: true, phase: nil, transient: nil)

    VStack(alignment: .leading, spacing: 20) {
        AssistantThinkingLine(steps: [], startedAt: Date())
        AssistantThinkingLine(steps: [search], startedAt: Date())
        AssistantThinkingLine(steps: [search, handoff, read], startedAt: Date())
        AssistantThinkingLine(steps: [search, handoff, read, write], startedAt: Date())
        AssistantThinkingLine(steps: [search], startedAt: Date().addingTimeInterval(-30), isStopping: true)
        Divider()
        AssistantThoughtSummary(summary: AgentThinkingSummary(seconds: 42, steps: [search, handoff, read, write]), isExpanded: .constant(false))
        AssistantThoughtSummary(summary: AgentThinkingSummary(seconds: 42, steps: [search, handoff, read, write]), isExpanded: .constant(true))
        AssistantThoughtSummary(summary: AgentThinkingSummary(seconds: 92, steps: []), isExpanded: .constant(false))
    }
    .padding(SCPageMetrics.horizontal)
}

#Preview("Wskaźnik tury — dark") {
    let search = AgentProgressStepDTO(tool: "search_recipes", label: "Szukam przepisów", at: "2026-09-18T10:00:01.000Z", writes: nil, phase: nil, transient: nil)
    let handoff = AgentProgressStepDTO(tool: "start_planning", label: "Biorę się za plan", at: "2026-09-18T10:00:05.000Z", writes: nil, phase: "PLANNING", transient: nil)

    VStack(alignment: .leading, spacing: 20) {
        AssistantThinkingLine(steps: [], startedAt: Date())
        AssistantThinkingLine(steps: [search, handoff], startedAt: Date())
        Divider()
        AssistantThoughtSummary(summary: AgentThinkingSummary(seconds: 42, steps: [search, handoff]), isExpanded: .constant(false))
    }
    .padding(SCPageMetrics.horizontal)
    .preferredColorScheme(.dark)
}

// MARK: - Atomy kart

/// Kontener karty w rozmowie. `tone` steruje tłem i obrysem: sage = zapisane,
/// indigo = analiza, `nil` = zwykła karta.
/// Ton karty i jej przycisku głównego: sage = zapisane, indigo = analiza,
/// neutral = zwykła propozycja. Na poziomie pliku, żeby stopka i akcje mogły
/// go przyjąć bez sięgania przez generyk `AssistantCard<EmptyView>`.
enum AssistantTone { case neutral, sage, indigo }

struct AssistantCard<Content: View>: View {
    typealias Tone = AssistantTone

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
        case .neutral: return Color.scCardSurface(scheme)
        case .sage: return Color.scSageTint(scheme)
        case .indigo: return Color.scIndigoTint(scheme)
        }
    }

    private var stroke: Color {
        switch tone {
        case .neutral: return Color.scCardStroke(scheme)
        case .sage: return SCPalette.sage.opacity(0.24)
        case .indigo: return SCPalette.indigo.opacity(0.26)
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
    var eyebrowColor: Color = SCPalette.terracotta
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
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }
}

extension AssistantCardHead where Right == EmptyView {
    init(eyebrow: String, eyebrowColor: Color = SCPalette.terracotta, title: String) {
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
    var primaryTone: AssistantTone = .neutral
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
                                .foregroundStyle(Color.scMuted(scheme))
                        }
                        Text(secondaryTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Color.scLabel(scheme))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.scTileBg(scheme)))
                    .overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            let primaryAccent: Color = primaryTone == .sage ? SCPalette.sage : SCPalette.terracotta
            Button(action: onPrimary) {
                HStack(spacing: 7) {
                    if isBusy {
                        ProgressView().controlSize(.small).tint(primaryAccent)
                    } else {
                        Image(systemName: primaryIcon)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(primaryTitle)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.25)
                }
                .foregroundStyle(primaryAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .scSoftCapsule(primaryAccent)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .padding(12)
        .background(Color.scPageBase(scheme).opacity(scheme == .dark ? 0.14 : 0.04))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.scRule(scheme)).frame(height: 1)
        }
    }
}

// MARK: - „Uwzględniłem: …”

/// Jedna linia pod odpowiedzią: z czym serwer ją policzył (tydzień, dla
/// kogo, cel). To są te same chipy, co nad polem, tylko po fakcie — i to
/// jest miejsce, w którym łapie się, że asystent wziął złego domownika.
struct AssistantUsedContextLine: View {
    let items: [String]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.scFaint(scheme))
                .padding(.top, 2)
            Text("Uwzględniłem: " + items.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Color.scFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pasek stanu propozycji i akcje zależne od stanu

/// Pasek nad akcjami karty: sześć stanów, jedna ramka.
///
/// Ten sam korpus karty, zmienia się tylko ten pasek i przyciski pod nim —
/// karta w historii jest sterownikiem, nie zdjęciem. Terminy („do piątku”,
/// „Cofnij możliwe jeszcze 52 min”) liczymy z `until`, które serwer daje
/// przy każdym odczycie.
struct AssistantStatusBand: View {
    let state: AgentCardStateDTO

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(tint.opacity(0.16))
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .tracking(-0.15)
                    .foregroundStyle(tint)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.scFaint(scheme))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(scheme == .dark ? 0.10 : 0.07))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.scRule(scheme)).frame(height: 1)
        }
    }

    private var icon: String {
        switch state.status {
        case "APPLIED": return "checkmark"
        case "UNDONE": return "arrow.uturn.backward"
        case "STALE": return "info"
        case "FAILED": return "xmark"
        default: return "clock"
        }
    }

    private var tint: Color {
        switch state.status {
        case "APPLIED": return SCPalette.sage
        case "STALE": return SCPalette.butter
        case "FAILED": return SCPalette.terracotta
        case "EXPIRED", "UNDONE": return Color.scMuted(scheme)
        default: return Color.scMuted(scheme)
        }
    }

    private var title: String {
        switch state.status {
        case "PENDING": return "Propozycja czeka na decyzję"
        case "APPLIED": return "Zapisano w planie"
        case "UNDONE": return "Cofnięto"
        case "STALE": return "Plan zmienił się od tej propozycji"
        case "EXPIRED": return "Propozycja wygasła"
        case "FAILED": return "Nie udało się zapisać"
        default: return "Propozycja"
        }
    }

    private var subtitle: String? {
        switch state.status {
        case "PENDING":
            return Self.deadline(state.until).map { "do \($0)" }
        case "APPLIED":
            return Self.remaining(state.until).map { "Cofnij możliwe jeszcze \($0)" }
        case "UNDONE":
            return "Możesz zastosować ponownie"
        case "STALE":
            return "Zapiszesz mimo to albo poprosisz o nową"
        case "EXPIRED":
            return "Poproś o nową — asystent policzy od nowa"
        case "FAILED":
            return "Plan bez zmian · spróbuj ponownie"
        default:
            return nil
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

/// Akcje propozycji zależne od stanu — to jest cała różnica między
/// zdjęciem a sterownikiem.
///
/// PENDING: zapisz + zmień. UNDONE: zastosuj ponownie. FAILED: spróbuj
/// ponownie. STALE: przelicz na nowo (główna) + zapisz mimo to (duch), bo
/// serwer i tak przeliczy, ale użytkownik ma wiedzieć, że baza się zmieniła.
/// EXPIRED i APPLIED nie mają „Zapisz” wcale — przycisk, który nie zadziała,
/// jest gorszy niż brak przycisku.
struct AssistantProposalFooter: View {
    let state: AgentCardStateDTO
    /// Napis zapisu z serwera („Dodaj do planu”, „Zapisz wtorek”).
    let applyLabel: String
    var applyIcon: String = "checkmark"
    let reviseLabel: String
    var reviseIcon: String = "slider.horizontal.3"
    let isBusy: Bool
    /// `force` = „Zapisz mimo to” przy STALE.
    let onApply: (_ force: Bool) -> Void
    let onRevise: () -> Void
    /// „Poproś o nową” — wysyła gotowe zdanie, bez zapisu.
    let onAskNew: () -> Void
    /// Cofnięcie zapisu z karty, która została ZASTOSOWANA — pasek mówił
    /// „Cofnij możliwe jeszcze 52 min", a przycisku nie było.
    var onUndo: (() -> Void)? = nil
    /// Ton przycisku głównego — zielona karta zapisu dostaje zielony przycisk.
    var tone: AssistantTone = .neutral

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            AssistantStatusBand(state: state)
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state.status {
        case "PENDING" where state.canApply:
            AssistantCardActions(
                primaryTitle: applyLabel,
                primaryIcon: applyIcon,
                primaryTone: tone,
                isBusy: isBusy,
                secondaryTitle: reviseLabel,
                secondaryIcon: reviseIcon,
                onSecondary: onRevise,
                onPrimary: { onApply(false) }
            )
        case "APPLIED" where state.canUndo:
            if let onUndo {
                AssistantCardActions(
                    primaryTitle: "Cofnij zapis",
                    primaryIcon: "arrow.uturn.backward",
                    primaryTone: .sage,
                    isBusy: isBusy,
                    onPrimary: onUndo
                )
            }
        case "UNDONE" where state.canApply:
            AssistantCardActions(
                primaryTitle: "Zastosuj ponownie",
                primaryIcon: "checkmark",
                isBusy: isBusy,
                onPrimary: { onApply(false) }
            )
        case "FAILED" where state.canApply:
            AssistantCardActions(
                primaryTitle: "Spróbuj ponownie",
                primaryIcon: "arrow.uturn.backward",
                isBusy: isBusy,
                onPrimary: { onApply(false) }
            )
        case "STALE" where state.canApply:
            AssistantCardActions(
                primaryTitle: "Przelicz na nowo",
                primaryIcon: "sparkles",
                isBusy: isBusy,
                secondaryTitle: "Zapisz mimo to",
                secondaryIcon: nil,
                onSecondary: { onApply(true) },
                onPrimary: onAskNew
            )
        case "EXPIRED", "STALE":
            AssistantCardActions(
                primaryTitle: "Poproś o nową",
                primaryIcon: "sparkles",
                isBusy: isBusy,
                onPrimary: onAskNew
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - Szybkie odpowiedzi

/// Podpowiedzi kolejnego ruchu pod odpowiedzią — rozmowa nie kończy się ścianą
/// tekstu i pustym polem.
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
