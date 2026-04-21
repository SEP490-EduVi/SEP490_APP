"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveRuntimeEntry = resolveRuntimeEntry;
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
function resolveEntryFromManifest(packagePath) {
    const manifestPath = (0, node_path_1.join)(packagePath, 'package.manifest.json');
    if (!(0, node_fs_1.existsSync)(manifestPath)) {
        return null;
    }
    try {
        const manifest = JSON.parse((0, node_fs_1.readFileSync)(manifestPath, 'utf8'));
        if (!manifest.entryFile) {
            return null;
        }
        const candidate = (0, node_path_1.resolve)(packagePath, manifest.entryFile);
        return (0, node_fs_1.existsSync)(candidate) ? candidate : null;
    }
    catch {
        return null;
    }
}
function resolveRuntimeEntry(contract, bundledRuntimeEntry) {
    if (contract.entryFile) {
        const candidate = (0, node_path_1.resolve)(contract.packagePath, contract.entryFile);
        if ((0, node_fs_1.existsSync)(candidate)) {
            return candidate;
        }
    }
    const fromManifest = resolveEntryFromManifest(contract.packagePath);
    if (fromManifest) {
        return fromManifest;
    }
    return bundledRuntimeEntry;
}
