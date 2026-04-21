const asar = require("@electron/asar");
const fs = require("fs");

function listAsarContent(filePath) {
  console.log("--- Listing: " + filePath + " ---");
  if (!fs.existsSync(filePath)) {
    console.log("File NOT FOUND");
    return;
  }
  try {
    const filenames = asar.listPackage(filePath);
    console.log("Total files:", filenames.length);
    console.log("Top 20 files:");
    console.log(filenames.slice(0, 20).join("\n"));
  } catch (err) {
    console.log("Error listing asar:", err.message);
  }
}

listAsarContent("D:/2026/game-runtime/resources/app.asar");
listAsarContent("d:/2026/SEP490-APP/SEP490_APP/eduvi_viewer/build/windows/x64/runner/Release/game-runtime/resources/app.asar");
