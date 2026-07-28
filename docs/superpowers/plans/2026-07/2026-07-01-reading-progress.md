# Reader Reading Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a quiet Reader progress line and optional automatic resume to the last stored article reading position.

**Architecture:** Store a normalized `readingProgress` scalar on `Article`, keep calculation/persistence thresholds in a small focused helper, and let `ReaderView` track/restore scroll position for native Reader and Readability mode only. Keep `WKWebView` unchanged for v1.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, `@AppStorage`, existing `ReaderView`, `ReaderTypographySettings`, `NewAppearanceSettingsView`.

---

## File Structure

- Modify `Feedivo/Models/Article.swift`: add `readingProgress` with default `0`, include it in `lightFetchDescriptor`.
- Create `Feedivo/Views/Reader/ReaderReadingProgress.swift`: clamp, persistence threshold, scroll target helper.
- Modify `Feedivo/Views/Reader/ReaderTypographySettings.swift`: add setting key/default for automatic resume.
- Modify `Feedivo/Views/Settings/SettingsView.swift`: add the toggle in `Einstellungen -> Darstellung` under the reading block.
- Modify `Feedivo/Views/Reader/ReaderView.swift`: add progress line, scroll tracking, throttled persistence, one-shot resume.
- Add `FeedivoTests/ReaderReadingProgressTests.swift`: unit tests for clamp, threshold, resume default, model default.
- Modify `AGENTS.md` and `FEATURES.md`: mark Feature 11.2 implemented and document behavior.

## Task 1: Model And Progress Helper

**Files:**
- Modify: `Feedivo/Models/Article.swift`
- Create: `Feedivo/Views/Reader/ReaderReadingProgress.swift`
- Test: `FeedivoTests/ReaderReadingProgressTests.swift`

- [ ] **Step 1: Write failing tests**

Create `FeedivoTests/ReaderReadingProgressTests.swift`:

```swift
import Testing
@testable import Feedivo

struct ReaderReadingProgressTests {
    @Test func articleReadingProgressHatSicherenDefault() {
        let article = Article(title: "Test")

        #expect(article.readingProgress == 0)
    }

    @Test func readingProgressKlemmtWerteAufGueltigenBereich() {
        #expect(ReaderReadingProgress.clamped(-0.2) == 0)
        #expect(ReaderReadingProgress.clamped(0.42) == 0.42)
        #expect(ReaderReadingProgress.clamped(1.7) == 1)
    }

    @Test func readingProgressSpeichertNurSinnvolleAenderungen() {
        #expect(!ReaderReadingProgress.shouldPersist(current: 0.2, stored: 0.205))
        #expect(ReaderReadingProgress.shouldPersist(current: 0.2, stored: 0.215))
        #expect(ReaderReadingProgress.shouldPersist(current: 1, stored: 0.98))
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/ReaderReadingProgressTests
```

Expected: build fails because `Article.readingProgress` or `ReaderReadingProgress` does not exist.

- [ ] **Step 3: Add model field**

In `Feedivo/Models/Article.swift`, add the scalar field near the other article state fields:

```swift
var readingProgress: Double = 0
```

Add it to `lightFetchDescriptor.propertiesToFetch`:

```swift
\.offlineRequestedAt, \.offlineSavedAt, \.offlineErrorMessage,
\.readingProgress
```

No initializer parameter is needed; new articles should start at `0`.

- [ ] **Step 4: Add focused progress helper**

Create `Feedivo/Views/Reader/ReaderReadingProgress.swift`:

```swift
import Foundation

enum ReaderReadingProgress {
    static let minimumPersistedDelta = 0.01

    static func clamped(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    static func shouldPersist(current: Double, stored: Double) -> Bool {
        abs(clamped(current) - clamped(stored)) >= minimumPersistedDelta
    }
}
```

- [ ] **Step 5: Run tests and verify pass**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/ReaderReadingProgressTests
```

Expected: tests pass.

## Task 2: Resume Setting

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderTypographySettings.swift`
- Modify: `Feedivo/Views/Settings/SettingsView.swift`
- Test: `FeedivoTests/ReaderReadingProgressTests.swift`

- [ ] **Step 1: Add failing default test**

Append to `ReaderReadingProgressTests`:

```swift
@Test func resumeSettingIstStandardmaessigAktiv() {
    #expect(ReaderTypographySettings.defaultResumesReadingPosition)
    #expect(ReaderTypographySettings.resumesReadingPositionKey == "reader.resumesReadingPosition")
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/ReaderReadingProgressTests/resumeSettingIstStandardmaessigAktiv
```

Expected: build fails because the setting constants do not exist.

- [ ] **Step 3: Add setting constants**

In `Feedivo/Views/Reader/ReaderTypographySettings.swift`, add:

```swift
static let resumesReadingPositionKey = "reader.resumesReadingPosition"
static let defaultResumesReadingPosition = true
```

- [ ] **Step 4: Add UI toggle**

In `NewAppearanceSettingsView`, add AppStorage:

```swift
@AppStorage(ReaderTypographySettings.resumesReadingPositionKey)
private var readerResumesReadingPosition = ReaderTypographySettings.defaultResumesReadingPosition
```

Inside `NewSettingsBlock(eyebrow: L10n.settingsReadingSection, showsBottomDivider: false)`, after content width:

```swift
NewSettingRow(
    title: "Artikel an letzter Leseposition fortsetzen",
    description: "Öffnet Artikel automatisch ungefähr an der zuletzt gelesenen Stelle."
) {
    Toggle("", isOn: $readerResumesReadingPosition)
        .labelsHidden()
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/ReaderReadingProgressTests
```

Expected: tests pass.

## Task 3: Reader Progress Line And Scroll Persistence

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderView.swift`

- [ ] **Step 1: Add Reader state and setting**

In `ReaderView`, add AppStorage and state:

```swift
@AppStorage(ReaderTypographySettings.resumesReadingPositionKey)
private var readerResumesReadingPosition = ReaderTypographySettings.defaultResumesReadingPosition

@State private var visibleReaderProgress = 0.0
@State private var hasRestoredReadingPosition = false
@State private var pendingReadingProgressToRestore: Double?
@State private var readerViewportHeight: CGFloat = 0
@State private var readerContentHeight: CGFloat = 0
```

- [ ] **Step 2: Add scroll coordinate names**

Add private coordinate constants near other Reader constants:

```swift
private let nativeReaderScrollCoordinateSpace = "nativeReaderScroll"
private let readabilityReaderScrollCoordinateSpace = "readabilityReaderScroll"
```

- [ ] **Step 3: Wrap native Reader in ScrollViewReader**

Replace the body of `nativeReader` with this shape:

```swift
private var nativeReader: some View {
    readerScrollContainer(coordinateSpaceName: nativeReaderScrollCoordinateSpace) {
        VStack(alignment: .leading, spacing: contentBlockSpacing) {
            readerHeader

            if shouldShowOfflineStatusNotice {
                offlineStatusNotice
            }

            if contentBlocks.isEmpty, isBuildingPreparedArticle {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }

            ForEach(Array(contentBlocks.enumerated()), id: \.element.id) { index, block in
                VStack(alignment: .leading, spacing: imageTextDividerSpacing) {
                    readerContentBlock(block)

                    if shouldShowImageTextDivider(after: index, in: contentBlocks) {
                        readerSectionDivider
                    }
                }
            }

            readerFooter
        }
    }
}
```

- [ ] **Step 4: Use same container in Readability mode**

Inside `readabilityReader(originalURL:)`, replace the inner `ScrollView` with:

```swift
readerScrollContainer(coordinateSpaceName: readabilityReaderScrollCoordinateSpace) {
    VStack(alignment: .leading, spacing: contentBlockSpacing) {
        readerHeader
        readabilityStatusNotice

        let blocks = readabilityContentBlocks
        ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
            VStack(alignment: .leading, spacing: imageTextDividerSpacing) {
                readerContentBlock(block)

                if shouldShowImageTextDivider(after: index, in: blocks) {
                    readerSectionDivider
                }
            }
        }

        readerFooter
    }
}
```

- [ ] **Step 5: Add reusable scroll container**

Add below `readabilityReader(originalURL:)`:

```swift
private func readerScrollContainer<Content: View>(
    coordinateSpaceName: String,
    @ViewBuilder content: @escaping () -> Content
) -> some View {
    GeometryReader { viewportGeometry in
        ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: 1)
                                .id("reader-progress-top")

                            content()
                                .frame(maxWidth: clampedContentWidth, alignment: .leading)
                                .padding(.horizontal, 28)
                                .padding(.top, articleTopPadding)
                                .padding(.bottom, articleBottomPadding)
                                .background(readerProgressGeometry(coordinateSpaceName: coordinateSpaceName))
                        }

                        restoreTargetMarker
                    }
                }
                .coordinateSpace(name: coordinateSpaceName)
                .onAppear {
                    readerViewportHeight = viewportGeometry.size.height
                    visibleReaderProgress = ReaderReadingProgress.clamped(article.readingProgress)
                    scheduleReadingPositionRestoreIfNeeded()
                    restoreReadingPositionIfNeeded(using: proxy)
                }
                .onChange(of: viewportGeometry.size.height) {
                    readerViewportHeight = viewportGeometry.size.height
                    scheduleReadingPositionRestoreIfNeeded()
                }
                .onChange(of: article.id) {
                    hasRestoredReadingPosition = false
                    visibleReaderProgress = ReaderReadingProgress.clamped(article.readingProgress)
                    scheduleReadingPositionRestoreIfNeeded()
                    restoreReadingPositionIfNeeded(using: proxy)
                }
                .onChange(of: pendingReadingProgressToRestore) {
                    restoreReadingPositionIfNeeded(using: proxy)
                }
            }

            readerProgressLine
        }
    }
}
```

- [ ] **Step 6: Add progress geometry and line helpers**

Add:

```swift
private func readerProgressGeometry(coordinateSpaceName: String) -> some View {
    GeometryReader { geometry in
        Color.clear
            .onAppear {
                updateReadingProgress(from: geometry, coordinateSpaceName: coordinateSpaceName)
            }
            .onChange(of: geometry.frame(in: .named(coordinateSpaceName)).minY) {
                updateReadingProgress(from: geometry, coordinateSpaceName: coordinateSpaceName)
            }
            .onChange(of: geometry.size.height) {
                readerContentHeight = geometry.size.height
                scheduleReadingPositionRestoreIfNeeded()
            }
    }
}

private var restoreTargetMarker: some View {
    Color.clear
        .frame(width: 1, height: 1)
        .offset(y: restoreTargetOffset)
        .id("reader-progress-restore-target")
}

private var restoreTargetOffset: CGFloat {
    let progress = CGFloat(ReaderReadingProgress.clamped(pendingReadingProgressToRestore ?? article.readingProgress))
    let scrollableHeight = max(readerContentHeight - readerViewportHeight, 0)
    return max(scrollableHeight * progress, 0)
}

private var readerProgressLine: some View {
    GeometryReader { geometry in
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: geometry.size.width * visibleReaderProgress, height: 2)
            .opacity(visibleReaderProgress > 0 ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: visibleReaderProgress)
    }
    .frame(height: 2)
}
```

- [ ] **Step 7: Add update and restore methods**

Add:

```swift
private func updateReadingProgress(from geometry: GeometryProxy, coordinateSpaceName: String) {
    let frame = geometry.frame(in: .named(coordinateSpaceName))
    let visibleTop = max(-frame.minY, 0)
    readerContentHeight = geometry.size.height

    let scrollableHeight = max(geometry.size.height - readerViewportHeight, 1)
    let progress = ReaderReadingProgress.clamped(visibleTop / scrollableHeight)

    visibleReaderProgress = progress

    if ReaderReadingProgress.shouldPersist(current: progress, stored: article.readingProgress) {
        article.readingProgress = progress
        try? modelContext.save()
    }
}

private func scheduleReadingPositionRestoreIfNeeded() {
    guard readerResumesReadingPosition, !hasRestoredReadingPosition else {
        return
    }

    let progress = ReaderReadingProgress.clamped(article.readingProgress)
    guard progress > 0 else {
        return
    }

    pendingReadingProgressToRestore = progress
}

private func restoreReadingPositionIfNeeded(using proxy: ScrollViewProxy) {
    guard readerResumesReadingPosition, !hasRestoredReadingPosition else {
        return
    }

    guard let progress = pendingReadingProgressToRestore ?? Optional(article.readingProgress),
          ReaderReadingProgress.clamped(progress) > 0 else {
        return
    }

    DispatchQueue.main.async {
        proxy.scrollTo("reader-progress-restore-target", anchor: .top)
        hasRestoredReadingPosition = true
        pendingReadingProgressToRestore = nil
    }
}
```

- [ ] **Step 8: Flush on disappear**

Add to the main `body` modifier chain:

```swift
.onDisappear {
    if ReaderReadingProgress.shouldPersist(current: visibleReaderProgress, stored: article.readingProgress) {
        article.readingProgress = visibleReaderProgress
        try? modelContext.save()
    }
}
```

- [ ] **Step 9: Build**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/ReaderReadingProgressTests
```

Expected: build succeeds and tests pass. If SwiftUI geometry code needs small API adjustment, keep behavior identical and rerun.

## Task 4: Documentation And Roadmap

**Files:**
- Modify: `FEATURES.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Update FEATURES**

In `FEATURES.md`, change Feature 11.2 from `✅ Entschieden` to `✔️ Fertig` and document:

```markdown
- Dünne Fortschrittslinie unter der Reader-Toolbar im nativen Reader und Vollartikel-Modus.
- Pro Artikel gespeicherter Fortschritt als normalisierter Wert.
- Einstellung `Artikel an letzter Leseposition fortsetzen`, Standard an.
- Originalansicht bleibt für v1 unverändert.
```

- [ ] **Step 2: Update AGENTS**

In `AGENTS.md`, add a short note under `ReaderView.swift` and `Article.swift`:

```markdown
- Reader zeigt eine 2px-Fortschrittslinie und speichert `Article.readingProgress`.
- Automatisches Fortsetzen ist per `reader.resumesReadingPosition` steuerbar und standardmäßig aktiv.
```

- [ ] **Step 3: Final verification**

Run:

```bash
xcodebuild test -project Feedivo.xcodeproj -scheme Feedivo -configuration Debug -only-testing:FeedivoTests/ReaderReadingProgressTests
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Manual verification**

Launch Feedivo from Xcode or the built Debug app and verify:

- Native Reader shows the progress line while scrolling.
- Closing/reopening an article resumes near the saved position when the toggle is on.
- Disabling the toggle starts at the top while the progress line still updates.
- Vollartikel-Modus shows and updates the line.
- Originalansicht remains unchanged.

## Self-Review

- Spec coverage: The plan covers the progress line, per-article storage, default-on automatic resume, user setting, native Reader and Vollartikel mode, and excludes `WKWebView`.
- Placeholder scan: No placeholder steps remain.
- Type consistency: The plan consistently uses `Article.readingProgress`, `ReaderReadingProgress`, and `ReaderTypographySettings.resumesReadingPositionKey`.
