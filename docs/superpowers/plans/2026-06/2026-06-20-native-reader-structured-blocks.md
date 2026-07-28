# Native Reader Structured Blocks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve simple article structure in the native Reader by rendering headings, quotes, and list items as distinct SwiftUI blocks.

**Architecture:** Extend `ReaderContentBlock` with `heading`, `quote`, and `listItem`. Keep `ReaderContentRenderer` as the single conversion point from feed HTML/text to block arrays, and keep `ReaderView` as the single rendering point for those blocks.

**Tech Stack:** Swift, SwiftUI, Foundation regular expressions, existing Swift Testing tests.

---

### Task 1: Renderer Block Tests

**Files:**
- Modify: `FeedivoTests/FeedivoTests.swift`
- Modify: `Feedivo/Views/Reader/ReaderContentRenderer.swift`

- [x] **Step 1: Add failing tests**

Add tests that expect `ReaderContentRenderer` to return `.heading`, `.quote`, and
`.listItem` blocks while preserving text block order.

- [x] **Step 2: Run focused tests**

Run:

```bash
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests/FeedivoTests
```

Expected before implementation: compile fails because the new enum cases do not exist.

- [x] **Step 3: Extend renderer implementation**

Add enum cases and parse known HTML block tags conservatively. Keep image extraction and
fallback behavior.

- [x] **Step 4: Run focused tests again**

Run the same focused test command and expect success.

### Task 2: Reader Rendering

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderView.swift`

- [x] **Step 1: Render the new block types**

Handle `.heading`, `.quote`, and `.listItem` in the existing `switch block`.

- [x] **Step 2: Build**

Run:

```bash
xcodebuild build -scheme Feedivo -destination 'platform=macOS'
```

Expected: build succeeds.

### Task 3: Documentation and Final Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`
- Modify: `docs/superpowers/plans/2026-06-20-native-reader-structured-blocks.md`

- [x] **Step 1: Update feature docs and project memory**

Document that native reader structured blocks are implemented as a basis.

- [x] **Step 2: Verify**

Run:

```bash
git diff --check
xcodebuild test -scheme Feedivo -destination 'platform=macOS' -only-testing:FeedivoTests
xcodebuild build -scheme Feedivo -destination 'platform=macOS'
```

Expected: no whitespace errors, tests pass, build succeeds.

- [x] **Step 3: Commit and push**

Stage all feature files except Xcode user state, commit, and push `main`.
