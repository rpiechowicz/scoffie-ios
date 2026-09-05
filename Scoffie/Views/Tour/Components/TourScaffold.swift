import SwiftUI

/// Wymiary wspólne dla siedmiu ekranów przewodnika.
///
/// Ekrany przejeżdżają na bok jeden po drugim, więc każda różnica między
/// nimi jest widoczna jako skok w trakcie przejścia. Przed ujednoliceniem
/// powitanie miało margines 28, kroki 22–24, a górny odstęp wahał się
/// między 10 a 24 punktami — tytuł i chip lądowały za każdym razem gdzie
/// indziej.
enum TourLayout {
    static let horizontal: CGFloat = 24
    /// Zdjęcie kroku wychodzi 4 pt poza margines tekstu — celowo, żeby
    /// kadr czytał się jako fotografia, a nie kolejny akapit.
    static let mediaHorizontal: CGFloat = 20
    static let top: CGFloat = 16
    static let bottom: CGFloat = 8
}

/// Wspólna podłoga wszystkich trzech ekranów przewodnika: kremowe/ciemne
/// tło z ciepłą poświatą u góry.
///
/// Poświata jest tu, a nie w `SCPageBackground`, bo tamta wersja startuje
/// od `scPageBase` (o pół tonu ciemniejszego od canvasu) i pod pełną
/// stroną bez nagłówka robiła widoczny szew przy dolnej krawędzi.
struct TourBackground: View {
    let scheme: ColorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.scCanvas(scheme)
            RadialGradient(
                colors: [
                    SCPalette.terracotta.opacity(scheme == .dark ? 0.24 : 0.16),
                    .clear,
                ],
                center: .top,
                startRadius: 0,
                endRadius: 300
            )
            .frame(height: 380)
        }
        .ignoresSafeArea()
    }
}

/// Przewijalna treść jednego ekranu przewodnika.
///
/// Treść ma mieścić się bez przewijania — taki jest cel projektu i dlatego
/// każdy krok dostaje trzy punkty, a nie pięć. `ScrollView` jest tu jako
/// zabezpieczenie: na iPhonie mini albo przy powiększonej czcionce
/// systemowej to samo ułożenie nie zmieści się co do punktu, a wtedy
/// lepiej przewinąć niż przyciąć. `.basedOnSize` gasi gumowanie, gdy
/// wszystko się mieści, więc na docelowym ekranie strona stoi nieruchomo.
///
/// Stopki tu celowo nie ma. Składa ją `FeatureTourView` pod animowaną
/// treścią, żeby stepper i przyciski stały w miejscu, gdy kroki
/// przejeżdżają na bok — dokładnie tak, jak w kreatorze profilu.
struct TourPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, TourLayout.top)
                .padding(.bottom, TourLayout.bottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

/// Kapsułka nad treścią: ikona w kafelku i krótka etykieta. Kroki mówią
/// nią „Znajdziesz w Zakładce Plan", ekran domykający — „Zostały dwie
/// minuty". Jeden widok dla obu, bo stoją w tym samym miejscu na kolejnych
/// ekranach: inna wysokość albo inne tło robiłyby skok przy przejściu.
struct TourChip: View {
    let icon: String
    let accent: Color
    let label: Text

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.18))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                )

            label
                .font(.system(size: 13))
                .tracking(-0.08)
        }
        .padding(.leading, 7)
        .padding(.trailing, 13)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Color.scTileBg(scheme)))
        .overlay(Capsule(style: .continuous).stroke(Color.scCardStroke(scheme), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Wiersz „ikona w kafelku + tytuł + podpis" z hairline'em pod spodem.
/// Używają go ekran powitalny i ekran domykający — w obu niesie tę samą
/// myśl: jedna rzecz na wiersz, powód napisany wprost.
struct TourFeatureRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    var isLast: Bool = false
    /// Ekran domykający ma dłuższe podpisy i potrzebuje wyrównania do góry.
    var alignsTop: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: alignsTop ? .top : .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint)
                    )
                    .padding(.top, alignsTop ? 1 : 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)

            if !isLast {
                Rectangle()
                    .fill(Color.scCardStroke(scheme))
                    .frame(height: 1)
            }
        }
    }
}

/// Jedna stopka na wszystkie siedem ekranów przewodnika.
///
/// Wcześniej były trzy osobne (powitanie, kroki, domknięcie) i przenikały
/// się krzyżowo — ale miały różną wysokość, więc przy każdej zmianie
/// przycisk główny podskakiwał o 26 pt, a na powitaniu stał wyżej niż na
/// kroku tuż po nim. Teraz układ jest STAŁY: górne gniazdo o stałej
/// wysokości (stepper albo odnośnik „Pomiń", albo nic), pod nim rząd
/// przycisków. Zmienia się tylko zawartość gniazda, tytuł przycisku
/// i obecność „Wstecz" — każde z własnym, cichym przejściem.
///
/// Ten sam szkielet ma `WelcomeFooter`: stepper i przycisk lądują w tym
/// samym miejscu, więc przy przejściu z przewodnika do kreatora pigułki
/// stoją nieruchomo, a zmienia się tylko to, która świeci.
struct TourFooter: View {
    enum Kind: Equatable {
        case intro
        case step(index: Int, total: Int)
        case done

        /// Klucz przejścia gniazda: wszystkie kroki dzielą jedną instancję
        /// steppera, więc pigułka przesuwa się sprężyście, zamiast wjeżdżać
        /// od nowa z każdą stroną.
        var slot: Int {
            switch self {
            case .intro: return 0
            case .step: return 1
            case .done: return 2
            }
        }
    }

    let kind: Kind
    let onBack: () -> Void
    let onPrimary: () -> Void
    let onSkip: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// Wysokość gniazda nad przyciskami — mieści stepper (8 pt) i odnośnik
    /// tekstowy (ok. 18 pt) bez zmiany wysokości stopki. Ta sama wartość w
    /// `WelcomeFooter`.
    static let slotHeight: CGFloat = 20

    private var showsBack: Bool { kind != .intro }

    private var primaryTitle: String {
        switch kind {
        case .intro:
            return "Poznaj aplikację"
        case let .step(index, total):
            return index == total - 1 ? "Poznajmy się" : "Dalej"
        case .done:
            return "Opowiedz nam o sobie"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                slotContent
                    .id(kind.slot)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.slotHeight)
            .animation(.easeInOut(duration: 0.34), value: kind.slot)

            HStack(spacing: 10) {
                if showsBack {
                    SCSoftIconButton(
                        systemName: "chevron.left",
                        accessibilityLabel: "Wstecz",
                        action: onBack
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                SCSoftButton(title: primaryTitle, action: onPrimary)
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: kind)
        }
        .padding(.horizontal, TourLayout.horizontal)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var slotContent: some View {
        switch kind {
        case .intro:
            Button(action: onSkip) {
                Text("Pomiń i przejdź do konfiguracji")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.scMuted(scheme))
            }
            .buttonStyle(.plain)
        case let .step(index, total):
            WelcomeStepper(step: index + 1, total: total)
        case .done:
            Color.clear
        }
    }
}
