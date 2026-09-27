#!/bin/sh
# Sprawdzian synchronizacji katalogu (`catalog:snapshot` / `catalog:changes`):
# snapshot bez sufitu 4000, delta stronami z untilRevision, tombstone'y,
# powtórzona dostawa, przerwany przebieg, RESET_REQUIRED, anulowanie i format
# pliku cache — bez Xcode GUI.
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy czystą logikę (`CatalogSync.swift`, tylko Foundation)
# razem ze scenariuszami w `Scripts/CatalogSync/main.swift` i uruchamiamy.
#
# Uruchomienie:  sh Scripts/catalog-sync-check.sh
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/catalogsync
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Components/CatalogSync.swift" \
  "Scripts/CatalogSync/main.swift"
"$OUT"
