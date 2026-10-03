#!/bin/sh
# Sprawdzian granicy store → repozytorium dla porcji per osoba: prawdziwy
# `MealCalendarStore` z atrapą `WeeklyPlanRepository`, która zapisuje wywołania
# (pozycja z alokacją → PRESERVE z tokenami, bez tokenów → zero zapytań;
# stepper porcji → setPortion per osoba; konflikt → cofnięcie bez ponowienia).
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy potrzebne pliki aplikacji (domknięcie zależności
# `MealCalendarStore.swift` bez `ScoffieApp.swift`) ze scenariuszami
# w `Scripts/PlanStore/main.swift` i uruchamiamy jako program macOS.
#
# Store zapisuje cache w Documents i przy starcie kasuje `saved_plan.json`,
# więc program biegnie z `CFFIXED_USER_HOME` w katalogu tymczasowym (sam
# sprawdzian odmawia startu bez tego).
#
# Uruchomienie:  sh Scripts/plan-store-check.sh
set -e
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
OUT="$WORK/planstore"
mkdir -p "$WORK/home/Documents"
# `#Preview` w PolishPlural.swift rozwija wtyczka makr platformy — jawnie,
# gdyby sterownik nie dodał jej sam.
PLUGIN_ARGS=""
PLUGINS="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
if [ -d "$PLUGINS" ]; then
  PLUGIN_ARGS="-plugin-path $PLUGINS"
fi
# shellcheck disable=SC2086
xcrun swiftc $PLUGIN_ARGS -o "$OUT" \
  "Scoffie/Models/Stores/MealCalendarStore.swift" \
  "Scoffie/Models/Stores/WeeklyPlanStore.swift" \
  "Scoffie/Models/Stores/PlanChangeNotificationService.swift" \
  "Scoffie/Models/Stores/UserFacingErrorMapper.swift" \
  "Scoffie/Models/Stores/ConnectivityMonitor.swift" \
  "Scoffie/Models/Stores/DebugLog.swift" \
  "Scoffie/Models/Plans/SavedMealPlan.swift" \
  "Scoffie/Models/Plans/PlanPortions.swift" \
  "Scoffie/Models/Cook/CookScenario.swift" \
  "Scoffie/Models/Cook/CookAmounts.swift" \
  "Scoffie/Models/Cook/CookSession.swift" \
  "Scoffie/Models/Cook/CookFeedback.swift" \
  "Scoffie/Models/Components/PlanWeek.swift" \
  "Scoffie/Models/Components/RecipesModel.swift" \
  "Scoffie/Models/Components/RecipeTaxonomy.swift" \
  "Scoffie/Models/Components/MealSlot.swift" \
  "Scoffie/Models/Components/CatalogSync.swift" \
  "Scoffie/Models/Components/ShoppingItemModel.swift" \
  "Scoffie/Models/ShoppingList/ShoppingListData.swift" \
  "Scoffie/Constants/PolishPlural.swift" \
  "Scoffie/Constants/KitchenAmountFormatter.swift" \
  "Scoffie/Networking/Recipes/BackendRecipeDTOs.swift" \
  "Scoffie/Networking/Recipes/BackendCatalogSyncDTOs.swift" \
  "Scoffie/Networking/Recipes/RecipeProtocols.swift" \
  "Scoffie/Models/Session/DeepLink.swift" \
  "Scoffie/Networking/ShoppingList/BackendShoppingListDTOs.swift" \
  "Scoffie/Networking/Integrations/IntegrationsAPIClient.swift" \
  "Scoffie/Networking/Integrations/IntegrationsDTOs.swift" \
  "Scripts/PlanStore/main.swift"
CFFIXED_USER_HOME="$WORK/home" "$OUT"
