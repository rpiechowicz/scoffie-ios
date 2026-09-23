import SwiftUI

#if DEBUG
// Podglądy kart i stanów asystenta — jedno miejsce, wspólne wzorce
// (`AssistantPreviewFixtures`). Każdy podgląd jasny; kilka reprezentatywnych
// w ciemnym motywie, bo tam najłatwiej o zbyt blade tinty.

private struct PreviewCanvas<Content: View>: View {
    var scheme: ColorScheme = .light
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(20)
        }
        .background(SCPageBackground(scheme: scheme).ignoresSafeArea())
        .preferredColorScheme(scheme)
    }
}

#Preview("PLAN_WEEK — do zatwierdzenia") {
    struct Demo: View {
        @State private var expanded = false
        var body: some View {
            PreviewCanvas {
                AssistantPlanWeekCard(
                    card: AssistantPreviewFixtures.planWeek,
                    isBusy: false,
                    isExpanded: $expanded,
                    onApply: { _ in },
                    onRevise: {},
                    onAskNew: {},
                    onUndo: {},
                    onOpenPlan: {}
                )
            }
        }
    }
    return Demo()
}

#Preview("PLAN_WEEK — zapisane / nieaktualna / cofnięte") {
    PreviewCanvas {
        AssistantPlanWeekCard(card: AssistantPreviewFixtures.planWeek(status: "APPLIED", canApply: false, canUndo: true), isBusy: false, isExpanded: .constant(false), onApply: { _ in }, onRevise: {}, onAskNew: {}, onUndo: {}, onOpenPlan: {})
        AssistantPlanWeekCard(card: AssistantPreviewFixtures.planWeek(status: "STALE", canApply: true, canUndo: false), isBusy: false, isExpanded: .constant(false), onApply: { _ in }, onRevise: {}, onAskNew: {}, onUndo: {}, onOpenPlan: {})
        AssistantPlanWeekCard(card: AssistantPreviewFixtures.planWeek(status: "UNDONE", canApply: true, canUndo: false), isBusy: false, isExpanded: .constant(false), onApply: { _ in }, onRevise: {}, onAskNew: {}, onUndo: {}, onOpenPlan: {})
    }
}

#Preview("PLAN_DAY") {
    PreviewCanvas {
        AssistantPlanDayCard(card: AssistantPreviewFixtures.planDay, isBusy: false, onApply: { _ in }, onRevise: {}, onAskNew: {}, onUndo: {}, onOpenPlan: {})
    }
}

#Preview("OPTIONS + CLARIFY") {
    PreviewCanvas {
        AssistantOptionsCard(card: AssistantPreviewFixtures.options, onAsk: { _ in })
        AssistantClarifyCard(card: AssistantPreviewFixtures.clarify, onAsk: { _ in })
        AssistantClarifyCard(card: AssistantPreviewFixtures.clarify, reply: "Dla dwóch", onAsk: { _ in })
    }
}

#Preview("SWAP + REMOVE") {
    PreviewCanvas {
        AssistantSwapCard(card: AssistantPreviewFixtures.swap, isBusy: false, onApply: { _ in }, onRevise: {}, onAskNew: {}, onAsk: { _ in }, onUndo: {}, onOpenPlan: {})
        AssistantRemoveMealCard(card: AssistantPreviewFixtures.removeMeal, isBusy: false, onApply: { _ in }, onRevise: {}, onAskNew: {}, onAsk: { _ in }, onUndo: {}, onOpenPlan: {})
    }
}

#Preview("MACRO_GAP + SHOPPING") {
    PreviewCanvas {
        AssistantMacroGapCard(card: AssistantPreviewFixtures.macroGap, onAsk: { _ in })
        AssistantShoppingListCard(card: AssistantPreviewFixtures.shoppingList, onOpenShopping: {})
    }
}

#Preview("HOUSEHOLD + APPLIED") {
    PreviewCanvas {
        AssistantHouseholdSplitCard(card: AssistantPreviewFixtures.householdSplit, isBusy: false, onApply: { _ in }, onRevise: {}, onAskNew: {}, onUndo: {}, onOpenPlan: {})
        AssistantAppliedCard(card: AssistantPreviewFixtures.applied, isBusy: false, onUndo: {}, onOpenPlan: {})
    }
}

#Preview("Ciemny — propozycja, zapis, bilans") {
    PreviewCanvas(scheme: .dark) {
        AssistantPlanDayCard(card: AssistantPreviewFixtures.planDay, isBusy: false, onApply: { _ in }, onRevise: {}, onAskNew: {}, onUndo: {}, onOpenPlan: {})
        AssistantAppliedCard(card: AssistantPreviewFixtures.applied, isBusy: false, onUndo: {}, onOpenPlan: {})
        AssistantMacroGapCard(card: AssistantPreviewFixtures.macroGap, onAsk: { _ in })
        AssistantOutcomeCard(code: "AI_TIMEOUT", message: "", wrote: false, onAsk: { _ in }, onAskAgain: {})
    }
}

#Preview("Powitania — pory dnia") {
    PreviewCanvas {
        ForEach([AssistantBriefing.Kind.breakfastMissing, .todayEmpty, .cookSoon, .dinnerMissing, .tomorrowPartial, .lateNight], id: \.rawValue) { kind in
            AssistantEmptyState(briefing: AssistantPreviewFixtures.briefing(kind), onAction: { _ in })
        }
    }
}

#Preview("Powitania — tydzień, bilans, nowe konto, pula") {
    PreviewCanvas {
        ForEach([AssistantBriefing.Kind.weekEmpty, .nextWeekEmpty, .balanceIssue, .weekReady, .newUser, .trialExhausted], id: \.rawValue) { kind in
            AssistantEmptyState(briefing: AssistantPreviewFixtures.briefing(kind), onAction: { _ in })
        }
    }
}

#Preview("Powitanie — ciemny, pisanie") {
    PreviewCanvas(scheme: .dark) {
        AssistantEmptyState(briefing: AssistantPreviewFixtures.briefing(.dinnerMissing), onAction: { _ in })
        AssistantEmptyState(briefing: AssistantPreviewFixtures.briefing(.dinnerMissing), composing: true, onAction: { _ in })
    }
}

#Preview("Tura — praca i podsumowanie") {
    struct Demo: View {
        @State private var expanded = false
        private let steps = [
            AgentProgressStepDTO(tool: "read", label: "Już się tym zajmuję", at: "2026-09-19T10:00:00.000Z", writes: nil, phase: nil, transient: true),
            AgentProgressStepDTO(tool: "get_week_plan", label: "Sprawdzam plan tygodnia", at: "2026-09-19T10:00:02.000Z", writes: false, phase: nil, transient: nil),
            AgentProgressStepDTO(tool: "search_recipes_by_ingredient", label: "Szukam pasujących przepisów", at: "2026-09-19T10:00:04.000Z", writes: false, phase: nil, transient: nil),
            AgentProgressStepDTO(tool: "start_planning", label: "Układam propozycję tygodnia", at: "2026-09-19T10:00:05.000Z", writes: nil, phase: "PLANNING", transient: nil),
        ]

        var body: some View {
            PreviewCanvas {
                AssistantThoughtLine(
                    phase: .working(startedAt: Date().addingTimeInterval(-7), isStopping: false),
                    steps: steps,
                    isExpanded: .constant(false)
                )
                AssistantThoughtLine(
                    phase: .working(startedAt: Date().addingTimeInterval(-3), isStopping: true),
                    steps: steps,
                    isExpanded: .constant(false)
                )
                AssistantThoughtLine(
                    phase: .settled(duration: 42.3),
                    steps: steps.filter { !$0.isTransient },
                    isExpanded: $expanded
                )
            }
        }
    }
    return Demo()
}
#endif
