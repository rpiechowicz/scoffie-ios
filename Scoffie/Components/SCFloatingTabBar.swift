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

    let items: [SCTabBarItem]
    @Binding var selection: DashboardTab
    let isCompact: Bool

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill
    /// Zakładka podświetlona NA PASKU — kopia `selection` z własną
    /// transakcją. `selection` musi zmieniać się BEZ animacji (inaczej
    /// `TabView` przenika treść), a pigułka ma się przesunąć — jedna
    /// wartość nie może jechać w dwóch transakcjach naraz, więc są dwie.
    @State private var highlighted: DashboardTab?

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.38)
    }

    /// Ruch pigułki między zakładkami — jak systemowa pigułka z iOS 26:
    /// krótka sprężyna, bez odbicia.
    private var pillMotion: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3, extraBounce: 0)
    }

    private var current: DashboardTab { highlighted ?? selection }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .padding(.horizontal, 6)
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
        .animation(motion, value: isCompact)
        // Zmiana spoza paska (asystent → Plan, wylogowanie): pigułka
        // dojeżdża tą samą sprężyną, co po stuknięciu.
        .onChange(of: selection) { _, tab in
            guard highlighted != tab else { return }
            withAnimation(pillMotion) { highlighted = tab }
        }
        // Bez `sensoryFeedback` i bez `.animation(value: selection)` na całym
        // pasku: systemowy pasek nie wibruje przy zmianie zakładki, a
        // animacja na całym `HStack` łapała też wypełnienie symbolu i podpis
        // — każde stuknięcie było trzema ruchami zamiast jednego.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zakładki")
    }

    private func tabButton(_ item: SCTabBarItem) -> some View {
        let selected = item.tab == current
        return Button {
            guard item.tab != selection else { return }
            // Zmiana wyboru spoza systemowego paska jest dla `TabView` zmianą
            // „programową", a taką od iOS 18 pokazuje przenikaniem treści —
            // stąd animacja, której z systemowym paskiem nie było. Transakcja
            // bez animacji przywraca cięcie jak w systemie. Pigułka jedzie
            // w OSOBNEJ transakcji po `highlighted` — gdyby animować
            // `selection`, `TabView` znów przenikałby treść.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { selection = item.tab }
            withAnimation(pillMotion) { highlighted = item.tab }
        } label: {
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
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? Self.compactHeight - 8 : Self.expandedHeight - 8)
            .background {
                if selected {
                    Capsule(style: .continuous)
                        .fill(SCPalette.terracotta.opacity(scheme == .dark ? 0.2 : 0.13))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PlanPressStyle(scale: 0.94))
        .accessibilityLabel(item.title)
        .accessibilityValue(item.badge > 0 ? "\(item.badge) nowe" : "")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
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
