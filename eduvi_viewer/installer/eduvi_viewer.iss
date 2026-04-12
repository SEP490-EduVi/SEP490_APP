; Inno Setup script for EduVi Viewer
; Build release first: flutter build windows --release

#define MyAppName "EduVi Viewer"
#define MyAppVersion "1.1.0"
#define MyAppPublisher "EduVi"
#define MyAppExeName "eduvi_viewer.exe"
#define MyBuildOutput "..\\build\\windows\\x64\\runner\\Release"

[Setup]
AppId={{A1FD380A-3A0D-4D65-AE09-3A9FEAA4C1A0}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\\Programs\\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=.
OutputBaseFilename=EduViViewer-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "{#MyBuildOutput}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"
Name: "{group}\\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\\{#MyAppName}"; Filename: "{app}\\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; Register .eduvi file association
Root: HKCU; Subkey: "Software\\Classes\\.eduvi"; ValueType: string; ValueName: ""; ValueData: "EduViFile"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\EduViFile"; ValueType: string; ValueName: ""; ValueData: "EduVi File"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\EduViFile\\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\\{#MyAppExeName},0"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\EduViFile\\shell\\open\\command"; ValueType: string; ValueName: ""; ValueData: """{app}\\{#MyAppExeName}"" ""%1"""; Flags: uninsdeletekey

[Run]
Filename: "{app}\\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
