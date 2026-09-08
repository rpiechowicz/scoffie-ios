import SwiftUI

// Pusty stan Zakupów, gdy lista tygodnia jest już zamknięta.
// Źródło: canvas claude.ai → „Weekly Meals - Zakupy v2.html”
// (`components/shop-v2-history-flow.jsx` → `ShopHistFlowHome`).
//
// Bez ani jednego przycisku — i to jest sedno. Zamknięta lista nie czeka na
// żadną decyzję: nowa ułoży się sama, gdy w Planie coś dojdzie. Ekran ma to
// powiedzieć i zejść z drogi, a nie proponować akcję, której nikt nie potrzebuje.
struct ShoppingClosedHero: View {
    /// Zdjęcia dań tygodnia — zachodzące na siebie krążki, jak awatary
    /// domowników. Pusty stan bez nich byłby samym akapitem tekstu.
    let imageURLs: [URL]
    let bought: Int
    let total: Int

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    private let photo: CGFloat = 64
    private let overlap: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            if !imageURLs.isEmpty {
                photos
                    .padding(.bottom, 18)
            }

            Text("Lista na ten tydzień jest zamknięta")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Color.scLabel(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(bought) z \(total) kupione. Gdy w Planie coś dojdzie, nowa lista ułoży się sama.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                appeared = true
            }
        }
    }

    /// Krążki wchodzą po kolei, od lewej — stos zdjęć układa się na oczach
    /// użytkownika zamiast pojawiać się gotowy. Opóźnienie rośnie o 0,05 s
    /// na krążek, więc cztery zdjęcia wchodzą w 0,15 s: to jest akcent,
    /// nie animacja do oglądania.
    private var photos: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.scTileBg(scheme)
                    }
                }
                .frame(width: photo, height: photo)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.scPageBase(scheme), lineWidth: 3)
                )
                .zIndex(Double(imageURLs.count - index))
                .scaleEffect(appeared ? 1 : 0.82)
                .opacity(appeared ? 1 : 0)
                .animation(photoAnimation(index: index), value: appeared)
            }
        }
        .accessibilityHidden(true)
    }

    /// Jawna funkcja zamiast `reduceMotion ? nil : .spring(…)` w argumencie.
    /// Warunek z `nil` po jednej stronie i wnioskowanym typem po drugiej daje
    /// dwa równorzędne rozwiązania (SE-0418) i kompilator zgłasza to kilkadziesiąt
    /// linii wyżej, przy najbliższym kontenerze SwiftUI.
    private func photoAnimation(index: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: 0.44, dampingFraction: 0.78)
            .delay(0.08 + Double(index) * 0.05)
    }
}
