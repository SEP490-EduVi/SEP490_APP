"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.readLaunchContract = readLaunchContract;
exports.extractLaunchContractPath = extractLaunchContractPath;
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
function isNonEmptyString(value) {
    return typeof value === 'string' && value.trim().length > 0;
}
function readLaunchContract(contractPath) {
    const raw = (0, node_fs_1.readFileSync)(contractPath, 'utf8');
    const parsed = JSON.parse(raw);
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
        packagePath: (0, node_path_1.resolve)(String(parsed.packagePath)),
        sessionId: String(parsed.sessionId),
        outputDir: (0, node_path_1.resolve)(String(parsed.outputDir)),
        mode,
        entryFile: isNonEmptyString(parsed.entryFile) ? String(parsed.entryFile) : undefined,
    };
}
function extractLaunchContractPath(argv) {
    const token = argv.find((item) => item.startsWith('--launch-contract='));
    if (!token) {
        throw new Error('Missing --launch-contract argument');
    }
    const value = token.replace('--launch-contract=', '').trim();
    if (!value) {
        throw new Error('Launch contract path cannot be empty');
    }
    return (0, node_path_1.resolve)(value);
}
