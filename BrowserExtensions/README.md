# BrowserExtensions/

Chrome-Erweiterung zum Erkennen und Hinzufügen von RSS-Feeds direkt aus dem
Browser (Feature 27).

- **`Chrome/`** — Chrome-Erweiterung (Manifest V3)
- **`Shared/`** — Feed-Erkennungslogik, gemeinsam genutzt von Chrome und Safari

**Safari-Gegenstück liegt NICHT hier**, sondern unter
[`../FeedivoSafariExtension/`](../FeedivoSafariExtension/) — als eigenes
Xcode-Target (`PBXFileSystemSynchronizedRootGroup`) muss dessen Root-Ordner
auf oberster Ebene neben `Feedivo.xcodeproj` liegen, sonst müsste das
Xcode-Projekt selbst angepasst werden. Beide Erweiterungen sind inhaltlich
byte-identisch (Safari unterstützt den `chrome.*`-Namespace) — Details siehe
[`../CLAUDE.md`](../CLAUDE.md) unter Feature 27.
