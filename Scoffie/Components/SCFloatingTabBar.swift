import SwiftUI

// MARK: - Stan paska

/// Stan dolnego menu współdzielony między paskiem a treścią zakładek.
///
/// Pasek jest własny (nie systemowy), bo systemowe `tabBarMinimizeBehavior`
/// z iOS 26 zwija menu do JEDNEJ ikony bieżącej zakładki — a chodzi o to,
/// co robi Revolut: przy przewijaniu w dół pasek robi się niższy i węższy,
/// podpisy znikają, ale WSZYSTKIE ikony zostają i dalej da się w nie stuknąć.
/// Systemowy pasek nie ma takiego trybu, więc rysujemy go sami.
///
/// Kto pisze: `scTracksTabBarCompaction()` na głównym `ScrollView` zakładki
/// (kierunek przewijania) i `NavigationMenu` (klawiatura, zmiana zakładki).
/// Kto czyta: `SCFloatingTabBar` (wysokość) i rezerwa miejsca pod treścią.
@Observable
final class SCTabBarChrome {
    /// Pasek zwinięty do samych ikon.
    var isCompact = false
    /// Klawiatura zasłania pasek — treść nie rezerwuje pod nim miejsca,
    /// inaczej pole asystenta wisiałoby 70 pt nad klawiaturą.
    var isKeyboardVisible = false
}

private struct SCTabBarChromeKey: EnvironmentKey {
    @MainActor static let defaultValue = SCTabBarChrome()
}

extension EnvironmentValues {
    var scTabBarChrome: SCTabBarChrome {
        get { self[SCTabBarChromeKey.self] }
        set { self[SCTabBarChromeKey.self] = newValue }
    }
}

// MARK: - Pozycja

struct SCTabBarItem: Identifiable {
    let tab: DashboardTab
    let title: String
    let icon: String
    var badge: Int = 0

    var id: DashboardTab { tab }
}

// MARK: - Pasek

/// Pływające dolne menu z Liquid Glass, które kurczy się przy przewijaniu.
///
/// Dwa stany. Pełny: ikona z podpisem, 20 pt od krawędzi ekranu — dokładnie
/// tam, gdzie stał pasek systemowy, więc pole asystenta nad nim (też 20 pt)
/// dalej jest z nim w jednej linii. Zwinięty: same ikony, pasek niższy
/// o jedną czwartą i węższy o ~60 pt — czyta się jako TEN SAM pasek, który
/// zszedł z drogi treści, a nie jako inny element.
///
/// Dotyk jest JEDEN na cały pasek, jak w systemowym pasku z iOS 26: pigułka
/// idzie za palcem (stuknięcie, przeciągnięcie w lewo i w prawo), a zakładka
/// zmienia się po puszczeniu. Pozycje nie są przyciskami — nie ma stylu
/// wciśnięcia, `matchedGeometryEffect` ani osobnych animacji na ikonach,
/// które wcześniej nakładały się na siebie przy szybkim przełączaniu.
///
/// Rezerwa pod treścią (`reservedHeight`) jest STAŁA, liczona od pełnego
/// paska: pasek pływa nad treścią, a treść nie skacze przy każdym zwinięciu.
struct SCFloatingTabBar: View {
    static let expandedHeight: CGFloat = 60
    static let compactHeight: CGFloat = 46
    /// Margines boczny pełnego paska — ten sam co pole asystenta.
    static let sideMargin: CGFloat = 20
    static let compactSideMargin: CGFloat = 50
    /// Ile treść trzyma pod paskiem, żeby ostatni wiersz kończył się nad szkłem.
    static let reservedHeight: CGFloat = expandedHeight + 8
    /// Wcięcie pozycji od krawędzi szkła.
    private static let innerPadding: CGFloat = 6

    let items: [SCTabBarItem]
    @Binding var selection: DashboardTab
    let isCompact: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Palec na pasku: środek pigułki w układzie paska. `nil` = pigułka
    /// stoi na wybranej zakładce.
    @State private var dragX: CGFloat?

    private var compaction: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.38)
    }

    /// Pigułka za palcem: krótka sprężyna bez odbicia — nadąża za ruchem,
    /// a pierwszy dotyk daleko od pigułki nie jest teleportacją.
    private var follow: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .interactiveSpring(response: 0.2, dampingFraction: 0.9)
    }

    /// Dojazd pigułki na środek zakładki po puszczeniu palca.
    private var settle: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.26, extraBounce: 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let slot = slotWidth(in: proxy.size.width)
            let highlighted = highlightedIndex(slot: slot)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.2 : 0.13))
                    .frame(width: slot, height: proxy.size.height - 8)
                    .scaleEffect(dragX == nil ? 1 : 1.06)
                    .offset(x: pillCenter(slot: slot, width: proxy.size.width) - slot / 2)

                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        tabLabel(item, selected: index == highlighted)
                    }
                }
                .padding(.horizontal, Self.innerPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Capsule(style: .continuous))
            .gesture(touch(slot: slot))
        }
        .frame(height: isCompact ? Self.compactHeight : Self.expandedHeight)
        // To samo szkło co pigułka „Cel dnia" i pole asystenta: warstwa tła
        // pod szkłem przygasza przelatującą treść do rozmytej plamy, odblaski
        // zostają na szkle.
        .glassEffect(
            .regular.tint(Color.scPageBase(scheme).opacity(0.35)),
            in: .capsule
        )
        .background(Color.scPageBase(scheme).opacity(0.72), in: .capsule)
        .padding(.horizontal, isCompact ? Self.compactSideMargin : Self.sideMargin)
        .animation(compaction, value: isCompact)
        // Zmiana spoza paska (asystent → Plan, powiadomienie): pigułka
        // dojeżdża tą samą sprężyną, co po puszczeniu palca.
        .animation(settle, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zakładki")
    }

    // MARK: Geometria

    private func slotWidth(in width: CGFloat) -> CGFloat {
        max(1, (width - 2 * Self.innerPadding) / CGFloat(max(items.count, 1)))
    }

    private func center(of index: Int, slot: CGFloat) -> CGFloat {
        Self.innerPadding + slot * (CGFloat(index) + 0.5)
    }

    private func index(at x: CGFloat, slot: CGFloat) -> Int {
        let raw = Int(((x - Self.innerPadding) / slot).rounded(.down))
        return min(max(raw, 0), items.count - 1)
    }

    private func pillCenter(slot: CGFloat, width: CGFloat) -> CGFloat {
        let selected = items.firstIndex { $0.tab == selection } ?? 0
        guard let dragX else { return center(of: selected, slot: slot) }
        // Pigułka nie wyjeżdża poza szkło, nawet gdy palec zjedzie z paska.
        return min(max(dragX, center(of: 0, slot: slot)), center(of: items.count - 1, slot: slot))
    }

    private func highlightedIndex(slot: CGFloat) -> Int {
        if let dragX { return index(at: dragX, slot: slot) }
        return items.firstIndex { $0.tab == selection } ?? 0
    }

    // MARK: Dotyk

    private func touch(slot: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                withAnimation(follow) { dragX = value.location.x }
            }
            .onEnded { value in
                let tab = items[index(at: value.location.x, slot: slot)].tab
                // Treść zmienia się CIĘCIEM, jak w systemie — animuje się
                // wyłącznie pigułka. Dwie osobne transakcje, żeby sprężyna
                // pigułki nie przeszła na budowanie treści zakładki.
                if tab != selection {
                    var cut = Transaction()
                    cut.disablesAnimations = true
                    withTransaction(cut) { selection = tab }
                }
                withAnimation(settle) { dragX = nil }
            }
    }

    // MARK: Pozycja

    private func tabLabel(_ item: SCTabBarItem, selected: Bool) -> some View {
        VStack(spacing: isCompact ? 0 : 3) {
            Image(systemName: item.icon)
                .font(.system(size: 22, weight: .medium))
                .symbolVariant(selected ? .fill : .none)
                // Skalowanie zamiast mniejszego kroju: rozmiar czcionki
                // nie animuje się płynnie, `scaleEffect` tak.
                .scaleEffect(isCompact ? 0.86 : 1)
                .frame(width: 28, height: 26)
                .scCountBadge(item.badge, offset: CGSize(width: 8, height: -4))

            Text(item.title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(-0.1)
                .lineLimit(1)
                .fixedSize()
                // Podpis zwija się do zera wysokości i gaśnie — nie
                // znika skokiem, tylko chowa się pod ikonę.
                .frame(height: isCompact ? 0 : 12)
                .opacity(isCompact ? 0 : 1)
                .clipped()
        }
        .foregroundStyle(selected ? SCPalette.terracotta : Color.scMuted(scheme))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Kolor i wypełnienie symbolu przeskakują razem z pigułką — bez
        // własnej animacji, która ciągnęłaby się za palcem.
        .animation(nil, value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.badge > 0 ? "\(item.badge) nowe" : "")
        .accessibilityAddTraits(item.tab == selection ? [.isSelected, .isButton] : [.isButton])
        .accessibilityAction {
            var cut = Transaction()
            cut.disablesAnimations = true
            withTransaction(cut) { selection = item.tab }
        }
    }
}

// MARK: - Śledzenie przewijania

/// Zwija pasek przy przewijaniu w dół, rozwija przy przewijaniu w górę.
///
/// Zawieszone na `onScrollGeometryChange`, nie na gestach: to samo źródło,
/// z którego korzysta system, więc działa też przy programowym przewinięciu
/// i przy odhaczaniu wiersza, który przesuwa listę.
///
/// Trzy zasady, żeby pasek nie „mrugał":
/// - blisko góry (do 24 pt) zawsze pełny — tam jest miejsce i tam się wraca;
/// - liczy się DROGA w jednym kierunku (28 pt), a nie pojedyncza klatka —
///   drżenie palca o kilka punktów nic nie przełącza;
/// - odbicia sprężyste na końcach listy nie liczą się wcale: offset jest
///   przycinany do zakresu treści, więc szarpnięcie za dół listy nie
///   rozwija paska.
/// Lista krótsza niż ekran plus 120 pt nie zwija nic — nie ma czego
/// przewijać, więc nie ma z czego schodzić.
private struct SCTabBarCompactionTracker: ViewModifier {
    @Environment(\.scTabBarChrome) private var chrome
    /// Droga przebyta w bieżącym kierunku: dodatnia w dół, ujemna w górę.
    @State private var run: CGFloat = 0

    private static let topSlack: CGFloat = 24
    private static let runThreshold: CGFloat = 28
    private static let minimumOverflow: CGFloat = 120

    private struct Sample: Equatable {
        var offset: CGFloat
        /// O ile treść jest dłuższa od okna — maksymalny sensowny offset.
        var overflow: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Sample.self) { geometry in
                Sample(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    overflow: geometry.contentSize.height
                        + geometry.contentInsets.top + geometry.contentInsets.bottom
                        - geometry.containerSize.height
                )
            } action: { old, new in
                handle(old: old, new: new)
            }
    }

    private func handle(old: Sample, new: Sample) {
        guard new.overflow > Self.minimumOverflow else {
            run = 0
            set(compact: false)
            return
        }
        if new.offset <= Self.topSlack {
            run = 0
            set(compact: false)
            return
        }
        let clampedNew = min(max(new.offset, 0), new.overflow)
        let clampedOld = min(max(old.offset, 0), new.overflow)
        let delta = clampedNew - clampedOld
        guard delta != 0 else { return }
        if (delta > 0) != (run > 0) { run = 0 }
        run += delta
        if run > Self.runThreshold {
            set(compact: true)
        } else if run < -Self.runThreshold {
            set(compact: false)
        }
    }

    private func set(compact: Bool) {
        guard chrome.isCompact != compact else { return }
        chrome.isCompact = compact
    }
}

/// Rezerwa miejsca pod własnym paskiem — KORZEŃ każdej zakładki, WEWNĄTRZ
/// jej `NavigationStack`.
///
/// Wchodzi bezpiecznym obszarem, nie paddingiem: `ScrollView` przewija wtedy
/// treść POD szkłem paska (widać ją przez nie), a kończy nad nim — jak
/// z paskiem systemowym. Wysokość jest stała (od pełnego paska), więc
/// zwijanie nie rusza układu. Przy klawiaturze schodzi do zera, bo pasek
/// i tak jest pod nią — inaczej pole asystenta wisiałoby 70 pt nad klawiaturą.
///
/// Dlaczego wewnątrz `NavigationStack`, a nie raz na `TabView`: wcięcie
/// założone NA ZEWNĄTRZ stosu nie dochodzi do jego korzenia (stos bierze
/// bezpieczny obszar od UIKit), więc pigułka „Cel dnia" i ostatnie wiersze
/// list lądowały pod paskiem. Nakładać PO wcięciach własnych ekranu
/// (pigułka celu dnia), żeby rezerwa była najniżej.
private struct SCTabBarSpaceReservation: ViewModifier {
    @Environment(\.scTabBarChrome) private var chrome

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: chrome.isKeyboardVisible ? 0 : SCFloatingTabBar.reservedHeight)
                .animation(.easeOut(duration: 0.25), value: chrome.isKeyboardVisible)
        }
    }
}

extension View {
    /// Główny `ScrollView` zakładki melduje kierunek przewijania do paska.
    func scTracksTabBarCompaction() -> some View {
        modifier(SCTabBarCompactionTracker())
    }

    /// Korzeń zakładki trzyma pod treścią miejsce na pasek — patrz
    /// `SCTabBarSpaceReservation`.
    func scReservesTabBarSpace() -> some View {
        modifier(SCTabBarSpaceReservation())
    }
}

#Preview("Pełny i zwinięty") {
    struct Demo: View {
        @State private var tab: DashboardTab = .calendar
        @State private var compact = false
        var body: some View {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.orange.opacity(0.3), .blue.opacity(0.3)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 24) {
                    Toggle("Zwinięty", isOn: $compact).padding()
                    Spacer()
                    SCFloatingTabBar(
                        items: [
                            SCTabBarItem(tab: .recipes, title: "Przepisy", icon: "book.pages"),
                            SCTabBarItem(tab: .plan, title: "Plan", icon: "receipt"),
                            SCTabBarItem(tab: .calendar, title: "Kalendarz", icon: "calendar"),
                            SCTabBarItem(tab: .assistant, title: "Asystent", icon: "sparkles", badge: 2),
                            SCTabBarItem(tab: .settings, title: "Ustawienia", icon: "gearshape"),
                        ],
                        selection: $tab,
                        isCompact: compact
                    )
                }
            }
        }
    }
    return Demo()
}
