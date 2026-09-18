import SwiftUI

// Wspólne klocki ekranów „Co potrafi asystent", onboardingu i „Jak działa
// asystent" (projekt „Asystent Zgoda", 3.09.2026): opisy możliwości,
// miniatury kart, które wracają z serwera, i atomy w dark-first stylu
// Cozy Kitchen. Jedna implementacja — trzy wejścia.

// MARK: - Ton i kolory

enum AssistantAccent {
    case terracotta, sage, indigo, butter

    var color: Color {
        switch self {
        case .terracotta: return SCPalette.terracotta
        case .sage: return SCPalette.sage
        case .indigo: return SCPalette.indigo
        case .butter: return SCPalette.butter
        }
    }

    func tint(_ scheme: ColorScheme) -> Color {
        switch self {
        case .terracotta: return Color.scAccentTint(scheme)
        case .sage: return Color.scSageTint(scheme)
        case .indigo: return Color.scIndigoTint(scheme)
        case .butter: return Color.scButterTint(scheme)
        }
    }
}

/// Kafelek z ikoną w tinacie akcentu — jak w Ustawieniach.
struct AssistantIconTile: View {
    let icon: String
    let accent: AssistantAccent
    var size: CGFloat = 32
    var radius: CGFloat = 10

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(accent.tint(scheme))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(accent.color)
            )
    }
}

/// Karta w stylu asystenta: tło kafla, cienki obrys, 20 pt.
struct AssistantSurfaceCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.scTileBg(scheme)))
            // Tła wierszy (podświetlony wiersz zgody, rozwinięty wiersz
            // akordeonu) to prostokąty — bez przycięcia wystawały z rogów.
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))
    }
}

/// Stopka przyklejona do dołu: treść chowa się pod miękkim gradientem tła,
/// jak w kreatorze „Poznajmy się". Wewnątrz przyciski w stylu `SCSoftButton`.
struct AssistantStickyFooter<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 10) { content() }
            .padding(.horizontal, SCPageMetrics.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background {
                VStack(spacing: 0) {
                    // Ten sam kolor co `SCPageBackground` (scPageBase), nie kanwa —
                    // inny odcień rysował twardą linię nad przyciskiem. Gradient
                    // zaczyna się NAD stopką (ujemny offset), więc nie zjada
                    // miejsca, a treść i tak ginie pod nim łagodnie.
                    LinearGradient(
                        colors: [Color.scPageBase(scheme).opacity(0), Color.scPageBase(scheme)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 36)
                    .offset(y: -36)
                    .padding(.bottom, -36)
                    Color.scPageBase(scheme)
                }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
    }
}

/// Drugorzędny przycisk stopki — tekst bez wypełnienia, obok `SCSoftButton`.
struct AssistantTextButton: View {
    let title: String
    var role: ButtonRole? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(role == .destructive ? SCPalette.terracotta : Color.scMuted(scheme))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Etykieta sekcji kapitalikami.
struct AssistantSectionLabel: View {
    let text: String
    var color: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(color ?? Color.scMuted(scheme))
    }
}

/// Dymek „jak wiadomość użytkownika" z przykładowym poleceniem. Gdy ma
/// `onTap`, jest przyciskiem: ekran pomocy kończy się wysłaniem, nie czytaniem.
struct AssistantExampleBubble: View {
    let text: String
    var onTap: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Spacer(minLength: 0)
            Button {
                onTap?()
            } label: {
                // Bez strzałki „wyślij" w dymku: to podgląd pytania, nie pole
                // wysyłki, a strzałka sugerowała akcję także tam, gdzie dymek
                // jest tylko ilustracją. Stuknięcie nadal wysyła, gdy ma `onTap`.
                Text(text)
                    .font(.system(size: 14.5))
                    .tracking(-0.2)
                    .lineSpacing(2.5)
                    .foregroundStyle(Color.scLabel(scheme))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous)
                        .fill(Color.scAccentTint(scheme))
                )
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous)
                        .stroke(SCPalette.terracotta.opacity(0.25), lineWidth: 1)
                )
                .frame(maxWidth: 260, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            .accessibilityLabel(onTap == nil ? "Przykład: \(text)" : "Wyślij: \(text)")
        }
    }
}

/// Podgląd wymiany: dymek użytkownika (opcjonalnie do wysłania), pod nim
/// odpowiedź asystenta w jego prawdziwej formie — tekst na całą szerokość
/// i karta. Pokazuje, CO wróci, zamiast kazać wierzyć opisowi.
struct AssistantExchangePreview: View {
    let example: String
    var reply: String? = nil
    var thumb: AssistantCapability.Thumb? = nil
    var weekDays: Int = 7
    var onSend: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AssistantExampleBubble(text: example, onTap: onSend)

            if let reply {
                HStack(alignment: .top, spacing: 10) {
                    AssistantIconTile(icon: "sparkles", accent: .terracotta, size: 26, radius: 8)
                        .padding(.top, 1)
                    Text(reply)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .foregroundStyle(Color.scLabel(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Asystent: \(reply)")
            }

            if let thumb {
                // Karta na pełną szerokość, jak w prawdziwej rozmowie —
                // wcięcie pod tekst zabierałoby jej 36 pt.
                AssistantThumb(kind: thumb, weekDays: weekDays)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - Możliwości (dane)

/// Jedna umiejętność asystenta — źródło prawdy dla trzech ekranów.
struct AssistantCapability: Identifiable {
    enum Thumb { case week, day, swap, macro, split, options, shopping, clarify, decide, edit, limits }

    let id: String
    let icon: String
    let accent: AssistantAccent
    let title: String
    let body: String
    let example: String?
    let thumb: Thumb?
    /// Zdanie, którym asystent odpowiada na `example` — nad kartą, tak jak
    /// w prawdziwej rozmowie (odpowiedź to tekst na całą szerokość + karta).
    var reply: String? = nil
}

enum AssistantCapabilities {
    static let all: [AssistantCapability] = [
        .init(id: "week", icon: "sparkles", accent: .terracotta, title: "Plan całego tygodnia", body: "Układa wszystkie włączone posiłki na 7 dni z uwzględnieniem diety, alergenów, wykluczeń, celu kalorycznego i maks. czasu gotowania.", example: "Zaplanuj cały tydzień, w tygodniu szybkie obiady", thumb: .week, reply: "Ułożyłem 14 posiłków na 12–18 września: w tygodniu obiady do 30 minut, w weekend luźniej. Średnio 2 023 kcal przy celu 2 100 — sprawdź i dodaj do planu."),
        .init(id: "day", icon: "calendar", accent: .terracotta, title: "Plan jednego dnia", body: "Dokłada brakujące posiłki dnia albo przebudowuje go od nowa pod Twój cel.", example: "Ułóż mi czwartek pod 1800 kcal", thumb: .day, reply: "Dołożyłem do czwartku obiad, kolację i przekąskę; śniadanie zostawiłem, bo już było. Razem 1 600 kcal, 200 zostaje do celu."),
        .init(id: "swap", icon: "arrow.triangle.2.circlepath", accent: .indigo, title: "Podmiana dania", body: "Jedno danie w slocie, z powodem zmiany i różnicą kalorii.", example: "Podmień wtorkową kolację na coś bez laktozy do 30 minut", thumb: .swap, reply: "Zapiekanka odpada przez laktozę i 55 minut. Proponuję tofu z warzywami i ryżem: 25 minut, o 80 kcal mniej, nic nie trzeba dokupować."),
        .init(id: "macro", icon: "chart.bar.fill", accent: .indigo, title: "Domknięcie makro", body: "Pokazuje, ile średnio brakuje białka, węgli, tłuszczu albo kalorii, i proponuje boostery jednym stuknięciem.", example: "Czego brakuje w planie, żeby wyrobić się z białkiem?", thumb: .macro, reply: "Do 140 g białka brakuje średnio 24 g dziennie. Dwa boostery domkną to bez zmiany dań — stuknij, który dołożyć."),
        .init(id: "split", icon: "person.2.fill", accent: .sage, title: "Różne dania dla domowników", body: "Ta sama baza, inne porcje dla osób z innymi ograniczeniami.", example: "Ania nie je ryb, zrób jej coś innego w piątek", thumb: .split, reply: "Ania dostaje kurczaka z warzywami zamiast pstrąga, reszta domu bez zmian. Jedna baza, dwie wersje, te same zakupy."),
        .init(id: "options", icon: "list.bullet.rectangle", accent: .butter, title: "Kilka opcji do wyboru", body: "2–4 propozycje z katalogu zamiast decyzji za Ciebie.", example: "Daj mi trzy szybkie kolacje do wyboru", thumb: .options, reply: "Trzy szybkie kolacje, wszystkie do 12 minut i w Twoim limicie. Wybierz jedną, resztę odłożę."),
        .init(id: "shopping", icon: "cart.fill", accent: .sage, title: "Lista zakupów z planu", body: "Składniki z tego, co jest w planie, pogrupowane działami sklepu.", example: "Co wyjdzie na liście zakupów z tego tygodnia?", thumb: .shopping, reply: "Z planu na ten tydzień wychodzą 23 pozycje w 5 działach; 4 już masz odhaczone. Dodać całość do listy?"),
        .init(id: "cook", icon: "text.book.closed.fill", accent: .butter, title: "Skład i sposób przygotowania", body: "Czyta cały przepis: wszystkie składniki z gramaturą i kroki po kolei. Pyta o to bazę, więc nie zgaduje ze skrótu w katalogu.", example: "Jak ugotować ten czwartkowy obiad?", thumb: nil, reply: "Kurczak w curry z ryżem, 4 porcje, 35 minut. Potrzebujesz 600 g piersi, 400 ml mleka kokosowego, 250 g ryżu i pasty curry — kroki mam, mogę je wypisać."),
        .init(id: "byingredient", icon: "magnifyingglass", accent: .butter, title: "Dania z tego, co masz", body: "Szuka po CAŁYM składzie przepisów, nie po nazwach dań — znajdzie też te, w których składnik jest w środku.", example: "Co mogę zrobić z bakłażanem?", thumb: nil, reply: "W katalogu są cztery dania z bakłażanem, od 25 do 55 minut. Najszybsze to warzywa z piekarnika; mam je wstawić w któryś wieczór?"),
        .init(id: "remove", icon: "trash", accent: .indigo, title: "Zdjęcie dania z planu", body: "Usuwa jeden posiłek, nie ruszając reszty tygodnia. Może zdjąć je tylko Tobie — reszta domu zostaje przy swoim.", example: "W czwartek jemy u teściów, zdejmij kolację", thumb: nil, reply: "Zdejmuję czwartkową kolację — reszta tygodnia bez zmian. Z listy zakupów zniknie wtedy cukinia i feta."),
        .init(id: "checkoff", icon: "checkmark.circle.fill", accent: .sage, title: "Odhaczanie zjedzonego i zakupów", body: "„Zjadłem obiad” zmienia Twój bilans dnia, „kupiłem mleko i jajka” odhacza pozycje na liście. Bez wychodzenia z rozmowy.", example: "Kupiłem mleko i jajka", thumb: nil, reply: "Odhaczyłem mleko i jajka. Na liście zostaje 12 rzeczy w 4 działach."),
        .init(id: "recipes", icon: "book.closed.fill", accent: .butter, title: "Własne przepisy", body: "Tworzy przepis domu ze składników katalogu, poprawia go i usuwa. Makro liczy sam.", example: "Zapisz mój przepis na chili: 400 g indyka mielonego, puszka fasoli, passata, papryka…", thumb: nil, reply: "Zapisałem „Chili z indykiem” w przepisach domu: 4 porcje, 610 kcal i 42 g białka na porcję. Poprawisz jednym zdaniem."),
        .init(id: "memory", icon: "brain.head.profile", accent: .indigo, title: "Pamięć domu", body: "Zapamiętuje fakty na prośbę i używa ich w każdym planie. Notatki widzisz i kasujesz w menu.", example: "Zapamiętaj, że w piątki jemy rybę", thumb: nil, reply: "Zapamiętałem: w piątki jecie rybę. Uwzględnię to w każdym kolejnym planie; notatkę znajdziesz w menu → Pamięć domu."),
        .init(id: "scope", icon: "person.crop.circle.badge.checkmark", accent: .sage, title: "Dla kogo liczyć", body: "Pytanie może dotyczyć jednej osoby albo całego domu. Napisz to w zdaniu — asystent czyta to z pytania, nie z osobnego ustawienia.", example: "Policz bilans tylko dla mnie", thumb: nil, reply: "Liczę tylko dla Ciebie: dziś 1 980 kcal przy celu 2 100. Napisz „dla całego domu”, jeśli mam policzyć inaczej."),
        .init(id: "clarify", icon: "questionmark.bubble.fill", accent: .terracotta, title: "Dopytanie zamiast zgadywania", body: "Gdy brakuje informacji, asystent zadaje jedno konkretne pytanie z gotowymi odpowiedziami.", example: nil, thumb: .clarify),
        .init(id: "decide", icon: "checkmark.rectangle.stack.fill", accent: .sage, title: "Ty decydujesz", body: "Każda zmiana planu to karta z „Dodaj do planu”. Nic nie zapisuje się samo; zapis cofniesz przyciskiem „Cofnij zapis” w ciągu doby. Propozycja jest ważna 3 dni, a jeśli ktoś w domu zmienił plan po propozycji, karta prosi „Przelicz na nowo”.", example: nil, thumb: .decide),
        .init(id: "edit", icon: "pencil.and.outline", accent: .butter, title: "Poprawianie i zgłaszanie", body: "Przytrzymaj swoje pytanie, żeby je poprawić lub zadać jeszcze raz. Przytrzymaj odpowiedź, żeby ją zgłosić lub skopiować.", example: nil, thumb: .edit),
        .init(id: "limits", icon: "lock.shield.fill", accent: .indigo, title: "Limity i prywatność", body: "Pula wiadomości i zapisanych planów na miesiąc dla całego domu. Do modelu nie idą wzrost, waga, płeć, rok urodzenia, kroki ani e-mail; dane domowników tylko za ich zgodą. Zgodę cofniesz w menu.", example: nil, thumb: .limits),
    ]

    static func by(_ id: String) -> AssistantCapability {
        all.first { $0.id == id } ?? all[0]
    }

    struct Group: Identifiable {
        let id: String
        let label: String
        let accent: AssistantAccent
        let lead: String
        let items: [String]
    }

    /// Cztery grupy po tym, co użytkownik ROBI: planuje → liczy → dzieli na dom → kupuje.
    static let groups: [Group] = [
        .init(id: "plan", label: "Plan i posiłki", accent: .terracotta, lead: "To, co asystent robi najczęściej", items: ["week", "day", "swap", "options"]),
        .init(id: "goal", label: "Cel i makro", accent: .indigo, lead: "Liczy pod Twoje zapotrzebowanie", items: ["macro", "scope"]),
        .init(id: "home", label: "Dom", accent: .sage, lead: "Różne osoby, jeden plan", items: ["split", "memory"]),
        .init(id: "kitchen", label: "Zakupy i przepisy", accent: .butter, lead: "Z planu do sklepu i z powrotem", items: ["shopping", "recipes"]),
    ]

    struct Rule: Identifiable {
        let id: String
        let icon: String
        let accent: AssistantAccent
        let title: String
        let detail: String
    }

    static let rules: [Rule] = [
        .init(id: "auto", icon: "checkmark.rectangle.stack.fill", accent: .sage, title: "Nic nie zapisuje się samo", detail: "Każda zmiana to karta z „Dodaj do planu”. Cofniesz ją w ciągu doby."),
        .init(id: "ttl", icon: "clock.fill", accent: .butter, title: "Propozycja żyje 3 dni", detail: "Jeśli ktoś w domu zmienił plan po drodze, karta poprosi „Przelicz na nowo”."),
        .init(id: "ask", icon: "questionmark.bubble.fill", accent: .terracotta, title: "Dopyta, zamiast zgadywać", detail: "Jedno konkretne pytanie z gotowymi odpowiedziami do stuknięcia."),
        .init(id: "edit", icon: "pencil.and.outline", accent: .indigo, title: "Poprawisz i zgłosisz", detail: "Przytrzymaj swoje pytanie, żeby je poprawić; odpowiedź — żeby zgłosić lub skopiować."),
    ]

    /// Sześć kart onboardingu — wszystkie możliwości pogrupowane po tym, co user robi.
    struct OnboardingCard: Identifiable {
        let id: String
        let icon: String
        let accent: AssistantAccent
        let title: String
        let body: String
        let example: String?
        var reply: String? = nil
        let thumb: AssistantCapability.Thumb?
        var showsPrivacy: Bool = false
        var showsCapabilitiesLink: Bool = false
    }

    /// Cztery karty — jedna na to, co user robi najczęściej. „Ty decydujesz"
    /// i prywatność nie mają własnych kart: siedzą jako wiersz na ostatniej,
    /// bo to zasady, nie umiejętności. Limity zostają pod menu ⋯.
    static let onboarding: [OnboardingCard] = [
        .init(id: "plan", icon: "sparkles", accent: .terracotta, title: "Zaplanuj tydzień albo jeden dzień", body: "Asystent zna dietę, alergeny, cele i maks. czas gotowania wszystkich domowników, którzy wyrazili zgodę. Powiedz, co i na kiedy.", example: "Zaplanuj mi obiady i kolacje na ten tydzień, w tygodniu do 30 minut", reply: "Ułożyłem obiady i kolacje na cały tydzień, w tygodniu wszystko do 30 minut. Średnio 2 023 kcal przy celu 2 100 — sprawdź i dodaj do planu.", thumb: .week),
        .init(id: "swap", icon: "arrow.triangle.2.circlepath", accent: .indigo, title: "Podmieniaj, domykaj makro, wybieraj", body: "Jedno danie, cały dzień, brakujące białko albo kilka opcji do wyboru. Każda zmiana ma powód i różnicę kalorii.", example: "Podmień kolację we wtorek na coś bez laktozy", reply: "Zapiekanka odpada przez laktozę i 55 minut. Proponuję tofu z warzywami i ryżem: 25 minut, o 80 kcal mniej, nic nie trzeba dokupować.", thumb: .swap),
        .init(id: "home", icon: "person.2.fill", accent: .sage, title: "Cały dom albo tylko Ty", body: "Inne porcje dla osób z innymi ograniczeniami. Kogo dotyczy pytanie, mówisz w samym zdaniu, a fakty typu „nie jemy pieczarek” asystent zapamięta i użyje w każdym planie.", example: "Ania nie je ryb, zrób jej coś innego w piątek", reply: "Ania dostaje kurczaka z warzywami zamiast pstrąga, reszta domu bez zmian. Jedna baza, dwie wersje, te same zakupy.", thumb: .split),
        .init(id: "kitchen", icon: "cart.fill", accent: .butter, title: "Zakupy i Twoje przepisy", body: "Lista zakupów z tego, co jest w planie, pogrupowana działami sklepu. Własny przepis zapiszesz jednym zdaniem — makro policzy sam.", example: "Co wyjdzie na liście zakupów z tego tygodnia?", reply: "Z planu na ten tydzień wychodzą 23 pozycje w 5 działach; 4 już masz odhaczone. Dodać całość do listy?", thumb: .shopping, showsPrivacy: true, showsCapabilitiesLink: true),
    ]
}

// MARK: - Miniatury kart

/// Miniatura karty, która wraca z serwera — statyczna, przykładowa, ta sama
/// na trzech ekranach. Dane są zmyślone i tak podpisane w projekcie.
struct AssistantThumb: View {
    let kind: AssistantCapability.Thumb
    /// Ile dni pokazuje miniatura tygodnia (onboarding: 3, pełny ekran: 7).
    var weekDays: Int = 7

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch kind {
        case .week: week
        case .day: day
        case .swap: swap
        case .macro: macro
        case .split: split
        case .options: options
        case .shopping: shopping
        case .clarify: clarify
        case .decide: decide
        case .edit: edit
        case .limits: limits
        }
    }

    // ─── klocki

    private func mini<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.scInsetSurface(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.scTileStroke(scheme), lineWidth: 1))
            .accessibilityElement(children: .combine)
    }

    /// Eyebrow i dopisek po prawej w jednym wierszu, tytuł pod nimi na całą
    /// szerokość. Wcześniej tytuł dzielił wiersz z dopiskiem i przy 325 pt
    /// łamał się na dwie linie („12–18 września · / 14 posiłków"), a eyebrow
    /// 13 pt kapitalikami — na trzy.
    private func head(_ eyebrow: String, _ title: String, right: String? = nil, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(eyebrow)
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(color ?? SCPalette.terracotta)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let right {
                    Text(right)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.scMuted(scheme))
                        .lineLimit(1)
                }
            }
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Color.scLabel(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    private func row(_ left: String?, _ middle: String, _ right: String?, dim: Bool = false, strike: Bool = false) -> some View {
        HStack(spacing: 8) {
            if let left {
                Text(left)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.scMuted(scheme))
                    .frame(width: 34, alignment: .leading)
            }
            Text(middle)
                .font(.system(size: 13))
                .strikethrough(strike)
                .foregroundStyle(Color.scLabel(scheme))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let right {
                Text(right)
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Color.scMuted(scheme))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .opacity(dim ? 0.5 : 1)
    }

    /// Ramka ma 13 pt — tyle, co znacznik celu. Wcześniej 7 pt (sam pasek),
    /// a 12-punktowy znacznik wystawał poza nią i siadał na podpisie pod
    /// spodem: „Średnio 2 023 kcal" było przyklejone do paska.
    private func bar(_ fraction: Double, color: Color, target: Double? = nil) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.scBarTrack(scheme)).frame(height: 7)
                Capsule().fill(color).frame(width: geometry.size.width * min(1, fraction), height: 7)
                if let target {
                    Rectangle()
                        .fill(Color.scLabel(scheme))
                        .frame(width: 2, height: 13)
                        .offset(x: geometry.size.width * min(1, target) - 1)
                }
            }
            .frame(height: 13)
        }
        .frame(height: 13)
    }

    /// Pasek z podpisem pod nim — jeden odstęp dla wszystkich miniatur.
    private func barBlock<Caption: View>(_ fraction: Double, color: Color, target: Double? = nil, @ViewBuilder caption: () -> Caption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            bar(fraction, color: color, target: target)
            caption()
                .font(.system(size: 13))
                .foregroundStyle(Color.scMuted(scheme))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// Rząd chipów, który nie łamie chipów na dwie linie: przy ciaśniejszej
    /// szerokości (akordeon „Co potrafi") przewija się w bok, zamiast
    /// zawijać „Ten tydzień" do „Ten / tydzień".
    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) { content() }
                .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func foot(primary: String = "Dodaj do planu", ghost: String = "Zmień", tone: Color = SCPalette.terracotta) -> some View {
        HStack(spacing: 6) {
            Text(ghost)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.scLabel(scheme))
                .padding(.horizontal, 11)
                .frame(height: 36)
                .overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
                Text(primary).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .scSoftCapsule(tone)
        }
        .padding(.horizontal, 12)
        .padding(.top, 13)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) }
    }

    private func chip(_ text: String, accent: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(accent ? SCPalette.terracotta : Color.scMuted(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(accent ? Color.scAccentTint(scheme) : Color.scChipBg(scheme)))
    }

    private func avatar(_ initial: String, _ color: Color, size: CGFloat = 24) -> some View {
        Circle().fill(color).frame(width: size, height: size)
            .overlay(Text(initial).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(Color.scPageBase(scheme)))
    }

    // ─── miniatury

    private var week: some View {
        let days = [("Pon", "Curry z ciecierzycą", "1 980"), ("Wt", "Łosoś z kaszą", "2 040"), ("Śr", "Makaron z cukinią", "1 910"), ("Czw", "Chili z indykiem", "2 120"), ("Pt", "Pstrąg z warzywami", "1 960"), ("Sob", "Shakshuka", "2 060"), ("Nd", "Pieczony kurczak", "2 090")].prefix(weekDays)
        return mini {
            head("Propozycja · Tydzień", "12–18 września · 14 posiłków", right: "cel 2 100 kcal/dzień")
            ForEach(Array(days), id: \.0) { d in row(d.0, d.1, "\(d.2) kcal") }
            barBlock(0.96, color: SCPalette.sage, target: 1) {
                HStack { Text("Średnio 2 023 kcal"); Spacer(); Text("−77 do celu") }
            }
            foot()
        }
    }

    private var day: some View {
        mini {
            head("Propozycja · Czwartek", "3 posiłki dołożone", right: "cel 1 800")
            row("Śn.", "Owsianka z orzechami · jest", "420", dim: true)
            row("Ob.", "Chili z indykiem", "610")
            row("Kol.", "Sałatka z jajkiem", "380")
            row("Prz.", "Jogurt z jagodami", "190")
            barBlock(0.89, color: SCPalette.terracotta, target: 1) {
                HStack { Text("1 600 kcal"); Spacer(); Text("zostaje 200 do celu").foregroundStyle(SCPalette.sage).fontWeight(.semibold) }
            }
            foot()
        }
    }

    private var swap: some View {
        mini {
            head("Podmiana · Wtorek, kolacja", "Bez laktozy, do 30 min")
            row(nil, "Zapiekanka z serem", "720 kcal", dim: true, strike: true)
            HStack(spacing: 6) {
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                Text("powód: laktoza, 55 min")
            }
            .font(.system(size: 11)).foregroundStyle(SCPalette.sage).padding(.horizontal, 14)
            row(nil, "Tofu z warzywami i ryżem", "640 kcal")
            chipRow { chip("−25 min"); chip("−80 kcal"); chip("0 zł do dokupienia") }
                .padding(.top, 4).padding(.bottom, 12)
            foot(primary: "Podmień")
        }
    }

    private var macro: some View {
        mini {
            head("Makro · Białko", "Brakuje średnio 24 g dziennie")
            barBlock(0.69, color: SCPalette.indigo, target: 1) {
                HStack { Text("116 g / dzień"); Spacer(); Text("cel 140 g") }
            }
            .padding(.top, -4)
            .padding(.bottom, 4)
            // Kiedy i co w dwóch linijkach, przyrost po prawej. W jednym
            // wierszu z kolumną 86 pt na termin opis boostera ucinał się do
            // „zamień makaron na…" — dokładnie ten fragment, który mówi, co
            // zrobić.
            ForEach([("Wt · kolacja", "Dołóż jogurt grecki 200 g", "+18 g"), ("Czw · obiad", "Zamień makaron na soczewicę", "+22 g")], id: \.0) { b in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.0).font(.system(size: 12)).foregroundStyle(Color.scMuted(scheme))
                        Text(b.1).font(.system(size: 13.5)).foregroundStyle(Color.scLabel(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(b.2).font(.system(size: 13.5, weight: .bold)).monospacedDigit().foregroundStyle(SCPalette.indigo)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .overlay(alignment: .top) { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) }
            }
            Text("Stuknięcie wysyła pytanie o booster, nic nie zapisuje.")
                .font(.system(size: 12.5)).foregroundStyle(Color.scFaint(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 12)
        }
    }

    private var split: some View {
        mini {
            head("Podział · Piątek, obiad", "Jedna baza, dwie wersje")
            // Krótkie nazwy: wiersz ma awatar, imię i kalorie, więc na danie
            // zostaje ~170 pt — „Pstrąg z warzywami · pół porcji" ucinało się
            // w połowie tego, co odróżnia wersje.
            ForEach([("M", SCPalette.terracotta, "Marek", "Pstrąg z warzywami", "640"), ("Z", SCPalette.indigo, "Zosia", "Pstrąg · pół porcji", "380"), ("A", SCPalette.sage, "Ania", "Kurczak · bez ryby", "610")], id: \.2) { p in
                HStack(spacing: 8) {
                    avatar(p.0, p.1)
                    Text(p.2).fontWeight(.semibold).foregroundStyle(Color.scLabel(scheme)).frame(width: 54, alignment: .leading)
                    Text(p.3).lineLimit(1).foregroundStyle(Color.scMuted(scheme))
                    Spacer(minLength: 4)
                    Text(p.4).monospacedDigit().foregroundStyle(Color.scMuted(scheme))
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14).padding(.vertical, 7)
            }
            foot()
        }
    }

    private var options: some View {
        mini {
            head("Opcje · Kolacja", "Trzy szybkie kolacje do wyboru")
            ForEach(Array([("Omlet ze szpinakiem", "12 min · 410"), ("Tosty z awokado i jajkiem", "10 min · 460"), ("Sałatka z tuńczykiem", "8 min · 390")].enumerated()), id: \.offset) { i, o in
                HStack(spacing: 8) {
                    Circle()
                        .strokeBorder(i == 0 ? SCPalette.butter : Color.scFaint(scheme), lineWidth: 1.5)
                        .background(Circle().fill(i == 0 ? SCPalette.butter : Color.clear))
                        .frame(width: 18, height: 18)
                    Text(o.0).lineLimit(1).foregroundStyle(Color.scLabel(scheme))
                    Spacer(minLength: 4)
                    Text(o.1).foregroundStyle(Color.scMuted(scheme))
                }
                .font(.system(size: 13))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) } }
            }
            foot(primary: "Wybierz tę", ghost: "Inne")
        }
    }

    private var shopping: some View {
        mini {
            head("Zakupy · Ten tydzień", "23 pozycje · 5 działów", right: "4 odhaczone", color: SCPalette.terracotta)
            ForEach([("Warzywa i owoce", "cukinia 2 szt. · szpinak 200 g · cytryna"), ("Mięso i ryby", "indyk mielony 400 g · łosoś 2 × 150 g"), ("Nabiał", "jogurt grecki 400 g · tofu 300 g")], id: \.0) { d in
                VStack(alignment: .leading, spacing: 2) {
                    AssistantSectionLabel(text: d.0, color: SCPalette.sage).font(.system(size: 13, weight: .bold))
                    Text(d.1).font(.system(size: 13)).foregroundStyle(Color.scMuted(scheme)).lineLimit(1)
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
            }
            HStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
                Text("Dodaj do listy zakupów").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(SCPalette.sage)
            .frame(maxWidth: .infinity).frame(height: 36)
            .scSoftCapsule(SCPalette.sage)
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
        }
    }

    // Miniatura `scope` rysowała chipy „Ten tydzień · Tylko ja · Cel 2 100
    // kcal" — obrazek kontrolki, której nie ma. Zakres mówi się teraz zdaniem,
    // więc karta „Dla kogo liczyć" została bez miniatury.

    private var clarify: some View {
        mini {
            Text("W piątek o 18:00 masz w kalendarzu trening. Kolacja przed nim czy po?")
                .font(.system(size: 14)).lineSpacing(2).foregroundStyle(Color.scLabel(scheme))
                .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)
            chipRow { chip("Przed, lekka", accent: true); chip("Po, do 20 min", accent: true); chip("Pomiń kolację", accent: true) }
                .padding(.bottom, 12)
        }
    }

    private var decide: some View {
        mini {
            head("Zapisano · 14:02", "Kolacja we wtorek podmieniona", color: SCPalette.sage)
            VStack(alignment: .leading, spacing: 5) {
                Label("Cofnij zapis możliwy jeszcze 23 h 40 min", systemImage: "arrow.uturn.backward")
                Label("Propozycja ważna 3 dni od otrzymania", systemImage: "clock")
                Label { Text("Plan zmieniony po propozycji → ") + Text("Przelicz na nowo").fontWeight(.bold).foregroundColor(Color.scLabel(scheme)) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(SCPalette.butter) }
            }
            .font(.system(size: 13)).foregroundStyle(Color.scMuted(scheme))
            .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 10)
            HStack(spacing: 6) {
                Label("Cofnij zapis", systemImage: "arrow.uturn.backward").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.scLabel(scheme))
                    .padding(.horizontal, 11).frame(height: 36).overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
                Text("Otwórz plan").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.scLabel(scheme))
                    .frame(maxWidth: .infinity).frame(height: 36).overlay(Capsule().stroke(Color.scTileStroke(scheme), lineWidth: 1))
            }
            .padding(.horizontal, 12).padding(.top, 13).padding(.bottom, 12)
            .overlay(alignment: .top) { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) }
        }
    }

    private var edit: some View {
        HStack(spacing: 8) {
            ForEach([("Twoje pytanie", ["Popraw", "Zadaj jeszcze raz"]), ("Odpowiedź", ["Zgłoś odpowiedź", "Kopiuj"])], id: \.0) { g in
                mini {
                    Text(g.0).font(.system(size: 13, weight: .bold)).tracking(0.6).textCase(.uppercase).foregroundStyle(Color.scFaint(scheme))
                        .padding(.horizontal, 12).padding(.top, 13).padding(.bottom, 3)
                    ForEach(g.1, id: \.self) { m in
                        Text(m).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.scLabel(scheme))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { Rectangle().fill(Color.scRule(scheme)).frame(height: 1) }
                    }
                }
            }
        }
    }

    private var limits: some View {
        mini {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("Wiadomości").fontWeight(.semibold).foregroundStyle(Color.scLabel(scheme)); Spacer(); (Text("12").bold().foregroundColor(Color.scLabel(scheme)) + Text(" z 200")).foregroundStyle(Color.scMuted(scheme)) }.font(.system(size: 13.5))
                bar(0.06, color: SCPalette.terracotta)
                HStack { Text("Zapisane plany").fontWeight(.semibold).foregroundStyle(Color.scLabel(scheme)); Spacer(); (Text("2").bold().foregroundColor(Color.scLabel(scheme)) + Text(" z 30")).foregroundStyle(Color.scMuted(scheme)) }.font(.system(size: 13.5)).padding(.top, 4)
                bar(0.07, color: SCPalette.sage)
                Text("Wspólne dla całego domu · odnowienie 1 października").font(.system(size: 13.5)).foregroundStyle(Color.scFaint(scheme)).padding(.top, 2)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
    }
}
