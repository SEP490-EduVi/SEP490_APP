# Installable Windows App Guide

This project can be distributed as an installable desktop app for end users.

## 1. Prerequisites on build machine

- Flutter SDK (stable)
- Visual Studio 2022 with these components:
  - Desktop development with C++
  - MSVC v142 - VS 2019 C++ x64/x86 build tools
  - C++ CMake tools for Windows
  - Windows 10 SDK
- Inno Setup 6 (for creating installer .exe)

## 2. Build release app

From project root:

```powershell
flutter clean
flutter pub get
flutter build windows --release
```

Release output folder:

```text
build/windows/x64/runner/Release
```

## 3. Create installer (.exe)

This repo includes Inno Setup script:

- installer/eduvi_viewer.iss

### Option A: GUI

1. Open Inno Setup Compiler.
2. Open file `installer/eduvi_viewer.iss`.
3. Click Compile.
4. Output installer is generated in `installer/`.

### Option B: Command line

```powershell
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\eduvi_viewer.iss
```

Installer output:

```text
installer/EduViViewer-Setup.exe
```

## 4. End-user flow

After user installs:

- Launch app from Start Menu or desktop shortcut.
- Click "Mo file .eduvi" or drag-drop file into app.
- Or double-click a `.eduvi` file in Explorer:
  - Installer registers `.eduvi` to open with EduVi Viewer.
  - App receives file path and opens it automatically.

## 5. Quick verification checklist

- Install the generated setup file.
- Start app and manually import one `.eduvi` file.
- Close app, then double-click `.eduvi` from Explorer.
- Confirm app opens and renders slides.

## 6. Notes

- If app icon or app metadata changes, update `installer/eduvi_viewer.iss` constants.
- Rebuild release before every installer compile.
