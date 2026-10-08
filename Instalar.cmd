@echo off
setlocal EnableExtensions
net session >nul 2>&1
if errorlevel 1 (
  echo ERROR: Abra Instalar.cmd mediante "Ejecutar como administrador".
  pause
  exit /b 1
)

set "TARGET=%ProgramData%\AulaGuard"
set "SRC=%~dp0"
echo Instalando AulaGuard v0.3.3 de forma protegida...

REM Secure ProgramData and create signed defaults BEFORE copying executable scripts there.
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%SRC%src\AulaGuard.Initialize.ps1"
if errorlevel 1 (
  echo ERROR: No se pudo inicializar la proteccion de AulaGuard.
  echo Si existe una configuracion anterior, consulte docs\SECURITY.md antes de migrar.
  pause
  exit /b 1
)

if not exist "%TARGET%\src" mkdir "%TARGET%\src"
for %%F in (AulaGuard.ps1 AulaGuard.Core.psm1 AulaGuard.Security.psm1 AulaGuard.Initialize.ps1 AulaGuard.Policy.psm1 AulaGuard.USB.psm1 AulaGuard.Diagnostics.psm1 AulaGuard.AppControl.psm1 AulaGuard.Startup.ps1) do (
  copy /Y "%SRC%src\%%F" "%TARGET%\src\%%F" >nul
  if errorlevel 1 (
    echo ERROR al copiar %%F
    pause
    exit /b 1
  )
)

REM Re-apply ACLs to the newly installed files.
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "Import-Module '%TARGET%\src\AulaGuard.Security.psm1' -Force; Protect-AulaGuardDataAcl -Root '%TARGET%'"
if errorlevel 1 exit /b 1

set "LINK=%Public%\Desktop\AulaGuard.lnk"
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -Command "$w = New-Object -ComObject WScript.Shell; $s = $w.CreateShortcut('%LINK%'); $s.TargetPath = 'powershell.exe'; $s.Arguments = '-NoProfile -ExecutionPolicy RemoteSigned -File ""%TARGET%\src\AulaGuard.ps1""'; $s.WorkingDirectory = '%TARGET%'; $s.Save()"
if errorlevel 1 exit /b 1

schtasks /Create /TN "AulaGuard\PolicySync" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR "powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File \"%TARGET%\src\AulaGuard.Startup.ps1\"" /F
if errorlevel 1 (
  echo ERROR al registrar tarea de arranque.
  pause
  exit /b 1
)

echo.
echo AulaGuard instalado. La configuracion y la bitacora se autentican con HMAC.
echo RECOMENDADO: Utilice el instalador grafico firmado para equipos en produccion.
pause
endlocal
