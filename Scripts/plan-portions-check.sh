#!/bin/sh
# Sprawdzian porcji per osoba (`PlanItem.portions`): jednostki 1/20 porcji,
# etykiety, stepper co 0,5 i decyzja zapisu — pozycje z alokacją idą
# z `PRESERVE` i tokenami, bez tokenów wcale; legacy bez zmian.
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy czystą logikę (`PlanPortions.swift`, tylko Foundation)
# razem ze scenariuszami w `Scripts/PlanPortions/main.swift` i uruchamiamy.
#
# Uruchomienie:  sh Scripts/plan-portions-check.sh
set -e
cd "$(dirname "$0")/.."

# Regresja statyczna: pełna mapa `portions` wychodzi WYŁĄCZNIE z polityką
# `REPLACE` (pierwsze ustawienie porcji osób, z tokenem pozycji) — porcję
# jednej osoby zmienia `setPortion`, a przeliczenie audytorium robi serwer
# (`PRESERVE`). Jedno miejsce w transporcie, tuż po `"REPLACE"`.
COUNT=$(grep -c 'data\["portions"\]' Scoffie/Models/Stores/WeeklyPlanStore.swift || true)
if [ "$COUNT" != "1" ] || ! grep -B1 'data\["portions"\]' Scoffie/Models/Stores/WeeklyPlanStore.swift | grep -q '"REPLACE"'; then
  echo "BŁĄD pole \"portions\" w zapisie planu poza gałęzią REPLACE (wystąpień: $COUNT)"
  exit 1
fi
echo "OK   pole \"portions\" tylko z polityką REPLACE"

OUT=$(mktemp -d)/planportions
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Plans/PlanPortions.swift" \
  "Scripts/PlanPortions/main.swift"
"$OUT"
