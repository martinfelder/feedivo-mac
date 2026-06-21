# M3 Tag Management Design

Datum: 2026-06-21
Status: Approved for planning

## Ziel

M3 startet mit der zentralen Tag-Verwaltung. Feedivo kann Tags bereits im
Reader-Inspector an Artikel haengen; dieser Block macht Tags als eigenes
Organisationsobjekt pflegbar, bevor Sidebar-Tag-Filter und automatische Regeln darauf
aufbauen.

Die vereinbarte M3-Reihenfolge ist:

1. Tag-Verwaltung
2. Sidebar-Tag-Filter
3. Regeln

## Umfang

Dieser Block umfasst:

- Tags erstellen
- Tags umbenennen
- Tag-Farbe aendern
- Tags loeschen
- leere Tag-Namen verhindern
- doppelte Tag-Namen case-insensitive verhindern
- Reader-Inspector-Tag-Pills mit gespeicherter Tag-Farbe anzeigen

Nicht Teil dieses Blocks:

- Sidebar-Tag-Filter
- automatische Regeln
- Feed-Tags aktiv nutzen
- Bulk-Aktionen oder komplexes Tag-Merging

## Datenmodell

Das bestehende `Tag` Modell bleibt unveraendert:

- `name`
- `colorHex`
- Beziehung zu `Article`
- Beziehung zu `Feed`

Die Validierung liegt im neuen Tag-ViewModel, nicht im SwiftData-Modell selbst. Das
haelt das Modell schlicht und passt zum bisherigen Projektstil.

## Architektur

### TagViewModel

Ein neues `TagViewModel` kapselt die Bearbeitungslogik:

- `createTag(name:colorHex:availableTags:context:)`
- `renameTag(_:name:availableTags:context:)`
- `updateColor(_:colorHex:context:)`
- `deleteTag(_:context:)`
- `normalizedTagName(_:)`

Die Methoden laufen auf dem `@MainActor`, weil SwiftData-Objekte im UI-Kontext
bearbeitet werden. Fehler werden als `errorMessage` oder klarer Rueckgabewert
sichtbar gemacht, passend zu bestehenden ViewModels.

### TagManagerView

Eine neue `TagManagerView` zeigt alle Tags als native macOS-Verwaltung:

- Liste aller Tags, sortiert nach Name
- Farbindikator pro Tag
- Name des Tags
- optional Anzahl verknuepfter Artikel und Feeds
- Bearbeiten ueber ein kleines Sheet oder Detailbereich
- Loeschen mit Bestaetigung

Der erste Zugang kann pragmatisch als Sheet erfolgen. Ein spaeterer Menuepunkt oder
eine staerkere Sidebar-Integration bleibt moeglich, ohne die Kernlogik zu aendern.

### Reader-Inspector

Der Reader-Inspector bleibt die schnelle Stelle, um einem Artikel Tags zuzuweisen.
Er verwendet weiterhin vorhandene Tags wieder und erstellt nur bei Bedarf neue Tags.
Die sichtbaren Tag-Pills nutzen kuenftig `Tag.colorHex`, statt immer gruen zu sein.

## UI-Richtung

Die Tag-Verwaltung soll ruhig und mac-like bleiben:

- keine grosse Landing-Ansicht
- kompakte Liste mit klaren Aktionen
- Farbauswahl ueber vordefinierte Swatches plus gespeicherten Hex-Wert
- destructive Delete mit Bestaetigung

Die Farbauswahl startet mit einer kleinen festen Palette. Freie Farbeingabe oder ein
voller Color-Picker kann spaeter folgen, falls notwendig.

## Fehlerfaelle

- Leerer oder nur aus Leerzeichen bestehender Name wird nicht gespeichert.
- Doppelter Name wird case-insensitive erkannt.
- Beim Umbenennen auf denselben Namen passiert nichts.
- Beim Loeschen werden Beziehungen ueber SwiftData entfernt; Artikel und Feeds selbst
  bleiben erhalten.
- Ungueltige oder unbekannte Farben fallen in der UI auf einen neutralen Default
  zurueck.

## Tests

Neue oder angepasste Tests sollten abdecken:

- Normalisierung von Tag-Namen
- leere Namen werden abgelehnt
- doppelte Namen werden case-insensitive abgelehnt
- Erstellen eines Tags speichert Name und Farbe
- Umbenennen aendert nur den Namen
- Farbwechsel aendert nur `colorHex`
- Loeschen entfernt das Tag, aber keine Artikel

UI-Tests sind fuer diesen Block optional. Ein Build plus Unit-Tests reichen als
Abschlussverifikation.

## Dokumentation

Nach Umsetzung muessen aktualisiert werden:

- `AGENTS.md`: Implementierter Code, M3-Status, letzte Aenderungen
- `docs/FEATURES.md`: Tag-Verwaltung von offen auf fertig als Basis

## Naechster Schritt

Nach Freigabe dieser Spec wird ein Implementierungsplan erstellt. Die Umsetzung soll
mit dem `TagViewModel` und den Tests beginnen, danach folgt die `TagManagerView` und
zum Schluss die kleine Reader-Inspector-Farbanpassung.
