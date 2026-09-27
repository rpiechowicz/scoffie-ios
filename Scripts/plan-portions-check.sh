#!/bin/sh
# Sprawdzian porcji per osoba (`PlanItem.portions`): jednostki 1/20 porcji,
# etykiety i decyzja zapisu — pozycje z alokacją są ZABLOKOWANE do edycji
# (serwer zastępuje całą alokację bez kontroli wersji), legacy bez zmian.
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy czystą logikę (`PlanPortions.swift`, tylko Foundation)
# razem ze scenariuszami w `Scripts/PlanPortions/main.swift` i uruchamiamy.
#
# Uruchomienie:  sh Scripts/plan-portions-check.sh
set -e
cd "$(dirname "$0")/.."

# Regresja statyczna: iOS nie buduje zapisu z polem `portions` — bez kontroli
# wersji po stronie serwera taki zapis mógłby cofnąć zmianę innego telefonu.
if grep -n '"portions"' Scoffie/Models/Stores/WeeklyPlanStore.swift | grep -v '^[0-9]*: *///'; then
  echo "BŁĄD iOS wysyła pole \"portions\" w zapisie planu (API GAP — zablokowane)"
  exit 1
fi
echo "OK   zapis planu nie zawiera pola \"portions\""

OUT=$(mktemp -d)/planportions
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Plans/PlanPortions.swift" \
  "Scripts/PlanPortions/main.swift"
"$OUT"
