import { EduviManifest, EduviPackageType } from './eduvi-manifest';

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object';
}

export function classifyPackageType(manifest: EduviManifest): EduviPackageType {
  const declaredType = manifest.packageType?.trim().toLowerCase();
  if (declaredType === 'game') return 'game';
  if (declaredType === 'slide') return 'slide';

  if (manifest.gameRuntime && isObject(manifest.gameRuntime)) {
    return 'game';
  }

  if (Array.isArray(manifest.cards)) {
    return 'slide';
  }

  return 'slide';
}

export function parseEduviJson(raw: string): EduviManifest {
  const decoded: unknown = JSON.parse(raw);
  if (!isObject(decoded)) {
    throw new Error('Invalid eduvi payload: expected a JSON object');
  }

  const manifest = decoded as EduviManifest;
  manifest.packageType = classifyPackageType(manifest);
  return manifest;
}
