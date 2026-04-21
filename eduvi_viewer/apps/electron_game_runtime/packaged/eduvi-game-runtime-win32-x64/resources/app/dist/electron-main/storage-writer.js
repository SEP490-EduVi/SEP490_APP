"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.writeProgressSnapshot = writeProgressSnapshot;
exports.writeGameResult = writeGameResult;
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
function writeJsonAtomic(filePath, payload) {
    const tempPath = `${filePath}.tmp`;
    const serialized = JSON.stringify(payload, null, 2);
    (0, node_fs_1.writeFileSync)(tempPath, serialized, 'utf8');
    (0, node_fs_1.renameSync)(tempPath, filePath);
}
function writeProgressSnapshot(outputDir, payload) {
    (0, node_fs_1.mkdirSync)(outputDir, { recursive: true });
    writeJsonAtomic((0, node_path_1.join)(outputDir, 'progress.snapshot.json'), payload);
}
function writeGameResult(outputDir, payload) {
    (0, node_fs_1.mkdirSync)(outputDir, { recursive: true });
    writeJsonAtomic((0, node_path_1.join)(outputDir, 'game.result.json'), payload);
}
