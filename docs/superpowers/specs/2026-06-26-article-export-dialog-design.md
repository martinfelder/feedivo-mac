# Article Export Dialog Design

## Goal

Feature 18.1a adds a real article export dialog for Feedivo before expanding into PDF and DOCX. The first implementation slice should support Markdown, Plain Text, and HTML exports, with optional metadata and a short preview step before the native macOS save dialog opens.

## Product Decision

Use the selected Product Design direction: **Variant B with a second-step preview**.

The flow is:

1. The user chooses `Exportieren...` from the article context menu or a Reader toolbar action.
2. Feedivo opens a compact macOS-style sheet named `Export vorbereiten`.
3. The user chooses one format: Markdown, Plain Text, or HTML.
4. The user toggles whether metadata should be included.
5. `Weiter` opens a preview step named `Export prüfen`.
6. The preview step shows a short text preview for the selected format, the generated filename, and a summary of export settings.
7. `Sichern...` opens the native macOS file exporter/save dialog.

`PDF` and `DOCX` are intentionally not shown in this first slice. They remain part of later 18.1 slices because they need separate rendering, layout, and image-handling decisions.

## Visual Direction

The dialog should feel like a native macOS utility sheet:

- Quiet, compact, and practical.
- No marketing-style layout.
- No heavy card nesting.
- Use light row separators and simple grouped surfaces.
- Prefer standard controls: radio-style format rows, a toggle/checkbox for metadata, and normal macOS button hierarchy.
- Primary action text:
  - Step 1: `Weiter`
  - Step 2: `Sichern...`
  - Secondary actions: `Zurück`, `Abbrechen`

The selected layout uses two steps rather than one dense dialog. This keeps the first step readable and lets the preview be useful without crowding the initial decision.

## Step 1: Export Vorbereiten

Content:

- Title: `Export vorbereiten`
- Short explanation: choose file format and included information.
- Format rows:
  - Markdown, `.md`, good for notes and plain portable archives.
  - Plain Text, `.txt`, pure readable text.
  - HTML, `.html`, preserves article structure and links.
- Metadata toggle:
  - Label: `Metadaten einschließen`
  - Detail: title, publication date, feed, URL, and tags.
- Buttons:
  - `Abbrechen`
  - `Weiter`

## Step 2: Export Prüfen

Content:

- Title: `Export prüfen`
- Short explanation: Feedivo shows a preview before the native save dialog.
- Preview box:
  - Header shows selected format and generated filename.
  - Body shows a short text preview of the exported content.
- Summary rows:
  - Format
  - Metadata on/off
  - Content source: offline copy preferred, otherwise feed content or summary fallback.
- Buttons:
  - `Zurück`
  - `Abbrechen`
  - `Sichern...`

## Behavior

- The format choice controls document text, content type, and default filename extension.
- The metadata toggle controls whether export metadata is included.
- The preview updates when format or metadata option changes.
- `Zurück` returns to step 1 without losing selected options.
- `Sichern...` opens SwiftUI `.fileExporter`.
- Closing or canceling returns to the article view/list.

## Implementation Scope For 18.1a

In scope:

- Markdown export using the existing service, refactored behind export options.
- Plain Text export.
- HTML export.
- Metadata on/off option.
- Two-step SwiftUI dialog.
- Reader toolbar entry point in addition to the existing context menu.
- Tests for format choice, metadata inclusion, generated filenames, and text output.

Out of scope:

- PDF export.
- DOCX export.
- Batch export.
- ZIP export.
- Image embedding options.
- Share extension or incoming share workflows.

## Open Notes

- The preview should be text-only for 18.1a. It does not need to render HTML visually.
- The file exporter should still use a stable root-level presentation path, because the current code intentionally avoids opening file export directly from a short-lived context menu view.
