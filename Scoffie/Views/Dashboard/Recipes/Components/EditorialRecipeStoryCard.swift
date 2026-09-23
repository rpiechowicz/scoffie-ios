import SwiftUI

// Full-bleed story-style hero card used inside the featured carousel on
// Przepisy v2. Source: design/Scoffie - Przepisy.html →
// recipes-v2.jsx W3StoryCard.
//   Outer card — 330pt tall (makieta: 420, patrz `cardHeight`), corner 26pt, photo `cover/center` or category
//   tint gradient placeholder with the category glyph at 84pt.
//   Top scrim — `linear-gradient(180deg, rgba(0,0,0,0.28) 0%, transparent
//   32%, transparent 50%, rgba(0,0,0,0.78) 100%)`.
//   Heart chip — pinned top-trailing at 14pt inset, 32pt circle.
//   Title — 22pt 700, tracking -0.4, line-height 26pt, up to 3 lines,
//   `text-shadow: 0 2px 12px rgba(0,0,0,0.6)`.
//   Glass chips — clock + flame meta, bottom-leading inset 16pt.
struct EditorialRecipeStoryCard: View {
    /// Wysokość karty publikowana statycznie, bo karuzela w `RecipesView`
    /// używa `GeometryReader { ... }.frame(height:)` żeby uniknąć
    /// dwuwymiarowego layoutu — musi znać tę liczbę z zewnątrz.
    ///
    /// 330, nie 420 z makiety. Zdjęcia katalogu są kwadratowe (1024², ujęcie
    /// z góry pod kątem), a karta ma ~350 pt szerokości: przy 420 pt
    /// wysokości `scaledToFill` skalował zdjęcie DO WYSOKOŚCI, ucinał po
    /// ~35 pt z boków i talerz wychodził zbliżony, jak przez lupę. Przy
    /// proporcji bliskiej kwadratu zdjęcie skaluje się do szerokości, cięcie
    /// schodzi do kilkunastu punktów góra–dół i widać całe danie — a karta
    /// przestaje zajmować cały ekran.
    static let cardHeight: CGFloat = 330

    let recipe: Recipe

    @Environment(\.colorScheme) private var scheme

    private let cornerRadius: CGFloat = 26
    private var height: CGFloat { Self.cardHeight }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            cover

            // Bottom-anchored editorial scrim — light at top so the photo
            // breathes, deep at the bottom so the title is always legible.
            // Przyciemnienie zaczyna się niżej niż na 420-punktowej karcie —
            // na niższej te same proporcje zasłaniały pół talerza.
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.24), location: 0.00),
                    .init(color: .clear,                    location: 0.24),
                    .init(color: .clear,                    location: 0.52),
                    .init(color: Color.black.opacity(0.80), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            bottomContent
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { heartChip }
        // Bez cienia pod kartą. Karuzela to poziomy `ScrollView`, który
        // przycina wszystko poza swoimi granicami — cień urywał się równo
        // z krawędzią sekcji zamiast zanikać, więc na dole karty rysowała
        // się twarda ciemna kreska.
    }

    // MARK: - Cover

    // UWAGA na `Color.clear.overlay { … }` — to NIE jest ozdobnik, tylko
    // jedyny sposób żeby `scaledToFill()` nie rozpychał layoutu.
    //
    // Wcześniej było `CachedAsyncImage { … scaledToFill() }
    // .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()`. Problem:
    // aspect-fill przy propozycji 362×420 zwraca 420×420 (musi POKRYĆ obie
    // osie), a `frame(maxWidth: .infinity)` rośnie do dziecka, gdy dziecko
    // jest większe od propozycji. `.clipped()` przycina wtedy rysowanie, ale
    // do ramki, która ma już 420pt — więc cała karta raportowała 420pt
    // szerokości i wylewała się poza swój slot na pełny ekran.
    //
    // `Color.clear` przyjmuje propozycję CO DO PIKSELA i nigdy nie rośnie do
    // dziecka, a overlay jest układany w jej granicach — zdjęcie dalej
    // wypełnia kadr, ale nie ma już wpływu na szerokość karty.
    @ViewBuilder
    private var cover: some View {
        if let url = recipe.imageURL {
            Color.clear
                .overlay {
                    CachedAsyncImage(url: url, variant: .large) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .empty, .failure:
                            placeholder
                        @unknown default:
                            placeholder
                        }
                    }
                }
                .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        let tint = RecipeAccent.accent(for: recipe.category)
        return ZStack {
            LinearGradient(
                colors: [
                    tint.opacity(scheme == .dark ? 0.85 : 0.45),
                    tint.opacity(scheme == .dark ? 0.45 : 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Diagonal hatch overlay — matches the design's repeating 45°
            // linear-gradient on photo-less covers, gives placeholders some
            // editorial texture instead of a flat fill.
            Canvas { context, size in
                let spacing: CGFloat = 9
                let diagonal = size.width + size.height
                var x: CGFloat = -size.height
                while x < diagonal {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height + 2, y: size.height))
                    path.addLine(to: CGPoint(x: x + 2, y: 0))
                    path.closeSubpath()
                    context.fill(path, with: .color(.white.opacity(0.04)))
                    x += spacing
                }
            }
            .allowsHitTesting(false)

            Image(systemName: RecipesConstants.icon(for: recipe.category))
                .font(.system(size: 84, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Heart

    private var heartChip: some View {
        let liked = recipe.favourite
        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Color.black.opacity(0.40)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))

            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(liked ? SCPalette.terracotta : Color.white.opacity(0.95))
        }
        .frame(width: 32, height: 32)
        .padding(.top, 14)
        .padding(.trailing, 14)
        .accessibilityHidden(true)
    }

    // MARK: - Bottom content (title + glass chips)

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.name)
                .font(.system(size: 21, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 2)

            HStack(spacing: 6) {
                EditorialGlassChip(icon: "clock",     text: "\(recipe.prepTimeMinutes) min")
                EditorialGlassChip(icon: "flame.fill", text: "\(Int(recipe.nutritionPerServing.kcal.rounded())) kcal")
                if recipe.isThermomix {
                    EditorialGlassChip(icon: "cooktop.fill", text: "Thermomix")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Glass chip used inside hero overlays — same translucent surface used
// elsewhere by the v2 design tokens. Always renders on a photographic /
// dark surface, so colors are fixed (not theme-aware).
struct EditorialGlassChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(Color.white.opacity(0.96))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Capsule(style: .continuous).fill(Color.black.opacity(0.36)))
        }
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
