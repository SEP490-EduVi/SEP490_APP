import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export type LaunchMode = 'new' | 'resume';

export interface LaunchContract {
  packagePath: string;
  sessionId: string;
  outputDir: string;
  mode: LaunchMode;
  entryFile?: string;
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

export function readLaunchContract(contractPath: string): LaunchContract {
  const raw = readFileSync(contractPath, 'utf8');
  const parsed = JSON.parse(raw) as Record<string, unknown>;

  if (!isNonEmptyString(parsed.packagePath)) {
    throw new Error('Invalid launch contract: packagePath is required');
  }
  if (!isNonEmptyString(parsed.sessionId)) {
    throw new Error('Invalid launch contract: sessionId is required');
  }
  if (!isNonEmptyString(parsed.outputDir)) {
    throw new Error('Invalid launch contract: outputDir is required');
  }

  const mode = parsed.mode;
  if (mode !== 'new' && mode !== 'resume') {
    throw new Error('Invalid launch contract: mode must be new or resume');
  }

  return {
    packagePath: resolve(String(parsed.packagePath)),
    sessionId: String(parsed.sessionId),
    outputDir: resolve(String(parsed.outputDir)),
    mode,
    entryFile: isNonEmptyString(parsed.entryFile) ? String(parsed.entryFile) : undefined,
  };
}

export function extractLaunchContractPath(argv: string[]): string {
  const token = argv.find((item) => item.startsWith('--launch-contract='));
  if (!token) {
    throw new Error('Missing --launch-contract argument');
  }

  const value = token.replace('--launch-contract=', '').trim();
  if (!value) {
    throw new Error('Launch contract path cannot be empty');
  }

  return resolve(value);
}
