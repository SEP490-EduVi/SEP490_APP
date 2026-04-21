import {
  EduviManifest,
  LaunchContract,
  ProgressSnapshotJson,
  GameResultJson,
} from '../dto/game-offline.contracts';

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value != null && typeof value === 'object';
}

function isManifest(value: unknown): value is EduviManifest {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const candidate = value as EduviManifest;

  if (candidate.packageType !== 'slide' && candidate.packageType !== 'game') {
    return false;
  }

  if (!Array.isArray(candidate.assets)) {
    return false;
  }

  for (const asset of candidate.assets) {
    if (!isObject(asset)) {
      return false;
    }

    if (
      !isNonEmptyString(asset.path) ||
      !isNonEmptyString(asset.sha256) ||
      !Number.isFinite(asset.size)
    ) {
      return false;
    }
  }

  return (
    isNonEmptyString(candidate.schemaVersion) &&
    isNonEmptyString(candidate.packageId) &&
    isNonEmptyString(candidate.title) &&
    isNonEmptyString(candidate.version) &&
    isNonEmptyString(candidate.entryFile) &&
    isNonEmptyString(candidate.checksumSha256)
  );
}

export function isValidEduviManifest(value: unknown): value is EduviManifest {
  return isManifest(value);
}

export function isValidLaunchContract(value: unknown): value is LaunchContract {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const candidate = value as LaunchContract;

  return (
    isNonEmptyString(candidate.packagePath) &&
    isNonEmptyString(candidate.sessionId) &&
    isNonEmptyString(candidate.outputDir) &&
    (candidate.mode === 'new' || candidate.mode === 'resume')
  );
}

export function isValidSnapshot(value: unknown): value is ProgressSnapshotJson {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const candidate = value as ProgressSnapshotJson;

  return (
    isNonEmptyString(candidate.snapshotId) &&
    isNonEmptyString(candidate.sessionId) &&
    isNonEmptyString(candidate.packageId) &&
    isNonEmptyString(candidate.levelId) &&
    Number.isFinite(candidate.score) &&
    Number.isFinite(candidate.timerMsRemaining) &&
    isObject(candidate.state) &&
    isNonEmptyString(candidate.checksumSha256) &&
    isNonEmptyString(candidate.createdAt)
  );
}

export function isValidGameResult(value: unknown): value is GameResultJson {
  if (!value || typeof value !== 'object') {
    return false;
  }

  const candidate = value as GameResultJson;

  return (
    isNonEmptyString(candidate.resultId) &&
    isNonEmptyString(candidate.sessionId) &&
    isNonEmptyString(candidate.packageId) &&
    (candidate.status === 'completed' ||
      candidate.status === 'failed' ||
      candidate.status === 'aborted') &&
    Number.isFinite(candidate.score) &&
    Number.isFinite(candidate.durationMs) &&
    isNonEmptyString(candidate.completedAt)
  );
}
