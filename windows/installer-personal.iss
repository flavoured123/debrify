; Installer for "Debrify Personal" (the IPTV / Sports Hub mod).
; Separate AppId, folder, shortcuts and data from the official Debrify, so
; both can be installed side by side. It deliberately does NOT register the
; stremio:// magnet:// debrify:// link handlers - those stay with the
; official app.

#define AppVersion GetEnv("DEBRIFY_VERSION")
#if AppVersion == ""
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{5E0C7F3A-2B9D-4C61-9A47-D2F1B8C3E901}}
AppName=Debrify Personal
AppVersion={#AppVersion}
AppPublisher=Personal build
DefaultDirName={localappdata}\Programs\Debrify Personal
DisableDirPage=yes
DefaultGroupName=Debrify Personal
DisableProgramGroupPage=yes
; Per-user install: no administrator prompt needed.
PrivilegesRequired=lowest
OutputDir=..\build\windows\installer
OutputBaseFilename=Debrify-Personal-Setup
Compression=lzma
SolidCompression=yes
; x64 build. Also runs on Windows 11 on ARM through Windows' x64 emulation.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\DebrifyPersonal.exe
UninstallDisplayName=Debrify Personal
WizardStyle=modern

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Debrify Personal"; Filename: "{app}\DebrifyPersonal.exe"
Name: "{autodesktop}\Debrify Personal"; Filename: "{app}\DebrifyPersonal.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\DebrifyPersonal.exe"; Description: "Launch Debrify Personal"; Flags: nowait postinstall skipifsilent
