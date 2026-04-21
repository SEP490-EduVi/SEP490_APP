const asar = require("@electron/asar");
const fs = require("fs");
const path = require("path");

function analyzeAsar(filePath) {
  console.log("--- Analyzing: " + filePath + " ---");
  if (!fs.existsSync(filePath)) {
    console.log("File NOT FOUND");
    return;
  }

  const tempDir = "temp_asar_extract_" + Date.now();
  if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir);

  try {
    asar.extractAll(filePath, tempDir);
    
    function checkFile(relPath) {
        const full = path.join(tempDir, relPath);
        if (fs.existsSync(full)) {
            const content = fs.readFileSync(full, "utf8");
            if (relPath.endsWith("index.html")) {
                const csp = content.match(/<meta http-equiv=\"Content-Security-Policy\".*?>/i);
                console.log("CSP:", csp ? csp[0] : "Not found");
            } else if (relPath.endsWith("renderer.js")) {
                console.log("renderer.js contains 'Contract mode — auto-starting game':", content.includes("Contract mode — auto-starting game"));
                console.log("renderer.js contains 'Engine init failed:':", content.includes("Engine init failed:"));
            } else if (relPath.endsWith("main.js")) {
                console.log("main.js contains 'get-launch-contract':", content.includes("get-launch-contract"));
                console.log("main.js contains 'read-source-eduvi':", content.includes("read-source-eduvi"));
            }
        } else {
            console.log(relPath + ": Not found");
        }
    }

    checkFile("src/renderer/index.html");
    checkFile("src/renderer/renderer.js");
    checkFile("src/main/main.js");

  } catch (err) {
    console.log("Error:", err.message);
  } finally {
    try { fs.rmSync(tempDir, { recursive: true, force: true }); } catch(e) {}
  }
}

analyzeAsar("D:/2026/game-runtime/resources/app.asar");
analyzeAsar("d:/2026/SEP490-APP/SEP490_APP/eduvi_viewer/build/windows/x64/runner/Release/game-runtime/resources/app.asar");
