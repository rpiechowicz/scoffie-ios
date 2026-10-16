import SwiftUI
import UIKit

// Przesunięcie wiersza w lewo odsłania „Usuń” — jak w Przypomnieniach
// i Poczcie (16.10.2026, Rafał o Zakupach: „chcę, aby można było usunąć te
// składniki”). Usuwanie stało dotąd tylko pod przytrzymaniem wiersza i nikt
// go nie znajdował.
//
// Własny, bo systemowe `swipeActions` działa wyłącznie w `List` (akapit
// „Posiłki w planie” w CLAUDE.md), a Zakupy to `ScrollView` z roletami alejek
// i przypiętym paskiem postępu — przebudowa na `List` zabrałaby je wszystkie.
// Gest jest UIKit-owy z tego samego powodu co `OptionsPagePan`: rusza TYLKO
// przy ruchu wyraźnie poziomym, więc przewijanie listy w pionie i zamykanie
// arkusza w dół nie mają z kim konkurować.
//
// Zasady jak w systemie: otwarty jest najwyżej jeden wiersz; stuknięcie
// w cokolwiek innego go zamyka (i NIE odhacza produktu); pełne przesunięcie
// usuwa od razu; przytrzymanie z menu zostaje obok jako druga droga.

/// Który wiersz jest otwarty i czy stuknięcie ma się liczyć — jeden na ekran.
@MainActor
@Observable
final class SCSwipeState {
    fileprivate(set) var openId: String?
    /// Koniec ostatniego przesunięcia. Palec puszczony po geście nie może
    /// zaraz potem odhaczyć wiersza pod sobą. Pisane w każdej klatce gestu,
    /// a żaden widok go nie rysuje — poza obserwacją.
    @ObservationIgnored fileprivate var lastGestureAt: Date = .distantPast

    nonisolated init() {}

    /// Stuknięcie w wiersz: `true` = przeszło (nic nie było otwarte), `false`
    /// = tylko zamknęło otwarty wiersz albo było końcem gestu.
    func admitsTap() -> Bool {
        if Date().timeIntervalSince(lastGestureAt) < 0.35 { return false }
        guard openId == nil else {
            close()
            return false
        }
        return true
    }

    func close() {
        guard openId != nil else { return }
        withAnimation(Self.motion) { openId = nil }
    }

    fileprivate static let motion = Animation.spring(response: 0.32, dampingFraction: 0.86)
}

private struct SCSwipeToRemoveModifier: ViewModifier {
    let id: String
    let title: String
    let state: SCSwipeState
    let onRemove: () -> Void

    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 0

    /// Szerokość odsłoniętego przycisku.
    private static let actionWidth: CGFloat = 88

    private var isOpen: Bool { state.openId == id }

    /// Przesunięcie, od którego puszczenie palca usuwa od razu.
    private var fullSwipe: CGFloat { max(Self.actionWidth * 2, width * 0.55) }

    private var offset: CGFloat {
        let resting: CGFloat = isOpen ? -Self.actionWidth : 0
        // Tylko w lewo; w prawo — lekki opór, jak w systemie.
        let raw = resting + drag
        return raw > 0 ? raw * 0.15 : raw
    }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) { action }
            .background {
                GeometryReader { geo in
                    Color.clear.onAppear { width = geo.size.width }
                        .onChange(of: geo.size.width) { _, value in width = value }
                }
            }
            .gesture(
                SCSwipePan(
                    canBegin: { velocityX in velocityX < 0 || isOpen },
                    onChanged: { dx in
                        if state.openId != id, state.openId != nil { state.close() }
                        // Przy KAŻDEJ klatce, nie tylko na końcu: akcja przycisku
                        // wiersza potrafi przyjść przed końcem gestu i odhaczyłaby
                        // produkt spod palca.
                        state.lastGestureAt = Date()
                        drag = dx
                    },
                    onEnded: { dx, velocity in finish(dx: dx, velocity: velocity) }
                )
            )
            .accessibilityAction(named: Text(title), onRemove)
    }

    /// Czerwony przycisk za wierszem — rośnie razem z przesunięciem.
    private var action: some View {
        let revealed = max(0, -offset)
        return Button {
            state.lastGestureAt = Date()
            withAnimation(SCSwipeState.motion) {
                state.openId = nil
                drag = 0
            }
            onRemove()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "trash.fill")
                    .font(.sc(size: 15, weight: .semibold))
                Text(title)
                    .font(.sc(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(width: max(revealed - 8, 0))
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SCDestructiveButton.tint)
            )
            .padding(.vertical, 5)
            .opacity(revealed > 12 ? 1 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: revealed, alignment: .trailing)
        .accessibilityHidden(true)
    }

    private func finish(dx: CGFloat, velocity: CGFloat) {
        state.lastGestureAt = Date()
        let travelled = -(isOpen ? -Self.actionWidth + dx : dx)
        if travelled > fullSwipe {
            withAnimation(SCSwipeState.motion) {
                state.openId = nil
                drag = 0
            }
            onRemove()
            return
        }
        let opens = travelled > Self.actionWidth * 0.5 || velocity < -600
        withAnimation(SCSwipeState.motion) {
            state.openId = opens ? id : (isOpen ? nil : state.openId)
            drag = 0
        }
    }
}

/// Poziomy gest wiersza — rusza wyłącznie przy ruchu wyraźnie poziomym
/// (decyzja z prędkości w pierwszej klatce), więc pion zostaje dla listy.
private struct SCSwipePan: UIGestureRecognizerRepresentable {
    /// Czy zaczynać przy tej prędkości poziomej (w prawo tylko otwarty wiersz).
    let canBegin: (CGFloat) -> Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (_ dx: CGFloat, _ velocity: CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(canBegin: canBegin)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.canBegin = canBegin
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let dx = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(dx)
        case .ended:
            onEnded(dx, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnded(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var canBegin: (CGFloat) -> Bool

        init(canBegin: @escaping (CGFloat) -> Bool) {
            self.canBegin = canBegin
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) * 1.4 else { return false }
            return canBegin(velocity.x)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension View {
    /// Przesunięcie w lewo odsłania „Usuń” (`title`). `isEnabled: false` =
    /// wiersz bez gestu, nietknięty.
    @ViewBuilder
    func scSwipeToRemove(
        id: String,
        title: String = "Usuń",
        isEnabled: Bool = true,
        state: SCSwipeState,
        onRemove: @escaping () -> Void
    ) -> some View {
        if isEnabled {
            modifier(SCSwipeToRemoveModifier(id: id, title: title, state: state, onRemove: onRemove))
        } else {
            self
        }
    }
}
