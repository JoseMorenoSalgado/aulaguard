param(
    [Parameter(Mandatory=$true)][string]$Path
)

$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Path).Path

# Do not embed credentials in source code or CI logs.
if ([string]::IsNullOrWhiteSpace($env:AULAGUARD_PFX_BASE64) -or
    [string]::IsNullOrWhiteSpace($env:AULAGUARD_PFX_PASSWORD)) {
    Write-Warning "Sin certificado de firma de código: $exe se distribuirá SIN firma Authenticode."
    return
}

$kitsRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10\bin'
$signtool = Get-ChildItem -LiteralPath $kitsRoot -Filter signtool.exe -File -Recurse -ErrorAction Stop |
    Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $signtool) { throw 'No se encontró Windows SDK SignTool x64.' }

$pfxPath = Join-Path $env:RUNNER_TEMP ('AulaGuardSigning-' + [guid]::NewGuid().ToString('N') + '.pfx')
try {
    [IO.File]::WriteAllBytes($pfxPath,[Convert]::FromBase64String($env:AULAGUARD_PFX_BASE64))
    & $signtool.FullName sign /fd SHA256 /f $pfxPath /p $env:AULAGUARD_PFX_PASSWORD /tr http://timestamp.digicert.com /td SHA256 $exe
    if ($LASTEXITCODE -ne 0) { throw "No se pudo firmar $exe." }
    & $signtool.FullName verify /pa $exe
    if ($LASTEXITCODE -ne 0) { throw "La firma Authenticode no se verifica: $exe." }
    Write-Host "Firma Authenticode verificada: $exe"
} finally {
    Remove-Item -LiteralPath $pfxPath -Force -ErrorAction SilentlyContinue
}
