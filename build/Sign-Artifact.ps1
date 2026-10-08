param(
    [Parameter(Mandatory=$true)][string]$Path
)

# Release signing requires a real code-signing certificate preinstalled on a
# dedicated, access-controlled Windows runner. No private keys in CI variables.
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
$thumbprint = ($env:AULAGUARD_SIGNING_THUMBPRINT -replace '[^0-9a-fA-F]','').ToUpperInvariant()
if ($thumbprint -notmatch '^[0-9A-F]{40,64}$') {
    throw 'No se configuró AULAGUARD_SIGNING_THUMBPRINT: no se permiten publicaciones sin firma.'
}

$kitsRoot = Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Windows Kits\10\bin'
$signTools = @(Get-ChildItem -LiteralPath $kitsRoot -Filter signtool.exe -File -Recurse -ErrorAction Stop |
    Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
    Sort-Object FullName -Descending)
if ($signTools.Count -eq 0) { throw 'Se requiere SignTool x64 del SDK oficial de Windows.' }
$signTool = $signTools[0].FullName

# /sha1 uses the certificate in the Windows personal certificate store; this
# avoids placing a PFX private key or its password in environment variables.
if ($thumbprint.Length -ne 40) { throw 'SignTool /sha1 requiere huella SHA-1 de 40 caracteres.' }
& $signTool sign /sha1 $thumbprint /s My /fd SHA256 /tr https://timestamp.digicert.com /td SHA256 $exe
if ($LASTEXITCODE -ne 0) { throw "Falló la firma de código: $exe" }

$sig = Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction Stop
if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate) {
    throw "Firma Authenticode inválida para $exe (estado: $($sig.Status))."
}
if ($sig.SignerCertificate.Thumbprint.ToUpperInvariant() -ne $thumbprint) {
    throw "El certificado de firma no coincide con el editor autorizado: $exe"
}
& $signTool verify /pa $exe
if ($LASTEXITCODE -ne 0) { throw "SignTool rechazó la firma Authenticode: $exe" }
Write-Host "[OK] Verificada firma Authenticode del editor autorizado: $exe"
