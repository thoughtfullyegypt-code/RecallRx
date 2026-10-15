# RecallRx 🩺

**RecallRx** is an advanced, offline-first medical spaced repetition flashcard application engineered for USMLE Step 1, Step 2 CK, COMLEX, and Clinical Shelf Exams.

Built natively in Swift 5.9 with SwiftUI and SwiftData for iOS 17.0+.

---

## Key Features

- **FSRS-6 & SM-2 Schedulers:** Built-in modern FSRS-6 (21 parameters) memory model with on-device Adam weight training, statistical significance safeguards (1,000+ review threshold), and traditional SuperMemo SM-2 fallback.
- **Hands-Free Driving Mode:** 100% on-device hands-free voice review utilizing `AVSpeechSynthesizer`, `SFSpeechRecognizer` with contextual answer vocabulary injection, medical synonyms/acronyms dictionary, strict NEVER-Easy safety invariant, and a post-drive parked review audit list.
- **AI Card Generation from Notes:** On-device AI draft concept extraction from PDFs and clinical text with automatic safety markers for drug dosages and lab values (`"⚠️ Verify against your source"`).
- **Local-First CloudKit Sync:** Non-destructive deterministic conflict resolution engine (timestamp/UUID set union for review logs, Last-Write-Wins on cards).
- **QBank Fast-Unsuspend:** Native tokenizer matching UWorld and AMBOSS question IDs for rapid bulk unsuspending.
- **AnKing Hierarchical Tag Explorer:** Nested tag trie with fast card count aggregation and search filtering.
- **Interactive One-by-One Cloze & Image Occlusion:** Multi-cloze note type support and vector SVG diagram occlusion.
- **8BitDo Bluetooth Remote & Burnout Shield:** Gamepad/remote study routing with ±5% fuzzy interval smoothing and overdue backlog redistribution.
- **Automated Rolling Backups:** 7-day rolling local JSON snapshots independent of cloud sync.
- **14 Immutable Free-Forever Guarantees:** All core study, FSRS, driving mode, and backup features are permanently free.

---

## Diagnostic Test Suite

Includes a comprehensive 20/20 test suite verifying scheduling math, CloudKit sync resolution, hands-free voice driving invariants, dosage safety flags, and database restore fidelity.

Run tests directly inside the app or launch with the `--run-tests` argument.

---

## License

All rights reserved.
