# teacher_ai

A Flutter web app for teachers. It starts as a **seating chart builder**; lesson
plan generation comes later. Math is the focus subject for now.

## Running it

```sh
flutter pub get
flutter run -d chrome
flutter test
```

## GitHub Pages

The workflow in `.github/workflows/pages.yml` tests and builds the Flutter web
app, then publishes `build/web` to GitHub Pages on every push to `main`.
It sets the base path from the repository name, so project sites such as
`https://jamiewest.github.io/teacher_ai/` load their assets correctly.

GitHub Pages hosts the app files. Each visitor's edits stay in that browser's
local storage; the site does not sync them between devices. The seeded class is
sample data.

For the native macOS app, use `flutter run -d macos`. Its `Info.plist`
temporarily disables Impeller and uses Skia to work around the texture-size
crash observed with Flutter 3.47.4 (see
[Flutter's engine fix](https://github.com/flutter/flutter/pull/192522)). Remove
`FLTEnableImpeller` after upgrading to an engine containing that fix and
verifying window resizing and fullscreen transitions. Changes to this native
setting require stopping and rebuilding the app; hot reload is insufficient.

First run seeds a sample Algebra I class — 24 students across three grade
levels, six Kagan pods, and a set of starter tags — so there is something real
on screen immediately.

## Seating workflow

- **Seat students** opens a focused roster and chart. Pick a student and tap a
  seat, or tap a seat to search the roster. Moving an already seated student to
  an occupied seat swaps the two students.
- **Seat remaining** fills open seats without changing existing placements.
  Shuffle rearranges the class while keeping pinned students in place. Both
  actions can be undone.
- **Design room** exposes furniture, grid, arrangement, and room properties.
  Seating mode protects furniture positions from accidental edits.
- Click a **group name or outline** in Design room to edit the whole group.
  Drag its outline to move it, or drag its rotation handle to turn it together.
  Group properties include color, position locking, desk size and shape,
  arrangement, duplication, deletion, and ungrouping. Clicking a desk still
  selects that desk individually; group edits support undo and autosave.
- Open the layout name to browse room previews and create a new layout from a
  preset. Each layout keeps its draft and undo history while the app is open.
- **Save chart** records a seating arrangement and its pins in history. Room
  edits save automatically; seating drafts still need Save chart before reload.
- Small windows use the **Students** and **Properties** buttons to open panels.
  Zoomed-out seats show initials; zoom in to read names.
- **Expand view** gives the canvas more space and fits the room automatically.
  Editing, student placement, zoom, and saving remain available. **Restore view**
  brings back the panels and your previous zoom and position.

## Architecture

The app boots on the [`extensions`](https://pub.dev/packages/extensions) host,
so Flutter, DI, logging, and lifecycle share one pipeline:

```dart
Host.createApplicationBuilder()
  ..logging.addSimpleConsole()
  ..services.addTeacherServices()
  ..services.addFlutter((f) => f.runApp((sp) => TeacherApp(services: sp)));
```

| Layer | Location | Notes |
|---|---|---|
| Domain models | `lib/domain/models` | Immutable, hand-written JSON, no Flutter widgets |
| Pure operations | `lib/domain/ops` | Align, distribute, pod, shuffle — all testable without a widget tree |
| Persistence | `lib/data` | One JSON document behind a `KeyValueStore` (localStorage on web) |
| State | `TeacherWorkspace`, `SeatingEditorController` | `ChangeNotifier`s registered as DI singletons |
| UI | `lib/features`, `lib/app` | `ListenableBuilder` over the controllers |

### Two decisions worth knowing

**Desks are stored in room centimeters, never screen pixels.** A desk's `x`/`y`
is its center in a coordinate space measured from the room's top-left corner,
and `RoomViewController` applies scale and pan at paint time. A saved layout
therefore survives a window resize, a different screen density, or being opened
on a tablet. Hit-testing inverts the same transform, so what is drawn and what
is stored cannot drift apart.

**Room edits autosave; seating arrangements are saved explicitly.** Moving a
desk is not something a teacher should have to remember to save, so layout
changes are pushed to the workspace (which persists on a debounce) as soon as a
gesture finishes. Seating is different: a saved arrangement is a named,
append-only snapshot in the history, so that stays an explicit action.

The tradeoff: autosave removes the "discard my experiment" path. Undo (capped at
100 steps) is the only way back, and reloading makes a
change permanent. Switching layouts retains each layout’s undo history for the
current session. Losing a teacher's room is the worse failure, so this is the
deliberate choice — but if freehand experimenting becomes a real workflow, the
answer is a scratch layout, not turning autosave off.

**The editor is a stack of immutable snapshots.** Every mutation produces a new
`EditorSnapshot` holding the layout, the seating map, and the pinned seats
together. Undo is a stack of these rather than a pile of inverse operations,
which is what makes "shuffle the class, then fix three seats by hand" usable.
Continuous gestures wrap in `beginInteraction()` / `endInteraction()` so a drag
lands as one undo step, and drags resolve against the gesture's starting
positions so grid snapping cannot accumulate drift.

## What is built

- **Room grid** with snap-to-grid, adjustable room size and grid spacing.
- **Desks and fixtures** — student desks, group tables, plus the teacher desk,
  board, door, and storage so the room reads as a real room. Only seats can
  hold a student.
- **Rotation** by free 360°, or snapped to 15° / 45° / 90° steps. A handle on
  the canvas follows the desk's facing; a chevron shows which way it points.
- **Multi-select** by marquee, shift-click, or whole group.
- **Arrange helpers** — align to six edges, space evenly (equal gaps, so desks
  of different sizes still look right), space by an exact gap, pull together
  into a block, and arrange as a Kagan pod facing inward.
- **Groups** — name a selection "Group 1", recolor it, rename it, rotate it as
  a unit. Groups can be marked Kagan teams.
- **Multiple saved layouts** per class, with presets (rows, pods, horseshoe),
  duplicate, rename, and "save as new layout".
- **Seating** — assign, swap, pin a seat through shuffles, seeded shuffle,
  rotate whole teams between pods.
- **Assignment history** — append-only snapshots, each recording its source and
  RNG seed so an arrangement can be reproduced and restored.
- **Custom tags** — teacher-defined, with a category and a structured
  `SeatingHint`. The shuffle already honors front-of-room hints.
- **Responsive layout** — wide windows dock the panel for the active task
  (students or room properties), while narrower windows use sheets. Resizing
  between navigation layouts preserves seating drafts and undo history.

## Known limits

- **Storage ceiling.** The whole workspace is one JSON blob in localStorage
  (~5MB on web), and assignment history is append-only with no cap. Fine for
  now; across several classes over a school year this is the first thing that
  will need a real backing store or a history cap.
- **No UI to create classes or subjects yet.** The model supports a teacher
  teaching many subjects with many sections, and the seed includes a second
  subject, but only the seeded class is reachable. Deliberately deferred —
  the seating chart came first.
- **The browser-reload round trip is not covered by an automated test.**
  `SharedPreferencesStore` is tested against the mocked preferences backend, so
  its own logic is verified, but nothing exercises real `localStorage`: web
  plugins are not registered under `flutter test --platform chrome`, and a true
  check needs `integration_test` plus chromedriver, which is not installed here.
  Verify by hand for now — `flutter run -d chrome`, drag a desk, hard-reload.
- **`agents` / `agents_flutter` are not wired up.** They are deliberately left
  out of `pubspec.yaml` until the AI work starts, so there is no unused
  dependency to keep in sync.

## Ready for AI, not yet using it

Nothing here calls a model. The groundwork that matters is that tags and
assignment history are **structured records with stable ids**, not display
strings: tags carry a `TagCategory` and a `SeatingHint`, and every saved
arrangement records what produced it. `AssignmentSource.ai` already exists in
the model, so an AI-proposed arrangement will flow through the same save path a
manual one does.

## Keyboard

| Key | Action |
|---|---|
| Arrows (Design room) | Nudge selection by one grid step |
| Delete / Backspace | Clear seats; delete furniture in Design room |
| Esc | Clear selection |
| Ctrl/Cmd + A (Design room) | Select all seats |
| Ctrl/Cmd + D (Design room) | Duplicate |
| Ctrl/Cmd + G (Design room) | Group selection |
| Ctrl/Cmd + Z / Shift+Z | Undo / redo |
| Right-click / long-press | Desk menu |
| Ctrl/Cmd + +/- / 0 | Zoom in, out, fit |
| Shift + click | Add to selection |
