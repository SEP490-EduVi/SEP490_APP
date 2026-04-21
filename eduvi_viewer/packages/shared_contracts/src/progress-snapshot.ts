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
