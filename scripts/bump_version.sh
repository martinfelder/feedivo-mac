#!/bin/bash
# Zaehlt die Build-Nummer (CURRENT_PROJECT_VERSION in Feedivo.xcodeproj/project.pbxproj)
# hoch, ergaenzt CHANGELOG.md um einen neuen Eintrag und pusht den Bump-Commit.
#
# Wird nach JEDEM Bash-Aufruf durch den PostToolUse-Hook in .claude/settings.json
# aufgerufen (nicht nur nach git push) - die Entscheidung, ob tatsaechlich etwas zu
# bumpen ist, trifft dieses Skript selbst anhand des echten Git-Zustands, nicht
# anhand des ausgeloesten Befehlstexts. Grund: reines Text-Matching auf "git push"
# im Bash-Befehl loest faelschlich auch dann aus, wenn dieser String nur zufaellig
# irgendwo im Befehl vorkommt (z. B. in einem Kommentar, einer Testausgabe oder wie
# hier im eigenen Test-Snippet) - siehe CHANGELOG-Eintrag zu Build 3.
#
# Bump-Bedingung: aktueller Branch ist "main" UND lokaler HEAD ist identisch mit
# dem lokal bekannten origin/main (also tatsaechlich gepusht) UND dieser HEAD wurde
# noch nicht gebumpt (Marker-Datei .git/feedivo-last-bumped-sha, maschinenlokal -
# fuer dieses Solo-Projekt auf einem einzelnen Mac ausreichend).
#
# Manuell testen ohne Aenderungen/Push mit --dry-run.
#
# Env:
#   BUMP_VERSION_DRY_RUN=1   wie --dry-run
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
  esac
done
if [ "${BUMP_VERSION_DRY_RUN:-0}" = "1" ]; then
  DRY_RUN=1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PBXPROJ="Feedivo.xcodeproj/project.pbxproj"
CHANGELOG="CHANGELOG.md"
MARKER_FILE="$(git rev-parse --git-dir)/feedivo-last-bumped-sha"

# Nur auf main bumpen - Feature-Branches/Worktrees sollen die Buildnummer nicht anfassen.
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ "$CURRENT_BRANCH" != "main" ]; then
  [ "$DRY_RUN" = "1" ] && echo "bump_version.sh: aktueller Branch ist '$CURRENT_BRANCH', nicht 'main' - kein Bump."
  exit 0
fi

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
REMOTE_SHA="$(git rev-parse origin/main 2>/dev/null || true)"
if [ -z "$HEAD_SHA" ] || [ -z "$REMOTE_SHA" ]; then
  [ "$DRY_RUN" = "1" ] && echo "bump_version.sh: HEAD oder origin/main nicht auflösbar - kein Bump."
  exit 0
fi
if [ "$HEAD_SHA" != "$REMOTE_SHA" ]; then
  # main ist lokal (noch) nicht vollstaendig gepusht - noch nichts zu bumpen.
  [ "$DRY_RUN" = "1" ] && echo "bump_version.sh: HEAD ($HEAD_SHA) != origin/main ($REMOTE_SHA) - noch nicht gepusht, kein Bump."
  exit 0
fi

LAST_BUMPED_SHA=""
if [ -f "$MARKER_FILE" ]; then
  LAST_BUMPED_SHA="$(cat "$MARKER_FILE" 2>/dev/null || true)"
fi
if [ "$HEAD_SHA" = "$LAST_BUMPED_SHA" ]; then
  [ "$DRY_RUN" = "1" ] && echo "bump_version.sh: $HEAD_SHA wurde bereits gebumpt - kein erneuter Bump."
  exit 0
fi

# Sicherheitsnetz falls die Marker-Datei fehlt/geloescht wurde: ist HEAD selbst
# schon ein Versions-Bump-Commit, nur die Marker-Datei nachziehen statt erneut
# zu bumpen.
LAST_SUBJECT="$(git log -1 --format=%s 2>/dev/null || true)"
if [[ "$LAST_SUBJECT" == chore:\ Version\ * ]]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "bump_version.sh: HEAD ist bereits ein Versions-Bump-Commit - kein erneuter Bump."
  else
    echo "$HEAD_SHA" > "$MARKER_FILE"
  fi
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
# Botschaft nicht verloren geht. Ohne beides: komplette Historie.
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

NEW_HEAD_SHA="$(git rev-parse HEAD)"
echo "$NEW_HEAD_SHA" > "$MARKER_FILE"

echo "bump_version.sh: Version ${VERSION_LABEL} committed und gepusht."
