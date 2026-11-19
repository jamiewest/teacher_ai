# HANDOFF.md

Running handoff log for AI agents and maintainers working on `teacher_ai`.

## Update Rules

Every AI commit must update this file **in the same commit**:

1. Prepend a new dated entry at the top of `## Change Log` covering:
   - **What** changed (files, endpoints, schema, UI, config).
   - **Why** it was done (problem solved, design rationale, tradeoffs).
   - **Verification** performed (exact checks/tests run and scope) and any **follow-ups or risks**.
2. Keep `## Current State` and `## Open Review Findings & Follow-Ups` current whenever architecture, pending work, or known issues change.

## Current State

- The root `Dockerfile` builds the hosted Flutter client and .NET API into one image. Railway can build it with the repository root as its source once the hosted app sources are available on the deployment branch.

- **Architecture**: `teacher_ai` runs in two build modes from the same Flutter codebase:
  - **Local / demo mode** (`TEACHER_CLOUD=false`, default): Single-blob `WorkspaceDocument` (`schemaVersion = 1`) in `SharedPreferencesStore` / `localStorage`, seeded with a sample Algebra I class on first run, deployed to GitHub Pages via `.github/workflows/pages.yml`.
  - **Hosted / cloud mode** (`TEACHER_CLOUD=true`): Account-scoped Drift/SQLite `Replica` (`schemaVersion = 2`) and `CloudRepository` syncing atomic record batches against an ASP.NET Core 10 Minimal API (`backend/TeacherAI.Api`) backed by PostgreSQL 17, Auth0 OIDC (cookie + CSRF on same-origin web; PKCE + Bearer JWT on native iOS/Android/macOS), .NET Aspire 13.6 (`backend/TeacherAI.AppHost`), and Raspberry Pi ARM64 Docker Compose deployment (`backend/deploy/`).
- **Working tree status (as of 2026-11-19)**: `AGENTS.md`, `HANDOFF.md`, the tooltip/helper-text pass (with `test/tooltips_and_helper_text_test.dart`), the Material 3 theme / Schedule period cards / Seating header pill refinements, and the live classroom equity random picker, AI seating assistant sheet, and roster Material 3 polish are committed cleanly ahead of `7d0016a`. The full hosted/sync architecture migration (`backend/`, `lib/data/sync/`, `lib/app/cloud_classroom.dart`, `lib/app/classroom_sign_in.dart`, `lib/data/classroom_backup.dart`, `lib/features/settings/classroom_files.dart`, `android/`, `ios/`, `integration_test/`, `tool/`, `.github/workflows/classroom.yml`, and modified Flutter/macOS/doc files—including the navigation badge, settings Teacher AI Pro card, and cloud tooltip/helper-text additions in `lib/app/home_shell.dart`, `lib/features/settings/settings_sheet.dart`, `lib/features/settings/classroom_files.dart`, and `lib/app/cloud_classroom.dart`) remains **uncommitted in the working tree**.

## Open Review Findings & Follow-Ups

From the 2026-11-19 architecture review (ordered by severity):

1. **High — Untracked `backend/TeacherAI.Api/bin\Debug/` artifact directory**:
   - A directory whose literal name contains a backslash (`backend/TeacherAI.Api/bin\Debug/`) holds ~45 `.dll`/`.exe` build-host binaries and is **not** matched by `backend/**/bin/` in `.gitignore`.
   - Remove this directory and add a matching ignore rule before staging/committing `backend/`.
2. **High — Lifecycle flush gap in hosted mode (`lib/app/app.dart`, `lib/app/cloud_classroom.dart`)**:
   - `TeacherApp._flush()` flushes the DI-registered `TeacherWorkspace`, which is unused when `CloudApi.enabled` is true.
   - `CloudClassroom.didChangeAppLifecycleState` only triggers `_repo?.sync()` on `AppLifecycleState.resumed` and does not flush/sync when paused or detached. Wire pause/detach lifecycle flushing to the active cloud workspace/repository.
3. **High — `422`/`400` sync rejection retry storm trips health alert (`lib/data/sync/cloud_repository.dart`, `backend/TeacherAI.Api/Program.cs`, `backend/deploy/classroom-check`)**:
   - On HTTP `422`/`400`, `CloudRepository._exchange()` calls `db.releaseRejected(batch)` (clearing `state.request`) while leaving the rejected records marked `dirty = 1`.
   - The 15s poll timer (and any subsequent save/resume) re-freezes and resubmits the same invalid records, repeatedly logging `Classroom sync failed with HTTP 422` and triggering `classroom-check`'s `>= 5` failures/15m alert. Pause automatic retries for a rejected payload until the teacher modifies the affected records or explicitly triggers `Sync now`.
4. **Medium — Static cache headers for service worker & bootstrap (`backend/TeacherAI.Api/Program.cs`, `backend/deploy/README.md`)**:
   - `UseStaticFiles` sets no `Cache-Control` headers, and the Cloudflare bypass list in `backend/deploy/README.md` only excludes `/api/*`, `/auth/*`, `/signin-oidc`, and `/ready`. Because Cloudflare caches `.js` assets by default, `/classroom-worker.js` and `/flutter_bootstrap.js` (plus `/index.html`) should be served with `Cache-Control: no-cache` and bypassed at the edge so web releases propagate cleanly.
5. **Medium — `ASPNETCORE_FORWARDEDHEADERS_ENABLED` proxy trust in Docker Compose (`backend/deploy/pi.compose.yaml`)**:
   - `pi.compose.yaml` sets `ASPNETCORE_FORWARDEDHEADERS_ENABLED=true`, but ASP.NET Core's forwarded-headers middleware only trusts loopback proxies by default while `cloudflared` (`tunnel`) connects from the Docker `ingress` bridge network. Configure `ForwardedHeadersOptions` to trust the proxy network/address if forwarded scheme/client IP headers are relied upon.
6. **Low / Maintenance**:
   - `CloudRepository._exchange()` (`lib/data/sync/cloud_repository.dart`) ends with `(await db.freeze()) == null`, which eagerly freezes a new `operationId` batch just to test whether dirty rows remain (a read-only dirty check avoids splitting rapid edits across batches).
   - `DELETE /api/v1/account` (`backend/TeacherAI.Api/AccountDeletion.cs`) does not call `HttpContext.SignOutAsync` for cookie sessions (relies on `410 Gone` responses to clear the client).
   - `Sync.ValidateRoster` (`backend/TeacherAI.Api/Sync.cs`) validates `classes.studentIds` and `students.tagIds` only (narrower than `readClassroomBackup`), and `Receipts` rows grow without a retention cleanup job.
   - `README.md` still contains stale local-only statements in the Architecture table (line 79) and final paragraph (lines 216–220) that conflict with the hosted sync description at the top.

## Change Log

### 2026-11-19 — Add live random student picker, AI seating assistant sheet, and roster Material 3 polish

- **What**: Enhanced [`lib/features/seating/live_classroom.dart`](lib/features/seating/live_classroom.dart) with a 1-tap `'Pick a random student'` button (prioritizing students not yet scored today and avoiding immediate repeats), an expanded-panel class participation pulse (`'$activeTodayCount of ${editor.roster.length} active today'`), semantic tonal `Add 1`/`Deduct 1` buttons (`_ScoringButtonsRow`), and `tabularFigures()` on live score summaries; added `'AI seating assistant…'` in `_moreMenu` and an `_AiAssistantSheet` modal bottom sheet in [`lib/features/seating/seating_page.dart`](lib/features/seating/seating_page.dart) surfacing live classroom signals, instant smart seating / Kagan team rotation actions, and a `Teacher AI Pro` tier preview; polished [`lib/features/roster/roster_page.dart`](lib/features/roster/roster_page.dart) with a tonal student-count badge, tonal initials avatars, grade pill badges, and rounded tonal tag color markers; and added widget tests in [`test/tooltips_and_helper_text_test.dart`](test/tooltips_and_helper_text_test.dart). Also refined the `NavigationRail` school icon badge in [`lib/app/home_shell.dart`](lib/app/home_shell.dart) and added a `Teacher AI Pro` card in [`lib/features/settings/settings_sheet.dart`](lib/features/settings/settings_sheet.dart) in the working tree (left unstaged alongside the uncommitted hosted-architecture changes).
- **Why**: Help teachers run live participation more effortlessly, polish Material 3 hierarchy across Roster and navigation/settings surfaces, and showcase the optional `Teacher AI Pro` subscription capability cleanly alongside built-in local smart-seating workflows.
- **Verification**: `analyze_files` (Dart MCP) reported `No errors`; `dart analyze --fatal-infos` reported `No issues found!`; `flutter test` passed all `126` tests.
- **Follow-ups**: Stage and commit the working-tree `home_shell.dart` and `settings_sheet.dart` refinements when committing the hosted-architecture slice.

### 2026-11-19 — Add a root Dockerfile for Railway source builds

- Added a multi-stage build using the Flutter version pinned in CI, the existing offline web build script, and the .NET 10 SDK and runtime. The app runs as the unprivileged .NET user and listens on Railway’s `PORT`, with 8080 as the local default. The entrypoint also accepts `--migrate-only`.
- Added an allowlist in `.dockerignore` so Docker receives the app sources and skips local configuration, generated outputs, and database credentials. Verified the build context and ran Docker’s build check.
- The cold Linux build completed dependency restore and reached Flutter compilation before the local Docker VM stopped under disk pressure. For the runtime test, built Flutter locally from the filtered source and supplied its output as the web stage. The resulting Linux AMD64 image ran migrations against disposable PostgreSQL 17, served the web app and offline assets, returned 204 for readiness on a custom port, and returned 401 for an anonymous workspace request. Restored and verified the original preview, including sign-in. A complete Railway-hosted build remains to be verified.

### 2026-11-19 — Refine Material 3 theme, schedule period cards, and seating header pills

- **What**: Refined Material 3 component styling in [`lib/app/theme.dart`](lib/app/theme.dart) (`cardTheme`, `outlinedButtonTheme`, `appBarTheme`, `navigationRailTheme`, `navigationBarTheme`, `dialogTheme`, `bottomSheetTheme` while keeping native `textTheme` font metrics), redesigned [`lib/features/schedule/schedule_page.dart`](lib/features/schedule/schedule_page.dart) with a tonal calendar control deck, class/break summary pill, compact break strips, layered class period cards (time pill, tabular duration, `Now` badge, metadata pills, and tonal `Seating chart` action bar), and updated the single-row header pills in [`lib/features/seating/seating_page.dart`](lib/features/seating/seating_page.dart) (`ActionChip` tonal fill/padding, flexible dropdown icons, and hiding segmented-button icons below `860px`).
- **Why**: Give the app stronger Material 3 surface hierarchy and clear schedule scanability for teachers while fixing a medium-width horizontal overflow inside the two seating header `ActionChip`s.
- **Verification**: `analyze_files` (Dart MCP) reported `No errors`; `flutter test` passed all `124` tests across every responsive viewport.
- **Follow-ups**: Continue with live-classroom teacher UX refinements, the AI seating assistant sheet, roster card polish, and dedicated widget tests.

### 2026-11-19 — Add roster and schedule tooltips, helper text, and tooltip widget tests

- **What**: Added hover tooltips (`excludeFromSemantics: true` on labeled controls) and calm contextual helper copy across Roster ([`lib/features/roster/roster_page.dart`](lib/features/roster/roster_page.dart), [`lib/features/roster/student_editor_dialog.dart`](lib/features/roster/student_editor_dialog.dart), [`lib/features/roster/tag_editor_dialog.dart`](lib/features/roster/tag_editor_dialog.dart), [`lib/features/roster/roster_membership_dialog.dart`](lib/features/roster/roster_membership_dialog.dart)) and Schedule ([`lib/features/schedule/schedule_page.dart`](lib/features/schedule/schedule_page.dart), [`lib/features/schedule/period_editor_dialog.dart`](lib/features/schedule/period_editor_dialog.dart)), and added [`test/tooltips_and_helper_text_test.dart`](test/tooltips_and_helper_text_test.dart). Also applied navigation, settings, and cloud-action hover tooltips and helper captions in the working tree to [`lib/app/home_shell.dart`](lib/app/home_shell.dart), [`lib/features/settings/settings_sheet.dart`](lib/features/settings/settings_sheet.dart), [`lib/features/settings/classroom_files.dart`](lib/features/settings/classroom_files.dart), and [`lib/app/cloud_classroom.dart`](lib/app/cloud_classroom.dart) (left unstaged alongside the uncommitted hosted-architecture changes).
- **Why**: Complete the hover-tooltip and lightweight helper-text UX pass across every primary screen while preserving exact semantic names for accessibility/Playwright tests and keeping clean incremental commits isolated from the pending hosted-architecture work.
- **Verification**: `analyze_files` (Dart MCP) reported `No errors`; `flutter test` passed all `124` tests after all edits.
- **Follow-ups**: Stage and commit the navigation/settings/cloud tooltip additions together with the hosted-architecture increments when committing that work.

### 2026-11-19 — Add tooltip theme and seating/live classroom hover tooltips and helper text

- **What**: Added a styled `TooltipThemeData` in [`lib/app/theme.dart`](lib/app/theme.dart) (`450 ms` hover wait, `2.5 s` show duration, `inverseSurface` Material styling) and added hover tooltips (`excludeFromSemantics: true` on labeled controls so accessible names stay clean) plus restrained helper captions across [`lib/features/seating/seating_page.dart`](lib/features/seating/seating_page.dart), [`lib/features/seating/live_classroom.dart`](lib/features/seating/live_classroom.dart), [`lib/features/seating/widgets/editor_toolbar.dart`](lib/features/seating/widgets/editor_toolbar.dart), [`lib/features/seating/widgets/inspector_panel.dart`](lib/features/seating/widgets/inspector_panel.dart), [`lib/features/seating/widgets/layouts_panel.dart`](lib/features/seating/widgets/layouts_panel.dart), [`lib/features/seating/widgets/roster_panel.dart`](lib/features/seating/widgets/roster_panel.dart), and [`lib/features/seating/widgets/seat_picker.dart`](lib/features/seating/widgets/seat_picker.dart).
- **Why**: Buttons, chips, dropdowns, and icon menus lacked consistent hover explanations, and key flows (live tap modes, saving seating vs. autosaving rooms, picking students, and preset creation) benefited from concise contextual cues without cluttering the canvas.
- **Verification**: `analyze_files` (Dart MCP) reported `No errors`; `flutter test` passed all `120` tests.
- **Follow-ups**: Continue with Roster & Schedule tooltips/helper text and add dedicated widget tests, plus navigation/settings/cloud polish.

### 2026-11-19 — Add AGENTS.md and HANDOFF.md after architecture review

- **What**: Created [`AGENTS.md`](AGENTS.md) and [`HANDOFF.md`](HANDOFF.md) at the repository root documenting the updated dual-mode Flutter + ASP.NET Core / PostgreSQL sync architecture, frontend/backend module layout, key invariants, build/test commands, architecture review findings, and mandatory incremental-commit + handoff workflow.
- **Why**: The project expanded from a local-only Flutter app to a dual-mode local/hosted architecture with Drift offline storage, ASP.NET Core sync API, Auth0 OIDC, Aspire orchestration, and Raspberry Pi deployment. Agents need accurate architectural guidance and a strict rule to commit small increments with matching `HANDOFF.md` rationale entries.
- **Verification**: Read-only inspection of the repository structure, Flutter app, sync layer, ASP.NET Core API, EF Core migrations, `.NET`/Playwright/Flutter tests, CI workflows, and Raspberry Pi deployment scripts. Pre-existing uncommitted architecture files in the working tree were left untouched and excluded from this commit.
- **Follow-ups**: Address the open review findings above (starting with removing `backend/TeacherAI.Api/bin\Debug/`) and commit the pending architecture changes incrementally in cohesive slices.
