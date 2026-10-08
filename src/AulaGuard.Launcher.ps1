$ErrorActionPreference = 'Stop'

# Fallback launcher for classrooms where PS2EXE packaging or execution is restricted.
$mainScript = Join-Path $PSScriptRoot 'AulaGuard.ps1'
if (-not (Test-Path -LiteralPath $mainScript -PathType Leaf)) {
    throw "No se encontró el archivo de inicio: $mainScript"
}

$powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -STA -ExecutionPolicy RemoteSigned -File "' + $mainScript + '"'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    & $powerShell -NoProfile -STA -ExecutionPolicy RemoteSigned -File $mainScript
    exit $LASTEXITCODE
}

Start-Process -FilePath $powerShell -ArgumentList $arguments -Verb RunAs -ErrorAction Stop
