# AGENTS.md

Guidance for AI coding agents working in `teacher_ai`.

## Start Here

1. Read this file (`AGENTS.md`) and the top of [`HANDOFF.md`](HANDOFF.md) (Current State, Open Review Findings & Follow-Ups, and the latest Change Log entries) before editing code.
2. Check [`README.md`](README.md), [`backend/README.md`](backend/README.md), and [`backend/deploy/README.md`](backend/deploy/README.md) for product behavior, local setup, and Pi deployment details.
3. Run `git status` first—never assume the working tree is clean, and never stage or revert unrelated user changes.

## Mandatory Git & Handoff Workflow

Follow these rules on every task that modifies the repository:

1. **Commit small, incremental changes.**
   - Complete, verify, and commit each cohesive unit of work before starting the next one rather than batching unrelated edits into one large commit.
2. **Update [`HANDOFF.md`](HANDOFF.md) with every commit.**
   - Before running `git commit`, prepend a new dated entry at the top of `## Change Log` in `HANDOFF.md` documenting:
     - **What** changed (files, behavior, endpoints, schema, config).
     - **Why** it was done (problem solved, design rationale, tradeoffs).
     - **Verification** performed (tests, static analysis, builds actually run and their scope) and any **follow-ups or risks**.
   - Include the `HANDOFF.md` update in the **same commit** as the code/doc change (do not try to embed the commit's own SHA inside `HANDOFF.md`).
   - Update `## Current State` and `## Open Review Findings & Follow-Ups` in `HANDOFF.md` whenever the architecture, active work, or known issues change.
3. **Stage explicitly.**
   - Stage only the specific files for the current increment plus `HANDOFF.md` (`git add <file1> <file2> HANDOFF.md`). Do **not** use blanket `git add .` or `git add -A` when unrelated working-tree changes exist.
4. **Never push** to a remote unless the user explicitly asks you to.

## Architecture Overview

`teacher_ai` is a **dual-mode Flutter classroom app** (seating charts, room design, rosters, weekly schedules, and live participation scoring) backed optionally by an **ASP.NET Core 10 + PostgreSQL 17 sync backend** orchestrated with **.NET Aspire 13.6**.

### 1. Dual-Mode Flutter Client (repository root, Dart `^3.10.1`, Flutter `3.47.4` in CI)

The app boots on `extensions` / `extensions_flutter` (`lib/main.dart`, `lib/app/service_registration.dart`, `lib/app/app.dart`):

- **Local / Demo mode (`TEACHER_CLOUD=false`, default)** — Used by plain `flutter run` and GitHub Pages (`.github/workflows/pages.yml`).
  - `TeacherApp` loads the DI-registered `TeacherWorkspace` singleton backed by `StoredTeacherRepository` (`lib/data/teacher_repository.dart`) and `KeyValueStore` (`SharedPreferencesStore` / `localStorage` on web, `InMemoryStore` in tests).
  - First run seeds a sample Algebra I class (`lib/data/seed_data.dart`) into a single JSON `WorkspaceDocument` (`schemaVersion = 1`).
  - Supports classroom JSON export (`lib/features/settings/classroom_files.dart`).

- **Hosted / Cloud mode (`TEACHER_CLOUD=true`)** — Used by the ASP.NET-served PWA and native mobile/desktop builds.
  - `TeacherApp` skips loading the DI `TeacherWorkspace` and instead mounts `CloudClassroom` (`lib/app/cloud_classroom.dart`), which owns its own `CloudApi` (`lib/data/sync/cloud_api.dart`), account-scoped Drift/SQLite `Replica` (`lib/data/sync/local_store.dart`), `CloudRepository` (`lib/data/sync/cloud_repository.dart`), and `TeacherWorkspace`.
  - New hosted accounts open empty (no demo seed). Teachers can create classes in Schedule/Roster or import a local classroom via `ClassroomFiles` (`lib/data/classroom_backup.dart`, `lib/features/settings/classroom_files.dart`).
  - **Web auth**: same-origin OIDC via `/auth/login` -> `__Host-teacher` HttpOnly cookie + `X-CSRF` antiforgery header (`lib/data/sync/browser.dart`).
  - **Native auth (iOS, Android, macOS)**: `flutter_appauth` PKCE (`app.teacherai.classroom:/callback`) + `flutter_secure_storage` refresh token + Bearer JWT.

#### Frontend Layers

| Layer | Location | Responsibility |
|---|---|---|
| Domain models | `lib/domain/models/` | Immutable value objects with hand-written JSON (`ClassSection`, `Desk`, `DeskGroup`, `GradeLevel`, `ParticipationEntry`, `RoomLayout`, `SchedulePeriod`, `SeatingAssignment`, `Student`, `StudentTag`, `Subject`); no Flutter widgets. |
| Pure operations | `lib/domain/ops/` | Layout geometry/alignment, room presets, and seeded seating shuffle/rotation (`layout_ops.dart`, `layout_presets.dart`, `seating_ops.dart`). |
| Persistence & sync | `lib/data/` | `WorkspaceDocument`, `TeacherWorkspace` (`ChangeNotifier`), `TeacherRepository` / `SyncingTeacherRepository`, `KeyValueStore`, `classroom_backup.dart`, and `sync/` (`records.dart`, `local_store.dart`, `cloud_api.dart`, `cloud_repository.dart`, `browser.dart`, `browser_stub.dart`). |
| App shell & config | `lib/app/` | `TeacherApp`, `CloudClassroom`, `ClassroomSignIn`, `HomeShell`, `AppSettingsController`, `AppTheme` / `RoomPalette`, `responsive.dart` (`compact < 600`, `medium < 960`, `expanded >= 960`). |
| Feature UI | `lib/features/` | `seating/` (`LiveClassroom`, `SeatingPage`, `SeatingEditorController`, `RoomViewController`, canvas/painter/panel widgets), `roster/`, `schedule/`, `settings/`. |

### 2. Backend & Operations (`backend/`, .NET 10, Aspire 13.6.5, PostgreSQL 17)

- **`backend/TeacherAI.Api/`**:
  - `Program.cs`: Serves static same-origin Flutter web assets from `wwwroot/` (generated by `tool/build_cloud_web.py` with a precaching `classroom-worker.js` service worker). Configures policy-scheme auth (`Bearer` JWT or `Cookies` + `oidc`), `X-CSRF` validation on cookie mutations, per-`sub` fixed-window rate limiting (`180` req/min), `X-Workspace-Account` ownership verification, `X-Classroom-Generation` restore-generation check (`412` on mismatch), `410 Gone` for deleted accounts, `/ready` DB probe (`204` / `503`), and `/openapi/v1.json` in Development.
  - `Sync.cs`: Implements `GET /api/v1/workspace`, `GET /api/v1/changes?after=`, and `POST /api/v1/mutations`. Serializes writes per teacher via `pg_advisory_xact_lock`, enforces idempotency via `Receipts` (`OperationId` + SHA-256 `Digest`), rejects stale revisions with `409 Conflict`, validates roster/tag links (`422`), and records tombstones (`Payload = null`, incrementing `Revision` and `Cursor`).
  - `ClassroomDb.cs` & `Migrations/`: EF Core PostgreSQL schema (`Records`, `Receipts`, `DeletedAccounts`).
  - `AccountDeletion.cs`: `DELETE /api/v1/account` deletes `Records` and `Receipts`, writes a hashed `DeletedAccounts` tombstone + `PendingSubject`, and `AccountDeletionWorker` polls every 30s to delete the user in Auth0 via Management API.
  - `ReleaseMigration.cs`: `--migrate-only` entrypoint runs EF migrations and provisions the least-privilege `teacher_api` PostgreSQL role.
- **`backend/TeacherAI.AppHost/`**: .NET Aspire AppHost (`https://localhost:7240` locally; `aspire publish` for Docker Compose output).
- **`backend/TeacherAI.ServiceDefaults/`**: OpenTelemetry, service discovery, HTTP client resilience, and dev `/health` + `/alive` endpoints.
- **`backend/TeacherAI.Tests/`**: PostgreSQL integration & load tests (`RosterSyncTests.cs`, `ClassroomLoad.cs`, `TestIdentityManagement.cs`) and Playwright two-browser + legacy import E2E tests (`BrowserRosterTests.cs`, `browser/roster.cjs`, `browser/classroom-files.cjs`).
- **`backend/deploy/`**: Raspberry Pi ARM64 Compose overlay (`pi.compose.yaml`), Auth0 post-login `verified-email.js`, Dex local login styling (`dex/`), restic encrypted backup/restore/reconcile/health-check scripts (`classroom-backup`, `classroom-restore`, `classroom-reconcile`, `classroom-check`), and `systemd/` units.

## Key Invariants & Guardrails

1. **Room coordinates**: Desks are stored in room centimeters from top-left, never screen pixels. `RoomViewController` and `RoomPainter` share scale/pan math for rendering and hit-testing.
2. **Save semantics**: Room layout edits autosave (debounced 400ms in local mode; immediate Drift `Replica` writes + 400ms sync schedule in cloud mode). Seating arrangements (`SeatingAssignment`) are explicit, append-only snapshots in history. `SeatingEditorController` uses immutable `EditorSnapshot` undo stacks and merges incoming remote room/chart updates while preserving unsaved local seating drafts.
3. **Sync record keys & atomicity**: Synced records use `calendar` and `<collection>/<id>` across `subjects`, `tags`, `students`, `classes`, `layouts`, `assignments`, `periods`, `participation` (key max 180 chars, no `/` in IDs). `RoomLayout` is stored as a single record so desk drags and group edits remain atomic.
4. **Drift `Replica` (`schemaVersion = 2`)**: Keeps `records(key, value, revision, dirty)` and `state(id, cursor, request, generation)`. Frozen requests survive app restarts and lost acknowledgements; `pull()` must never overwrite `dirty = 1` rows. Web requires persistent WASM/OPFS (`web/sqlite3.wasm`, `web/drift_worker.js`) and rejects `inMemory` or `unsafeIndexedDb`.
5. **Cloud empty start**: `CloudRepository.load()` returns a non-null `WorkspaceDocument` so `TeacherWorkspace.load()` skips demo seeding and wires up `onRemote`.
6. **macOS Impeller workaround**: Keep `FLTEnableImpeller` disabled in `macos/Runner/Info.plist` until upgrading past Flutter 3.47.4 / engine PR #192522 and re-verifying window resize and fullscreen transitions.
7. **Repo hygiene & secrets**: Never commit secrets, `.env` files, `backend/TeacherAI.Api/wwwroot/`, `backend/aspire-output/`, `bin/`, `obj/`, or stray `bin\Debug/` directories.

## Common Commands

```sh
# Flutter analyze & tests (local / unit / widget)
flutter pub get
dart analyze --fatal-infos
flutter test

# Run local demo app
flutter run -d chrome

# Native SQLite offline integration test (requires target device/emulator)
flutter test integration_test/offline_classroom_test.dart -d <device>

# Build hosted Flutter web client into backend/TeacherAI.Api/wwwroot
python3 tool/build_cloud_web.py

# Run local Aspire hosted stack (requires configured user secrets & Docker)
dotnet run --project backend/TeacherAI.AppHost

# Run backend sync tests against disposable PostgreSQL
TEACHER_TEST_POSTGRES="Host=localhost;Database=classroom;Username=postgres;Password=..." \
  dotnet test backend/TeacherAI.Tests

# Optional backend test modes:
#   TEACHER_BROWSER_TEST=1 TEACHER_LEGACY_WEB=/abs/path/to/build/web PLAYWRIGHT_MODULE=/abs/path/to/playwright
#   TEACHER_LOAD_TEACHERS=16 (with --filter FullyQualifiedName~RosterSyncTests)
```

CI pipelines:
- [`.github/workflows/classroom.yml`](.github/workflows/classroom.yml): Dart analyze/tests, web & cloud web builds, `.NET` + PostgreSQL + Playwright E2E tests, cloud APK build, and Android emulator offline integration test.
- [`.github/workflows/pages.yml`](.github/workflows/pages.yml): Flutter tests and GitHub Pages deployment of the local web build on pushes to `main`.
