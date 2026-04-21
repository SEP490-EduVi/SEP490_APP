// scripts/download-mediapipe.js
const https = require('https');
const fs = require('fs');
const path = require('path');

const TASKS_VISION_VERSION = '0.10.18';
const BASE_CDN = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${TASKS_VISION_VERSION}/wasm`;
const MODEL_URL = 'https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';

const WASM_FILES = [
  'vision_wasm_internal.js',
  'vision_wasm_internal.wasm',
  'vision_wasm_nosimd_internal.js',
  'vision_wasm_nosimd_internal.wasm',
];

const wasmDir = path.join(__dirname, '..', 'assets', 'mediapipe', 'wasm');
const modelDir = path.join(__dirname, '..', 'assets', 'mediapipe', 'models');

function downloadFile(url, dest) {
  return new Promise((resolve, reject) => {
    console.log(`Downloading: ${url}`);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const file = fs.createWriteStream(dest);
    https.get(url, (response) => {
      if (response.statusCode === 301 || response.statusCode === 302) {
        file.close();
        fs.unlinkSync(dest);
        downloadFile(response.headers.location, dest).then(resolve).catch(reject);
        return;
      }
      if (response.statusCode !== 200) {
        file.close();
        fs.unlinkSync(dest);
        reject(new Error(`HTTP ${response.statusCode} for ${url}`));
        return;
      }
      response.pipe(file);
      file.on('finish', () => {
        file.close();
        const size = fs.statSync(dest).size;
        console.log(`  -> ${path.basename(dest)} (${(size / 1024 / 1024).toFixed(2)} MB)`);
        resolve();
      });
    }).on('error', (err) => {
      file.close();
      if (fs.existsSync(dest)) fs.unlinkSync(dest);
      reject(err);
    });
  });
}

async function main() {
  console.log('=== Downloading MediaPipe WASM files ===\n');
  for (const file of WASM_FILES) {
    await downloadFile(`${BASE_CDN}/${file}`, path.join(wasmDir, file));
  }

  console.log('\n=== Downloading MediaPipe Hand Landmarker model ===\n');
  await downloadFile(MODEL_URL, path.join(modelDir, 'hand_landmarker.task'));

  console.log('\nDone! All MediaPipe assets downloaded for offline use.');
}

main().catch(err => {
  console.error('Download failed:', err);
  process.exit(1);
});
