import SwiftUI

// Powłoka ekranu asystenta — 1:1 z `kit.jsx` makiety v4: nagłówek w dwóch
// rozmiarach, kapsuła limitu, okrągły przycisk, dymki wiadomości, szkic
// odpowiedzi w trakcie tury i linia „Uwzględniłem”. Wiersz „pracuję” żyje
// w `AssistantThoughtLine.swift`, atomy kart w `AssistantCardKit.swift`,
// briefing pustego ekranu w `AssistantBriefingCard.swift`.

// MARK: - Okrągły przycisk

/// `LRoundBtn`: krążek 36 (34 w kompaktowym pasku) — białe tło, włoskowaty
/// obrys, ikona 18 w kolorze tuszu. Sam RYSUNEK, żeby `Menu` mógł go
/// użyć jako etykiety.
struct AssistantRoundLabel: View {
    let icon: String
    var size: CGFloat = 36
    var tint: Color? = nil
    var color: Color? = nil
    var iconSize: CGFloat = 18

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().fill(tint ?? (scheme == .dark ? AssistantLook.field(scheme) : Color.white.opacity(0.7)))
            Circle().stroke(AssistantLook.cardStroke(scheme), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color ?? AssistantLook.ink(scheme))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

struct AssistantRoundButton: View {
    let icon: String
    var size: CGFloat = 36
    var tint: Color? = nil
    var color: Color? = nil
    var iconSize: CGFloat = 18
    var accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AssistantRoundLabel(icon: icon, size: size, tint: tint, color: color, iconSize: iconSize)
                .scTapTarget(44, drawn: size)
        }
        .buttonStyle(PlanPressStyle(scale: 0.9))
        .accessibilityLabel(accessibilityTitle)
    }
}

// MARK: - Nagłówek

/// Nagłówek zakładki w dwóch rozmiarach.
///
/// Duży tytuł tylko na pustym ekranie; w rozmowie kompaktowy pasek ze
/// znakiem i słowem „Asystent” na środku oddaje miejsce strumieniowi.
enum AssistantHeaderMode: Equatable {
    case large
    /// Tytuł rozmowy zostaje w modelu, ale makieta go nie pokazuje —
    /// kompaktowy pasek mówi „Asystent”.
    case compact(title: String?)
}

struct AssistantHeader<MenuContent: View>: View {
    typealias Mode = AssistantHeaderMode

    let mode: Mode
    var onNewConversation: () -> Void
    /// Kapsuła limitu po lewej od ⋯ — tylko na próbie, tylko w dużym nagłówku.
    var accessory: AnyView?
    /// Pozycje menu ⋯ — systemowe `Menu` z ikonami, nie arkusz z dołu.
    @ViewBuilder var menu: () -> MenuContent

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch mode {
        case .large:
            HStack(alignment: .center, spacing: 8) {
                Text("Asystent")
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(AssistantLook.ink(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                accessory
                    .fixedSize(horizontal: true, vertical: false)
                menuButton(size: 36)
            }
            .padding(.leading, SCPageMetrics.horizontal)
            .padding(.trailing, 16)
            .padding(.top, SCPageMetrics.top)
            .padding(.bottom, 12)

        case .compact:
            ZStack {
                HStack(spacing: 7) {
                    SCMarkShape()
                        .fill(AssistantLook.terraFill(scheme))
                        .frame(width: 15, height: 15)
                        .accessibilityHidden(true)
                    Text("Asystent")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(AssistantLook.ink(scheme))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                HStack {
                    Spacer(minLength: 0)
                    menuButton(size: 34)
                }
            }
            .frame(height: 46)
            .padding(.horizontal, 16)
            .padding(.top, 54)
            .padding(.bottom, 8)
        }
    }

    /// Ten sam krążek co `AssistantRoundLabel`, jako etykieta `Menu`.
    private func menuButton(size: CGFloat) -> some View {
        Menu {
            menu()
        } label: {
            AssistantRoundLabel(icon: "ellipsis", size: size)
                .scTapTarget(44, drawn: size)
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Więcej opcji asystenta")
    }
}

// MARK: - Kapsuła limitu

/// `TrialChip`: „1 pozostała” — mała, cicha kapsuła z drobnym znakiem.
/// Bez kropek (to nie paginacja), bez paska. Liczba przewija się
/// (`CountingNumber`), słowo odmienia się po liczbie.
struct AssistantQuotaPill: View {
    let remaining: Int
    let limit: Int

    @Environment(\.colorScheme) private var scheme

    private var isEmpty: Bool { remaining <= 0 }

    private var word: String {
        let n = max(0, remaining)
        if n == 1 { return "pozostała" }
        if (2...4).contains(n) { return "pozostałe" }
        return "pozostało"
    }

    var body: some View {
        HStack(spacing: 6) {
            SCMarkShape()
                .fill(isEmpty ? AssistantLook.faint(scheme) : AssistantLook.terraFill(scheme))
                .frame(width: 9, height: 9)
            HStack(spacing: 3) {
                CountingNumber(target: max(0, remaining))
                Text(word)
            }
            .font(.system(size: 12, weight: .semibold))
            .tracking(-0.1)
            .foregroundStyle(isEmpty ? AssistantLook.terra(scheme) : AssistantLook.muted(scheme))
            .lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .frame(height: 26)
        .background(Capsule().fill(scheme == .dark ? AssistantLook.field(scheme) : Color.white.opacity(0.55)))
        .overlay(Capsule().stroke(AssistantLook.cardStroke(scheme), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isEmpty
            ? "Pula wiadomości na próbę wyczerpana"
            : "Zostało \(remaining) z \(limit) wiadomości na próbę")
    }
}

// MARK: - Dymki

/// `LUserMsg`: pytanie użytkownika — dymek do 290 pt, terakotowy tint,
/// promienie 20/20/6/20, 16 pt. W trakcie poprawki obrys 1,5 terakoty.
struct AssistantUserBubble: View {
    let text: String
    var editing: Bool = false
    var pending: Bool = false

    @Environment(\.colorScheme) private var scheme

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 20,
            bottomLeadingRadius: 20,
            bottomTrailingRadius: 6,
            topTrailingRadius: 20,
            style: .continuous
        )
    }

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 16))
                .tracking(-0.3)
                .lineSpacing(3)
                .foregroundStyle(AssistantLook.ink(scheme))
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .frame(maxWidth: 290, alignment: .trailing)
                .background(shape.fill(AssistantLook.terraTint2(scheme)))
                .overlay(shape.stroke(editing ? AssistantLook.terra(scheme) : Color.clear, lineWidth: 1.5))
                .opacity(pending ? 0.6 : 1)
                .animation(.easeOut(duration: 0.2), value: pending)
                .animation(.easeOut(duration: 0.2), value: editing)
        }
    }
}

/// `LAsstMsg`: znak marki 18 pt obok treści odpowiedzi — treść na całą
/// szerokość, bez dymka.
struct AssistantVoice<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SCMarkShape()
                .fill(AssistantLook.terraFill(scheme))
                .frame(width: 18, height: 18)
                .padding(.top, 3)
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Szkic odpowiedzi

/// Szkic odpowiedzi w trakcie tury — tekst „pisze się" pod wskaźnikiem.
///
/// Serwer streamuje z modelu, ale telefon odpytuje co sekundę, więc bez
/// tego widoku tekst wskakiwałby akapitami raz na sekundę. Tu odsłania się
/// znak po znaku i DOGANIA serwer w ~0,9 s od każdej porcji. Liczone
/// z zegara względem kotwicy ustawianej przy każdej zmianie tekstu.
///
/// Serwer oddaje CAŁY dotychczasowy tekst i potrafi go wyzerować, gdy
/// runda skończyła się narzędziem. Gdy nowy tekst nie zaczyna się od
/// pokazanego, odsłanianie rusza od zera.
struct AssistantDraftAnswer: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anchorDate = Date()
    @State private var anchorCount = 0
    @State private var rate: Double = 45

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { context in
            let shown = reduceMotion ? text.count : revealedCount(at: context.date)
            AssistantVoice {
                AssistantAnswer(text: String(text.prefix(shown)))
            }
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

// MARK: - „Uwzględniłem: …”

/// Jedna linia pod odpowiedzią: z czym serwer ją policzył.
struct AssistantUsedContextLine: View {
    let items: [String]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AssistantLook.faint(scheme))
                .padding(.top, 2)
            Text("Uwzględniłem: " + items.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(AssistantLook.faint(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Znak w krążku

/// Znak marki w miękkim krążku (`EBrand`): tint pod spodem, kreskowany
/// pierścień wokół. `muted` = wersja przygaszona (wykorzystany limit).
struct AssistantMarkBadge: View {
    var size: CGFloat = 56
    var muted: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    muted ? AssistantLook.ink(scheme).opacity(0.12) : AssistantLook.terraFill(scheme).opacity(0.28),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
                .frame(width: size + 28, height: size + 28)
            Circle().fill(muted ? AssistantLook.ink(scheme).opacity(0.05) : AssistantLook.terraTint(scheme))
            SCMarkShape()
                .fill(muted ? AssistantLook.ink(scheme).opacity(0.3) : AssistantLook.terraFill(scheme))
                .frame(width: size / 2, height: size / 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
