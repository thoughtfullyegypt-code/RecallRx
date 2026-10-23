# RecallRx 🩺

**RecallRx** is an advanced, offline-first medical spaced repetition flashcard application engineered for USMLE Step 1, Step 2 CK, COMLEX, and Clinical Shelf Exams.

Built natively with SwiftUI and SwiftData for iOS 17.0+, using Swift 5 language mode and Xcode 15 or later.

---

## Key Features

- **FSRS-6 & SM-2 Schedulers:** FSRS-6 uses the current 21-parameter defaults, trainable decay, same-day stability, and Anki-style learning steps. SM-2 remains in Settings. Undo restores stability, difficulty, and interval. Weight training refuses to save synthetic reviews as your memory.
- **Hands-Free Driving Mode:** On-device `AVSpeechSynthesizer` and `SFSpeechRecognizer`. Microphone and speech permission are requested before listening. Easy is never assigned. Ambiguous abbreviations such as MS and AS are not expanded both ways.
- **Card Drafts from Notes:** On-device pattern extraction from PDFs and clinical text, not a cloud model. Drug dosages and lab values are marked `"⚠️ Verify against your source"`.
- **iCloud Sync:** Sync Now uses the private CloudKit database `iCloud.com.recallrx.app`. Cards merge by last write. Review logs are unioned by id. The app does not report success unless CloudKit accepts the change. Enable that iCloud container on the App ID before shipping.
- **QBank Fast-Unsuspend:** Native tokenizer matching UWorld and AMBOSS question IDs for rapid bulk unsuspending.
- **Hierarchical tag explorer:** Nested tag trie with fast card count aggregation and search filtering.
- **Interactive One-by-One Cloze & Image Occlusion:** Multi-cloze note type support and vector SVG diagram occlusion.
- **8BitDo Bluetooth Remote & Burnout Shield:** Gamepad/remote study routing with ±5% fuzzy interval smoothing and overdue backlog redistribution.
- **Home Screen Widget:** A WidgetKit extension reads the due count from the `group.com.recallrx.app` app group. Add that App Group to both the app and the widget in the developer portal.
- **14 Immutable Free-Forever Guarantees:** All core study, FSRS, driving mode, and backup features are permanently free.

---

## Reliability and backups

- Learning steps wait for their due time. Daily new/review budgets persist across sessions and reset at the local calendar-day boundary. Undo restores the session queue and counters.
- Sample decks are loaded only when requested. Ordinary launch never seeds, renames, or deletes library content.
- Version 2 backup files include deck hierarchy, stable IDs, complete scheduling/review state, tags, and embedded local media. Legacy JSON remains importable. Restore validates the archive before replacing data, requires a safety snapshot, and rolls back failed replacements.
- Foreground activity and successful saves refresh widgets/reminders and trigger a backup when the latest snapshot is at least 12 hours old. Notification text uses real study data.
- iCloud pulls apply decks/cards before reviews and checkpoint after a successful save. A durable deletion outbox and cloud tombstones propagate deletions; explicit snapshot restores can revive backed-up IDs. New cloud record types must be deployed to the production CloudKit schema before release.

## Tests

`RecallRxTests` is an XCTest target. It builds an in-memory SwiftData store (`isStoredInMemoryOnly: true`, `cloudKitDatabase: .none`) and runs the feature suite there. In Xcode, press Command-U. The shared test scheme sets `RECALLRX_TESTING=1`; the hosted app uses an in-memory container and bypasses normal startup work. Tests inject isolated preferences, temporary media/backups, and services with system side effects disabled.

The macOS GitHub Actions workflow regenerates the project with pinned XcodeGen, builds the app/widget/tests, and runs the simulator suite. Dedicated regressions cover scheduling/undo, corrupted backup recovery and media, real SQLite Anki packages, cloze audio/QBank matching, sync ordering/deletions/save failures, and lifecycle maintenance. A successful simulator run does not establish live CloudKit provisioning, two-device behavior, microphone recognition, or physical controller compatibility; verify those on signed-in devices before release.

To reproduce CI locally:

```sh
xcodegen generate --spec project.yml
xcodebuild test -project RecallRx.xcodeproj -scheme RecallRx \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

Choose an installed simulator name for your Xcode. Privacy manifests are bundled separately with the app and widget. Keep the iCloud container and App Group entitlements configured in the developer portal.

SwiftData is created with `cloudKitDatabase: .none`. Sync goes through `CloudSyncManager` and the private CloudKit database. Automatic Core Data mirroring crashes on launch because `Deck.cards` and `Card.reviewLogs` are non-optional.

---

## License

All rights reserved.
