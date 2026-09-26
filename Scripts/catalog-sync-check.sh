#!/bin/sh
# Sprawdzian synchronizacji katalogu (backend workstream Etap 4A): snapshot
# bez sufitu 4000, delta z upsertami i tombstone'ami, idempotencja, rewizja
# zapisywana dopiero po całym przebiegu — bez Xcode GUI.
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy czystą logikę (`CatalogSyncApplier.swift`, tylko Foundation)
# razem ze scenariuszami w `Scripts/CatalogSync/main.swift` i uruchamiamy.
#
# Uruchomienie:  sh Scripts/catalog-sync-check.sh
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/catalogsync
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Components/CatalogSyncApplier.swift" \
  "Scripts/CatalogSync/main.swift"
"$OUT"
