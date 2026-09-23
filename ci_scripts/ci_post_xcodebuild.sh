#!/bin/sh
# Xcode Cloud: po archiwum wysyła symbole (dSYM) do Sentry — bez nich crash
# z TestFlightu to same adresy. Xcode Cloud woła ten plik po KAŻDEJ akcji
# xcodebuild; robota jest tylko przy `archive`.
#
# Wymaga zmiennej środowiskowej SENTRY_AUTH_TOKEN (Secret) w workflow
# Xcode Cloud — token organizacji `scoffie` z Sentry. Bez niej, przy braku
# sieci albo przy złej sumie kontrolnej: ostrzeżenie i wyjście 0. Build
# i wysyłka do TestFlight mają przejść ZAWSZE — niezerowy kod stąd
# oznaczyłby cały build jako nieudany.
#
# `sentry-cli` przypięty co do wersji i sumy SHA-256 (plik z wydań GitHuba),
# a nie `brew install` bez wersji: 3.x zdjęło flagi, na których stał 2.x.
set -u

SENTRY_CLI_VERSION="3.8.0"
SENTRY_CLI_SHA256="2c26914636c47ab9bf9e710484ad7b44d371cbec8bd29cafb36b3cf877bf4285"

warn() {
  echo "warning: [sentry] $1"
  exit 0
}

[ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] || exit 0
[ -n "${SENTRY_AUTH_TOKEN:-}" ] || warn "brak SENTRY_AUTH_TOKEN w workflow Xcode Cloud — dSYM nie trafią do Sentry"

DSYMS="${CI_ARCHIVE_PATH:-}/dSYMs"
[ -d "$DSYMS" ] || warn "brak katalogu $DSYMS"

WORK=$(mktemp -d) || warn "mktemp nie wyszedł"
BIN="$WORK/sentry-cli"
curl -fsSL --retry 3 -o "$BIN" \
  "https://github.com/getsentry/sentry-cli/releases/download/${SENTRY_CLI_VERSION}/sentry-cli-Darwin-universal" \
  || warn "nie udało się pobrać sentry-cli ${SENTRY_CLI_VERSION}"
echo "${SENTRY_CLI_SHA256}  ${BIN}" | shasum -a 256 -c - >/dev/null 2>&1 \
  || warn "suma SHA-256 sentry-cli się nie zgadza — nie uruchamiam"
chmod +x "$BIN"

SENTRY_ORG=scoffie SENTRY_PROJECT=scoffie-ios \
  "$BIN" debug-files upload --include-sources "$DSYMS" \
  || warn "wysyłka dSYM nie wyszła (token? dostęp do org scoffie?)"

echo "[sentry] dSYM wysłane z $DSYMS"
exit 0
