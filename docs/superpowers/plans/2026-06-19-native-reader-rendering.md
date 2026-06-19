# Native Reader Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Render feed article content as native SwiftUI reader blocks instead of raw HTML/text.

**Architecture:** `ReaderContentRenderer` converts summary/content/image data into `ReaderContentBlock` values. `ReaderView` renders those blocks using SwiftUI text and image views.

**Tech Stack:** SwiftUI, AppKit `NSAttributedString` HTML conversion, Swift Testing.

---

### Task 1: Renderer Model And Tests

**Files:**
- Create: `Feedivo/Views/Reader/ReaderContentRenderer.swift`
- Modify: `FeedivoTests/FeedivoTests.swift`

- [x] Write failing tests for HTML paragraphs, HTML images and summary fallback.
- [x] Run focused tests and verify failure because `ReaderContentRenderer` is missing.
- [x] Implement `ReaderContentBlock` and `ReaderContentRenderer`.
- [x] Run focused tests and verify they pass.

### Task 2: ReaderView Integration

**Files:**
- Modify: `Feedivo/Views/Reader/ReaderView.swift`

- [x] Replace raw summary/content text rendering with renderer blocks.
- [x] Render paragraphs with native `Text`.
- [x] Render image blocks with `AsyncImage`.

### Task 3: Documentation And Verification

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/FEATURES.md`

- [x] Document native reader rendering status.
- [x] Run build and unit tests before completion.
