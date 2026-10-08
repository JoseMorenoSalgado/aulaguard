param(
    [Parameter(Mandatory=$true)][string[]]$Paths,
    [switch]$RequireActiveDefender
)

# Release safety gate: never suppress Defender, create exclusions, restore detections,
# or treat a scan failure / unavailable AV as a clean result.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Fail-Scan([string]$Reason) {
    Write-Error "AulaGuard Defender verification FAILED: $Reason" -ErrorAction Continue
    exit 1
}

if ($env:OS -ne 'Windows_NT') {
    Fail-Scan 'Solo se puede ejecutar esta verificación en Windows.'
}

if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) -or
    -not (Get-Command Start-MpScan -ErrorAction SilentlyContinue)) {
    Fail-Scan 'No hay cmdlets de Microsoft Defender disponibles. No es seguro publicar.'
}

try {
    $status = Get-MpComputerStatus -ErrorAction Stop
} catch {
    Fail-Scan "No se pudo consultar Microsoft Defender: $($_.Exception.Message)"
}

if (-not $status.AMServiceEnabled -or -not $status.AntivirusEnabled -or
    ($RequireActiveDefender -and -not $status.RealTimeProtectionEnabled)) {
    Fail-Scan 'El antivirus Microsoft Defender no está activo. No se considera aprobado el archivo.'
}
if (-not $status.AntivirusSignatureVersion -or
    -not $status.AntivirusSignatureLastUpdated -or
    ((Get-Date) - [datetime]$status.AntivirusSignatureLastUpdated).TotalDays -gt 7) {
    Fail-Scan 'Firmas antivirus ausentes o anteriores a siete días.'
}
Write-Host "Defender active. Signature version: $($status.AntivirusSignatureVersion); updated: $($status.AntivirusSignatureLastUpdated)"

foreach ($inputPath in $Paths) {
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        Fail-Scan "Archivo para análisis no encontrado: $inputPath"
    }
    $filePath = (Resolve-Path -LiteralPath $inputPath -ErrorAction Stop).Path
    $sha = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash
    $since = (Get-Date).AddSeconds(-15)

    try {
        Start-MpScan -ScanType CustomScan -ScanPath $filePath -ErrorAction Stop
    } catch {
        Fail-Scan "El análisis de $filePath falló: $($_.Exception.Message)"
    }

    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        Fail-Scan "Defender eliminó o puso en cuarentena: $filePath (SHA256: $sha)"
    }
    if ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash -ne $sha) {
        Fail-Scan "El archivo cambió durante el análisis: $filePath"
    }

    # Do not mistake previous machine-wide unrelated detections for this artifact.
    # A detection for this exact path since the scan began is a release blocker.
    $detections = @()
    try {
        $detections = @(Get-MpThreatDetection -ErrorAction Stop)
    } catch {
        Fail-Scan "No se pudo consultar el historial de amenazas tras analizar $filePath."
    }
    $matched = @($detections | Where-Object {
        $d = $_
        $recent = $d.InitialDetectionTime -and ([datetime]$d.InitialDetectionTime -ge $since)
        $resources = @($d.Resources) -join '|'
        $recent -and $resources.IndexOf($filePath,[StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($matched.Count -gt 0) {
        $threatIds = ($matched | ForEach-Object { $_.ThreatID } | Sort-Object -Unique) -join ', '
        Fail-Scan "Microsoft Defender detectó amenaza en $filePath. Threat IDs: $threatIds; SHA256: $sha"
    }
    Write-Host "[OK] Microsoft Defender scan completed without detection: $filePath SHA256=$sha"
}

Write-Host 'PASS: Antivirus verification completed. This is not a guarantee that the software is harmless or that SmartScreen will trust it.'
