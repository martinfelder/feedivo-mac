#!/bin/bash
# Baut Feedivo im Release-Modus, packt die .app und veroeffentlicht sie als
# GitHub Release im Repo. Liest Versionsnummer/Build aus
# Feedivo.xcodeproj/project.pbxproj und die Release-Notes aus dem obersten
# Eintrag von CHANGELOG.md.
#
# WICHTIG: Wird NIE automatisch aufgerufen (kein Hook) - nur manuell, wenn
# explizit ein Release veroeffentlicht werden soll. Fragt vor dem eigentlichen
# `gh release create` interaktiv nach Bestaetigung.
#
# Voraussetzungen: `gh` CLI installiert und eingeloggt (`gh auth status`),
# lokales Xcode-Signing fuer Release-Builds konfiguriert. Das Ergebnis ist ein
# lokal signierter, NICHT notarisierter Build - beim Oeffnen auf einem anderen
# Mac ist ggf. Rechtsklick -> "Oeffnen" noetig (Gatekeeper).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PBXPROJ="Feedivo.xcodeproj/project.pbxproj"
CHANGELOG="CHANGELOG.md"
SCHEME="Feedivo"
CONFIGURATION="Release"
BUILD_DIR="$REPO_ROOT/build_release"

if ! command -v gh >/dev/null 2>&1; then
  echo "create_github_release.sh: 'gh' CLI nicht gefunden. Bitte installieren (brew install gh) und 'gh auth login' ausfuehren." >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "create_github_release.sh: 'gh' ist nicht eingeloggt. Bitte 'gh auth login' ausfuehren." >&2
  exit 1
fi

MARKETING_VERSION="$(grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" | sed -E 's/.*= ([0-9.]+);.*/\1/')"
BUILD_NUMBER="$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" | sed -E 's/[^0-9]*([0-9]+);.*/\1/')"
if [ -z "$MARKETING_VERSION" ] || [ -z "$BUILD_NUMBER" ]; then
  echo "create_github_release.sh: Konnte Version/Build nicht aus $PBXPROJ lesen." >&2
  exit 1
fi

VERSION_LABEL="${MARKETING_VERSION} (${BUILD_NUMBER})"
TAG="v${MARKETING_VERSION}-${BUILD_NUMBER}"

if git rev-parse "$TAG" >/dev/null 2>&1 || gh release view "$TAG" >/dev/null 2>&1; then
  echo "create_github_release.sh: Tag/Release '$TAG' existiert bereits. Erst einen neuen Bump pushen, dann erneut versuchen." >&2
  exit 1
fi

# Release-Notes = oberster Eintrag aus CHANGELOG.md (zwischen der ersten und
# der naechsten "## ["-Zeile).
NOTES_FILE="$(mktemp)"
awk '
  /^## \[/ { count++ }
  count == 1 { print }
  count == 2 { exit }
' "$CHANGELOG" | tail -n +2 > "$NOTES_FILE"
if [ ! -s "$NOTES_FILE" ]; then
  echo "create_github_release.sh: Konnte keinen Changelog-Eintrag fuer die Release-Notes finden." >&2
  rm -f "$NOTES_FILE"
  exit 1
fi

echo "Release-Vorschau"
echo "  Tag:      $TAG"
echo "  Titel:    Feedivo ${VERSION_LABEL}"
echo "  Notes aus: $CHANGELOG (oberster Eintrag)"
echo "---"
cat "$NOTES_FILE"
echo "---"
read -r -p "Release wirklich bauen und auf GitHub veroeffentlichen? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Abgebrochen."
  rm -f "$NOTES_FILE"
  exit 0
fi

echo "Baue Release-Konfiguration..."
rm -rf "$BUILD_DIR"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS' \
  clean build

APP_PATH="$(find "$BUILD_DIR/Build/Products/$CONFIGURATION" -maxdepth 1 -name '*.app' | head -1)"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "create_github_release.sh: Konnte die gebaute .app nicht unter $BUILD_DIR/Build/Products/$CONFIGURATION finden." >&2
  rm -f "$NOTES_FILE"
  exit 1
fi

ZIP_PATH="$BUILD_DIR/Feedivo-${TAG}.zip"
echo "Packe $APP_PATH -> $ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Erstelle GitHub Release $TAG..."
gh release create "$TAG" "$ZIP_PATH" \
  --title "Feedivo ${VERSION_LABEL}" \
  --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"
echo "create_github_release.sh: Release $TAG veroeffentlicht."
