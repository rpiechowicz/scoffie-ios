import AudioToolbox
import SwiftUI

/// Koniec timera w aplikacji (ST4, D35): pełny ekran bez doku — tarcza
/// z czasem po terminie liczonym w górę, tytuł i treść alertu ze scenariusza,
/// inne trwające timery, a na dole, w zasięgu kciuka, jak alarm systemu
/// (6.10.2026, „mokre ręce”): duże „Gotowe”, obok „+1 min” i „…” z rzadszymi
/// ruchami (+2 / +5 min, „Tylko wycisz”). Wcześniej było tu pięć przycisków,
/// a najczęstszy — „Wycisz” — stał mały w górnym rogu, poza kciukiem.
/// „Tylko wycisz” zostawia timer po czasie (kapsuła pulsuje mocno); stuknięcie
/// w nią otwiera arkusz Timery z „Gotowe” i „+1 min”.
///
/// Tarcza, aureole, dzwonek i „Gotowe” są w kolorze TEGO timera
/// (runda 3: „każdy inny timer inny kolor”) — ten sam kolor co jego kapsuła.
///
/// Kilka dzwoni naraz (runda 8: „lepszy design i płynne przełączenie”): nad
/// tarczą przełącznik — kapsuła każdego dzwoniącego timera (dzwonek w jego
/// kolorze, nazwa, czas po terminie), wybrana na tincie swojego koloru,
/// zaznaczenie przejeżdża między kapsułami. Stuknięcie albo przeciągnięcie
/// tarczy w bok zmienia timer W MIEJSCU: ekran, tło i przyciski stoją, tarcza
/// i aureole przenikają (wskazówka nie cofa się po obwodzie), kolor przechodzi
/// płynnie, nazwa i tytuł rolują. „Gotowe” i „+1 min” dotyczą pokazywanego
/// timera — ekran przechodzi na następny dzwoniący tym samym ruchem;
/// „Tylko wycisz” ucisza wszystkie.
struct CookAlarmView: View {
    let session: CookSession
    /// Dzwoniące timery w kolejności kroków (`CookSession.ringingTimers`) —
    /// nigdy puste (ekran stoi tylko, gdy coś dzwoni).
    let items: [CookDockTimer]
    let now: Date
    let onExtend: (String, Int) -> Void
    let onSilence: () -> Void
    let onDone: (String) -> Void

    @State private var hasAppeared = false
    /// Pokazywany timer; `nil` albo timer, który przestał dzwonić = pierwszy.
    @State private var selectedId: String?
    /// Przełączenia ręką — haptyka tylko dla nich, nie dla wyboru z kodu.
    @State private var switches = 0
    @Namespace private var chipSpace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: CookDockTimer {
        items.first { $0.id == selectedId } ?? items[0]
    }

    private var color: Color { item.accent.color }

    private var over: TimeInterval {
        if case let .overdue(over, _, _) = item.status { return over }
        return 0
    }

    private var others: [CookDockTimer] {
        session.timerLineup(now: now).filter { other in
            guard other.id != item.id else { return false }
            if case .running = other.status { return true }
            return false
        }
    }

    var body: some View {
        ZStack {
            // Tło wchodzi szybko (dok TimelineView nie niesie animacji, więc
            // przenikanie idzie ze stanu), tarcza i reszta — kaskadą za nim.
            ZStack {
                Color.scPageBase(scheme).ignoresSafeArea()
                CookBackdropPhoto(url: session.imageURL, opacity: SCCook.Opacity.alarmPhoto)
                SCCook.Palette.alarmVeil(scheme).ignoresSafeArea()
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: hasAppeared)

            VStack(spacing: 0) {
                topBar
                    .cookChrome(hasAppeared)
                ZStack {
                    if items.count > 1 {
                        switcher
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .padding(.top, items.count > 1 ? 14 : 0)
                .cookReveal(hasAppeared, order: 0)
                dial
                    .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.86)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.72), value: hasAppeared)
                    .contentShape(Circle())
                    .gesture(dialSwipe)
                    .padding(.top, items.count > 1 ? 18 : 34)
                texts
                    .padding(.top, 26)
                    .cookReveal(hasAppeared, order: 1)
                if !others.isEmpty {
                    VStack(spacing: 8) {
                        // Same pigułki — że lecą dalej, widać po tykającym
                        // czasie (runda 2: „bez sensu ten tekst”).
                        ForEach(others) { other in
                            CookTimerPill(item: other)
                        }
                    }
                    .padding(.top, 16)
                    .cookReveal(hasAppeared, order: 2)
                }
                Spacer(minLength: 16)
                actions
                    .cookReveal(hasAppeared, order: 3)
            }
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.top, 11)
            .padding(.bottom, 8)
        }
        .sensoryFeedback(.warning, trigger: Int(over) / 4)
        .sensoryFeedback(.selection, trigger: switches)
        // Drugi timer zaczyna dzwonić — przełącznik wchodzi łagodnie.
        .animation(.smooth(duration: 0.35), value: items.count > 1)
        .onChange(of: items.map(\.id), initial: true) { _, ids in
            // Pokazywany przestał dzwonić („Gotowe”, „+1 min”) — ekran już
            // pokazuje pierwszy z reszty (`item`), wybór idzie za nim.
            if let selectedId, ids.contains(selectedId) { return }
            selectedId = ids.first
        }
        .task { await ring() }
        .task {
            // Dźwięk i haptyka ruszają od razu, obraz — po klatce oddechu
            // (w klatce wstawienia animacja wejścia nie grała).
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
        .accessibilityAction(named: "Gotowe") { onDone(item.id) }
    }

    // MARK: - Kilka naraz

    private func select(_ id: String) {
        guard id != item.id else { return }
        switches += 1
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : SCMotion.textRoll) {
            selectedId = id
        }
    }

    /// Przeciągnięcie tarczy w bok = sąsiedni dzwoniący timer.
    private var dialSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard items.count > 1,
                      abs(value.translation.width) > 40,
                      abs(value.translation.width) > abs(value.translation.height),
                      let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                let next = value.translation.width < 0 ? index + 1 : index - 1
                guard items.indices.contains(next) else { return }
                select(items[next].id)
            }
    }

    /// Kapsuły dzwoniących timerów — zaznaczenie (tint i obwódka w kolorze
    /// wybranego) przejeżdża między nimi.
    private var switcher: some View {
        AllergenChipFlow(spacing: 8, alignment: .center) {
            ForEach(items) { other in
                chip(other)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dzwonią \(items.count) \(PolishPlural.form(items.count, one: "timer", few: "timery", many: "timerów"))")
    }

    private func chip(_ other: CookDockTimer) -> some View {
        let selected = other.id == item.id
        let tint = other.accent.color
        let overText: String = {
            if case let .overdue(over, _, _) = other.status { return CookClock.overdueText(over) }
            return ""
        }()
        return Button { select(other.id) } label: {
            HStack(spacing: 7) {
                Image(systemName: "bell.fill")
                    .font(.sc(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(other.timer.label)
                    .font(.sc(size: 14, weight: .bold))
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                Text(overText)
                    .font(.sc(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .cookTicking(overText, countsDown: false)
            }
            .padding(.horizontal, 12)
            .frame(height: SCCook.Height.alarmChip)
            .background {
                ZStack {
                    Capsule()
                        .fill(Color.scCanvas(scheme).opacity(0.78))
                        .overlay(Capsule().strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
                    if selected {
                        Capsule()
                            .fill(tint.opacity(scheme == .dark ? 0.22 : 0.16))
                            .overlay(Capsule().strokeBorder(tint, lineWidth: 1.5))
                            .matchedGeometryEffect(id: "alarm-chip", in: chipSpace)
                    }
                }
            }
            .contentShape(Capsule())
            .scTapHeight(44, drawn: SCCook.Height.alarmChip)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(other.timer.label), po czasie \(overText)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Dźwięk alarmu co 2 s, dopóki nie padnie „Tylko wycisz”, „+min” albo „Gotowe” —
    /// widok znika z ekranu, a zadanie razem z nim. Gdy dzwoni alarm
    /// systemowy (`CookAlarmScheduler`, runda 11 — dźwięk alarmu telefonu),
    /// ekran swojego nie dokłada; własny dźwięk zostaje zapasem na brak
    /// zgody na alarmy.
    private func ring() async {
        // Alarm systemowy rusza w tej samej sekundzie co ekran — chwila na
        // jego start, żeby pierwszy takt nie zagrał dwoma dźwiękami naraz.
        if CookAlarmScheduler.shared.isAuthorized {
            try? await Task.sleep(for: .milliseconds(800))
        }
        while !Task.isCancelled {
            if case let .overdue(_, _, silenced) = item.status, silenced { return }
            if !CookAlarmScheduler.shared.isSystemAlerting {
                AudioServicesPlayAlertSound(SystemSoundID(1005))
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Sam pierścień kroków — „Wycisz” zszedł z rogu do „…” na dole
    /// („Tylko wycisz”), w zasięgu kciuka.
    private var topBar: some View {
        CookStepRing(count: session.stepCount, current: session.stepIndex)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Tarcza jak stoper (runda 4: „teksty wychodzą poza zegar — doszlifuj
    /// go”): po obwodzie podziałka sekund, po niej krąży kropka wskazówki ze
    /// smugą — raz na minutę po czasie, bez powrotu na start (`CookAlarmBezel`).
    /// W krążku zostają tylko trzy krótkie wiersze, każdy w szerokości, która
    /// mieści się w kole: nazwa timera z dzwonkiem, licznik i „po czasie”.
    /// Dłuższe maleją, zamiast wychodzić poza tarczę; czas nastawienia
    /// („było 10–12 min”) stoi w nagłówku „…”, przy +2 / +5 min.
    private var dial: some View {
        let minutes = Int(over) / 60
        let counter = CookClock.overdueText(over)
        return ZStack {
            // Inny timer = inna tarcza: aureole i podziałka przenikają (nowy
            // widok), zamiast cofać wskazówkę po obwodzie do krótszego czasu.
            ZStack {
                CookAlarmHalos(accent: item.accent)
                    .id(item.id)
                    .transition(.opacity)
            }
            ZStack {
                CookAlarmBezel(color: color, over: over)
                    .id(item.id)
                    .transition(.opacity)
            }
            .frame(width: SCCook.Size.alarmRing, height: SCCook.Size.alarmRing)
            Circle()
                .fill(Color.scPageBase(scheme))
                .overlay(Circle().strokeBorder(color, lineWidth: SCCook.Stroke.alarmDisc))
                .frame(width: SCCook.Size.alarmDisc, height: SCCook.Size.alarmDisc)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    CookBell(isRinging: !reduceMotion)
                    Text(item.timer.label.uppercased(with: Locale(identifier: "pl_PL")))
                        .cookText(SCCook.Typography.stage)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .cookRoll(item.timer.label)
                }
                .foregroundStyle(color)
                .frame(maxWidth: SCCook.Size.alarmTextWidth)
                Text(counter)
                    .cookText(SCCook.Typography.alarmCounter)
                    .monospacedDigit()
                    .foregroundStyle(Color.scLabel(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: SCCook.Size.alarmCounterWidth)
                    .cookTicking(counter, countsDown: false)
                    .padding(.top, 2)
                Text("po czasie")
                    .font(.sc(size: 13, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: SCCook.Size.alarmTextWidth)
            }
        }
        .frame(width: SCCook.Size.alarmDial, height: SCCook.Size.alarmDial)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.timer.label): czas minął \(minutes > 0 ? "\(minutes) min temu" : "przed chwilą")")
    }

    private var texts: some View {
        VStack(spacing: 10) {
            Text(item.timer.alert.title)
                .cookText(SCCook.Typography.alarmTitle)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .cookRoll(item.timer.alert.title)
                .accessibilityAddTraits(.isHeader)
            // Treść alertu przenika przy zmianie timera — akapit rolowany
            // literami był nieczytelny.
            ZStack {
                Text(item.timer.alert.body)
                    .font(.sc(size: 17))
                    .lineSpacing(4)
                    .foregroundStyle(SCCook.Palette.alarmBody(scheme))
                    .multilineTextAlignment(.center)
                    .id(item.id)
                    .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Akcje

    /// Na dole, w zasięgu kciuka — jak alarm systemu: duże „Gotowe” i jedna
    /// akcja dodatkowa („+1 min”), a rzadsze ruchy w systemowym menu „…”.
    /// Główna po prawej (pod kciukiem), „…” najdalej od niej. Dawny panel
    /// „Jeszcze chwilę?” (+1 / +2 / +5 min nad „Gotowe — dalej”) odpadł — jego
    /// przyciski stoją tu, a „było 10 min” w nagłówku menu, przy +2 / +5.
    private var actions: some View {
        HStack(spacing: SCCook.Spacing.alarmActionGap) {
            moreMenu
            extendButton
            doneButton
        }
    }

    /// „Gotowe” — kończy POKAZYWANY timer (i idzie krok dalej, gdy stoimy na
    /// jego kroku); przy kilku dzwoniących ekran zostaje następnemu.
    /// Pełny kolor timera — jedyna kryjąca kontrolka ekranu, jak „Zatrzymaj”
    /// w Zegarze iOS (decyzja 6.10.2026: zostaje pełny, nie „soft”); pismo
    /// z `CookTimerAccent.ink`, żeby czytało się na każdym z siedmiu kolorów.
    private var doneButton: some View {
        Button { onDone(item.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.sc(size: 17, weight: .heavy))
                Text("Gotowe")
                    .cookText(SCCook.Typography.buttonQuiet)
                    .lineLimit(1)
            }
            .foregroundStyle(item.accent.ink(scheme))
            .frame(maxWidth: .infinity)
            .frame(height: SCCook.Height.alarmDone)
            .scChromeGlass(in: Capsule(), tint: color)
            .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
        .accessibilityLabel("Gotowe: \(item.timer.label)")
        .accessibilityHint(items.count > 1 ? "Kończy ten timer, ekran przejdzie do następnego" : "Kończy timer")
    }

    /// „+1 min” — dokłada minutę POKAZYWANEMU timerowi; ten przestaje
    /// dzwonić i wraca do odliczania.
    private var extendButton: some View {
        Button { onExtend(item.id, 60) } label: {
            Text("+1 min")
                .cookText(SCCook.Typography.buttonQuiet)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Color.scLabel(scheme))
                // Wysokość jak „Gotowe” (`height.cookAlarmDone`), żeby rząd był równy.
                .padding(.horizontal, SCCook.Spacing.alarmExtendInset)
                .frame(height: SCCook.Height.alarmDone)
                .scChromeGlass(in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PlanPressStyle(scale: 0.96))
        .accessibilityLabel("Dodaj minutę: \(item.timer.label)")
    }

    /// „…” — systemowe menu: +2 / +5 min dla pokazywanego timera (w nagłówku
    /// czas, na jaki był nastawiony) i „Tylko wycisz” — dla WSZYSTKICH
    /// dzwoniących, bez kończenia (dźwięk jest jeden).
    private var moreMenu: some View {
        Menu {
            Section {
                ForEach([2, 5], id: \.self) { minutes in
                    Button("+\(minutes) min") { onExtend(item.id, minutes * 60) }
                }
            } header: {
                Text("Jeszcze chwilę? Było \(CookClock.duration(item.timer))")
            }
            Section {
                Button(action: onSilence) {
                    Label(items.count > 1 ? "Tylko wycisz wszystkie" : "Tylko wycisz", systemImage: "speaker.slash")
                }
            }
        } label: {
            // Szkło jako CAŁA etykieta menu — iOS 26 rozwija menu z krążka.
            Image(systemName: "ellipsis")
                .font(.sc(size: 18, weight: .bold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(width: SCCook.Height.alarmDone, height: SCCook.Height.alarmDone)
                .scChromeGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .accessibilityLabel("Więcej")
    }
}

/// Dwie aureole za tarczą, na zmianę (skala 0,86 → 1,22, krycie 0,55 → 0),
/// w kolorze timera.
private struct CookAlarmHalos: View {
    let accent: CookTimerAccent

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Circle()
                .fill(accent.tint(scheme))
                .frame(width: SCCook.Size.alarmHalo, height: SCCook.Size.alarmHalo)
        } else {
            TimelineView(.animation) { context in
                let period = SCCook.Duration.alarmHalo
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    halo(phase: (t / period).truncatingRemainder(dividingBy: 1), color: accent.color.opacity(SCCook.Opacity.alarmHalo))
                    halo(phase: (t / period + 0.5).truncatingRemainder(dividingBy: 1), color: accent.tint(scheme))
                }
            }
        }
    }

    private func halo(phase: Double, color: Color) -> some View {
        let eased = 1 - pow(1 - phase, 3)
        return Circle()
            .fill(color)
            .frame(width: SCCook.Size.alarmHalo, height: SCCook.Size.alarmHalo)
            .scaleEffect(0.86 + (1.22 - 0.86) * eased)
            .opacity(0.55 * (1 - eased))
    }
}

/// Pierścień tarczy końca timera: podziałka sekund (60 kresek, co piąta
/// dłuższa) i kropka wskazówki ze smugą, która okrąża go raz na minutę po
/// czasie. Kąt rośnie bez końca (6° na sekundę) i dojeżdża liniowo przez
/// sekundę, więc na pełnej minucie wskazówka biegnie dalej — dawny łuk
/// „sekund bieżącej minuty” wracał co minutę do zera.
private struct CookAlarmBezel: View {
    let color: Color
    let over: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let angle = over / 60 * 360
        let hand = SCCook.Size.alarmHand
        let ring = SCCook.Size.alarmRing
        // Smuga jako ułamek obwodu pierścienia.
        let trail = Double(SCCook.Size.alarmTrail / (.pi * ring))
        ZStack {
            CookAlarmTicks(every: 1, skippingEvery: 5, length: SCCook.Size.alarmTick)
                .stroke(color.opacity(SCCook.Opacity.alarmTick), style: StrokeStyle(lineWidth: SCCook.Stroke.alarmTick, lineCap: .round))
            CookAlarmTicks(every: 5, skippingEvery: 0, length: SCCook.Size.alarmTickMajor)
                .stroke(color.opacity(SCCook.Opacity.alarmTickMajor), style: StrokeStyle(lineWidth: SCCook.Stroke.alarmTick, lineCap: .round))
            ZStack {
                Circle()
                    .trim(from: 1 - trail, to: 1)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0), color],
                            center: .center,
                            startAngle: .degrees(360 * (1 - trail)),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: SCCook.Stroke.alarmTrail, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(color)
                    .frame(width: hand, height: hand)
                    .shadow(color: color.opacity(0.5), radius: 4)
                    .offset(y: -ring / 2)
            }
            .rotationEffect(.degrees(angle))
            .animation(reduceMotion ? nil : .linear(duration: 1), value: angle)
        }
        .accessibilityHidden(true)
    }
}

/// Kreski podziałki sekund od obwodu do środka: `every` — co ile sekund,
/// `skippingEvery` — bez kresek, które rysuje druga, dłuższa podziałka.
private struct CookAlarmTicks: Shape {
    let every: Int
    let skippingEvery: Int
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        var path = Path()
        for second in stride(from: 0, to: 60, by: every) {
            if skippingEvery > 0, second % skippingEvery == 0 { continue }
            let angle = Double(second) / 60 * 2 * .pi - .pi / 2
            let dx = CGFloat(cos(angle))
            let dy = CGFloat(sin(angle))
            path.move(to: CGPoint(x: center.x + dx * outer, y: center.y + dy * outer))
            path.addLine(to: CGPoint(x: center.x + dx * (outer - length), y: center.y + dy * (outer - length)))
        }
        return path
    }
}

/// Dzwonek, który się kołysze (`CookBellSwing`): 0° → 14° → −12° → 8° → 0°
/// w pierwszych 40 % okresu, potem spoczynek; oś u góry dzwonka.
private struct CookBell: View {
    let isRinging: Bool

    var body: some View {
        if isRinging {
            TimelineView(.animation) { context in
                let period = SCCook.Duration.alarmBell
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                bell.rotationEffect(.degrees(CookBellSwing.angle(at: t)), anchor: CookBellSwing.anchor)
            }
        } else {
            bell
        }
    }

    private var bell: some View {
        Image(systemName: "bell.fill")
            .font(.sc(size: 12, weight: .bold))
    }
}
