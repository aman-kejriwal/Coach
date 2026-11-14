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

- **Your vault is the database.** Each file you revise is a Markdown note. Coach writes only its own `coach_*`
  properties and appends to a `## Review log` section. Your other properties and text are never touched.
- **Only `Coach/` is used.** Its folders are the hierarchy (Subject → Topic → Subtopic → … at any depth).
  Moving or renaming in Obsidian moves or renames it in Coach.
- **Only files are rated, and only files are suggested.** Folders show statistics rolled up from every file
  inside them: average confidence, how many files at each level, due/overdue, never revised, weakest files, and
  how many notes are tracked.

  ```
  Coach/
  └── DSA/                          avg 2.9 · 14 files · 4 due
      └── Graphs/                   avg 2.4 ·  6 files · 3 due
          ├── Shortest Paths/       avg 1.8 ·  3 files · 2 due
          │   ├── Dijkstra.md       confidence 1
          │   └── Bellman-Ford.md   confidence 2
          └── BFS.md                confidence 4
  ```
- **Add files** one at a time, or paste a list (one per line, optional `| 1`–`| 5` per line). **Revise N due**
  on a folder walks through only that folder's due files.
- **Confidence 1–5.** Low means shaky, or too important to forget. Either way it comes back sooner.

| Confidence | First gap | Grows ×1.6 per good review, capped at |
|---|---|---|
| 1 Critical | 1 day  | 5 days   |
| 2 Weak     | 2 days | 12 days  |
| 3 Okay     | 4 days | 45 days  |
| 4 Good     | 7 days | 90 days  |
| 5 Solid    | 14 days| 180 days |

  Rating 1 or 2 resets the streak. A brand-new file gets half the first gap (at least 1 day).

- **Today: a daily goal (default 5 files, Settings → Revising).** Due dates stay the backbone, and
  priority decides what you see each day:
  - **Due** files come first, ordered by priority: how far past their gap they are (3 days late on a
    2-day gap beats 3 days late on a 60-day gap), with low confidence breaking ties.
  - **Getting ahead.** When fewer files are due than the goal, the list is topped up with the files closest
    to due, so there's something to revise every day and a reminder every morning.
  - **Also due.** When more are due than the goal, the top ones make today's list and the rest wait
    below it (still available, and first in line tomorrow).
  - Files revised today count toward the goal. A goal of 0 turns this off (due files only).
  - **Early reviews count for less.** A good rating on a file revised early grows its gap by 50–100% of
    normal, depending on how far through its gap it was, and only grows the streak from 75% of the way
    through. A weak rating counts in full.

```yaml
coach_id: 6B1E…            # stable identity (survives renames/moves)
coach_confidence: 2
coach_created: 2026-11-05T14:32:00+05:30
coach_last_reviewed: 2026-11-05T14:32:00+05:30
coach_next_review: 2026-11-07
coach_review_count: 1
coach_streak: 0
coach_schema: 1
```

## Revision page

Double-click a file, press **Revise Now**, or click a file in the menu bar to open it in its own window:
**1 Recall** (question + scratchpad, optionally saved under `## Recall attempts`) → **2 Check** (rendered note)
→ **3 Rate** (each button shows its next review date). Time spent is logged. After rating, jump to the next
due file (or the next due file in that folder) in the same window. A confidence-over-time chart is built from the note's review log.

## Writing notes

**Edit Note** (⌘E) on a file's revision page or detail pane, or right-click → **Edit Note…**, opens the
file in its own editor window (also opens automatically after adding a file):

- **Recall question** field at the top (shown first when revising).
- **Live-styled Markdown**: headings, **bold**, *italic*, `code`, code blocks, quotes, callouts, checklists
  and `[[links]]` are styled as you type; the file stays plain Markdown that Obsidian reads as usual.
- **Formatting bar + shortcuts**: ⌘B bold · ⌘I italic · ⌘E code · ⇧⌘X strikethrough · ⇧⌘H highlight ·
  ⌥⌘1–3 headings (⌥⌘0 normal) · ⇧⌘8 bullets · ⇧⌘7 numbers · ⇧⌘9 checklist (again to tick) · ⇧⌘. quote ·
  ⌘K link · ⇧⌘K `[[note]]` link · ⌥⌘C code block · ⌘F find. Plus table, divider and ready-made sections
  (Key points, Steps, Example, Complexity, Mistakes I made, Self-check…).
- **Smart lists**: Return continues a list (numbers count up), Return on an empty item ends it, Tab / ⇧Tab indent.
- **Images**: paste (⌘V, e.g. a screenshot), drop image files, or use the photo button. Each image is saved
  as a file (where Obsidian's "Default location for new attachments" says, or `Coach/Attachments`) and
  embedded as `![[Pasted image 20261107093000.png]]`. It shows in the editor, preview and revision page
  (`![[x.png|300]]` sets the width). Image-only folders are hidden from the sidebar.
- **Code**: type ```` ```python ```` (or use the code button's language menu) and press Return. The block closes
  itself and the code gets syntax colours (Swift, Python, JS/TS, Java/Kotlin, C/C++, C#, Go, Rust, Ruby,
  PHP, SQL, shell, JSON, YAML, HTML, CSS). Inside code, Return keeps the indentation and indents after
  `{ ( [ :`, Tab inserts 4 spaces, ⇧Tab outdents, and spell check is off. On the revision page, code
  blocks have the same colours and a Copy button.
- **Autosave** a moment after you stop typing (⌘S saves at once), spell check, undo, optional side preview.
- Only the note text and recall question are saved: `coach_*` properties, other frontmatter, `## Review log`
  and `## Recall attempts` are kept. If the note changes in Obsidian while you have unsaved edits, autosave
  pauses and asks which version to keep. ⌥⌘Z undoes the last save.

## Reminders

Settings → **Reminders**: a morning notification ("4 files to revise today", with critical/overdue counts and
the most urgent names) and an optional **evening catch-up** that only fires if files are still due; finishing
your reviews cancels it. Click a reminder or **Start Review** to open the most urgent file's revision page
(Next walks through the rest); **Remind Me in 1 Hour** snoozes. **Send Test Notification** checks it works.
Reminders are scheduled with macOS 4 weeks ahead, so they arrive even when Coach isn't running.
Settings → General → **Open Coach at login** starts Coach quietly in the menu bar at login so the reminders
always reflect today's real list.

## Study buddy

A small cat, dog or panda walks along the bottom of the screen every couple of hours while today's
list isn't done. It sits down in the middle with a message ("Meow! 3 files to revise today.") and
**Revise Now** / **Later** buttons; click it to pet it. It only visits during the day, while you're using the
Mac, and never over full-screen apps. Settings → Study buddy picks the animal, how often it comes, or
turns it off. The paw button in the menu bar calls it right away.

## Shortcuts

| | |
|---|---|
| ⌘N | New file(s) |
| ⇧⌘N | New folder |
| Double-click / ⌘O | Open the file's revision page (own window) |
| ⌘↩ | Revision page: show note, then "Next due file" |
| ⌘1–⌘5 | Revision page: rate confidence |
| ⌘E | Edit the file's note |
| ⌘R | Start review session |
| Space | Show note (in review) |
| 1–5 | Rate confidence (in review) |
| → | Skip (in review) |
| ⌥⌘Z | Undo last Coach change |
| ⇧⌘R | Rescan vault |

## Layout

- `Sources/CoachCore`: pure logic (frontmatter editing, scheduler, vault scan), unit tested
- `Sources/Coach`: SwiftUI app (store, FSEvents watcher, notifications, views)
