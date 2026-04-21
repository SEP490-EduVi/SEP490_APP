export type LaunchMode = 'new' | 'resume';

export interface LaunchContract {
  packagePath: string;
  sessionId: string;
  outputDir: string;
  mode: LaunchMode;
  entryFile?: string;
}
