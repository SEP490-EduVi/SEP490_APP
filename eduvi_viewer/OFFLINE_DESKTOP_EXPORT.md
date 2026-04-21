# OFFLINE DESKTOP EXPORT (READY-TO-USE)

## 1) Muc tieu

Xay dung desktop app offline 100%:
- Import file `.eduvi` thu cong.
- Neu la slide: mo va trinh chieu offline bang Flutter.
- Neu la game: launch ElectronJS runtime offline, tai su dung mediapipe runtime local.
- Khong API, khong cloud sync, khong network dependency.
- Progress/result chi luu local.

## 2) Kien truc tong the

- Flutter shell:
  - Import + validate `.eduvi`
  - Phan loai `slide` / `game`
  - Slide thi mo PresentationScreen
  - Game thi tao launch contract va goi Electron process

- Electron game runtime:
  - Doc launch contract
  - Mo runtime entry local
  - Autosave snapshot local
  - Ghi result local khi ket thuc

- Local storage:
  - SQLite: metadata package/session/snapshot/result/settings
  - File system: package extracted, launch contract, snapshot/result json, logs

## 3) Luong offline chi tiet

1. Import `.eduvi`
- User chon file trong Flutter.
- Parse JSON + classify package type.
- Tinh checksum SHA256.

2. Validate package
- Kiem tra field can thiet.
- Kiem tra checksum neu manifest co khai bao.
- Neu sai -> reject.

3. Extract package local
- Copy vao temp.
- Tao `package.manifest.json` local.
- Atomic rename sang folder active.
- Loi -> rollback ve ban truoc.

4. Open slide
- Parse schema va mo bang Flutter renderer.

5. Open game
- Tao session local.
- Tao launch contract json.
- Launch Electron voi `--launch-contract=<path>`.

6. Autosave progress
- Electron ghi `progress.snapshot.json` dinh ky.
- Flutter ingest snapshot metadata vao DB.

7. Save result
- Electron ghi `game.result.json`.
- Flutter ingest vao bang `game_results`.

8. Resume
- Flutter lay latest resumable session.
- Launch Electron mode `resume`.

## 4) Cau truc thu muc da tao

- `lib/features/offline_core/domain`
- `lib/features/offline_core/services`
- `test/offline`
- `apps/electron_game_runtime`
- `apps/flutter_player` (module scaffold)
- `packages/shared_contracts`
- `packages/eduvi_schema`
- `shared-contracts` (doc contracts/schema)

## 5) SQLite schema toi thieu

Da co file SQL:
- `shared-contracts/schema/offline-sync.sqlite.sql`

Bang bat buoc:
- `packages`
- `sessions`
- `progress_snapshots`
- `game_results`
- `app_settings`

Key/index da co:
- PK theo package/session/snapshot/result/setting key
- FK sessions -> packages, snapshots -> sessions/packages, results -> sessions/packages
- Index cho lookup package active, latest session, latest snapshot, latest result

## 6) Contracts

### Launch contract (Flutter -> Electron)

```json
{
  "packagePath": "D:/EduviOffline/packages/pkg_math_001/1.2.0",
  "sessionId": "pkg_math_001_1710000000",
  "outputDir": "D:/EduviOffline/sessions/pkg_math_001_1710000000",
  "mode": "resume",
  "entryFile": "runtime/index.html"
}
```

### Progress snapshot

```json
{
  "snapshotId": "snap_01",
  "sessionId": "ses_01",
  "packageId": "pkg_math_001",
  "levelId": "level_3",
  "checkpoint": "cp_7",
  "score": 640,
  "timerMsRemaining": 43000,
  "state": {"combo": 4, "lives": 2},
  "createdAt": "2026-04-20T10:21:00Z",
  "checksumSha256": "..."
}
```

### Game result

```json
{
  "resultId": "res_01",
  "sessionId": "ses_01",
  "packageId": "pkg_math_001",
  "status": "completed",
  "score": 920,
  "durationMs": 185000,
  "accuracy": 0.94,
  "completedAt": "2026-04-20T10:30:00Z",
  "detail": {"correct": 47, "wrong": 3}
}
```

## 7) Electron hardening

Da bat/toi uu trong runtime:
- `contextIsolation: true`
- `nodeIntegration: false`
- `sandbox: true`
- Preload whitelist IPC API
- Chan HTTP/HTTPS request tai runtime

## 8) Cac file implementation chinh

Flutter offline core:
- `lib/features/offline_core/services/eduvi_package_classifier.dart`
- `lib/features/offline_core/services/eduvi_import_service.dart`
- `lib/features/offline_core/services/local_database_service.dart`
- `lib/features/offline_core/services/game_session_manager.dart`
- `lib/screens/home_screen.dart`

Electron runtime:
- `apps/electron_game_runtime/electron-main/app.ts`
- `apps/electron_game_runtime/electron-main/launch-contract-reader.ts`
- `apps/electron_game_runtime/electron-preload/index.ts`
- `apps/electron_game_runtime/mediapipe-runtime/web-runtime/index.html`

Contracts/schema:
- `shared-contracts/dto/game-offline.contracts.ts`
- `shared-contracts/validators/game-contract.validators.ts`
- `shared-contracts/schema/offline-sync.sqlite.sql`

## 9) Cac test da tao

- `test/offline/eduvi_package_classifier_test.dart`
- `test/offline/local_database_service_test.dart`
- `test/offline/offline_import_launch_result_integration_test.dart`

## 10) Lenh chay nhanh

### Flutter

```bash
flutter pub get
flutter test test/offline/eduvi_package_classifier_test.dart
flutter test test/offline/local_database_service_test.dart
flutter test test/offline/offline_import_launch_result_integration_test.dart
```

### Electron runtime

```bash
cd apps/electron_game_runtime
npm install
npm run build
```

Sau do dat bien moi truong cho Flutter launch:
- `EDUVI_ELECTRON_EXE=<duong_dan_toi_eduvi-game-runtime.exe>`

## 11) Crash recovery checklist

- Dang choi game, force close process Electron.
- Mo lai app Flutter.
- Lay latest resumable session.
- Launch mode `resume`.
- Verify snapshot moi nhat duoc load.

## 12) Ghi chu quan trong

- Hien tai `.eduvi` sample trong repo la plain JSON (khong phai zip archive).
- Runtime mediapipe that tu web co the duoc copy vao package local va duoc uu tien load qua `entryFile`.
- Neu khong co `entryFile` hop le, runtime fallback se mo trang local shell offline.
