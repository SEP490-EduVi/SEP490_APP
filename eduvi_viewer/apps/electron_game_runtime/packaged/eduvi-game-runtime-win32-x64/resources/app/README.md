# Electron Game Runtime (Offline Only)

## Security defaults
- `contextIsolation: true`
- `nodeIntegration: false`
- `sandbox: true`
- Preload API is whitelist-only
- HTTP/HTTPS requests are blocked at runtime

## Launch
Flutter launches this runtime with:

```txt
--launch-contract=<absolute path to launch.contract.json>
```

Launch contract required fields:
- `packagePath`
- `sessionId`
- `outputDir`
- `mode`

## Runtime outputs (local only)
- `progress.snapshot.json`
- `game.result.json`
