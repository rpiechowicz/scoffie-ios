import SwiftUI

/// Kropki i podpis w pigułce — „ile z ilu”, czytane bez liczenia.
///
/// Wzór przyszedł z plakietki puli asystenta: „2 z 5” każe liczyć, a dwie
/// pełne kropki z pięciu widać od razu. Rysujemy CAŁOŚĆ — pełne kropki to
/// stan, wygaszone to reszta — bo same pełne (dwie kropki bez odniesienia)
/// nie mówią, ile było na starcie.
///
/// Komponent wyszedł z `AssistantQuotaPips` w chwili, gdy Kalendarz zaczął
/// mówić tym samym „2 z 4 zjedzone”: dwie kopie tego samego rysunku
/// rozjechałyby się przy pierwszej poprawce średnicy albo odstępu.
/// Znaczenie zostaje po stronie wywołującego — pigułka nie wie, czy liczy
/// wiadomości, czy posiłki, i dlatego bierze barwę i podpis z zewnątrz.
struct SCPipsBadge: View {
    /// Ile kropek jest pełnych.
    let filled: Int
    /// Cała pula; z niej liczy się liczba kropek.
    let total: Int
    let color: Color
    /// Podpis po prawej. `nil` = same kropki, gdy miejsce w wierszu jest
    /// droższe od słowa.
    var label: String?
    /// Czy kropki w ogóle rysować. Wyłącza się je, gdy pula jest pusta
    /// i rząd wygaszonych kółek mówiłby mniej niż samo zdanie.
    var showsPips: Bool = true
    /// Sufit rysowanych kropek — dłuższa pula nie ma prawa rozepchnąć wiersza.
    var maxPips: Int = 8

    @Environment(\.colorScheme) private var scheme

    private var pipCount: Int { max(1, min(maxPips, total)) }
    private var drawsPips: Bool { showsPips && total > 0 }

    var body: some View {
        HStack(spacing: 7) {
            if drawsPips {
                HStack(spacing: 3.5) {
                    ForEach(0..<pipCount, id: \.self) { index in
                        Circle()
                            .fill(index < filled ? color : color.opacity(0.28))
                            .frame(width: 6, height: 6)
                    }
                }
            }

            if let label {
                Text(label)
                    .font(.system(size: 11.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        // Kropka jest okrągła i sama sobie robi światło przy krawędzi,
        // podpis nie — stąd punkt różnicy po każdej stronie.
        .padding(.leading, drawsPips ? 10 : 11)
        .padding(.trailing, label == nil ? 10 : 11)
        .frame(height: 28)
        .background(Capsule().fill(color.opacity(scheme == .dark ? 0.15 : 0.10)))
    }
}

#Preview("SCPipsBadge") {
    ZStack {
        Color.scCanvas(.dark).ignoresSafeArea()

        VStack(spacing: 16) {
            SCPipsBadge(filled: 2, total: 5, color: SCPalette.butter, label: "2 wiadomości")
            SCPipsBadge(filled: 1, total: 4, color: SCPalette.sage, label: "1 z 4")
            SCPipsBadge(filled: 4, total: 4, color: SCPalette.sage, label: "4 z 4")
            SCPipsBadge(filled: 0, total: 5, color: SCPalette.terracotta, label: "pula wyczerpana", showsPips: false)
        }
    }
    .preferredColorScheme(.dark)
}
