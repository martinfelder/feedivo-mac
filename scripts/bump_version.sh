#!/bin/bash
# Zaehlt die Build-Nummer (CURRENT_PROJECT_VERSION in Feedivo.xcodeproj/project.pbxproj)
# hoch, ergaenzt CHANGELOG.md um einen neuen Eintrag und pusht den Bump-Commit.
#
# Wird automatisch nach jedem erfolgreichen `git push` nach origin/main durch den
# PostToolUse-Hook in .claude/settings.json ausgeloest. Kann auch manuell aufgerufen
# werden, z. B. zum Testen mit --dry-run (zeigt nur an, was passieren wuerde, aendert
# nichts und pusht nicht).
#
# Argumente (beide optional, vom Hook automatisch gesetzt):
#   $1  Der ausgeloeste Bash-Befehl (fuer Dry-Run-/Nicht-main-Erkennung), z. B.
#       "git push origin main". Ohne Argument wird nur der aktuelle Branch geprueft.
#
# Env:
#   BUMP_VERSION_DRY_RUN=1   wie --dry-run
set -euo pipefail

DRY_RUN=0
TRIGGER_COMMAND=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) TRIGGER_COMMAND="$arg" ;;
  esac
done
if [ "${BUMP_VERSION_DRY_RUN:-0}" = "1" ]; then
  DRY_RUN=1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PBXPROJ="Feedivo.xcodeproj/project.pbxproj"
CHANGELOG="CHANGELOG.md"

# Nur auf main bumpen - Feature-Branches/Worktrees sollen die Buildnummer nicht anfassen.
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "bump_version.sh: aktueller Branch ist '$CURRENT_BRANCH', nicht 'main' - kein Bump."
  exit 0
fi

# Dry-Run-/Nicht-Push-Aufrufe im ausgeloesten Befehl erkennen und ueberspringen.
case "$TRIGGER_COMMAND" in
  *"--dry-run"*|*" -n "*)
    echo "bump_version.sh: ausgeloest durch einen Dry-Run-Push - kein Bump."
    exit 0
    ;;
esac

# Wenn der letzte Commit selbst schon ein Versions-Bump ist, nicht erneut bumpen
# (verhindert doppeltes Hochzaehlen, falls der Hook aus irgendeinem Grund zweimal feuert).
LAST_SUBJECT="$(git log -1 --format=%s 2>/dev/null || true)"
if [[ "$LAST_SUBJECT" == chore:\ Version\ * ]]; then
  echo "bump_version.sh: letzter Commit ist bereits ein Versions-Bump - kein erneuter Bump."
  exit 0
fi

CURRENT_BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" | sed -E 's/[^0-9]*([0-9]+);.*/\1/')"
MARKETING_VERSION="$(grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" | sed -E 's/.*= ([0-9.]+);.*/\1/')"

if [ -z "$CURRENT_BUILD" ] || [ -z "$MARKETING_VERSION" ]; then
  echo "bump_version.sh: Konnte Version/Build nicht aus $PBXPROJ lesen, breche ab." >&2
  exit 1
fi

NEW_BUILD=$((CURRENT_BUILD + 1))
VERSION_LABEL="${MARKETING_VERSION} (${NEW_BUILD})"
TODAY="$(date +%Y-%m-%d)"

# Commit-Historie seit dem letzten Versions-Bump fuer den Changelog-Eintrag einsammeln.
# Gibt es bereits einen "chore: Version"-Commit, ab dort EXKLUSIV zaehlen (dessen
# eigene Bump-Botschaft ist reines Boilerplate). Gibt es noch keinen (allererster
# automatischer Bump), stattdessen ab dem PARENT des Commits zaehlen, der
# CHANGELOG.md eingefuehrt hat - INKLUSIV, damit dessen eigene, echte Commit-
# Botschaft nicht verloren geht (sonst waere der erste Eintrag leer, weil genau
# dieser Commit der aktuelle HEAD ist). Ohne beides: komplette Historie.
LAST_BUMP_SHA="$(git log --grep='^chore: Version ' -1 --format=%H 2>/dev/null || true)"
if [ -n "$LAST_BUMP_SHA" ]; then
  RANGE="${LAST_BUMP_SHA}..HEAD"
else
  CHANGELOG_ADDED_SHA="$(git log --diff-filter=A --format=%H -- "$CHANGELOG" 2>/dev/null | tail -1 || true)"
  if [ -n "$CHANGELOG_ADDED_SHA" ]; then
    PARENT_SHA="$(git rev-parse "${CHANGELOG_ADDED_SHA}^" 2>/dev/null || true)"
    if [ -n "$PARENT_SHA" ]; then
      RANGE="${PARENT_SHA}..HEAD"
    else
      RANGE="HEAD"
    fi
  else
    RANGE="HEAD"
  fi
fi
COMMIT_LINES="$(git log "$RANGE" --no-merges --format='- %s' 2>/dev/null | grep -v '^- chore: Version ' || true)"
if [ -z "$COMMIT_LINES" ]; then
  COMMIT_LINES="- (keine Commit-Nachrichten seit dem letzten Bump gefunden)"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "--- bump_version.sh: DRY RUN ---"
  echo "Branch: $CURRENT_BRANCH"
  echo "Aktuelle Build-Nummer: $CURRENT_BUILD -> neu: $NEW_BUILD"
  echo "Versions-Label: $VERSION_LABEL"
  echo "Changelog-Eintrag waere:"
  echo "## [$VERSION_LABEL] - $TODAY"
  echo ""
  echo "$COMMIT_LINES"
  echo "--- Ende Dry Run, keine Aenderungen vorgenommen ---"
  exit 0
fi

# Alle Build-Konfigurationen (Debug/Release je Target) in einem Rutsch ersetzen.
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"

# Neuen Eintrag direkt nach dem stabilen Anker "<!-- versions -->" einfuegen,
# statt die ganze Datei neu aufzubauen (Datei bleibt sonst leicht divergent/schwer diffbar).
ENTRY_FILE="$(mktemp)"
{
  printf '## [%s] - %s\n\n' "$VERSION_LABEL" "$TODAY"
  printf '%s\n' "$COMMIT_LINES"
} > "$ENTRY_FILE"

awk -v entryfile="$ENTRY_FILE" '
  { print }
  $0 == "<!-- versions -->" && !inserted {
    print ""
    while ((getline line < entryfile) > 0) print line
    inserted = 1
  }
' "$CHANGELOG" > "${CHANGELOG}.tmp"
mv "${CHANGELOG}.tmp" "$CHANGELOG"
rm -f "$ENTRY_FILE"

git add "$PBXPROJ" "$CHANGELOG"
git commit -m "chore: Version ${VERSION_LABEL}" >/dev/null
git push origin "$CURRENT_BRANCH" >/dev/null

echo "bump_version.sh: Version ${VERSION_LABEL} committed und gepusht."
