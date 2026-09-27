#!/bin/sh
# Sprawdzian porcji per osoba (`PlanItem.portions`): jednostki 1/20 porcji,
# etykiety, wartość na drucie i tabela decyzji zapisu — co odsyłać, żeby
# serwer nie skasował alokacji (pominięte `portions` = równy podział).
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy czystą logikę (`PlanPortions.swift`, tylko Foundation)
# razem ze scenariuszami w `Scripts/PlanPortions/main.swift` i uruchamiamy.
#
# Uruchomienie:  sh Scripts/plan-portions-check.sh
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/planportions
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Plans/PlanPortions.swift" \
  "Scripts/PlanPortions/main.swift"
"$OUT"
