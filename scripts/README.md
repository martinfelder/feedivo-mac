# scripts/

Zwei getrennte Bereiche:

- **Repo-Automatisierung** (dieser Ordner direkt): `bump_version.sh` (Build-
  Nummer/Changelog, läuft automatisch nach jedem Push, siehe
  [`../.claude/settings.json`](../.claude/settings.json)) und
  `create_github_release.sh` (GitHub Release bauen/veröffentlichen, nur
  manuell). Details siehe [`../README.md`](../README.md#versionierung--releases).
- **`l10n/`**: einmalige/wiederkehrende Hilfsdateien zur Pflege des
  Lokalisierungs-Katalogs (`Feedivo/Resources/Localizable.xcstrings`) — TSV-
  Quellen plus `l10n_inject.py` zum chirurgischen Einfügen neuer Einträge
  (siehe Gotcha zu `json.dump`-Reformatierung in [`../CLAUDE.md`](../CLAUDE.md)).
  Ursprünglich als `tools/` im Repo-Root, hierher verschoben, damit alles
  Automatisierungs-Tooling an einer Stelle liegt.
