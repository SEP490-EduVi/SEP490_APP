export type GameResultStatus = 'completed' | 'failed' | 'aborted';

export interface GameResultJson {
  resultId: string;
  sessionId: string;
  packageId: string;
  status: GameResultStatus;
  score: number;
  durationMs: number;
  accuracy?: number;
  completedAt: string;
  detail?: Record<string, unknown>;
}
