import { mkdirSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

function writeJsonAtomic(filePath: string, payload: unknown): void {
  const tempPath = `${filePath}.tmp`;
  const serialized = JSON.stringify(payload, null, 2);
  writeFileSync(tempPath, serialized, 'utf8');
  renameSync(tempPath, filePath);
}

export function writeProgressSnapshot(outputDir: string, payload: unknown): void {
  mkdirSync(outputDir, { recursive: true });
  writeJsonAtomic(join(outputDir, 'progress.snapshot.json'), payload);
}

export function writeGameResult(outputDir: string, payload: unknown): void {
  mkdirSync(outputDir, { recursive: true });
  writeJsonAtomic(join(outputDir, 'game.result.json'), payload);
}
