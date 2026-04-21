import { existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { LaunchContract } from './launch-contract-reader';

interface PackageManifest {
  entryFile?: string;
}

function resolveEntryFromManifest(packagePath: string): string | null {
  const manifestPath = join(packagePath, 'package.manifest.json');
  if (!existsSync(manifestPath)) {
    return null;
  }

  try {
    const manifest = JSON.parse(readFileSync(manifestPath, 'utf8')) as PackageManifest;
    if (!manifest.entryFile) {
      return null;
    }

    const candidate = resolve(packagePath, manifest.entryFile);
    return existsSync(candidate) ? candidate : null;
  } catch {
    return null;
  }
}

export function resolveRuntimeEntry(
  contract: LaunchContract,
  bundledRuntimeEntry: string,
): string {
  if (contract.entryFile) {
    const candidate = resolve(contract.packagePath, contract.entryFile);
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  const fromManifest = resolveEntryFromManifest(contract.packagePath);
  if (fromManifest) {
    return fromManifest;
  }

  return bundledRuntimeEntry;
}
