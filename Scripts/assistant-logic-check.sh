#!/bin/sh
# Sprawdzian logiki briefingu asystenta: priorytety sytuacji na pustym
# ekranie, teksty i formatowanie dat — bez SwiftUI i bez Xcode GUI.
#
# Projekt nie ma targetu testów, więc — jak `card-contract-check.sh` —
# kompilujemy czystą logikę (`Models/Assistant/AssistantBriefing.swift`
# importuje TYLKO Foundation) razem ze scenariuszami w
# `Scripts/AssistantLogic/main.swift` i uruchamiamy.
#
# Uruchomienie:  sh Scripts/assistant-logic-check.sh
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)/assistantlogic
xcrun swiftc -o "$OUT" \
  "Scoffie/Models/Assistant/AssistantBriefing.swift" \
  "Scripts/AssistantLogic/main.swift"
"$OUT"
