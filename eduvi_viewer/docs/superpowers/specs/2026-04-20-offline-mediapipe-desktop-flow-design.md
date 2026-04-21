# Offline MediaPipe Desktop Flow Design

## Assumptions

1. Desktop app chay offline 100%, khong su dung API, backend, websocket, firebase, hay cloud sync.
2. Input duy nhat la file `.eduvi` duoc import thu cong tu local disk.
3. `.eduvi` co 2 nhom chinh:
   - slide package (co the chua image/video blocks)
   - game package (MediaPipe game, render qua Electron)
4. File `.eduvi` hien tai la JSON payload (khong bat buoc la zip). Tuy nhien architecture cho phep mo rong sang archive format trong tuong lai.
5. MediaPipe model files (task/model/wasm) deu duoc dong goi local va load qua `file://` hoac duong dan local da resolve.
6. Session state, snapshot, result, telemetry logs deu luu local.
7. Flutter shell la process entry chinh. Electron runtime la process phu duoc launch khi package type = game.

## Architecture

### High-level components

1. Flutter Shell Process
   - Import package
   - Validate manifest + checksum
   - Route runtime: slide/video trong Flutter, game trong Electron
   - Quan ly package/session metadata qua SQLite

2. Electron Main Process
   - Khoi tao BrowserWindow
   - Harden security settings
   - Quan ly IPC channels
   - Read launch contract va source package payload
   - Ghi snapshot/result vao output dir (atomic write)

3. Electron Preload Bridge
   - Expose whitelist APIs cho renderer
   - Chan renderer truy cap Node APIs truc tiep
   - Mapping IPC methods: read contract, read source eduvi, save snapshot, save result

4. Electron Renderer UI
   - Hien thi game scene
   - Render camera preview + game HUD
   - Nhan landmarks/gesture updates
   - Tick game loop va render frame

5. Inference Worker Thread
   - Frame preprocess
   - Chay MediaPipe inference local
   - Post landmarks/events ve renderer loop

6. Local Storage Layer
   - SQLite metadata store
   - File system package/session/assets/logs store

### Process responsibility map

- Electron Main: process orchestration, window lifecycle, secure IPC, file write gateway.
- Preload: contract-safe IPC facade, strict API boundary.
- Renderer: UI + game logic + frame scheduling.
- Worker: heavy inference compute, frame drop control, landmark smoothing.

## MediaPipe Flow

### End-to-end flow (import game -> play -> save)

1. User import `.eduvi` game trong Flutter.
2. Importer parse manifest + classify package type = game.
3. Package manager verify checksum va extract vao local package folder (atomic + rollback).
4. Flutter tao session row va launch contract (`packagePath`, `sessionId`, `outputDir`, `mode`).
5. Flutter launch Electron runtime process voi arg `--launch-contract=<path>`.
6. Electron Main load runtime entry va expose preload bridge.
7. Renderer doc source game payload (games/resultJson) va bootstrap game state.
8. Camera capture loop start.
9. Worker inference loop chay MediaPipe local model.
10. Renderer tick game logic + render UI.
11. Autosave snapshot theo interval va milestone.
12. Ket thuc game => write result json + update SQLite metadata.
13. Dong app/mo lai => resume session tu latest valid snapshot.

### Frame pipeline

capture camera -> preprocess -> mediapipe inference -> game logic tick -> render -> autosave

Chi tiet:
1. Capture camera (renderer)
   - Read frame tu MediaStream/Video element
   - Timestamp frame va push vao ring buffer

2. Preprocess (worker)
   - Resize ve inference resolution (vd 256x256 hoac 320x320)
   - Normalize colorspace/layout

3. Inference (worker)
   - Run MediaPipe Tasks local
   - Output landmarks + confidence

4. Game logic tick (renderer)
   - Consume inference result moi nhat
   - Update gameplay states (selection, scoring, timer, combo)

5. Render (renderer)
   - requestAnimationFrame render
   - Overlay guide zones, pointer/gesture states, HUD

6. Autosave (main via preload IPC)
   - Persist compact snapshot JSON theo interval
   - Force save on checkpoint/end

### FPS stabilization and drop-frame strategy

1. Multi-loop design
   - Capture loop target 30 FPS
   - Inference loop target 15-30 FPS (adaptive)
   - Render loop target 60 FPS (RAF)

2. Latest-frame policy
   - Ring buffer size 2-3
   - Neu inference bi cham, bo frame cu, chi xu ly frame moi nhat

3. Dynamic quality scaling
   - Track moving-average inference latency
   - Neu latency > budget (vd 33ms), giam input resolution hoac tang frame stride
   - Neu latency on dinh, co the nang quality len

4. Landmark smoothing
   - EMA/Kalman smoothing cho jitter tay/mat
   - Tach latency control va visual smoothing

5. Backpressure guard
   - Gioi han max pending inference jobs = 1
   - Khong queue vo hanh frame jobs

### Resume session strategy

1. Session manager query latest resumable session (`running|paused|crashed`).
2. Load latest valid snapshot theo `session_id` order by `created_at desc`.
3. Verify snapshot checksum.
4. Neu snapshot moi nhat corrupt -> fallback snapshot truoc do.
5. Launch Electron mode `resume`, inject restored state va timer/score pointer.
6. Continue autosave cycle binh thuong.

## Slide and Video Flow

### Import slide/video package

1. User import `.eduvi`.
2. Parse manifest + integrity checks.
3. Package manager resolve local paths cho assets.
4. Slide runtime load deck metadata.
5. Video runtime bind local media tracks.

### Manifest parse and local asset resolve

1. Parse required fields: package id/type/version/entries/assets/checksum.
2. Resolve asset path theo hash map va package version map.
3. Neu asset da co trong shared hash store -> link/reference, khong copy duplicate.

### Open slide deck flow

1. Read deck entry file local.
2. Build slide tree + block render list.
3. Lazy render current slide, preload next/previous slide assets.

### Play local video flow

1. Open local video file path from resolver.
2. Support seek/pause/resume with persisted last position.
3. Save playback state theo session checkpoint.

### Cache and preload strategy

1. Asset cache tiers
   - Memory LRU cache (small hot assets)
   - File hash store (dedupe persistent cache)

2. Preload policy
   - Slide N preload static assets cho N+1
   - Video preload metadata + first keyframe area

3. I/O batching
   - Group read requests theo folder locality
   - Async file reads with priority (current frame > next slide)

## Local Folder Design Options

### Option A: Type-segregated top-level store

Structure:
- packages/
- slides/
- videos/
- games/
- shared_assets/
- sessions/
- logs/

Pros:
1. Ranh mach theo runtime domain, de debug nhanh.
2. Metrics/cleanup theo loai noi dung de lam.
3. De map ownership module -> storage namespace.

Cons:
1. Can them mapping layer package->type folders.
2. Co kha nang duplicate metadata neu governance kem.

### Option B: Package-centric store + typed indexes

Structure:
- packages/<pkg>/<version>/all_content
- indexes/slides
- indexes/videos
- indexes/games
- shared_assets/
- sessions/
- logs/

Pros:
1. Atomic package rollback de hon.
2. Tang tinh toan ven package-level.

Cons:
1. Debug theo media type kho hon.
2. Typed index co the stale neu update loi.

### Recommended choice

Chon Option A (type-segregated) vi:
1. Yeu cau bai toan uu tien de mo rong/de debug.
2. Team desktop thuong triage theo runtime domain (slide/video/game).
3. Dedupe theo hash van dat tai `shared_assets` nen khong ton dung luong du lieu trung.

## Recommended Folder Structure

Root: `%LOCALAPPDATA%/EduviOffline/`

- packages/
  - <package_id>/
    - <version>/
      - package.manifest.json
      - source.eduvi
      - map.asset.json

- slides/
  - <package_id>/<version>/
    - deck.json
    - rendered/

- videos/
  - <package_id>/<version>/
    - tracks/
    - thumbs/
    - state/

- games/
  - <package_id>/<version>/
    - runtime/
    - mediapipe_models/
    - game_payload.json

- shared_assets/
  - sha256/
    - ab/
      - cd/
        - <full_hash>.bin

- sessions/
  - <session_id>/
    - launch.contract.json
    - progress.snapshot.json
    - game.result.json
    - video.state.json

- logs/
  - app.log
  - mediapipe.log
  - crash/

### Dedupe by hash

1. Moi asset co `sha256` trong manifest.
2. Importer check `shared_assets/sha256/<hash>`:
   - Exists: tao reference map, khong copy lai.
   - Missing: copy asset vao hash store, verify post-write checksum.
3. package-level `map.asset.json` luu mapping logical asset -> hash path.

### Package versioning safety

1. Package install theo immutable path `<package_id>/<version>`.
2. Khong overwrite version cu.
3. Active version marker trong SQLite (`is_active`).
4. Loi import version moi => rollback, giu version active truoc do.

## Source Code Module Layout

Target desktop code layout:

- importer/
- package-manager/
- slide-runtime/
- video-runtime/
- mediapipe-runtime/
- session-store/
- telemetry-local/
- shared-contracts/

### Dependency direction (no cycle)

1. shared-contracts -> no deps
2. importer -> shared-contracts + package-manager
3. package-manager -> shared-contracts + session-store(fs/sqlite)
4. slide-runtime -> shared-contracts + package-manager + session-store
5. video-runtime -> shared-contracts + package-manager + session-store
6. mediapipe-runtime -> shared-contracts + package-manager + session-store + telemetry-local
7. telemetry-local -> shared-contracts + session-store

Rule:
- Runtime modules khong duoc depend truc tiep vao nhau.
- App composition root la noi duy nhat wire cac modules.

## Contracts and Schemas

### PackageManifest (minimum)

    export interface PackageManifest {
      manifestVersion: string;
      packageId: string;
      packageVersion: string;
      packageType: 'slide' | 'game';
      title: string;
      entry: {
        slideDeckPath?: string;
        gamePayloadPath?: string;
        gameRuntimeEntry?: string;
      };
      assets: Array<{
        assetId: string;
        mediaType: 'image' | 'video' | 'audio' | 'model' | 'other';
        relativePath: string;
        sha256: string;
        bytes: number;
      }>;
      integrity: {
        packageSha256: string;
        offlineReady: boolean;
      };
    }

### MediaPipeSession

    export interface MediaPipeSession {
      sessionId: string;
      packageId: string;
      packageVersion: string;
      mode: 'new' | 'resume';
      state: 'created' | 'running' | 'paused' | 'completed' | 'crashed';
      startedAt: string;
      updatedAt: string;
      lastSnapshotId?: string;
      fps: {
        capture: number;
        inference: number;
        render: number;
      };
      droppedFrames: number;
    }

### SlideDeck

    export interface SlideDeck {
      deckId: string;
      packageId: string;
      title: string;
      slides: Array<{
        slideId: string;
        blocks: Array<{
          type: string;
          contentPath?: string;
          html?: string;
        }>;
      }>;
    }

### VideoTrack

    export interface VideoTrack {
      trackId: string;
      packageId: string;
      assetHash: string;
      localPath: string;
      durationMs: number;
      codec?: string;
      width?: number;
      height?: number;
      lastPositionMs?: number;
    }

### GameResult

    export interface GameResult {
      resultId: string;
      sessionId: string;
      packageId: string;
      status: 'completed' | 'failed' | 'aborted';
      score: number;
      durationMs: number;
      accuracy?: number;
      completedAt: string;
      detail?: Record<string, unknown>;
    }

### Mapping manifest -> local path

1. package root = `packages/<packageId>/<packageVersion>/`
2. logical asset path => hash path trong `shared_assets/sha256/...`
3. runtime resolver tra ve absolute path theo `map.asset.json`

### Integrity and fallback rules

1. Import-time verify:
   - package sha256
   - moi asset sha256
2. Runtime-time verify lazy:
   - truoc khi play video/load model
3. Fallback:
   - Slide missing image/video: show placeholder + warning block
   - Video missing file: disable player + show local error panel
   - Game missing model: block start game, suggest re-import package

## Implementation Skeleton

### File list skeleton (core)

- importer/
  - import-controller.ts
  - manifest-parser.ts
  - checksum-validator.ts

- package-manager/
  - install-service.ts
  - path-resolver.ts
  - asset-dedupe-store.ts

- slide-runtime/
  - slide-engine.ts
  - slide-preload-cache.ts

- video-runtime/
  - video-engine.ts
  - video-state-store.ts

- mediapipe-runtime/
  - main-process-bridge.ts
  - renderer-game-loop.ts
  - worker-inference.ts
  - frame-queue.ts

- session-store/
  - sqlite-store.ts
  - snapshot-repo.ts
  - result-repo.ts

- telemetry-local/
  - metrics-recorder.ts
  - local-log-writer.ts

### Pseudocode: import package

    function importPackage(filePath): ImportedPackage {
      raw = readFile(filePath)
      manifest = parseManifest(raw)
      verifyPackageChecksum(raw, manifest.integrity.packageSha256)

      tempDir = createTempInstallDir(manifest.packageId, manifest.packageVersion)
      writeSourceEduvi(tempDir, raw)

      for asset in manifest.assets:
        bytes = readAssetFromPayload(raw, asset.relativePath)
        verifyAssetChecksum(bytes, asset.sha256)
        hashPath = putOrReuseSharedAsset(bytes, asset.sha256)
        mapAsset(tempDir, asset.assetId, hashPath)

      atomicallyPromoteTempDir(tempDir, finalPackageDir)
      savePackageRecordSqlite(manifest)
      return packageRecord
    }

### Pseudocode: launch mediapipe game

    function launchMediaPipeGame(packageRecord, mode): Session {
      session = createSession(packageRecord.packageId, mode)
      contract = buildLaunchContract(packageRecord.path, session.id, session.outputDir, mode)
      writeLaunchContract(contract)
      spawnElectronProcess(contract.path)
      markSessionRunning(session.id)
      return session
    }

### Pseudocode: save snapshot

    function saveSnapshot(sessionId, state): void {
      snapshot = buildSnapshot(sessionId, state)
      checksum = sha256(snapshot.payload)
      snapshot.checksumSha256 = checksum

      writeJsonAtomic(sessionOutputDir(sessionId) + '/progress.snapshot.json', snapshot)
      upsertSnapshotSqlite(snapshot)
      updateSessionLastSnapshot(sessionId, snapshot.snapshotId)
    }

### Pseudocode: resume session

    function resumeSession(): SessionState {
      session = getLatestResumableSession()
      snapshot = getLatestValidSnapshot(session.id)

      if (!snapshot) {
        return startNewSession(session.packageId)
      }

      if (!verifySnapshotChecksum(snapshot)) {
        snapshot = getPreviousValidSnapshot(session.id)
      }

      contract = buildLaunchContract(session.packagePath, session.id, session.outputDir, 'resume')
      spawnElectronProcess(contract.path)
      return restoreState(snapshot)
    }

## Test Plan

### Unit tests

1. Manifest parser tests
   - Parse slide manifest valid
   - Parse game manifest valid
   - Reject missing required fields

2. Path resolver tests
   - Resolve local path from asset hash
   - Resolve package version path
   - Fallback mapping behavior

3. Checksum tests
   - Accept correct checksum
   - Reject mismatch checksum

### Integration tests (offline only)

1. import -> open slide -> play local video -> save playback state
2. import -> open game -> run inference loop mock -> autosave -> save result
3. import -> open game -> force close -> resume from snapshot

### Crash recovery test

1. Start game session.
2. Force kill Electron process during running.
3. Reopen Flutter shell.
4. Resume same session.
5. Verify score/timer/checkpoint restored from latest valid snapshot.

### Test matrix by package type

1. Slide package matrix
   - plain slides
   - slides with local video
   - slides with missing asset fallback

2. Game package matrix
   - metadata.packageType game
   - games[] payload format
   - model file missing fallback
   - low FPS/drop-frame stability

### Offline guarantee checks

1. Disable network adapter and run full suite.
2. Assert no outbound HTTP/HTTPS from Electron runtime.
3. Assert all assets resolved from local path only.

## Risks and Mitigations

1. Risk: inference latency spike tren may yeu.
   - Mitigation: adaptive resolution + frame skipping + latest-frame policy.

2. Risk: package corruption lam loi runtime.
   - Mitigation: strict import-time checksum + atomic install + rollback.

3. Risk: duplicated assets phinh disk usage.
   - Mitigation: hash-based content-addressable shared asset store.

4. Risk: renderer crash khi inference loop overload.
   - Mitigation: move heavy inference sang worker, limit pending jobs = 1.

5. Risk: local data loss khi app bi kill.
   - Mitigation: autosave interval + milestone save + atomic write + snapshot fallback.

6. Risk: security issue tu renderer surface.
   - Mitigation: contextIsolation on, nodeIntegration off, preload whitelist, block remote navigation/request.

## Sprint Execution Checklist

### Sprint 0 - Foundation (3-4 ngay)

Objective:
- On dinh nen tang desktop offline va chot contract data.

Owners:
- Principal Desktop Architect
- Senior Electron Engineer
- Senior Flutter Engineer

Checklist:
- [ ] Chot PackageManifest, LaunchContract, ProgressSnapshot, GameResult.
- [ ] Chot local storage root + folder namespaces + hash dedupe strategy.
- [ ] Chot SQLite schema va migration strategy.
- [ ] Chot security baseline Electron (contextIsolation, nodeIntegration, preload whitelist).
- [ ] Chot baseline benchmark: import latency, launch latency, inference latency.

Exit criteria:
- [ ] Architecture doc approved.
- [ ] Contracts compile in shared types package.
- [ ] SQLite schema migration runs clean on fresh machine.

### Sprint 1 - Importer + Package Manager + Session Store (5-7 ngay)

Objective:
- Import package offline an toan, co integrity check, co rollback.

Owners:
- Senior Flutter Engineer (import UI + integration)
- Senior Desktop Engineer (filesystem + sqlite)

Checklist:
- [ ] Implement manifest parser + package classifier (slide/game).
- [ ] Implement package checksum verifier.
- [ ] Implement atomic install flow: temp write -> validate -> promote -> rollback.
- [ ] Implement asset hash dedupe store.
- [ ] Implement package/session repositories (SQLite).
- [ ] Implement resume session query APIs.

Exit criteria:
- [ ] Unit tests parser/checksum/path resolver pass.
- [ ] Integration import/install flow pass in offline mode.
- [ ] Corrupted package test triggers rollback correctly.

### Sprint 2 - Slide Runtime + Video Runtime (5-7 ngay)

Objective:
- Chay slide/video muot va on dinh khi offline.

Owners:
- Senior Flutter Engineer
- Senior Desktop Media Engineer

Checklist:
- [ ] Implement slide deck loader from local package map.
- [ ] Implement block renderer fallback khi thieu asset.
- [ ] Implement video runtime local playback (play/pause/seek/resume).
- [ ] Persist video playback state into session output.
- [ ] Implement memory LRU cache + adjacent slide preload.

Exit criteria:
- [ ] Slide package matrix tests pass.
- [ ] Video seek/resume tests pass.
- [ ] No remote URL dependency in playback path.

### Sprint 3 - MediaPipe Runtime (Electron) (7-10 ngay)

Objective:
- Van hanh game MediaPipe offline, fps on dinh, autosave an toan.

Owners:
- Senior Electron Engineer
- Senior CV/Media Engineer

Checklist:
- [ ] Implement Electron main/preload/renderer/worker boundaries.
- [ ] Implement source eduvi game payload reader.
- [ ] Implement frame pipeline: capture -> preprocess -> inference -> tick -> render.
- [ ] Implement adaptive FPS + drop-frame strategy + smoothing.
- [ ] Implement autosave interval + milestone save.
- [ ] Implement game result writer + session state transitions.
- [ ] Implement runtime hardening + network blocking policy.

Exit criteria:
- [ ] Game package matrix tests pass.
- [ ] Inference worker stress test pass (no crash, no unbounded queue).
- [ ] Crash recovery test restores latest valid snapshot.

### Sprint 4 - Reliability + Offline QA + Packaging (4-6 ngay)

Objective:
- Chot do on dinh va release artifact dung cho end-user.

Owners:
- QA Lead (offline scenario)
- Release Engineer
- Principal Desktop Architect

Checklist:
- [ ] Run full offline test suite with network adapters disabled.
- [ ] Run long-session stability test (>= 30 phut inference loop).
- [ ] Run repeated import/remove package cycles for storage consistency.
- [ ] Validate telemetry local logs rotation.
- [ ] Build release bundle and embed electron runtime executable.
- [ ] Create portable zip + installer artifact.

Exit criteria:
- [ ] All unit/integration/crash recovery tests pass.
- [ ] Release artifact opens slide + game offline with no manual patch.
- [ ] Checklist security baseline verified.

## Work Breakdown with Estimates

| Workstream | Estimate | Owner Role | Notes |
|---|---:|---|---|
| Contracts and schema finalization | 2 ngay | Principal Architect | Lock interfaces before code freeze |
| Import + integrity + rollback | 3 ngay | Senior Desktop Engineer | Highest impact to data safety |
| Slide runtime and asset resolver | 3 ngay | Senior Flutter Engineer | Prioritize rendering consistency |
| Video runtime with local state | 2 ngay | Media Engineer | Include seek/resume tests |
| Electron process architecture | 2 ngay | Senior Electron Engineer | Main/preload/renderer boundaries |
| MediaPipe worker pipeline | 3 ngay | CV Engineer | Adaptive fps and frame dropping |
| Autosave and resume state machine | 2 ngay | Senior Desktop Engineer | Atomic write required |
| Offline QA matrix and crash tests | 2 ngay | QA Lead | Run with network disabled |
| Packaging and release hardening | 2 ngay | Release Engineer | Bundle electron runtime with app |

## Definition of Done

- [ ] Slide package opens and runs fully offline.
- [ ] Game package opens and runs fully offline via Electron.
- [ ] MediaPipe models/assets load from local path only.
- [ ] Snapshot and result are persisted locally and recoverable.
- [ ] Crash during game can resume from latest valid state.
- [ ] No outbound network calls in production runtime path.
