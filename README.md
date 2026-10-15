# RecallRx 🩺

**RecallRx** is an advanced, offline-first medical spaced repetition flashcard application engineered for USMLE Step 1, Step 2 CK, COMLEX, and Clinical Shelf Exams.

Built natively in Swift 5.9 with SwiftUI and SwiftData for iOS 17.0+.

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

## Tests

`RecallRxTests` is an XCTest target. It builds an in-memory SwiftData store (`isStoredInMemoryOnly: true`, `cloudKitDatabase: .none`) and runs the feature suite there. In Xcode, press Command-U. The tests are not part of the app, and they do not write into the library you study with.

SwiftData is created with `cloudKitDatabase: .none`. Sync goes through `CloudSyncManager` and the private CloudKit database. Automatic Core Data mirroring crashes on launch because `Deck.cards` and `Card.reviewLogs` are non-optional.

---

## License

All rights reserved.
