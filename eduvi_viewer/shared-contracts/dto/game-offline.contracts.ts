export type EduviPackageType = 'slide' | 'game';

export type SessionMode = 'new' | 'resume';

export type SessionState =
  | 'created'
  | 'running'
  | 'paused'
  | 'completed'
  | 'crashed';

export interface EduviAssetEntry {
  path: string;
  sha256: string;
  size: number;
}

export interface EduviManifest {
  schemaVersion: string;
  packageId: string;
  packageType: EduviPackageType;
  title: string;
  version: string;
  entryFile: string;
  checksumSha256: string;
  assets: EduviAssetEntry[];
  metadata?: {
    createdAt?: string;
    updatedAt?: string;
    description?: string;
  };
  gameRuntime?: {
    engine: 'mediapipe-web';
    engineVersion: string;
    assetBaseDir: string;
    requiredModels: string[];
  };
}

export interface LaunchContract {
  packagePath: string;
  sessionId: string;
  outputDir: string;
  mode: SessionMode;
}

export interface ProgressSnapshotJson {
  snapshotId: string;
  sessionId: string;
  packageId: string;
  levelId: string;
  checkpoint?: string;
  score: number;
  timerMsRemaining: number;
  state: Record<string, unknown>;
  createdAt: string;
  checksumSha256: string;
}

export interface GameResultJson {
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

export interface PackageRecord {
  packageId: string;
  packageType: EduviPackageType;
  version: string;
  sourceFilePath: string;
  installPath: string;
  checksumSha256: string;
  installedAt: string;
  lastOpenedAt?: string;
}

export interface SessionRecord {
  sessionId: string;
  packageId: string;
  mode: SessionMode;
  state: SessionState;
  startedAt: string;
  endedAt?: string;
  lastSnapshotId?: string;
  crashRecovered: boolean;
}
