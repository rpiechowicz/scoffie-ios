import SwiftUI

/// Zakończenie (EF8, D20) — treść pod zdjęciem na wspólnym ekranie trybu
/// (`CookScreen`): „Smacznego!”, trzy liczby (czas · kroki · kcal porcji),
/// rada „na następny raz” i ocena w wierszu. „✓ Zjedzone” stoi w stopce
/// (`CookFinishFooter`). Po kciuku arkusz uwag (EF2); kciuk zapisuje się
/// także bez uwag.
///
/// Ruch: sekcje wjeżdżają kaskadą, liczby liczą się od zera razem z wejściem
/// swojego rzędu, kciuk podmienia glif i podskakuje, a kciuk w górę dostaje
/// „wybuch” kropek w szałwii i haptykę sukcesu (jak ocena odpowiedzi
/// Asystenta).
struct CookFinishContent: View {
    let session: CookSession
    let recipe: CookRecipeFacts
    let now: Date
    let onFeedback: (CookFeedback) -> Void

    @State private var rating: CookFeedback.Rating?
    @State private var isFeedbackSheetPresented = false
    @State private var hasAppeared = false
    @State private var cheer = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
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
                    .cookSheetBackground(scheme)
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
                    .font(.sc(size: 12, weight: .bold))
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
                .font(.sc(size: 17, weight: .semibold))
                .foregroundStyle(Color.scMuted(scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .cookReveal(hasAppeared, order: 1)

            stats
                .padding(.top, 26)
                .cookReveal(hasAppeared, order: 2)

            if let tip = session.scenario.nextTimeTip {
                // Ta sama zwarta karta co adnotacja kroku (runda 8).
                CookNoteCard(kind: .tip, text: tip, label: "NA NASTĘPNY RAZ")
                    .padding(.top, 18)
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
                .font(.sc(size: 20, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Color.scLabel(scheme))
            Text(caption)
                .font(.sc(size: 12))
                .foregroundStyle(Color.scMuted(scheme))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var ratingRow: some View {
        HStack(spacing: 10) {
            Text("Jak wyszło?")
                .font(.sc(size: 16, weight: .semibold))
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
            onFeedback(CookFeedback(rating: value, tags: [], comment: "", session: session))
            guard value == .up else {
                isFeedbackSheetPresented = true
                return
            }
            // Arkusz po „wybuchu” kropek, jak przy ocenie odpowiedzi
            // Asystenta — otwarty od razu zasłaniał podskok i kropki.
            cheer += 1
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(550))
                if rating == .up { isFeedbackSheetPresented = true }
            }
        } label: {
            Image(systemName: selected ? selectedName : systemName)
                .font(.sc(size: 18, weight: .medium))
                .foregroundStyle(Color.scLabel(scheme))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.up.byLayer, value: selected)
                .frame(width: 56, height: 44)
                // Szklane kciuki (Liquid Glass, 4.10.2026); wybrany w tincie
                // szałwii (w górę) albo terakoty (w dół).
                .scChromeGlass(
                    in: Capsule(),
                    tint: selected ? (value == .up ? SCPalette.sage : SCPalette.terracotta).opacity(0.24) : nil
                )
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

/// Stopka zakończenia: „✓ Zjedzone” w szałwii na płycie stopki aplikacji.
struct CookFinishFooter: View {
    let onEaten: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        SCSheetFooter(horizontalPadding: SCCook.Spacing.page, reservesShade: true) {
            CookPrimaryButton(
                title: "Zjedzone",
                leadingIcon: "checkmark",
                accent: SCPalette.sage,
                style: SCCook.Typography.buttonQuiet,
                action: onEaten
            )
            .cookReveal(hasAppeared, order: 5)
        }
        .task {
            guard !hasAppeared else { return }
            await CookEntrance.breathe()
            hasAppeared = true
        }
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
                            .font(.sc(size: 14, weight: .semibold))
                            .foregroundStyle(isOn ? SCPalette.terracotta : Color.scLabel(scheme).opacity(0.8))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            // Wspólny chip wyboru — szkło, wybrany w tincie.
                            .scChoiceSurface(Capsule(), isOn: isOn)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.top, 20)

            TextField("Co poprawić następnym razem?", text: $comment, axis: .vertical)
                .font(.sc(size: 16))
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
