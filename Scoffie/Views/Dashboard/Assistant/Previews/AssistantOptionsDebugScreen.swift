import SwiftUI

#if DEBUG
/// Ekran do porównywania karty wyboru z makietą — tylko w kompilacji DEBUG
/// i tylko, gdy proces dostał `SCOFFIE_DEBUG_OPTIONS`:
///
///     SIMCTL_CHILD_SCOFFIE_DEBUG_OPTIONS=0 xcrun simctl launch booted <bundle id>
///
/// Wartość to strona arkusza do otwarcia (`0…n` = dania, `n` = „Coś innego”)
/// albo `card`, żeby zobaczyć samą kotwicę w rozmowie. Prawdziwe przepisy
/// i zdjęcia z katalogu, żeby kadr i liczby były takie jak u użytkownika.
struct AssistantOptionsDebugScreen: View {
    let page: Int?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.toasts) private var toasts

    static var requested: AssistantOptionsDebugScreen? {
        guard let raw = ProcessInfo.processInfo.environment["SCOFFIE_DEBUG_OPTIONS"] else { return nil }
        return AssistantOptionsDebugScreen(page: Int(raw))
    }

    private static let json = #"""
    {"kind": "OPTIONS", "v": 1, "eyebrow": "Śniadanie · środa", "title": "Śniadanie na dziś", "options": [
      {"recipeId": "d0d09af3-1821-47be-be95-63a208fc47bd", "title": "Jogurt naturalny z musli, truskawkami i borówkami", "kcalPerServing": 316, "prepTimeMinutes": 6, "imageUrl": "https://pub-d6de57d50783403ab7f168d38802a1a6.r2.dev/recipe-images/d0d09af3-1821-47be-be95-63a208fc47bd.png", "description": "Szybkie śniadanie na zimno z jogurtem naturalnym, chrupiącym musli, truskawkami i borówkami. Lekkie, ale dobrze sycące na poranek.", "proteinGrams": 10, "carbsGrams": 40, "fatGrams": 12, "ingredientCount": 4, "tag": "Najszybsze", "prompt": "Wybieram: Jogurt naturalny z musli, truskawkami i borówkami"},
      {"recipeId": "1a66ef3b-f1dc-4427-b6b3-3ca5d6986e80", "title": "Omlet ze szpinakiem i fetą", "kcalPerServing": 450, "prepTimeMinutes": 15, "imageUrl": "https://pub-d6de57d50783403ab7f168d38802a1a6.r2.dev/recipe-images/1a66ef3b-f1dc-4427-b6b3-3ca5d6986e80.png", "description": "Puszysty omlet z dwóch jaj ze świeżym szpinakiem i fetą, smażony na maśle.", "proteinGrams": 26, "carbsGrams": 6, "fatGrams": 30, "ingredientCount": 6, "tag": "Najwięcej białka", "prompt": "Wybieram: Omlet ze szpinakiem i fetą"},
      {"recipeId": "386586d2-b4f8-41f0-9641-cce2b7c20dd7", "title": "Skyr z granolą i malinami", "kcalPerServing": 336, "prepTimeMinutes": 5, "imageUrl": "https://pub-d6de57d50783403ab7f168d38802a1a6.r2.dev/recipe-images/386586d2-b4f8-41f0-9641-cce2b7c20dd7.png", "tag": null, "prompt": "Wybieram: Skyr z granolą i malinami"}
    ], "actions": [{"type": "ASK", "proposalId": null, "label": "Coś innego", "style": "SECONDARY", "prompt": "Żadne z tych mi nie pasuje. Zaproponuj coś innego."}]}
    """#

    private var card: OptionsCardDTO {
        guard case .options(let card) = AssistantPreviewFixtures.card(Self.json) else { fatalError("OPTIONS") }
        return card
    }

    /// `SCOFFIE_DEBUG_OPTIONS=buttons` — zwykłe karty z akcjami, do obejrzenia
    /// stylu przycisków poza arkuszem.
    private var showsButtons: Bool {
        ProcessInfo.processInfo.environment["SCOFFIE_DEBUG_OPTIONS"] == "buttons"
    }

    private var mode: String? { ProcessInfo.processInfo.environment["SCOFFIE_DEBUG_OPTIONS"] }

    var body: some View {
        if mode == "auth" || mode == "auth-error" {
            // Ekran logowania: `auth`, z błędem: `auth-error`.
            AuthView(
                isLoading: false,
                errorMessage: mode == "auth-error" ? "Nie udało się zweryfikować logowania Apple. Spróbuj ponownie." : nil,
                onSignInWithAppleTap: {}
            )
        } else if mode == "legal" {
            // Arkusz dokumentu nad ekranem logowania.
            AuthView(isLoading: false, errorMessage: nil, onSignInWithAppleTap: {})
                .sheet(isPresented: .constant(true)) {
                    LegalDocumentSheet(title: "Warunki korzystania") { TermsOfServiceContent() }
                }
        } else if showsButtons {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AssistantSwapCard(card: AssistantPreviewFixtures.swap, isBusy: false, onApply: { _ in }, onRevise: {}, onAskNew: {}, onAsk: { _ in }, onUndo: {}, onOpenPlan: {})
                    AssistantAppliedCard(card: AssistantPreviewFixtures.applied, isBusy: false, onUndo: {}, onOpenPlan: {})
                }
                .padding(16)
                .padding(.top, 50)
            }
            .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
        } else {
            conversation
        }
    }

    private var conversation: some View {
        ZStack(alignment: .bottom) {
            SCPageBackground(scheme: scheme).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                AssistantUserBubble(text: "Co dziś na śniadanie?", editing: false, pending: false)
                AssistantVoice { AssistantAnswer(text: "Trzy śniadania z Twoich przepisów, wszystkie do 15 minut.") }
                AssistantOptionsCard(
                    card: card,
                    autoPresentID: page == nil ? nil : "debug-\(page ?? 0)",
                    autoPresentPage: page ?? 0,
                    onAsk: { _ in }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        // Symulator bez sesji jest „offline” — pasek o sieci zasłaniałby
        // nagłówek arkusza na zrzucie.
        .task {
            while !Task.isCancelled {
                toasts.setPersistent(nil)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}
#endif
