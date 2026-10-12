$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$candidate = Get-Content -LiteralPath (Join-Path $root '.github\workflows\build-installer.yml') -Raw
$release = Get-Content -LiteralPath (Join-Path $root '.github\workflows\release-verified.yml') -Raw
$sign = Get-Content -LiteralPath (Join-Path $root 'build\Sign-Artifact.ps1') -Raw
$builder = Get-Content -LiteralPath (Join-Path $root 'build\Build-App.ps1') -Raw

function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw "RELEASE SECURITY TEST FAILED: $Message" } }

Assert (-not ($candidate -match 'gh release create|actions/upload-artifact|Publish downloadable installer')) 'Development CI must not publish unverified binaries.'
Assert ($candidate -match 'Validate PowerShell syntax' -and $candidate -match 'Verify cryptographic security') 'Development tests must remain active.'
Assert ($release -match 'workflow_dispatch:' -and $release -match 'self-hosted, Windows, X64, aulaguard-defender') 'Release must use an opt-in trusted Windows runner.'
Assert ($release -match 'github\.ref == ''refs/heads/main''') 'Only reviewed main may publish.'
Assert ($release -match 'environment: verified-release') 'Release requires environment-level approval.'
Assert (($release -split 'Test-DefenderArtifacts\.ps1').Count -eq 3) 'Both binary and installer must be antivirus-scanned.'
Assert (($release -split 'Sign-Artifact\.ps1').Count -eq 3) 'Both binary and installer must be signed.'
Assert ($release.IndexOf('Sign and scan application') -lt $release.IndexOf('Package signed application')) 'Signed application must be packaged into installer.'
Assert ($release.IndexOf('Sign and scan final installer') -lt $release.IndexOf('Publish immutable verified GitHub Release')) 'Scan must complete before releasing.'
Assert ($sign -match 'Get-AuthenticodeSignature' -and $sign -match "Status -ne 'Valid'") 'Signer must validate Authenticode.'
Assert ($sign -notmatch 'PFX_BASE64|PFX_PASSWORD|SigningPassword') 'No PFX secrets may be stored in workflow variables.'
Assert ($builder -match "ps2exeVersion = '1.0.18'" -and $builder -match 'RequiredVersion') 'PS2EXE must be pinned.'
Assert ($release -notmatch 'Set-MpPreference|Add-MpPreference|ExclusionPath|DisableRealtimeMonitoring') 'Release must not weaken Defender.'
Assert ($release -match 'Add signed and Defender-scanned installer to main downloads') 'Verified installer must be published in main downloads.'
Assert ($release -match 'repos/\$repo/contents/\$path' -and $release -match 'downloads/\$filename') 'Main download must be written to a real GitHub repository file.'
Assert ($release.IndexOf('Sign and scan final installer') -lt $release.IndexOf('Add signed and Defender-scanned installer to main downloads')) 'The main branch must not receive installers before scanning and signing.'
Assert ($release.IndexOf('Add signed and Defender-scanned installer to main downloads') -lt $release.IndexOf('Publish immutable verified GitHub Release')) 'Main upload must complete before the immutable release.'
Assert ($release -match 'Get-FileHash -LiteralPath \$setup -Algorithm SHA256' -and $release -match 'git hash-object') 'Main upload must verify the installer checksum and GitHub blob SHA.'
Assert ($release -match 'main changed after verification started') 'Main changes must cancel an outdated release run.'

Write-Host 'PASS: releases require approval, signed and scanned binaries, immutable main download and GitHub Release.'
