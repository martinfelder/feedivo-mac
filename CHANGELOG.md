# Changelog

Alle nennenswerten Änderungen an Feedivo werden hier dokumentiert. Format lose
angelehnt an [Keep a Changelog](https://keepachangelog.com/de/1.0.0/).

Diese Datei wird automatisch nach jedem erfolgreichen `git push` nach
`origin/main` um einen neuen Eintrag ergänzt (siehe `scripts/bump_version.sh`
und den PostToolUse-Hook in `.claude/settings.json`). Die Einträge listen die
Commit-Nachrichten seit dem letzten Versions-Bump — für Details siehe `git log`.

<!-- versions -->

## [1.0 (7)] - 2026-07-28

- Docs: Projektstruktur-Diagramm in CLAUDE.md an die aufgeräumte Ablage angepasst
- Cleanup: Projekt-Ablage aufgeraeumt (Punkte 2-6 aus Struktur-Review)

## [1.0 (6)] - 2026-07-28

- Cleanup: Versehentlich committete xcresult-Testartefakte entfernt

## [1.0 (5)] - 2026-07-28

- Feat: --dry-run fuer create_github_release.sh ergaenzt

## [1.0 (4)] - 2026-07-28

- Fix: Bump-Hook auf echten Git-Zustand statt Text-Matching umgestellt

## [1.0 (3)] - 2026-07-28

- Fix: Bump-Skript ließ Commit-Nachricht des allerersten Bumps aus

## [1.0 (2)] - 2026-07-28

- Feat: README, Changelog und automatische Versionierung eingerichtet

## [1.0 (1)] - 2026-07-28

Erste getrackte Version. Ab hier zählt die Build-Nummer bei jedem Push nach
`origin/main` automatisch hoch; die Marketing-Version (`1.0`) bleibt fix, bis
sie bewusst manuell geändert wird.
