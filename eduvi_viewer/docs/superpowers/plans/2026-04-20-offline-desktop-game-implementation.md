# Offline Eduvi Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully offline desktop player that imports `.eduvi` files, plays slide packages in Flutter, runs game packages in Electron using local mediapipe runtime, and stores all data locally.

**Architecture:** Flutter handles import/type routing and slide playback; Electron handles game runtime hosting; SQLite + filesystem handle package/session/progress/result persistence.

**Tech Stack:** Flutter desktop, Electron, TypeScript, SQLite, local file system.

---

## Phase 1: Flutter shell + import eduvi

### Output
1. User can import `.eduvi` package manually.
2. Package parser detects package type (`slide` or `game`).
3. Invalid package is rejected before extraction.

### Files expected (create/modify)
- Create: `apps/flutter_player/lib/features/import_eduvi/application/import_controller.dart`
- Create: `apps/flutter_player/lib/features/import_eduvi/domain/import_validator.dart`
- Create: `apps/flutter_player/lib/features/import_eduvi/data/eduvi_archive_reader.dart`
- Create: `packages/eduvi_schema/src/eduvi-manifest.ts`
- Create: `packages/eduvi_schema/src/package-parser.ts`
- Create: `packages/eduvi_schema/src/checksum.ts`
- Create: `apps/flutter_player/test/import_eduvi/import_validator_test.dart`

### Completion checklist
- [ ] Import dialog accepts local `.eduvi` file only.
- [ ] Manifest parse succeeds for valid package.
- [ ] Package type is classified correctly.
- [ ] Invalid checksum blocks import.

### Offline pass/fail criteria
- PASS: Import and validation complete with network disabled.
- FAIL: Any step requires internet connection.

---

## Phase 2: Slide renderer offline

### Output
1. Slide package renders entirely inside Flutter.
2. Assets are loaded only from local extracted path.
3. Slide session metadata is persisted locally.

### Files expected (create/modify)
- Create: `apps/flutter_player/lib/features/slide_player/presentation/slide_player_screen.dart`
- Create: `apps/flutter_player/lib/features/slide_player/data/slide_asset_resolver.dart`
- Create: `apps/flutter_player/lib/features/slide_player/domain/slide_session_service.dart`
- Modify: `apps/flutter_player/lib/main.dart`
- Create: `apps/flutter_player/test/slide_player/slide_player_screen_test.dart`

### Completion checklist
- [ ] Slide navigation works without network.
- [ ] Embedded media assets resolve from local folder.
- [ ] Last viewed slide index is persisted in local session.

### Offline pass/fail criteria
- PASS: Full slide playback works in airplane mode.
- FAIL: Missing remote URL causes playback break.

---

## Phase 3: Electron runtime for game mediapipe

### Output
1. Flutter launches Electron with launch contract file.
2. Electron loads local mediapipe runtime from extracted package.
3. Renderer is hardened with secure Electron defaults.

### Files expected (create/modify)
- Create: `apps/electron_game_runtime/electron-main/app.ts`
- Create: `apps/electron_game_runtime/electron-main/launch-contract-reader.ts`
- Create: `apps/electron_game_runtime/electron-main/package-runtime-loader.ts`
- Create: `apps/electron_game_runtime/electron-preload/index.ts`
- Create: `apps/electron_game_runtime/electron-preload/game-api.ts`
- Create: `apps/electron_game_runtime/electron-renderer/shell/App.tsx`
- Create: `packages/shared_contracts/src/launch-contract.ts`
- Create: `apps/flutter_player/lib/features/game_launcher/application/electron_launcher.dart`
- Create: `apps/electron_game_runtime/test/integration/launch_contract_test.ts`

### Completion checklist
- [ ] Launch contract includes `packagePath`, `sessionId`, `outputDir`, `mode`.
- [ ] Electron opens local game entry without network.
- [ ] `contextIsolation=true`.
- [ ] `nodeIntegration=false`.
- [ ] Preload exposes whitelist APIs only.

### Offline pass/fail criteria
- PASS: Game starts and is playable while network adapters are disabled.
- FAIL: Game runtime tries to call remote endpoint.

---

## Phase 4: Autosave + resume

### Output
1. Progress snapshots are written periodically with atomic write.
2. App can resume from latest valid snapshot after restart/crash.
3. Game final result is written to local result file and DB record.

### Files expected (create/modify)
- Create: `apps/electron_game_runtime/storage/snapshot-writer.ts`
- Create: `apps/electron_game_runtime/storage/result-writer.ts`
- Create: `apps/electron_game_runtime/storage/resume-loader.ts`
- Create: `packages/shared_contracts/src/progress-snapshot.ts`
- Create: `packages/shared_contracts/src/game-result.ts`
- Create: `apps/electron_game_runtime/test/integration/crash_resume_test.ts`
- Create: `apps/flutter_player/lib/features/session_resume/presentation/resume_prompt.dart`

### Completion checklist
- [ ] Snapshot interval can be configured.
- [ ] Snapshot write is atomic using temp file then rename.
- [ ] Corrupted snapshot is detected by checksum.
- [ ] Resume loads previous valid snapshot.
- [ ] Final result saved on session completion.

### Offline pass/fail criteria
- PASS: Crash recovery and resume work fully offline.
- FAIL: Session progress is lost after abrupt process kill.

---

## Phase 5: Local DB + package/session manager

### Output
1. SQLite tables for packages/sessions/progress/results/settings are active.
2. Package manager supports install/update/rollback local extract.
3. Session manager supports start, pause, resume, complete.

### Files expected (create/modify)
- Create: `apps/flutter_player/lib/data/local/sqlite/database.dart`
- Create: `apps/flutter_player/lib/data/local/sqlite/migrations/001_init.sql`
- Create: `apps/flutter_player/lib/data/local/repositories/package_repository.dart`
- Create: `apps/flutter_player/lib/data/local/repositories/session_repository.dart`
- Create: `apps/flutter_player/lib/data/local/repositories/result_repository.dart`
- Modify: `shared-contracts/schema/offline-sync.sqlite.sql`
- Create: `apps/flutter_player/test/data/local/package_repository_test.dart`
- Create: `apps/flutter_player/test/data/local/session_repository_test.dart`

### Completion checklist
- [ ] DB creates required 5 tables.
- [ ] FK constraints protect integrity.
- [ ] Indexes support package/session/result lookup.
- [ ] Extract rollback keeps previous package valid.

### Offline pass/fail criteria
- PASS: Full import->open->play->save->resume works with no network.
- FAIL: Any storage operation depends on remote service.

---

## Verification checklist before release
1. Unit test parser for both slide and game manifests.
2. Unit test local repository CRUD and checksum verification.
3. Integration test import -> open -> play -> save result.
4. Crash recovery test from forced kill.
5. Security checks for Electron hardening and preload whitelist.

## Scope guardrails
1. Do not call API.
2. Do not use REST/WebSocket/Firebase.
3. Keep all package assets, progress, and results local.
4. Reuse existing mediapipe runtime from web package instead of rewriting game logic.
