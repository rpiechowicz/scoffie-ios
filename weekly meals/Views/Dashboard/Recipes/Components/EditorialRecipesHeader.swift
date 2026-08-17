import SwiftUI

// Editorial top header on Przepisy v2 — W3 "Story carousel" variant.
// Source: design/Weekly Meals - Przepisy.html → recipes-v2.jsx RecipesV2_W3.
//   Outer block — `padding: '58px 20px 16px'` for the title row,
//   `0 20px 18px` for the search row.
//   Title — 32pt 700, tracking -0.5, line-height 38pt, label color.
//   Search — pill, `padding: 12px 14px 12px 16px`, rounded 99,
//   surface bg + line border + inset highlight. Magnifying glass icon
//   at 17pt with dim color; placeholder "Szukaj przepisów" at 16pt.
//
// Settings drops the "№ X · …" eyebrow because there's no week context to
// surface — same call here. The recipe list is a global library, not a
// per-week thing.
struct EditorialRecipesHeader: View {
    @Binding var searchText: String
    var onSubmit: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Przepisy")
                .font(.system(size: 32, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.wmLabel(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            searchPill
        }
    }

    private var searchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.wmMuted(scheme).opacity(0.7))

            TextField(text: $searchText) {
                Text("Szukaj przepisów")
                    .foregroundStyle(Color.wmMuted(scheme).opacity(0.7))
            }
            .font(.system(size: 16))
            .tracking(-0.2)
            .foregroundStyle(Color.wmLabel(scheme))
            .focused($isSearchFocused)
            .submitLabel(.search)
            .onSubmit { onSubmit?() }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.wmMuted(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść wyszukiwanie")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color.wmTileBg(scheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.wmTileStroke(scheme), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { isSearchFocused = true }
    }
}
