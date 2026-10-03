#!/bin/sh
# Sprawdzian logiki trybu Gotuj: dekodowanie scenariusza z serwera
# (`recipes:cookScenario`), ilości w krokach po skalowaniu porcji (§5.4),
# tokeny `{count:…}`, zegar timerów i sesja — kroki, dok z timerami (czeka /
# trwa / po czasie / pauza, kolory), „+min”, zapis i odczyt, pora wpisu spoza
# planu (`CookPlanEntry`).
#
# Projekt nie ma targetu testów, więc — jak `deep-link-check.sh` — kompilujemy
# czystą logikę razem ze scenariuszami w `Scripts/CookLogic/main.swift`.
# Wzorzec to scenariusz kotleta z backendu (`kotlet.json`). Odświeżenie po
# zmianie wzorca: `node Scripts/CookLogic/make-fixture.mjs ../scoffie-backend`.
#
# Uruchomienie:  sh Scripts/cook-logic-check.sh
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/cooklogic
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Cook/CookScenario.swift" \
  "Scoffie/Models/Cook/CookAmounts.swift" \
  "Scoffie/Models/Cook/CookSession.swift" \
  "Scoffie/Models/Cook/CookPlanEntry.swift" \
  "Scoffie/Models/Components/MealSlotSchedule.swift" \
  "Scoffie/Models/Components/RecipesModel.swift" \
  "Scoffie/Models/Components/MealSlot.swift" \
  "Scoffie/Models/Components/RecipeTaxonomy.swift" \
  "Scoffie/Constants/KitchenAmountFormatter.swift" \
  "Scoffie/Constants/PolishPlural.swift" \
  "Scripts/CookLogic/main.swift"
"$OUT"
