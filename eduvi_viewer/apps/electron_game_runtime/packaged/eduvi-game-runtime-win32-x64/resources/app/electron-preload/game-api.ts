export interface EduviGameApi {
  readLaunchContract: () => Promise<{
    packagePath: string;
    sessionId: string;
    outputDir: string;
    mode: 'new' | 'resume';
    entryFile?: string;
  }>;
  readSourceEduvi: () => Promise<Record<string, unknown> | null>;
  saveProgressSnapshot: (payload: unknown) => Promise<{ ok: true }>;
  saveGameResult: (payload: unknown) => Promise<{ ok: true }>;
}

declare global {
  interface Window {
    eduviGameApi: EduviGameApi;
  }
}
