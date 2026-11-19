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

- **Architecture**: `teacher_ai` runs in two build modes from the same Flutter codebase:
  - **Local / demo mode** (`TEACHER_CLOUD=false`, default): Single-blob `WorkspaceDocument` (`schemaVersion = 1`) in `SharedPreferencesStore` / `localStorage`, seeded with a sample Algebra I class on first run, deployed to GitHub Pages via `.github/workflows/pages.yml`.
  - **Hosted / cloud mode** (`TEACHER_CLOUD=true`): Account-scoped Drift/SQLite `Replica` (`schemaVersion = 2`) and `CloudRepository` syncing atomic record batches against an ASP.NET Core 10 Minimal API (`backend/TeacherAI.Api`) backed by PostgreSQL 17, Auth0 OIDC (cookie + CSRF on same-origin web; PKCE + Bearer JWT on native iOS/Android/macOS), .NET Aspire 13.6 (`backend/TeacherAI.AppHost`), and Raspberry Pi ARM64 Docker Compose deployment (`backend/deploy/`).
- **Working tree status (as of 2026-11-19)**: Only `AGENTS.md` and `HANDOFF.md` have been committed on top of `7d0016a`. The full hosted/sync architecture migration (`backend/`, `lib/data/sync/`, `lib/app/cloud_classroom.dart`, `lib/app/classroom_sign_in.dart`, `lib/data/classroom_backup.dart`, `lib/features/settings/classroom_files.dart`, `android/`, `ios/`, `integration_test/`, `tool/`, `.github/workflows/classroom.yml`, and modified Flutter/macOS/doc files) remains **uncommitted in the working tree**.

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
