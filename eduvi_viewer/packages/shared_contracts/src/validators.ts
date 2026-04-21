import { GameResultJson } from './game-result';
import { LaunchContract } from './launch-contract';
import { ProgressSnapshotJson } from './progress-snapshot';

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object';
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

export function isLaunchContract(value: unknown): value is LaunchContract {
  if (!isObject(value)) return false;

  return (
    nonEmptyString(value.packagePath) &&
    nonEmptyString(value.sessionId) &&
    nonEmptyString(value.outputDir) &&
    (value.mode === 'new' || value.mode === 'resume')
  );
}

export function isProgressSnapshot(value: unknown): value is ProgressSnapshotJson {
  if (!isObject(value)) return false;

  return (
    nonEmptyString(value.snapshotId) &&
    nonEmptyString(value.sessionId) &&
    nonEmptyString(value.packageId) &&
    nonEmptyString(value.levelId) &&
    Number.isFinite(value.score) &&
    Number.isFinite(value.timerMsRemaining) &&
    isObject(value.state) &&
    nonEmptyString(value.createdAt) &&
    nonEmptyString(value.checksumSha256)
  );
}

export function isGameResult(value: unknown): value is GameResultJson {
  if (!isObject(value)) return false;

  return (
    nonEmptyString(value.resultId) &&
    nonEmptyString(value.sessionId) &&
    nonEmptyString(value.packageId) &&
    (value.status === 'completed' || value.status === 'failed' || value.status === 'aborted') &&
    Number.isFinite(value.score) &&
    Number.isFinite(value.durationMs) &&
    nonEmptyString(value.completedAt)
  );
}
