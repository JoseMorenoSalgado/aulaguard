#define MyAppName "AulaGuard"
#define MyAppVersion "0.3.0"
#define MyAppPublisher "Elearning Cloud"
#define MyAppExeName "AulaGuard.exe"

[Setup]
AppId={{A8DC5E43-0E31-46BA-A8F3-463780F56C55}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\AulaGuard
DefaultGroupName=AulaGuard
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\dist\installer
OutputBaseFilename=AulaGuard-Setup-v{#MyAppVersion}
SetupIconFile=..\build\AulaGuard.ico
UninstallDisplayIcon={app}\src\AulaGuard.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Dirs]
Name: "{app}\src"
Name: "{app}\config"
Name: "{app}\docs"
Name: "{commonappdata}\AulaGuard\config"
Name: "{commonappdata}\AulaGuard\logs"
Name: "{commonappdata}\AulaGuard\backup"
Name: "{commonappdata}\AulaGuard\profiles"

[Files]
Source: "..\dist\AulaGuard.exe"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Core.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Policy.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Diagnostics.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.AppControl.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Startup.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\config\default.json"; DestDir: "{app}\config"; Flags: ignoreversion
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{commondesktop}\AulaGuard"; Filename: "{app}\src\AulaGuard.exe"; WorkingDir: "{app}"; IconFilename: "{app}\src\AulaGuard.exe"
Name: "{group}\AulaGuard"; Filename: "{app}\src\AulaGuard.exe"; WorkingDir: "{app}"; IconFilename: "{app}\src\AulaGuard.exe"
Name: "{group}\Desinstalar AulaGuard"; Filename: "{uninstallexe}"

[Run]
Filename: "{cmd}"; Parameters: "/C if not exist ""{commonappdata}\AulaGuard\config\settings.json"" copy /Y ""{app}\config\default.json"" ""{commonappdata}\AulaGuard\config\settings.json"""; Flags: runhidden waituntilterminated
Filename: "{sys}\schtasks.exe"; Parameters: "/Create /TN ""AulaGuard\PolicySync"" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR ""powershell.exe -NoProfile -ExecutionPolicy Bypass -File \""{app}\src\AulaGuard.Startup.ps1\"""" /F"; Flags: runhidden waituntilterminated
Filename: "{app}\src\AulaGuard.exe"; Description: "Abrir AulaGuard"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""AulaGuard\PolicySync"" /F"; Flags: runhidden; RunOnceId: "DeletePolicySync"

[Code]
procedure InitializeWizard;
begin
  WizardForm.WelcomeLabel2.Caption :=
    'Este asistente instalará AulaGuard en el equipo y creará un acceso directo en el escritorio.' + #13#10 + #13#10 +
    'AulaGuard requiere permisos de administrador para configurar las políticas de Windows.';
end;
