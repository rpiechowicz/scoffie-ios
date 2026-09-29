#!/bin/sh
# Sprawdzian parsera linków (`DeepLink`): Universal Links z scoffie.app
# (zaproszenie, przepis katalogu po slugu / UUID, przepis domu po tokenie),
# schemat `scoffie://`, końcowe ukośniki, hosty i adres kanoniczny, na którym
# stoi odkładanie linku przed zalogowaniem.
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy czystą logikę (`DeepLink.swift`, tylko Foundation) razem ze
# scenariuszami w `Scripts/DeepLink/main.swift` i uruchamiamy.
#
# Uruchomienie:  sh Scripts/deep-link-check.sh
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/deeplink
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Session/DeepLink.swift" \
  "Scripts/DeepLink/main.swift"
"$OUT"
