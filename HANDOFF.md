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

- Railway serves the hosted Flutter client and .NET API together from the root `Dockerfile`. The deployment from `68370d9` passed its production readiness check on 2026-11-19. [Hosted classroom](https://teacherai-production-c48eb422.up.railway.app/)

- **Architecture**: `teacher_ai` runs in two build modes from the same Flutter codebase:
  - **Local / demo mode** (`TEACHER_CLOUD=false`, default): Single-blob `WorkspaceDocument` (`schemaVersion = 1`) in `SharedPreferencesStore` / `localStorage`, seeded with a sample Algebra I class on first run, deployed to GitHub Pages via `.github/workflows/pages.yml`.
  - **Hosted / cloud mode** (`TEACHER_CLOUD=true`): Account-scoped Drift/SQLite `Replica` (`schemaVersion = 2`) and `CloudRepository` syncing atomic record batches against an ASP.NET Core 10 Minimal API (`backend/TeacherAI.Api`) backed by PostgreSQL 17, Auth0 OIDC (cookie + CSRF on same-origin web; PKCE + Bearer JWT on native iOS/Android/macOS), .NET Aspire 13.6 (`backend/TeacherAI.AppHost`), and Raspberry Pi ARM64 Docker Compose deployment (`backend/deploy/`).
- The iOS runner uses the Railway endpoint, Auth0 issuer, public native Client ID and API audience in `ios/railway.json`. The native callback is registered. The native application still needs user-delegated access to the classroom API in Auth0.
- **Working tree status (2026-11-19)**: The remaining local changes include the Aspire AppHost, backend integration harness, Pi deployment scripts, Android and macOS updates and CI configuration.

## Open Review Findings & Follow-Ups

From the 2026-11-19 architecture review (ordered by severity):

1. The local directory whose name contains a literal backslash, `backend/TeacherAI.Api/bin\Debug/`, is now ignored and excluded from deployment source.
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

### 2026-11-19 — Connect the Railway iOS preset to the native Auth0 application

- Added the supplied public native Client ID to the preset and updated the iOS run instructions to use the preset alone.
- Built and launched on the iPhone 17 simulator. Verified that Flutter received all five preset values and Railway readiness returned 204.
- A PKCE authorization request from the simulator reached the registered iOS callback with an Auth0 error stating the native client lacks access to the classroom API. Signed-in sync awaits the user-delegated API grant and a teacher sign-in.

### 2026-11-19 — Configure the iOS Railway API audience

- Set the supplied API audience in the iOS preset and simplified the run command to require only the native client ID.
- Built and launched the app on the iPhone 17 simulator with the supplied client ID and audience. Checked that the generated Flutter build settings contained both values.
- Compared the supplied ID against Railway’s web login redirect and confirmed they match. A separate PKCE authorization request returned HTTP 403 from Auth0 because that client does not allow `app.teacherai.classroom:/callback`. Signed-in verification awaits a native client with that callback registered.

### 2026-11-19 — Run the iOS classroom against Railway

- Added the iOS Xcode workspace, plugin dependencies, callback scheme and Keychain entitlement. Added a Flutter build configuration for the deployed API and its Auth0 issuer, iOS run instructions, and the existing native offline-replica integration test.
- On an iPhone 17 simulator running iOS 27, the offline test passed and the regular Flutter app launched to the cloud sign-in screen. A separate native URLSession probe using the same configuration received 204 from Railway readiness, 401 from its anonymous session endpoint, and 200 from the Auth0 discovery endpoint.
- Signed-in sync still requires the tenant's public native client ID, matching API audience, and a teacher login. Physical-device signing was outside the simulator checks.

### 2026-11-19 — Finish the local sign-in design handoff

- Added the password form and light/dark stylesheet used by the local Dex preview under `backend/deploy/dex/`. They carry the classroom colors, type and form controls through the local sign-in flow. The Flutter entry screen and the Account & sync settings shipped in `68370d9`.
- To apply the preview theme, copy `password.html` into `templates/` and `classroom.css` into `static/` under the Dex web directory selected by `frontend.dir`. Production identity-provider branding is configured separately.
- Matched both files against the running Dex preview and checked the rendered form in Chrome at 360 × 640 in light mode and 1280 × 800 in dark mode. Both displayed the sign-in button in the viewport, loaded the expected theme color and fit without horizontal scrolling.

### 2026-11-19 — Verify the Railway deployment

- Confirmed that Railway reported a successful deployment for `68370d9` on GitHub, closing the build failure recorded below.
- Verified live GET responses from the Railway hostname. The classroom root returned 200, the database readiness probe at `/ready` returned 204, and anonymous access to `/api/v1/workspace` returned 401. These checks covered public serving, database connectivity and the authentication boundary. Signed-in sync was outside this smoke test.

### 2026-11-19 — Include the source required by the Railway Dockerfile

- GitHub reported the Railway deployment of `5dc7a39` failed. Reproduced Docker’s missing-source error using a Git archive of that revision.
- Added the API and service-defaults projects, schema migrations, hosted Flutter build script, cloud classroom and storage code, locked dependencies, browser SQLite assets and related Flutter tests. These are the source inputs needed to ship the same hosted classroom as the local preview.
- Verified Docker’s source-copy steps against an archive of the prospective commit. From that archive, restored the locked Flutter packages, built the hosted web release, published the .NET API with its web assets, and passed all 126 Flutter tests. Started the published application in a Linux AMD64 runtime container after migrating disposable PostgreSQL, verified readiness (204), static assets (200) and anonymous workspace access (401). A hosted Railway build requires the corrected revision on its deployment branch.

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
