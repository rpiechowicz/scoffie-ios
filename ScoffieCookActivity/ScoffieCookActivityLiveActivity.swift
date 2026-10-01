import ActivityKit
import AppIntents
import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// Live Activity trybu Gotuj (E5) — Dynamic Island i ekran blokady według
/// makiet Claude Design (DC3/DC5 kompakt, MN4/MN6 minimal, ER1–4 rozwinięta,
/// LK0–3 ekran blokady; liczby w `CookActivityLook`). Jedna reguła (D25):
/// działa timer → wokół zdjęcia pierścień TIMERA, brak → pierścień KROKÓW;
/// nagłówek rozwiniętej i ekranu blokady ma zawsze pierścień kroków, a timery
/// stoją w kaflach. Odliczanie rysują widoki czasowe systemu — rozszerzenie
/// nie dostaje aktualizacji co sekundę. Przyciski to `CookActivityIntent`
/// (wykonuje go aplikacja), stuknięcie w resztę otwiera tryb (`scoffie://gotuj`).
struct ScoffieCookActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookActivityAttributes.self) { context in
            CookLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(CookActivityLook.card)
                .activitySystemActionForegroundColor(CookActivityLook.cream)
                .widgetURL(CookActivityLook.openURL)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CookStepsRingPhoto(recipeId: attributes.recipeId, state: state, diameter: 48, photo: 35)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CookNextButton(state: state, diameter: 48)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        CookStepHeading(state: state, titleSize: state.timers.isEmpty ? 20 : 17, titleLines: state.timers.isEmpty ? 2 : 1)
                        CookStateSection(state: state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                CookCompactRing(recipeId: attributes.recipeId, state: state)
            } compactTrailing: {
                CookCompactTrailing(state: state)
            } minimal: {
                CookCompactRing(recipeId: attributes.recipeId, state: state)
            }
            .widgetURL(CookActivityLook.openURL)
            .keylineTint(CookActivityLook.terracotta)
        }
    }
}

// MARK: - Wygląd

/// Liczby i kolory z makiet Live Activity (ciemne tło wyspy i karty).
enum CookActivityLook {
    static let cream = Color(rgb: 0xFBF3E8)
    static let sage = Color(rgb: 0x87C2A5)
    static let terracotta = Color(rgb: 0xDB8452)
    /// Glif na terakotowych i szałwiowych krążkach.
    static let ink = Color(rgb: 0x0C0806)
    /// Tło karty ekranu blokady: rgba(20, 14, 11, 0.74).
    static let card = Color(red: 20 / 255, green: 14 / 255, blue: 11 / 255).opacity(0.74)
    static let futureStep = cream.opacity(0.16)
    static let openURL = URL(string: "scoffie://gotuj")!

    static let stepStroke: CGFloat = 2.4
    /// Odstęp między odcinkami pierścienia kroków (przed zaokrągleniem końców).
    static let stepGap: CGFloat = 5
    static let tileHeight: CGFloat = 60
    static let tileRadius: CGFloat = 20
    static let tileRing: CGFloat = 28
    static let tileRingStroke: CGFloat = 3.4
    static let compactRing: CGFloat = 27
    static let compactPhoto: CGFloat = 19
    static let compactTimerStroke: CGFloat = 2.6
}

extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

extension CookActivityTimer {
    var tint: Color { Color(rgb: color) }

    /// Przedział odliczania — tylko poprawny (początek przed końcem).
    var interval: ClosedRange<Date>? {
        guard let start, let end, start < end else { return nil }
        return start...end
    }

    /// Ułamek, który ZOSTAŁ — łuk pauzy i timera, który czeka.
    var remainingFraction: Double {
        switch phase {
        case .pending: return 1
        case .paused: return total > 0 ? min(1, max(0, (remaining ?? 0) / total)) : 0
        case .running, .overdue: return 0
        }
    }
}

extension CookActivityAttributes.ContentState {
    var isLastStep: Bool { stepIndex >= stepCount - 1 }

    /// Timer, który „działa” (reguła D25): najbliżej końca spośród
    /// biegnących, a gdy żaden nie biegnie — ten po czasie.
    var leadTimer: CookActivityTimer? {
        let running = timers
            .filter { $0.phase == .running && $0.interval != nil }
            .sorted { ($0.end ?? .distantFuture) < ($1.end ?? .distantFuture) }
        return running.first ?? timers.first { $0.phase == .overdue && $0.end != nil }
    }
}

/// „9:41”, „1:02:05”.
private func clockText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.up)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

// MARK: - Zdjęcie i pierścienie

/// Zdjęcie dania z kontenera App Group (zapisuje je aplikacja); bez pliku —
/// krążek w terakocie z nożem i widelcem.
struct CookActivityPhoto: View {
    let recipeId: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url = CookActivityImage.url(recipeId: recipeId),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    CookActivityLook.terracotta.opacity(0.3)
                    Image(systemName: "fork.knife")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(CookActivityLook.cream)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Pierścień kroków: N odcinków od godziny 12, zgodnie ze wskazówkami;
/// zrobione szałwia, bieżący terakota, dalsze krem 16 %.
struct CookStepsRing: View {
    let count: Int
    let current: Int
    let diameter: CGFloat

    var body: some View {
        let lineWidth = CookActivityLook.stepStroke
        let radius = (diameter - lineWidth) / 2
        let circumference = 2 * CGFloat.pi * radius
        let segments = max(1, count)
        let pitch = circumference / CGFloat(segments)
        let dash = max(0.01, pitch - CookActivityLook.stepGap)
        ZStack {
            ForEach(0..<segments, id: \.self) { index in
                Circle()
                    .trim(from: CGFloat(index) * pitch / circumference, to: (CGFloat(index) * pitch + dash) / circumference)
                    .stroke(color(index), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func color(_ index: Int) -> Color {
        if index < current { return CookActivityLook.sage }
        if index == current { return CookActivityLook.terracotta }
        return CookActivityLook.futureStep
    }
}

/// Pierścień timera — biegnący liczy się sam (`ProgressView(timerInterval:)`),
/// wstrzymany i czekający stoją na swoim ułamku, po czasie — pusty tor.
struct CookTimerRing: View {
    let timer: CookActivityTimer
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            if timer.phase == .running, let interval = timer.interval {
                ProgressView(timerInterval: interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(timer.tint)
            } else {
                Circle()
                    .stroke(timer.tint.opacity(0.25), lineWidth: lineWidth)
                    .padding(lineWidth / 2)
                Circle()
                    .trim(from: 0, to: timer.remainingFraction)
                    .stroke(timer.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(lineWidth / 2)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Zdjęcie w pierścieniu kroków — nagłówek rozwiniętej i ekranu blokady.
struct CookStepsRingPhoto: View {
    let recipeId: String
    let state: CookActivityAttributes.ContentState
    let diameter: CGFloat
    let photo: CGFloat

    var body: some View {
        ZStack {
            CookActivityPhoto(recipeId: recipeId, size: photo)
            CookStepsRing(count: state.stepCount, current: state.stepIndex, diameter: diameter)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Krok \(state.stepIndex + 1) z \(state.stepCount)")
    }
}

/// Kompakt i minimal: zdjęcie w pierścieniu timera, gdy działa timer,
/// inaczej w pierścieniu kroków.
struct CookCompactRing: View {
    let recipeId: String
    let state: CookActivityAttributes.ContentState

    var body: some View {
        ZStack {
            if let timer = state.leadTimer {
                CookActivityPhoto(recipeId: recipeId, size: CookActivityLook.compactPhoto - 1)
                CookTimerRing(timer: timer, diameter: CookActivityLook.compactRing, lineWidth: CookActivityLook.compactTimerStroke)
            } else {
                CookActivityPhoto(recipeId: recipeId, size: CookActivityLook.compactPhoto)
                CookStepsRing(count: state.stepCount, current: state.stepIndex, diameter: CookActivityLook.compactRing)
            }
        }
        .frame(width: CookActivityLook.compactRing, height: CookActivityLook.compactRing)
    }
}

/// Prawa strona kompaktu: czas timera w jego kolorze albo „8/12” w szałwii.
struct CookCompactTrailing: View {
    let state: CookActivityAttributes.ContentState

    var body: some View {
        Group {
            if let timer = state.leadTimer {
                CookTimerTime(timer: timer)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.15)
                    .foregroundStyle(timer.tint)
            } else {
                Text("\(state.stepIndex + 1)/\(state.stepCount)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CookActivityLook.sage)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 64, alignment: .trailing)
    }
}

/// Zegar timera: biegnący odlicza sam, po czasie liczy w górę z „+”,
/// wstrzymany i czekający stoją.
struct CookTimerTime: View {
    let timer: CookActivityTimer

    var body: some View {
        switch timer.phase {
        case .running:
            if let interval = timer.interval {
                Text(timerInterval: interval, countsDown: true)
            } else {
                Text("0:00")
            }
        case .overdue:
            if let end = timer.end {
                Text("+") + Text(end, style: .timer)
            } else {
                Text("0:00")
            }
        case .paused, .pending:
            Text(clockText(timer.remaining ?? timer.total))
        }
    }
}

// MARK: - Nagłówek i przyciski

/// „KROK 8 Z 12” + tytuł kroku.
struct CookStepHeading: View {
    let state: CookActivityAttributes.ContentState
    let titleSize: CGFloat
    let titleLines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("KROK \(state.stepIndex + 1) Z \(state.stepCount)")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.72)
                .foregroundStyle(CookActivityLook.sage)
            Text(state.stepTitle)
                .font(.system(size: titleSize, weight: .bold))
                .tracking(-titleSize * 0.01)
                .foregroundStyle(CookActivityLook.cream)
                .lineLimit(titleLines)
                .minimumScaleFactor(0.85)
        }
    }
}

/// Okrągły terakotowy „Dalej →”; na ostatnim kroku ptaszek („Zakończ”).
struct CookNextButton: View {
    let state: CookActivityAttributes.ContentState
    let diameter: CGFloat

    var body: some View {
        Button(intent: CookActivityIntent(.next)) {
            ZStack {
                Circle().fill(CookActivityLook.terracotta)
                Image(systemName: state.isLastStep ? "checkmark" : "arrow.right")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(CookActivityLook.ink)
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.isLastStep ? "Zakończ gotowanie" : "Następny krok")
    }
}

// MARK: - Stan pod nagłówkiem

/// 1 timer (kafel + „+1 min”), 2 timery (dwa kafle), bez timera („Dalej: …”).
struct CookStateSection: View {
    let state: CookActivityAttributes.ContentState

    var body: some View {
        if state.timers.isEmpty {
            CookNextStepRow(state: state)
        } else if state.timers.count == 1, let timer = state.timers.first {
            CookTimerTile(timer: timer, showsExtend: true)
        } else {
            HStack(spacing: 8) {
                ForEach(state.timers.prefix(2)) { timer in
                    CookTimerTile(timer: timer, showsExtend: false)
                }
            }
        }
    }
}

/// Kafel timera; czekający na włączenie ma przerywaną obwódkę i ▶.
struct CookTimerTile: View {
    let timer: CookActivityTimer
    let showsExtend: Bool

    var body: some View {
        if timer.phase == .pending {
            waiting
        } else {
            running
        }
    }

    private var running: some View {
        let shape = RoundedRectangle(cornerRadius: CookActivityLook.tileRadius, style: .continuous)
        return HStack(spacing: 10) {
            CookTimerRing(timer: timer, diameter: CookActivityLook.tileRing, lineWidth: CookActivityLook.tileRingStroke)
            VStack(alignment: .leading, spacing: 0) {
                Text(timer.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(timer.tint)
                    .lineLimit(1)
                CookTimerTime(timer: timer)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.44)
                    .monospacedDigit()
                    .foregroundStyle(CookActivityLook.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if showsExtend, timer.phase == .running || timer.phase == .overdue {
                Button(intent: CookActivityIntent(.extend, timerId: timer.id)) {
                    Text("+1 min")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(CookActivityLook.cream)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Capsule().fill(CookActivityLook.cream.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: CookActivityLook.tileHeight, maxHeight: CookActivityLook.tileHeight)
        .background(shape.fill(timer.tint.opacity(0.14)))
    }

    private var waiting: some View {
        let shape = RoundedRectangle(cornerRadius: CookActivityLook.tileRadius, style: .continuous)
        let condition = timer.startLabel.map { "\($0) " } ?? ""
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(timer.label.uppercased(with: Locale(identifier: "pl_PL"))) · CZEKA")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(timer.tint)
                    .lineLimit(1)
                Text(condition + clockText(timer.remaining ?? timer.total))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(CookActivityLook.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Button(intent: CookActivityIntent(.startTimer, timerId: timer.id)) {
                ZStack {
                    Circle().fill(timer.tint)
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CookActivityLook.ink)
                        .offset(x: 2)
                }
                .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Włącz timer \(timer.label)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: CookActivityLook.tileHeight, maxHeight: CookActivityLook.tileHeight)
        .background(shape.fill(timer.tint.opacity(0.10)))
        .overlay(shape.strokeBorder(timer.tint.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }
}

/// „Dalej: Przełóż do piekarnika · 5 min” pod cienką kreską.
struct CookNextStepRow: View {
    let state: CookActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(CookActivityLook.cream.opacity(0.10))
                .frame(height: 1)
            HStack(spacing: 8) {
                if let title = state.nextTitle {
                    Text("Dalej:")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CookActivityLook.cream.opacity(0.8))
                    Text(state.nextTimerMinutes.map { "\(title) · \($0) min" } ?? title)
                        .font(.system(size: 14))
                        .foregroundStyle(CookActivityLook.cream.opacity(0.6))
                        .lineLimit(1)
                } else {
                    Text("Ostatni krok — potem Smacznego!")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CookActivityLook.cream.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Ekran blokady

/// Karta ekranu blokady (LK0–3): w jednym rzędzie zdjęcie w pierścieniu
/// kroków, „KROK 8 Z 12” + tytuł w jednej linii i „Dalej →” 44 pt; pod
/// spodem ten sam stan co w rozwiniętej wyspie.
struct CookLockScreenView: View {
    let attributes: CookActivityAttributes
    let state: CookActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CookStepsRingPhoto(recipeId: attributes.recipeId, state: state, diameter: 48, photo: 35)
                CookStepHeading(state: state, titleSize: 17, titleLines: 1)
                Spacer(minLength: 0)
                CookNextButton(state: state, diameter: 44)
            }
            CookStateSection(state: state)
        }
        .padding(16)
    }
}
