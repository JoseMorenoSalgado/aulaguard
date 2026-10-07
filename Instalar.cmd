@echo off
setlocal

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo AulaGuard debe instalarse como administrador.
    echo Haga clic derecho sobre Instalar.cmd y seleccione "Ejecutar como administrador".
    pause
    exit /b 1
)

set "TARGET=%ProgramData%\AulaGuard"
set "SRC=%~dp0"

echo.
echo Instalando AulaGuard v0.2.0 en:
echo %TARGET%
echo.

if not exist "%TARGET%" mkdir "%TARGET%"
if not exist "%TARGET%\src" mkdir "%TARGET%\src"
if not exist "%TARGET%\config" mkdir "%TARGET%\config"
if not exist "%TARGET%\logs" mkdir "%TARGET%\logs"
if not exist "%TARGET%\backup" mkdir "%TARGET%\backup"
if not exist "%TARGET%\profiles" mkdir "%TARGET%\profiles"

copy /Y "%SRC%src\AulaGuard.ps1" "%TARGET%\src\AulaGuard.ps1" >nul
copy /Y "%SRC%src\AulaGuard.Core.psm1" "%TARGET%\src\AulaGuard.Core.psm1" >nul
copy /Y "%SRC%src\AulaGuard.Policy.psm1" "%TARGET%\src\AulaGuard.Policy.psm1" >nul
copy /Y "%SRC%src\AulaGuard.Diagnostics.psm1" "%TARGET%\src\AulaGuard.Diagnostics.psm1" >nul
copy /Y "%SRC%config\default.json" "%TARGET%\config\default.json" >nul

if not exist "%TARGET%\config\settings.json" (
    copy /Y "%SRC%config\default.json" "%TARGET%\config\settings.json" >nul
)

set "LINK=%Public%\Desktop\AulaGuard.lnk"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%LINK%'); $s.TargetPath = 'powershell.exe'; $s.Arguments = '-NoProfile -ExecutionPolicy Bypass -File ""%TARGET%\src\AulaGuard.ps1""'; $s.WorkingDirectory = '%TARGET%'; $s.IconLocation = 'shell32.dll,47'; $s.Save()"

echo.
echo Instalacion completada.
echo AulaGuard fue instalado con su motor modular de politicas y diagnostico.
echo.
pause
endlocal
