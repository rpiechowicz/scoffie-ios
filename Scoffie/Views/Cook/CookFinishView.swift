import SwiftUI

/// Zakończenie (EF8, D20): „Smacznego!”, trzy liczby (czas · kroki · kcal
/// porcji), rada „na następny raz”, ocena w wierszu i „✓ Zjedzone”. Po
/// kciuku arkusz uwag (EF2); kciuk zapisuje się także bez uwag.
///
/// Ruch: sekcje wjeżdżają kaskadą, liczby liczą się od zera razem z wejściem
/// swojego rzędu, kciuk podmienia glif i podskakuje, a kciuk w górę dostaje
/// „wybuch” kropek w szałwii i haptykę sukcesu (jak ocena odpowiedzi
/// Asystenta).
struct CookFinishView: View {
    let session: CookSession
    let recipe: CookRecipeFacts
    let now: Date
    let isPhotoRevealed: Bool
    let onEaten: () -> Void
    let onClose: () -> Void
    let onFeedback: (CookFeedback) -> Void

    @State private var rating: CookFeedback.Rating?
    @State private var isFeedbackSheetPresented = false
    @State private var hasAppeared = false
    @State private var cheer = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Color.scPageBase(scheme).ignoresSafeArea()

            ScrollView {
                ZStack(alignment: .top) {
                    CookHeaderPhoto(url: session.imageURL, isRevealed: isPhotoRevealed)
                    content
                }
                // Szerokość treści = szerokość ekranu (wzór szczegółów posiłku).
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
            .scSheetFooter(horizontalPadding: SCCook.Spacing.page) {
                CookPrimaryButton(
                    title: "Zjedzone",
                    leadingIcon: "checkmark",
                    accent: SCPalette.sage,
                    style: SCCook.Typography.buttonQuiet,
                    action: onEaten
                )
                .cookReveal(hasAppeared, order: 5)
            }

            HStack {
                Spacer()
                SCSheetCloseButton(onImage: true, action: onClose)
            }
            .padding(.horizontal, SCCook.Spacing.page)
            .padding(.top, 11)
            .cookChrome(hasAppeared)
        }
        .sheet(isPresented: $isFeedbackSheetPresented) {
            if let rating {
                CookFeedbackSheet(
                    session: session,
                    rating: rating,
                    onSend: { tags, comment in
                        onFeedback(CookFeedback(rating: rating, tags: tags, comment: comment, session: session))
                        isFeedbackSheetPresented = false
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(40)
                .presentationBackground(Color.scCanvas(scheme))
            }
        }
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: SCCook.Spacing.titleTop - 20)

            VStack(spacing: 0) {
                Text("UGOTOWANE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.44)
                    .foregroundStyle(Color.scMuted(scheme))
                Text("Smacznego!")
                    .cookText(SCCook.Typography.finishTitle)
                    .foregroundStyle(Color.scLabel(scheme))
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            .cookReveal(hasAppeared, order: 0)

            Text(recipe.headline)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .cookReveal(hasAppeared, order: 1)

            stats
                .padding(.top, 26)
                .cookReveal(hasAppeared, order: 2)

            if let tip = session.scenario.nextTimeTip {
                nextTimeCard(tip)
                    .padding(.top, 20)
                    .cookReveal(hasAppeared, order: 3)
            }

            ratingRow
                .padding(.top, 22)
                .cookReveal(hasAppeared, order: 4)

            Color.clear.frame(height: 24)
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .frame(maxWidth: .infinity)
    }

    private var stats: some View {
        let rule = SCCook.Palette.dockStroke(scheme)
        return HStack(spacing: 0) {
            stat(value: "\(session.cookingMinutes(now: now)) min", caption: "czas")
            rule.frame(width: 1)
            stat(value: "\(session.stepCount)", caption: PolishPlural.form(session.stepCount, one: "krok", few: "kroki", many: "kroków"))
            if let kcal = recipe.kcalPerServing {
                rule.frame(width: 1)
                stat(value: "\(kcal) kcal", caption: "porcja")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { rule.frame(height: 1) }
        .overlay(alignment: .bottom) { rule.frame(height: 1) }
    }

    /// Liczba liczy się od zera, gdy jej rząd wjeżdża (opóźnienie = miejsce
    /// rzędu w kaskadzie), a co minutę czasu — dolicza się do nowej.
    private func stat(value: String, caption: String) -> some View {
        VStack(spacing: 3) {
            SCCountingText(value, loadAnimation: .easeOut(duration: 0.9).delay(0.3))
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Color.scLabel(scheme))
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Color.scMuted(scheme))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func nextTimeCard(_ tip: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous)
        return HStack(spacing: 12) {
            Image(systemName: "lightbulb")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SCPalette.butter)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.scButterTint(scheme)))
            VStack(alignment: .leading, spacing: 2) {
                Text("NA NASTĘPNY RAZ")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.88)
                    .foregroundStyle(SCPalette.butter)
                Text(tip)
                    .font(.system(size: 14, weight: .semibold))
                    .lineSpacing(3)
                    .foregroundStyle(Color.scLabel(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(shape.fill(Color.scTileBg(scheme)))
        .overlay(shape.strokeBorder(Color.scTileStroke(scheme), lineWidth: 1))
    }

    private var ratingRow: some View {
        HStack(spacing: 10) {
            Text("Jak wyszło?")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.scLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            thumb(.up, systemName: "hand.thumbsup", selectedName: "hand.thumbsup.fill", label: "Dobre")
            thumb(.down, systemName: "hand.thumbsdown", selectedName: "hand.thumbsdown.fill", label: "Słabe")
        }
        .padding(.top, 18)
        .overlay(alignment: .top) { SCCook.Palette.dockStroke(scheme).frame(height: 1) }
    }

    private func thumb(_ value: CookFeedback.Rating, systemName: String, selectedName: String, label: String) -> some View {
        let selected = rating == value
        return Button {
            withAnimation(.snappy(duration: 0.25)) { rating = value }
            if value == .up { cheer += 1 }
            onFeedback(CookFeedback(rating: value, tags: [], comment: "", session: session))
            isFeedbackSheetPresented = true
        } label: {
            Image(systemName: selected ? selectedName : systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.scLabel(scheme))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.up.byLayer, value: selected)
                .frame(width: 56, height: 44)
                .background(Capsule().fill(selected ? SCCook.Palette.badge(scheme) : Color.scTileStroke(scheme)))
                .overlay(Capsule().strokeBorder(selected ? Color.scLabel(scheme).opacity(0.4) : Color.scTileStroke(scheme), lineWidth: 1))
                .overlay {
                    if value == .up {
                        ThumbCheer(trigger: cheer, tint: SCPalette.sage)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(value == .up ? .success : .selection, trigger: selected) { _, isOn in isOn }
    }
}

/// Ocena gotowania: kciuk + pigułki + zdanie + zdarzenia sesji (§13.8).
/// Do wysłania, gdy backend przyjmie oceny Gotuj — na razie zostaje
/// w dzienniku sesji (TODO po stronie API, docs/workstreams/gotuj §13.8).
struct CookFeedback: Equatable {
    enum Rating: String, Equatable {
        case up = "UP"
        case down = "DOWN"
    }

    let rating: Rating
    let tags: [String]
    let comment: String
    let recipeId: UUID
    let scenarioVersion: Int
    /// „+min” z sesji: id timera → suma sekund.
    let extensions: [String: Int]

    init(rating: Rating, tags: [String], comment: String, session: CookSession) {
        self.rating = rating
        self.tags = tags
        self.comment = comment
        self.recipeId = session.recipeId
        self.scenarioVersion = session.package.version
        self.extensions = session.extensions.reduce(into: [:]) { $0[$1.timerId, default: 0] += $1.seconds }
    }
}

/// „Co byś zmienił?” po kciuku (EF2): pigułki powodów (pierwsza z sesji,
/// np. „Kotlety +4 min”), pole, „Wyślij”.
struct CookFeedbackSheet: View {
    let session: CookSession
    let rating: CookFeedback.Rating
    let onSend: (_ tags: [String], _ comment: String) -> Void

    @State private var selected: Set<String> = []
    @State private var comment = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var reasons: [String] {
        var list: [String] = []
        if let hint = session.extensionHint() { list.append(hint) }
        if rating == .down {
            list += ["Za słone", "Za mało porcji", "Za długo", "Niejasny krok"]
        } else {
            list += ["Jasne kroki", "Dobre porcje", "Wyszło jak na zdjęciu"]
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorialSheetHeader(
                eyebrow: CookRecipeFacts.shortTitle(session.recipeTitle).uppercased(with: Locale(identifier: "pl_PL")),
                title: rating == .down ? "Co byś zmienił?" : "Co było dobre?",
                icon: rating == .down ? "hand.thumbsdown" : "hand.thumbsup",
                accent: rating == .down ? SCPalette.terracotta : SCPalette.sage,
                compact: true,
                onClose: { dismiss() }
            )
            .padding(.top, 20)

            CookTagFlow(spacing: 8) {
                ForEach(reasons, id: \.self) { reason in
                    let isOn = selected.contains(reason)
                    Button {
                        if isOn { selected.remove(reason) } else { selected.insert(reason) }
                    } label: {
                        Text(reason)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isOn ? SCPalette.terracotta : Color.scLabel(scheme).opacity(0.8))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Capsule().fill(isOn ? SCPalette.terracotta.opacity(0.14) : Color.scChipBg(scheme)))
                            .overlay(Capsule().strokeBorder(isOn ? SCPalette.terracotta.opacity(0.45) : Color.scTileStroke(scheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.top, 20)

            TextField("Co poprawić następnym razem?", text: $comment, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(3...5)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous).fill(Color.scTileBg(scheme)))
                .overlay(RoundedRectangle(cornerRadius: SCCook.Radius.tile, style: .continuous).strokeBorder(SCCook.Palette.badge(scheme), lineWidth: 1))
                .padding(.top, 14)

            Spacer(minLength: 16)

            CookPrimaryButton(title: "Wyślij") {
                onSend(reasons.filter { selected.contains($0) }, comment.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        .padding(.horizontal, SCCook.Spacing.page)
        .padding(.bottom, 8)
    }
}

/// Pigułki w wierszach, zawijane na szerokość (powody w arkuszu uwag).
struct CookTagFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
