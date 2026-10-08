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

## Correcciones de publicación v0.4.1

El flujo normal de GitHub Actions **solo compila y ejecuta las pruebas**. No entrega ni publica archivos ejecutables que no hayan sido verificados con un antivirus activo. La ejecución anterior de Microsoft Defender en GitHub-hosted Windows no pudo realizar el análisis porque el servicio antivirus estaba inactivo en el runner.

Se preparó el flujo manual `.github/workflows/release-verified.yml` para publicar con controles reales. **No se debe afirmar que v0.4.1 está disponible hasta terminar todo el proceso**.

### Requisitos para una publicación

1. Preparar un ejecutor **Windows aislado y propio** con Microsoft Defender activado, protección en tiempo real, firmas actualizadas y permisos de administrador sobre una máquina de pruebas.
2. Instalar y revisar la versión fijada de `ps2exe 1.0.18`, Inno Setup 6, Windows SDK SignTool y GitHub CLI. El proceso de publicación no instalará dependencias automáticamente.
3. Instalar un certificado de firma de código Authenticode válido, cuya clave privada permanezca protegida, en `Cert:\CurrentUser\My` de la cuenta de ejecución.
4. En GitHub, crear el entorno **verified-release** con aprobación administrativa, configurar el secreto `AULAGUARD_SIGNING_THUMBPRINT` (huella de 40 caracteres) y asignar la etiqueta `aulaguard-defender` al ejecutor autorizado.
5. Desde `main`, ejecutar manualmente **Publish verified AulaGuard**. Primero se firma `AulaGuard.exe`, después se analiza con Defender, se incluye en Inno Setup, se firma el instalador y se analiza la versión final. Ambas firmas se validan antes de publicar.
6. Si algo falla, **no se publica el instalador**. No omitir las comprobaciones ni añadir exclusiones de Defender.

**Importante:** el análisis local y Authenticode no garantizan que un archivo sea inocuo. Tras una detección auténtica, debe identificarse la firma antivirus y, si procede, usar el portal de análisis de Microsoft antes de entregar la próxima versión a los colegios. Una actualización de PS2EXE o una firma Authenticode puede mejorar la confiabilidad del proceso, pero **no demuestra que se haya resuelto una detección concreta**.
