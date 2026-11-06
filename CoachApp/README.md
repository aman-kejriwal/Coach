# Coach

A macOS revision coach for an Obsidian vault. It runs as a main window and a menu bar item.

## Build and run

```bash
scripts/build.sh            # → build/Coach.app
scripts/build.sh --test     # also runs the CoachCore unit tests
scripts/build.sh --install  # copies to /Applications and launches it
scripts/make-icon.sh        # regenerates Resources/AppIcon.icns (drawn in scripts/make-icon.swift)
```

This uses `swiftc` directly, so only the Command Line Tools are needed. `Package.swift` is there for when
you open the project in Xcode; `swift build` fails with this machine's current CLT because its SwiftPM
manifest library is broken.

## How it works

- **Your vault is the database.** Each topic is a Markdown note. Coach writes only its own `coach_*`
  properties and appends to a `## Review log` section. Your other properties and text are never touched.
- **New topics** go to `Coach/<Subject>/<Topic>.md`. **Existing notes** anywhere in the vault can be tracked
  from **Other Notes**. Topic title = file name, so renaming in Obsidian renames the topic.
- **Confidence 1–5.** Low means shaky, or too important to forget. Either way it comes back sooner.

| Confidence | First gap | Grows ×1.6 per good review, capped at |
|---|---|---|
| 1 Critical | 1 day  | 5 days   |
| 2 Weak     | 2 days | 12 days  |
| 3 Okay     | 4 days | 45 days  |
| 4 Good     | 7 days | 90 days  |
| 5 Solid    | 14 days| 180 days |

  Rating 1 or 2 resets the streak. A brand-new topic gets half the first gap (at least 1 day).

```yaml
coach_id: 6B1E…            # stable identity (survives renames/moves)
coach_subject: "DSA"
coach_confidence: 2
coach_created: 2026-11-05T14:32:00+05:30
coach_last_reviewed: 2026-11-05T14:32:00+05:30
coach_next_review: 2026-11-07
coach_review_count: 1
coach_streak: 0
coach_schema: 1
```

## Revision page

Double-click a topic, press **Revise Now**, or click a topic in the menu bar to open it in its own window:
**1 Recall** (question + scratchpad, optionally saved under `## Recall attempts`) → **2 Check** (rendered note)
→ **3 Rate** (each button shows its next review date). Time spent is logged. After rating, jump to the next
due topic in the same window. A confidence-over-time chart is built from the note's review log.

## Shortcuts

| | |
|---|---|
| ⌘N | New topic |
| Double-click / ⌘O | Open the topic's revision page (own window) |
| ⌘↩ | Revision page: show note, then "Next due topic" |
| ⌘1–⌘5 | Revision page: rate confidence |
| ⌘R | Start review session |
| Space | Show note (in review) |
| 1–5 | Rate confidence (in review) |
| → | Skip (in review) |
| ⌥⌘Z | Undo last Coach change |
| ⇧⌘R | Rescan vault |

## Layout

- `Sources/CoachCore`: pure logic (frontmatter editing, scheduler, vault scan), unit tested
- `Sources/Coach`: SwiftUI app (store, FSEvents watcher, notifications, views)
