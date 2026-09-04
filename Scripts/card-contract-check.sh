#!/bin/sh
# Sprawdzian kontraktu kart asystenta: czy JSON, który liczy SERWER, wchodzi
# w struktury tego klienta.
#
# Po co osobny skrypt, a nie test: projekt nie ma targetu testów, a to jest
# jedyna rzecz w E2, która potrafi się zepsuć CAŁKIEM PO CICHU. Zmiana nazwy
# pola po stronie serwera nie wywoła żadnego błędu — karta stanie się
# `.unknown` i po prostu zniknie z ekranu, a odpowiedź asystenta będzie
# wyglądać na kompletną.
#
# Wzorzec (`Scripts/CardContract/main.swift`) trzyma odpowiedź serwera
# dosłownie. Po zmianie kart w backendzie odśwież go:
#   docker exec scoffie-api sh -c 'cd /app && npx tsx scripts/dump-card-fixtures.ts'
#
# Uruchomienie:  sh Scripts/card-contract-check.sh
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/cardcheck
xcrun swiftc -o "$OUT" \
  "Scoffie/Networking/Agent/AgentCardDTOs.swift" \
  "Scoffie/Networking/Agent/AgentDTOs.swift" \
  "Scripts/CardContract/main.swift"
"$OUT"
