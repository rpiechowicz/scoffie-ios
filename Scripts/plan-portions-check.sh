#!/bin/sh
# Sprawdzian porcji per osoba (backend Etap 2.2): dekodowanie starego
# i nowego planu, kcal osoby z jej porcji, suma dnia, cache — bez Xcode GUI.
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy modele planu razem ze scenariuszami
# w `Scripts/PlanPortions/main.swift` i uruchamiamy.
#
# Uruchomienie:  sh Scripts/plan-portions-check.sh
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/planportions
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Components/MealSlot.swift" \
  "Scoffie/Models/Components/RecipesModel.swift" \
  "Scoffie/Models/Plans/SavedMealPlan.swift" \
  "Scoffie/Views/Dashboard/WeeklyPlan/Components/PlanDayNutrition.swift" \
  "Scripts/PlanPortions/main.swift"
"$OUT"
