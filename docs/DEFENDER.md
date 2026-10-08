# Alertas de Microsoft Defender y SmartScreen — AulaGuard

## No ignorar ni desactivar Windows Security

Si Windows bloquea AulaGuard, no desactive Defender, no agregue exclusiones y no restaure archivos en cuarentena para probarlos. Puede existir un falso positivo, pero también puede ser una detección real.

## Distinguir los avisos

- Microsoft Defender SmartScreen ('Windows protegió su PC'): advertencia de reputación; no constituye por sí sola un diagnóstico de malware.
- Seguridad de Windows > Protección contra virus y amenazas > Historial de protección: detección antivirus con un nombre preciso como Trojan:Win32/... o PUA:Win32/.... Requiere investigación.

## Datos necesarios

1. Abra Seguridad de Windows > Protección contra virus y amenazas > Historial de protección.
2. Registre nombre exacto de amenaza, archivo afectado (instalador o EXE), fecha, acción de Defender y versión de firmas.
3. En PowerShell elevado consulte sin restaurar archivos:

    Get-MpThreatDetection | Sort-Object InitialDetectionTime -Descending | Select-Object -First 10 ThreatID,InitialDetectionTime,Resources | Format-List
    Get-MpComputerStatus | Select-Object AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureVersion,AntivirusSignatureLastUpdated

4. Si el archivo aún existe, compare su SHA-256 con SHA256SUMS.txt de la misma versión y compruebe la firma Authenticode mediante Get-AuthenticodeSignature. Coincidir con el hash publicado no prueba que el archivo sea seguro.

## Limitación verificada del ejecutor de GitHub Actions

La ejecución de comprobación del 8 de octubre de 2026 detectó que Microsoft Defender no estaba activo en el runner `windows-latest` de GitHub. **No se analizó el archivo y no se puede considerar que haya pasado una verificación antivirus.** Por seguridad, el proceso falló y no produjo una nueva publicación. La revisión deberá repetirse en una máquina Windows de compilación con Defender activo, firmas recientes y controles de integridad auditables. No se debe marcar la comprobación como superada ni saltarla.

## Comprobaciones automáticas para nuevas versiones

El script build/Test-DefenderArtifacts.ps1 analiza los archivos finales compilados utilizando Microsoft Defender activo, con firmas recientes. Si está inactivo, no hay firmas, ocurre un error, se detecta amenaza o el archivo se elimina durante el análisis, GitHub Actions falla y bloquea la publicación automática. NO se crean exclusiones ni se desactiva Defender.

La compilación usa PS2EXE y exige elevación UAC para controlar Windows. Es posible que estas características se clasifiquen heurísticamente; una clasificación de malware no debe ignorarse sin análisis. Un resultado sin detecciones en CI no garantiza seguridad en otros equipos.

## Revisión por Microsoft

Los desarrolladores pueden someter archivos sospechosos a Microsoft Security Intelligence: https://www.microsoft.com/en-us/wdsi/filesubmission. Seleccione el producto de Microsoft afectado y proporcione el nombre preciso de la detección. Solo Microsoft determina si procede reclasificar el archivo.

## Firma digital

Se recomienda firmar instalador y EXE con un certificado Authenticode válido a nombre del editor. Una firma autentica procedencia/integridad, pero no garantiza que una aplicación sea inocua. Sin firma, SmartScreen puede mostrar editor desconocido.
