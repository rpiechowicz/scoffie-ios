import SwiftUI

struct AuthHeaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Druga linia tytułu — to, co stoi po przecinku. Pisze się na maszynie,
    /// kasuje i wraca z następnym zdaniem: tyle samo obietnic, co zakładek
    /// w aplikacji, bez dokładania tekstu na ekranie.
    private static let endings = [
        "planujcie raz.",
        "kupujcie z listy.",
        "liczcie makro.",
        "pytajcie asystenta.",
    ]

    @State private var typed = Self.endings[0]
    @State private var isTyping = false

    var body: some View {
        // Spacingi z designu: paddingTop 4 nad title, 12pt do subtitle
        // (via VStack spacing). Subtitle→features dodawane w AuthView.
        VStack(alignment: .leading, spacing: 12) {
            title
            Text("Plan posiłków, lista zakupów i asystent, który ułoży tydzień za Was.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.scMuted(colorScheme))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await runTypewriter() }
    }

    private var title: some View {
        // „Gotujcie razem," stoi; „razem" italic + terracotta. Linia 40 pt na
        // foncie 32 (jak w designie). Druga linia ma STAŁĄ wysokość — pusty
        // tekst w trakcie kasowania nie może podciągać reszty ekranu.
        VStack(alignment: .leading, spacing: 0) {
            (
                Text("Gotujcie ")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.scLabel(colorScheme))
                + Text("razem")
                    .font(.system(size: 32, weight: .medium).italic())
                    .foregroundStyle(SCPalette.terracotta)
                + Text(",")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.scLabel(colorScheme))
            )
            .lineHeight(.exact(points: 40))

            HStack(alignment: .center, spacing: 3) {
                Text(typed.isEmpty ? " " : typed)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.scLabel(colorScheme))
                    .lineHeight(.exact(points: 40))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !reduceMotion { cursor }
            }
            .frame(height: 40, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gotujcie razem, \(Self.endings[0])")
        .accessibilityAddTraits(.isHeader)
    }

    /// Kursor: stoi, gdy litery się piszą, i mruga, gdy zdanie czeka.
    private var cursor: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.53)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(SCPalette.terracotta)
                .frame(width: 3, height: 30)
                .opacity(isTyping || tick.isMultiple(of: 2) ? 1 : 0)
        }
        .accessibilityHidden(true)
    }

    /// Pisz → czekaj → kasuj → następne. Anulowanie zadania (zejście ekranu)
    /// przerywa pętlę na najbliższym `sleep`.
    private func runTypewriter() async {
        guard !reduceMotion else { return }
        do {
            var index = 0
            try await Task.sleep(for: .milliseconds(2600))
            while true {
                isTyping = true
                while !typed.isEmpty {
                    typed.removeLast()
                    try await Task.sleep(for: .milliseconds(26))
                }
                isTyping = false
                try await Task.sleep(for: .milliseconds(320))

                index = (index + 1) % Self.endings.count
                isTyping = true
                for character in Self.endings[index] {
                    typed.append(character)
                    // Spacja dostaje dłuższy oddech — równe tempo brzmi jak automat.
                    try await Task.sleep(for: .milliseconds(character == " " ? 95 : 52))
                }
                isTyping = false
                try await Task.sleep(for: .milliseconds(2400))
            }
        } catch {
            return
        }
    }
}

#Preview("Dark") {
    AuthHeaderView()
        .padding()
        .background(Color.scCanvas(.dark))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    AuthHeaderView()
        .padding()
        .background(Color.scCanvas(.light))
        .preferredColorScheme(.light)
}
