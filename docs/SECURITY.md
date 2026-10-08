# Seguridad de AulaGuard v0.3.4

## Alcance y amenaza

AulaGuard está diseñado para cuentas **estándar** de estudiantes en Windows 10/11 actualizado. No existe software local invulnerable: alguien con una cuenta administradora, acceso de arranque externo o privilegios SYSTEM puede modificar el equipo. Los controles criptográficos detectan cambios en archivos, pero **no sustituyen** las políticas de Windows ni la seguridad física.

### Controles implementados

1. **ACL de ProgramData**: `%ProgramData%\AulaGuard` y sus archivos se protegen con permisos exclusivos de `BUILTIN\Administrators` y `NT AUTHORITY\SYSTEM`. Se rechazan rutas de unión/redirección (junctions/reparse points). Se necesita elevación UAC para inicializar y administrar.
2. **Clave local de 256 bits**: generada con un CSPRNG del sistema y cifrada en disco mediante **DPAPI LocalMachine**. La clave nunca se incluye en GitHub o el instalador. La protección de acceso al blob es esencial: DPAPI LocalMachine, por sí sola, no separa a todos los usuarios locales.
3. **Configuración autenticada**: `config/settings.json` se acompaña de `config/settings.json.mac` (HMAC-SHA-256). Se rechazan datos alterados, falta de firma y ausencia de clave. El arranque programado nunca reconstruye en silencio una firma faltante ni pasa automáticamente al modo Auditoría ante corrupción.
4. **Bitácora encadenada**: `logs/secure-audit-AAAA-MM-DD.jsonl` encadena cada entrada con la MAC anterior y una MAC de su contenido. La interfaz valida la cadena antes de mostrarla. Una cadena alterada impide nuevas escrituras a ese archivo. Los registros históricos anteriores a v0.3.4 quedan señalados como no autenticados.
5. **Arranque seguro y diagnóstico**: el sincronizador SYSTEM importa módulos desde su carpeta instalada en lugar de asumir `ProgramData\AulaGuard\src`. Si falla la comprobación, no aplica configuración no confiable y emite el evento 101 en el registro de Aplicación de Windows.
6. **Instalación**: el instalador inicializa los permisos y la configuración firmada antes de crear la tarea de sincronización. Si falla la inicialización, aborta. `Instalar.cmd` endurece `ProgramData` antes de copiar scripts.

**Importante:** HMAC verifica integridad y procedencia respecto a la clave *del equipo*, pero no proporciona firma pública de autoría. Las MAC y los archivos son administrables por un administrador local. La cadena de auditoría detecta la edición de entradas conservadas, **pero no garantiza detectar truncado/borrado completo o sustitución por un administrador**; para eso se necesita un servidor externo de logs de solo anexado.

## Primera instalación

1. Utilice el instalador en un equipo de pruebas con una cuenta de administrador.
2. Asegure que las cuentas de estudiantes sean **usuarios estándar**, sin credenciales UAC de administrador.
3. El instalador genera clave y configuración firmada automáticamente. No copie claves DPAPI a otro equipo.
4. Empiece en **Solo auditoría**. Verifique acceso a herramientas de clase, navegadores y AppLocker antes de activar bloqueo.
5. Guarde copias de seguridad y pruebe la restauración. Las copias de `settings.json` deben incluir su archivo `.mac` y son válidas solo si se conserva la misma clave de ese equipo.

## Actualizar desde una versión sin firma (v0.3.2 o anterior)

La configuración anterior **NO se firma automáticamente** porque podría haber sido manipulada.

1. Revise como administrador `%ProgramData%\AulaGuard\config\settings.json`.
2. Conserve una copia antes de actualizar.
3. En el asistente del instalador, marque **Migrar una configuración anterior REVISADA**; también es posible ejecutar, con PowerShell elevado:

```powershell
& "$env:ProgramFiles\AulaGuard\src\AulaGuard.Initialize.ps1" -MigrateLegacy
```

4. La migración fuerza `policyMode = Audit` y `appControl.enabled = false`. Reaplique manualmente restricciones desde la interfaz tras revisarlas.

Si una instalación ya dispone de una clave DPAPI pero perdió su firma, **no fuerce una nueva firma** de un archivo cuya procedencia desconoce: recupere conjuntamente archivo+MAC+clave de una copia confiable o reinstale configurando de cero tras una revisión administrativa.

## Endurecimiento adicional recomendado

- **BitLocker**, Secure Boot y contraseña de UEFI para impedir modificaciones fuera de Windows.
- Microsoft Defender actualizado, cuentas estándar, MFA para acceso administrativo remoto y bloqueo de arranque USB no autorizado.
- Actualizar Windows 10/11 e instalar las revisiones de seguridad. Según Microsoft, AppLocker se puede aplicar en Windows 10 v2004+ con KB5024351 y en Windows 11, incluidas ediciones Pro; compruebe el nivel de actualización.
- No conceda a estudiantes permisos de escritura en `Program Files`, `ProgramData\AulaGuard`, directivas o tareas programadas.
- Use un certificado de **firma de código Authenticode** confiable para publicar el instalador y `.exe`. Los artefactos CI actuales no se consideran firmados por publicar SHA-256: un checksum **no autentica al distribuidor**.
- Para resistencia frente a administradores maliciosos: WDAC/App Control for Business con reglas gestionadas, actualización firmada y recolección remota centralizada e inmutable de eventos.

## Archivos y pruebas

- Módulo criptográfico: `src/AulaGuard.Security.psm1`.
- Inicialización: `src/AulaGuard.Initialize.ps1`.
- Pruebas de regresión en Windows: `tests/Security.Tests.ps1`.
- Para restaurar el acceso a una PC donde falle la firma, iniciar con credenciales de administrador y revisar primero el evento 101; no elimine políticas a ciegas.

## Limitaciones conocidas

- Las firmas locales con clave de máquina **no son portables** entre equipos. Para distribuir perfiles entre computadoras se debe implementar firma asimétrica de perfiles (clave privada del administrador y clave pública fijada en cada PC).
- Un administrador puede modificar o reinstalar el software; la seguridad depende de UAC, ACL, actualizaciones del sistema y las restricciones del usuario estándar.
- Los perfiles exportados por la interfaz son **JSON editables** y no tienen firma de distribución. Importe solo perfiles revisados y de una fuente confiable. Al guardarlos localmente sí se autentican con el HMAC del equipo.
- La ejecución de PowerShell por SYSTEM depende de la protección del directorio de instalación. Use control de aplicaciones del propio Windows como capa adicional.

Referencias:
- [AppLocker: requisitos](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/requirements-to-use-applocker)
- [DPAPI LocalMachine](https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.dataprotectionscope)

## Error 740 al finalizar la instalación

En v0.3.4, la opción **Abrir AulaGuard ahora** del asistente ejecuta la aplicación con el contexto elevado del instalador (`runascurrentuser`). Es necesario porque el ejecutable exige permisos de administrador (`requireAdministrator`). No se eliminó UAC ni se relajaron las restricciones de Windows. Los accesos directos siguen solicitando aprobación de administrador al abrir la consola.


## Inicio del programa empaquetado (.exe)

Desde v0.3.5, el proceso de carga de módulos PowerShell detecta la carpeta real del ejecutable compilado con PS2EXE, sin depender de `$PSScriptRoot` ni del directorio de trabajo. Si falla el inicio, el diagnóstico se registra en `%TEMP%\AulaGuard-startup-error.txt` del usuario administrador. GitHub Actions verifica la compilación del EXE, la instalación de sus módulos y el arranque de la versión PowerShell; el flujo de integración continua no reemplaza una prueba interactiva del EXE con UAC en Windows 10/11 Pro.
