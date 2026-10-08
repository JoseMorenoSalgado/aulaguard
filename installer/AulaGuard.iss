#define MyAppName "AulaGuard"
#define MyAppVersion "0.3.3"
#define MyAppPublisher "Elearning Cloud"
#define MyAppURL "https://elearningcloud.io"
#define MyAppExeName "AulaGuard.exe"

[Setup]
AppId={{A8DC5E43-0E31-46BA-A8F3-463780F56C55}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\AulaGuard
DefaultGroupName=AulaGuard
DisableProgramGroupPage=yes
DisableWelcomePage=no
DisableReadyPage=no
DisableFinishedPage=no
PrivilegesRequired=admin
OutputDir=..\dist\installer
OutputBaseFilename=AulaGuard-Setup-v{#MyAppVersion}
SetupIconFile=..\build\AulaGuard.ico
WizardImageFile=..\build\WizardImage.bmp
WizardSmallImageFile=..\build\WizardSmallImage.bmp
UninstallDisplayIcon={app}\src\AulaGuard.exe
UninstallDisplayName=AulaGuard
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupLogging=yes
CloseApplications=yes
RestartApplications=yes
UsePreviousAppDir=yes
UsePreviousTasks=yes
ShowLanguageDialog=no
VersionInfoVersion=0.3.3.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Instalador de AulaGuard para aulas Windows
VersionInfoProductName={#MyAppName}
VersionInfoProductVersion={#MyAppVersion}

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"; Flags: checkedonce
Name: "startmenuicon"; Description: "Crear acceso directo en el menú Inicio"; GroupDescription: "Accesos directos:"; Flags: checkedonce
Name: "migratelegacy"; Description: "Migrar una configuración anterior REVISADA (la deja en modo auditoría)"; GroupDescription: "Seguridad de actualización:"; Flags: unchecked

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
Source: "..\src\AulaGuard.Security.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Initialize.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Core.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Policy.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Diagnostics.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.AppControl.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Startup.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\config\default.json"; DestDir: "{app}\config"; Flags: ignoreversion
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{commondesktop}\AulaGuard"; Filename: "{app}\src\AulaGuard.exe"; WorkingDir: "{app}"; IconFilename: "{app}\src\AulaGuard.exe"; Tasks: desktopicon
Name: "{group}\AulaGuard"; Filename: "{app}\src\AulaGuard.exe"; WorkingDir: "{app}"; IconFilename: "{app}\src\AulaGuard.exe"; Tasks: startmenuicon
Name: "{group}\Desinstalar AulaGuard"; Filename: "{uninstallexe}"; Tasks: startmenuicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\src\AulaGuard.Initialize.ps1"""; Flags: runhidden waituntilterminated; Tasks: not migratelegacy
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\src\AulaGuard.Initialize.ps1"" -MigrateLegacy"; Flags: runhidden waituntilterminated; Tasks: migratelegacy
Filename: "{sys}\schtasks.exe"; Parameters: "/Create /TN ""AulaGuard\PolicySync"" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR ""powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File \""{app}\src\AulaGuard.Startup.ps1\"""" /F"; Flags: runhidden waituntilterminated
Filename: "{app}\src\AulaGuard.exe"; Description: "Abrir AulaGuard ahora"; Flags: postinstall nowait skipifsilent

[UninstallRun]
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""AulaGuard\PolicySync"" /F"; Flags: runhidden; RunOnceId: "DeletePolicySync"

[Code]
procedure InitializeWizard;
begin
  WizardForm.Caption := 'Instalación de AulaGuard';
  WizardForm.WelcomeLabel1.Caption := 'Bienvenido a AulaGuard';
  WizardForm.WelcomeLabel2.Caption :=
    'AulaGuard ayuda a mantener los equipos del aula organizados, protegidos y listos para clase.' + #13#10 + #13#10 +
    'El instalador configurará la aplicación, los accesos directos y la sincronización de políticas de Windows.' + #13#10 + #13#10 +
    'Se requieren permisos de administrador.';
  WizardForm.FinishedHeadingLabel.Caption := 'AulaGuard está listo';
  WizardForm.FinishedLabel.Caption :=
    'La instalación se completó correctamente.' + #13#10 + #13#10 +
    'Tus configuraciones se almacenan de forma separada para conservarlas durante futuras actualizaciones.';
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
end;
