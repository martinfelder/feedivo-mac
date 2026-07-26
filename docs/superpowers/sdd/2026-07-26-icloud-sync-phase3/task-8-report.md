# Task 8 Verification Report — Changed Fields in FeedStore

## Findings from Whole-Branch Review

The reviewer identified one critical gap: the existing test `moveFeedMarkiertAlleUmsortiertenFeedsAlsPendingSync` only verified that affected feeds were marked as pending sync, but did NOT read back and assert the actual `changedFields` value stored for each feed.

## Fix Applied

Added a new comprehensive test `moveFeedMarkiertNurSortIndexAlsGeaendert` that:
1. Creates three feeds (feed-a, feed-b, feed-c)
2. Enables CloudSync
3. Moves feed-b to index 0 (triggering reorder of all three feeds)
4. Reads back the pending change for EACH affected feed via `CloudSyncPendingChangeStore.pendingChange(recordName:)`
5. Asserts that `changedFields == ["sortIndex"]` for each feed independently

Also improved the `updateRetentionSettingsMarkiertAlle5RetentionFelderAlsGeaendert` test to assert the full array of expected field names instead of just checking the count and a single field.

## Test Output

```
Test session results, code coverage, and logs:
	/Users/martinfelder/Library/Developer/Xcode/DerivedData/Feedivo-efocxwpprobcfnauckbpxubayqov/Logs/Test/Test-Feedivo-2026.07.26_15-57-04-+0200.xcresult

** TEST SUCCEEDED **

Testing started
Test suite 'FeedStoreChangedFieldsTests' started on 'My Mac - Feedivo (46466)'
Test case 'FeedStoreChangedFieldsTests/updateRetentionSettingsMarkiertAlle5RetentionFelderAlsGeaendert()' passed on 'My Mac - Feedivo (46466)' (0.219 seconds)
Test case 'FeedStoreChangedFieldsTests/renameFeedMarkiertNurTitleAlsGeaendert()' passed on 'My Mac - Feedivo (46466)' (0.219 seconds)
Test case 'FeedStoreChangedFieldsTests/moveFeedMarkiertNurSortIndexAlsGeaendert()' passed on 'My Mac - Feedivo (46466)' (0.321 seconds)
Test suite 'FeedStoreChangedFieldsTests' started on 'My Mac - Feedivo (46466)'
Test case 'FeedStoreChangedFieldsTests/updateRetentionSettingsMarkiertAlle5RetentionFelderAlsGeaendert()' passed on 'My Mac - Feedivo (46466)' (0.143 seconds)
Test case 'FeedStoreChangedFieldsTests/renameFeedMarkiertNurTitleAlsGeaendert()' passed on 'My Mac - Feedivo (46466)' (0.150 seconds)
Test case 'FeedStoreChangedFieldsTests/moveFeedMarkiertNurSortIndexAlsGeaendert()' passed on 'My Mac - Feedivo (46466)' (0.163 seconds)
```

## Build Verification

Release build:
```
xcodebuild -scheme Feedivo -configuration Release build
BUILD SUCCEEDED
```

## Critical Changes Made

### File: FeedivoTests/FeedStoreChangedFieldsTests.swift

1. **New test: `moveFeedMarkiertNurSortIndexAlsGeaendert()`**
   - Tests the multi-feed reorder scenario from `FeedStore.moveFeed()`
   - Verifies that ONLY `sortIndex` is marked as changed for all affected feeds
   - Follows exact pattern from `FeedFolderStoreChangedFieldsTests.moveFolderMarkiertNurSortIndexAlsGeaendert()`

2. **Improved test: `updateRetentionSettingsMarkiertAlle5RetentionFelderAlsGeaendert()`**
   - Now asserts the full array of 5 expected field names
   - Changed from loose `.contains()` checks to strict equality check

## Key Implementation Detail

The fix verifies that `FeedStore.moveFeed()` at line 388 correctly calls:
```swift
try enqueuePendingSync(db, feedID: feedID, changeType: .save, changedFields: ["sortIndex"])
```

For every feed affected by the reorder, including:
- The moved feed itself
- All other feeds that shift their sortIndex positions

## Status

✅ Gap closed — all tests pass
✅ Build succeeds (Debug + Release)
✅ Ready to merge
