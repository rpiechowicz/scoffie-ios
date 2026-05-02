import SwiftUI

// User's primary cooking / nutrition goal. Picked once during the welcome
// flow (step 2) and editable later in Settings. Stored as the rawValue in
// `@AppStorage` so unknown ids fall back to `.healthy`. The backend uses
// uppercase values (`HEALTHY`, `LOSE`, …) — we lowercase on read and
// uppercase on write at the SessionStore boundary.
enum UserGoal: String, CaseIterable, Identifiable {
    case healthy
    case lose
    case gain
    case maintain
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthy:  return "Jeść zdrowiej"
        case .lose:     return "Schudnąć"
        case .gain:     return "Przytyć / zbudować masę"
        case .maintain: return "Utrzymać wagę"
        case .plan:     return "Lepiej planować posiłki"
        }
    }

    var subtitle: String {
        switch self {
        case .healthy:  return "Zbilansowane posiłki, mniej przetworzonych."
        case .lose:     return "Lekki deficyt kaloryczny."
        case .gain:     return "Nadwyżka kaloryczna z białkiem."
        case .maintain: return "Dopasowane do bieżącego trybu."
        case .plan:     return "Bez konkretnego celu kalorycznego."
        }
    }

    var icon: String {
        switch self {
        case .healthy:  return "leaf.fill"
        case .lose:     return "flame.fill"
        case .gain:     return "sparkles"
        case .maintain: return "heart.fill"
        case .plan:     return "calendar"
        }
    }

    var accent: Color {
        switch self {
        case .healthy:  return WMPalette.sage
        case .lose:     return WMPalette.terracotta
        case .gain:     return WMPalette.butter
        case .maintain: return WMPalette.indigo
        case .plan:     return WMPalette.terracotta
        }
    }

    /// Suggested baseline kcal target for this goal. Used to seed the slider
    /// in welcome step 3 — the user can still drag to any value within the
    /// 1200…3500 range. Rough numbers for an average adult, not medical advice.
    var suggestedCalories: Int {
        switch self {
        case .healthy:  return 2200
        case .lose:     return 1800
        case .gain:     return 2700
        case .maintain: return 2200
        case .plan:     return 2300
        }
    }
}

// 4-step activity scale matching the welcome flow's "treningi w tygodniu"
// row. The numeric raw value mirrors the backend's `activityLevel` int
// (1 sedentary → 4 very active) so we can pass it through unchanged.
enum ActivityLevel: Int, CaseIterable, Identifiable {
    case sedentary = 1
    case light = 2
    case active = 3
    case veryActive = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sedentary:  return "0–1"
        case .light:      return "2–3"
        case .active:     return "4–5"
        case .veryActive: return "6+"
        }
    }

    var subtitle: String {
        switch self {
        case .sedentary:  return "Siedzący"
        case .light:      return "Lekko aktywny"
        case .active:     return "Aktywny"
        case .veryActive: return "Bardzo aktywny"
        }
    }
}
