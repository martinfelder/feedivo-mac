#!/bin/bash
# Baut Feedivo im Release-Modus, packt die .app und veroeffentlicht sie als
# GitHub Release im Repo. Liest Versionsnummer/Build aus
# Feedivo.xcodeproj/project.pbxproj und die Release-Notes aus dem obersten
# Eintrag von CHANGELOG.md.
#
# WICHTIG: Wird NIE automatisch aufgerufen (kein Hook) - nur manuell, wenn
# explizit ein Release veroeffentlicht werden soll. Fragt vor dem eigentlichen
# `gh release create` interaktiv nach Bestaetigung. Wird IMMER als Pre-Release
# markiert (--prerelease), nicht als "Latest Release".
#
# Mit --dry-run zeigt es nur Tag/Titel/Notes-Vorschau, baut NICHTS, fragt
# NICHT nach Bestaetigung und veroeffentlicht nichts.
#
# Voraussetzungen: `gh` CLI installiert und eingeloggt (`gh auth status`),
# lokales Xcode-Signing fuer Release-Builds konfiguriert. Das Ergebnis ist ein
# lokal signierter, NICHT notarisierter Build - beim Oeffnen auf einem anderen
# Mac ist ggf. Rechtsklick -> "Oeffnen" noetig (Gatekeeper).
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done

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
ZIP_PATH="$BUILD_DIR/Feedivo-${TAG}.zip"

TAG_EXISTS=0
if git rev-parse "$TAG" >/dev/null 2>&1 || gh release view "$TAG" >/dev/null 2>&1; then
  TAG_EXISTS=1
fi
if [ "$TAG_EXISTS" = "1" ] && [ "$DRY_RUN" != "1" ]; then
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
echo "  Tag:      $TAG$( [ "$TAG_EXISTS" = "1" ] && echo " (existiert bereits!)" )"
echo "  Titel:    Feedivo ${VERSION_LABEL}"
echo "  Notes aus: $CHANGELOG (oberster Eintrag)"
echo "---"
cat "$NOTES_FILE"
echo "---"
echo "  Zusätzliches Asset: $(basename "$ZIP_PATH").sha256 (SHA256-Prüfsumme)"

if [ "$DRY_RUN" = "1" ]; then
  echo "--- DRY RUN: kein Build, keine Bestaetigungsfrage, kein Release veroeffentlicht ---"
  if [ "$TAG_EXISTS" = "1" ]; then
    echo "Hinweis: Tag/Release '$TAG' existiert bereits - ein echter Lauf wuerde an dieser Stelle abbrechen."
  fi
  rm -f "$NOTES_FILE"
  exit 0
fi

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

APP_PATH="$(find "$BUILD_DIR/Build/Products/$CONFIGURATION" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "create_github_release.sh: Konnte die gebaute .app nicht unter $BUILD_DIR/Build/Products/$CONFIGURATION finden." >&2
  rm -f "$NOTES_FILE"
  exit 1
fi

echo "Packe $APP_PATH -> $ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

CHECKSUM_PATH="${ZIP_PATH}.sha256"
echo "Berechne SHA256-Prüfsumme -> $CHECKSUM_PATH"
shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "$CHECKSUM_PATH"

echo "Erstelle GitHub Release $TAG (als Pre-Release)..."
gh release create "$TAG" "$ZIP_PATH" "$CHECKSUM_PATH" \
  --title "Feedivo ${VERSION_LABEL}" \
  --notes-file "$NOTES_FILE" \
  --prerelease

# Notes-Inhalt VOR dem Loeschen von $NOTES_FILE sichern - wird weiter unten
# fuer den Appcast-CDATA-Block gebraucht, aber die Datei selbst ist ab hier weg.
RELEASE_NOTES_CONTENT="$(cat "$NOTES_FILE")"
rm -f "$NOTES_FILE"
echo "create_github_release.sh: Release $TAG veroeffentlicht."

echo "Signiere ZIP für Sparkle (EdDSA)..."
# Fix Whole-Branch-Review (Important 3): `find ... | head -1` ist unter
# `set -euo pipefail` riskant, sobald `find` mehr als einen Treffer liefert
# (normal bei mehreren DerivedData-Verzeichnissen) - `head -1` beendet sich
# nach der ersten Zeile, `find` bekommt dadurch SIGPIPE, und die Pipeline
# kann mit einem Nicht-Null-Status abbrechen - hier ERST NACH dem bereits
# veröffentlichten `gh release create` oben. `-print -quit` stoppt `find`
# selbst nach dem ersten Treffer, ganz ohne Pipe/SIGPIPE-Risiko.
# Live-Release-Fund (2026-08-01): dieses Skript baut mit einem eigenen
# -derivedDataPath ($BUILD_DIR statt der Standard-Xcode-DerivedData) - dessen
# SourcePackages-Ordner ist komplett getrennt von
# ~/Library/Developer/Xcode/DerivedData/Feedivo-*/SourcePackages, wo
# sign_update sonst normalerweise aufgelöst wird. Ohne diesen zusätzlichen
# Suchpfad schlägt die Signierung bei JEDEM echten Release-Lauf fehl -
# reproduziert beim allerersten echten Release nach der Sparkle-Umstellung
# (v1.0-16): GitHub-Release war zu dem Zeitpunkt bereits veröffentlicht,
# Appcast blieb ohne manuellen Nacheingriff dauerhaft ohne den neuen Eintrag.
SIGN_UPDATE_TOOL="$(find "$BUILD_DIR/SourcePackages" "$HOME/Library/Developer/Xcode/DerivedData" -path "*sparkle*/artifacts/sparkle/Sparkle/bin/sign_update" -print -quit 2>/dev/null)"
if [ -z "$SIGN_UPDATE_TOOL" ]; then
  echo "create_github_release.sh: sign_update-Tool nicht gefunden - Appcast wird NICHT aktualisiert. Bitte Xcode-Build einmal ausführen (löst SPM-Artefakte auf) und erneut versuchen." >&2
  exit 1
fi
ED_SIGNATURE_LINE="$("$SIGN_UPDATE_TOOL" "$ZIP_PATH")"
ED_SIGNATURE="$(echo "$ED_SIGNATURE_LINE" | grep -oE 'sparkle:edSignature="[^"]*"' | sed -E 's/sparkle:edSignature="([^"]*)"/\1/')"
if [ -z "$ED_SIGNATURE" ]; then
  echo "create_github_release.sh: Konnte edSignature nicht aus sign_update-Ausgabe extrahieren: $ED_SIGNATURE_LINE" >&2
  exit 1
fi
ZIP_LENGTH="$(stat -f%z "$ZIP_PATH")"

echo "Aktualisiere docs/appcast.xml..."
APPCAST_PATH="$REPO_ROOT/docs/appcast.xml"
NEW_ITEM="    <item>
      <title>${TAG}</title>
      <pubDate>$(date -u +"%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <description><![CDATA[${RELEASE_NOTES_CONTENT}]]></description>
      <enclosure url=\"https://github.com/martinfelder/feedivo-mac/releases/download/${TAG}/$(basename "$ZIP_PATH")\"
                 sparkle:version=\"${BUILD_NUMBER}\"
                 sparkle:shortVersionString=\"${MARKETING_VERSION}\"
                 sparkle:edSignature=\"${ED_SIGNATURE}\"
                 length=\"${ZIP_LENGTH}\"
                 type=\"application/octet-stream\"/>
    </item>"
# Fügt das neue <item> direkt nach dem stabilen Kommentar-Anker in der
# channel-Sektion ein (siehe docs/appcast.xml-Grundgerüst, Task 5) - nicht
# per XML-Parser-Roundtrip, um das Formatierungs-Risiko aus dem bekannten
# Localizable.xcstrings-Gotcha nicht zu wiederholen.
python3 - "$APPCAST_PATH" "$NEW_ITEM" <<'PYEOF'
import sys
path, new_item = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
anchor = "<!-- create_github_release.sh fügt hier bei jedem Release ein neues <item> ein -->"
# Fix Whole-Branch-Review (Important 4): str.replace() ist bei fehlendem
# Anker ein stiller No-Op - ohne diese Prüfung würde das Skript trotzdem mit
# `git add`/`git commit` weiterlaufen (der bereits veröffentlichte
# GitHub-Release ist da längst live), und `git commit` würde erst danach mit
# einer verwirrenden "nothing to commit"-Meldung scheitern, weil de facto
# nichts geändert wurde (z. B. nach einer Hand-Bearbeitung von
# docs/appcast.xml, die den Anker-Kommentar entfernt hat).
if anchor not in content:
    sys.exit("create_github_release.sh: Anker nicht in appcast.xml gefunden - Abbruch.")
content = content.replace(anchor, anchor + "\n" + new_item)
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

git -C "$REPO_ROOT" add docs/appcast.xml
git -C "$REPO_ROOT" commit -m "chore: Appcast-Eintrag für ${TAG}"

read -r -p "Appcast-Commit nach origin/main pushen? [y/N] " PUSH_CONFIRM
if [[ "$PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
  git -C "$REPO_ROOT" push
  echo "create_github_release.sh: Appcast gepusht."
else
  echo "create_github_release.sh: Appcast-Commit lokal, NICHT gepusht (manuell nachholen: git push)."
fi

TAP_REPO_DIR="$HOME/Developer/homebrew-feedivo"
if [ ! -d "$TAP_REPO_DIR" ]; then
  echo "Klone Tap-Repo nach $TAP_REPO_DIR..."
  git clone https://github.com/martinfelder/homebrew-feedivo.git "$TAP_REPO_DIR"
fi

echo "Aktualisiere Homebrew-Cask-Formel..."
cd "$TAP_REPO_DIR"
git pull --ff-only
NEW_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
python3 - "$TAP_REPO_DIR/Casks/feedivo.rb" "$MARKETING_VERSION,$BUILD_NUMBER" "$NEW_SHA256" <<'PYEOF'
import re
import sys
path, version, sha256 = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
content = re.sub(r'version "[^"]*"', f'version "{version}"', content, count=1)
content = re.sub(r'sha256 "[^"]*"', f'sha256 "{sha256}"', content, count=1)
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF
git add Casks/feedivo.rb
git commit -m "feat: Feedivo ${VERSION_LABEL}"

read -r -p "Homebrew-Cask-Update nach martinfelder/homebrew-feedivo pushen? [y/N] " TAP_PUSH_CONFIRM
if [[ "$TAP_PUSH_CONFIRM" =~ ^[Yy]$ ]]; then
  git push
  echo "create_github_release.sh: Homebrew-Cask-Formel gepusht."
else
  echo "create_github_release.sh: Cask-Commit lokal in $TAP_REPO_DIR, NICHT gepusht (manuell nachholen: cd $TAP_REPO_DIR && git push)."
fi
cd "$REPO_ROOT"
