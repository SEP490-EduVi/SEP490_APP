export type EduviPackageType = 'slide' | 'game';

export interface EduviAssetEntry {
  path: string;
  sha256?: string;
  size?: number;
}

export interface EduviManifest {
  schemaVersion?: string;
  version?: string;
  packageId?: string;
  packageType?: EduviPackageType;
  title?: string;
  entryFile?: string;
  checksumSha256?: string;
  cards?: unknown[];
  assets?: EduviAssetEntry[] | Record<string, unknown>;
  gameRuntime?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}
