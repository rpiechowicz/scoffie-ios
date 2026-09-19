import SwiftUI

// Powłoka ekranu asystenta — nagłówek, szkic odpowiedzi w trakcie tury
// oraz atomy kart. Wiersz „myślę" nad odpowiedzią (praca → osiadanie) żyje
// w `AssistantThoughtLine.swift`. Wydzielone z `AssistantView`, bo od tej zmiany odpowiedź
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

// MARK: - Szkic odpowiedzi

/// Szkic odpowiedzi w trakcie tury — tekst „pisze się" pod wskaźnikiem.
///
/// Serwer streamuje z modelu, ale telefon odpytuje co sekundę, więc bez
/// tego widoku tekst wskakiwałby akapitami raz na sekundę. Tu odsłania się
/// znak po znaku i DOGANIA serwer w ~0,9 s od każdej porcji — oko widzi
/// ciągłe pisanie, a nie serię skoków. Liczone z zegara względem kotwicy
/// ustawianej przy każdej zmianie tekstu; żadnej pętli na `@State`, więc
/// przebudowy widoku (nowy krok postępu, nowa porcja) niczego nie zatrzymują.
///
/// Serwer oddaje CAŁY dotychczasowy tekst, nie przyrost — i potrafi go
/// wyzerować, gdy runda skończyła się narzędziem (preambuła „sprawdzę plan…"
/// nie jest odpowiedzią). Gdy nowy tekst nie zaczyna się od pokazanego,
/// odsłanianie rusza od zera zamiast pokazywać znaki, których już nie ma.
struct AssistantDraftAnswer: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchorDate = Date()
    @State private var anchorCount = 0
    /// Znaki na sekundę; rośnie z zaległością, żeby nigdy nie zostać w tyle.
    @State private var rate: Double = 45

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let shown = reduceMotion ? text.count : revealedCount(at: context.date)
            AssistantAnswer(text: String(text.prefix(shown)))
        }
        .onChange(of: text) { old, new in
            let now = Date()
            let current = min(revealedCount(at: now), new.count)
            let continues = new.hasPrefix(String(old.prefix(current)))
            anchorCount = continues ? current : 0
            anchorDate = now
            rate = max(45, Double(new.count - anchorCount) / 0.9)
        }
    }

    private func revealedCount(at date: Date) -> Int {
        let elapsed = max(0, date.timeIntervalSince(anchorDate))
        return min(text.count, anchorCount + Int(elapsed * rate))
    }
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
