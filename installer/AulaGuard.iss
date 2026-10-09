#define MyAppName "AulaGuard"
#define MyAppVersion "0.4.3"
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
VersionInfoVersion=0.4.3.0
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

[Files]
Source: "..\dist\AulaGuard.exe"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Launcher.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Security.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Initialize.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Core.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Policy.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.USB.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Wallpaper.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.InstalledApps.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Diagnostics.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.AppControl.psm1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\src\AulaGuard.Startup.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "..\config\default.json"; DestDir: "{app}\config"; Flags: ignoreversion
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{commondesktop}\AulaGuard"; Filename: "{app}\src\AulaGuard.exe"; WorkingDir: "{app}"; IconFilename: "{app}\src\AulaGuard.exe"; Tasks: desktopicon
Name: "{group}\AulaGuard"; Filename: "{app}\src\AulaGuard.exe"; WorkingDir: "{app}"; IconFilename: "{app}\src\AulaGuard.exe"; Tasks: startmenuicon
Name: "{group}\AulaGuard (inicio alternativo)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File ""{app}\src\AulaGuard.Launcher.ps1"""; WorkingDir: "{app}\src"; IconFilename: "{app}\src\AulaGuard.exe"; Tasks: startmenuicon
Name: "{group}\Desinstalar AulaGuard"; Filename: "{uninstallexe}"; Tasks: startmenuicon

[Run]
Filename: "{sys}\schtasks.exe"; Parameters: "/Create /TN ""AulaGuard\PolicySync"" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR ""powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File \""{app}\src\AulaGuard.Startup.ps1\"""" /F"; Flags: runhidden waituntilterminated
Filename: "{sys}\schtasks.exe"; Parameters: "/Create /TN ""AulaGuard\PolicySyncLogon"" /SC ONLOGON /RU SYSTEM /RL HIGHEST /TR ""powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File \""{app}\src\AulaGuard.Startup.ps1\"""" /F"; Flags: runhidden waituntilterminated
; The compiled EXE has requireAdministrator in its manifest. Inno Setup normally runs postinstall items under the original unelevated user: use runascurrentuser to retain elevation and avoid CreateProcess error 740.
Filename: "{app}\src\AulaGuard.exe"; Description: "Abrir AulaGuard ahora"; Flags: postinstall nowait skipifsilent runascurrentuser

[UninstallDelete]
; Inno removes all tracked installed files. These three application-owned directories
; also contain files left by older package versions, which otherwise prevent {app}
; from being removed. NEVER recursively delete {app} itself or ProgramData.
Type: filesandordirs; Name: "{app}\src"
Type: filesandordirs; Name: "{app}\docs"
Type: filesandordirs; Name: "{app}\config"

[UninstallRun]
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""AulaGuard\PolicySync"" /F"; Flags: runhidden waituntilterminated; RunOnceId: "DeletePolicySync"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""AulaGuard\PolicySyncLogon"" /F"; Flags: runhidden waituntilterminated; RunOnceId: "DeletePolicySyncLogon"

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

procedure CurStepChanged(CurStep: TSetupStep);
var
  Params: string;
  ResultCode: Integer;
  Started: Boolean;
begin
  if CurStep <> ssPostInstall then
    Exit;

  Params := '-NoProfile -ExecutionPolicy RemoteSigned -File "' +
    ExpandConstant('{app}\src\AulaGuard.Initialize.ps1') + '"';
  if IsTaskSelected('migratelegacy') then
    Params := Params + ' -MigrateLegacy';

  ResultCode := -1;
  Started := Exec(
    ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Params, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode
  );
  if (not Started) or (ResultCode <> 0) then
  begin
    MsgBox('No se pudo verificar o crear la configuración protegida de AulaGuard.' + #13#10 +
      'Revise docs\SECURITY.md antes de continuar.' + #13#10 +
      'Código de salida: ' + IntToStr(ResultCode),
      mbCriticalError, MB_OK);
    Abort;
  end;
end;
