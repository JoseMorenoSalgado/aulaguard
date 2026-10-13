# AulaGuard — protocolo E2E Windows 10 / 11 Pro

Esta fase **prepara** pruebas reales; no significa que ya se hayan ejecutado en equipos Windows de producción.

## Matriz de aceptación

| Ensayo | Windows 10 Pro | Windows 11 Pro | Evidencia |
|---|---|---|---|
| Arranque, elevación UAC, acceso administrador | Pendiente | Pendiente | Captura y evento |
| Bloqueo AppLocker de EXE inofensivo de laboratorio | Pendiente | Pendiente | Ejecución y evento AppLocker |
| Ejecución de programa permitido | Pendiente | Pendiente | Salida del comprobador |
| Fondo, personalización, panel y administrador de tareas | Pendiente | Pendiente | Registro y acción real |
| Web permitida / bloqueada en Edge y Chrome | Pendiente | Pendiente | Sesión de navegador |
| USB extraíble: lectura y escritura | Pendiente | Pendiente | Memoria desechable |
| Accesos directos públicos: renombrar | Pendiente | Pendiente | Acceso directo desechable |
| Reversión, reinicio, mantenimiento y desinstalación | Pendiente | Pendiente | Comparación antes/después |
| Defender activo y firma Authenticode | Pendiente | Pendiente | Firma y protección |

## Procedimiento

1. Use **dos VM aisladas**, una Windows 10 Pro y otra Windows 11 Pro, con snapshot inicial, una cuenta administradora y otra **local estándar** llamada AulaGuardLabStudent. Inicie sesión con esta última al menos una vez.
2. Instale **solo una compilación revisada y firmada** de AulaGuard. Si Defender detecta malware, detenga la instalación; no lo desactive ni añada exclusiones. Mientras no exista instalador firmado, continúe únicamente con revisión de código y CI.
3. Abra AulaGuard con una cuenta administradora. Configure primero modo Auditoría y analice los eventos. Luego, exclusivamente en la VM, habilite las restricciones deseadas desde la interfaz y cambie a Enforce tras revisar los programas necesarios y preparar recuperación administrativa.
4. Desde PowerShell 5.1 **elevado**, en la raíz del repositorio revisado, ejecute:

        powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\e2e\Admin-Preflight.ps1 -StudentAccount "AulaGuardLabStudent" -RequireEnforcement -CreateBenignFixture

   No cambia las políticas. Comprueba edición Windows, usuario estándar, preparación, grupo AppLocker y estado de identidad de aplicación. Prepara un manifiesto de solo lectura en %ProgramData%\AulaGuardLab\manifest.json, con SHA-256 del programa inofensivo de prueba. Guarde el hash del manifiesto. Si el ejecutable ya existe, el script no lo sobrescribe.
5. Cierre sesión del administrador e inicie sesión **como estudiante estándar**. En la copia revisada del código ejecute SIN elevar:

        powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\e2e\Student-Probe.ps1

   Para probar el acceso de solo lectura a una memoria USB extraíble desechable, añada el argumento: -UsbDrive E:. Nunca use memorias con datos valiosos. No intente eludir AppLocker si bloquea el propio script.
6. Revise el informe de la sesión en %TEMP%\AulaGuard-Student-E2E.json. PASS = comprobación observada; FAIL = fallo; INCONCLUSIVE = no atribuible; SKIP = no ejecutada. El programa de prueba solo se ejecuta si su hash coincide con el autorizado. La denegación de AppLocker solo se acredita automáticamente con error Win32 **1260**.
7. Complete manualmente con el usuario estándar: cambiar el fondo con clic derecho; renombrar un acceso directo público **desechable**; abrir Panel de control, editor del registro o administrador de tareas si están restringidos; navegar a una web permitida y otra bloqueada; intentar lectura y escritura sobre USB desechable; y comprobar la restauración tras reiniciar.
8. Vuelva al administrador, restaure desde AulaGuard las políticas generales, USB y la política AppLocker respaldada. Nunca borre GPO de terceros. Reinicie, repita la observación de la cuenta estándar y documente cualquier restricción residual. Si algo falla, restaure el snapshot.
9. Repita en ambas VM y complete la matriz solo con evidencia. El CI de GitHub **no ejecuta bloqueos en sus runners**.

## Límites de las pruebas automatizadas

- El comprobador del administrador solo diagnostica y crea archivos de laboratorio; nunca impone políticas.
- El comprobador de estudiante verifica valores efectivos HKCU y puede comprobar procesos permitidos o bloqueados; no modifica el registro, el fondo ni los dispositivos USB.
- La presencia de valores en el Registro no demuestra el comportamiento de Windows.
- Los ensayos visuales de escritorio y de navegación se mantienen **pendientes de revisión manual**.
- Un resultado automatizado favorable **no aprueba la liberación**: el JSON mantiene completeE2E=false y readyForProduction=false.

## Salida a producción

No publicar ningún .exe hasta completar ambas matrices, comprobar restauración y desinstalación, superar el análisis Microsoft Defender, obtener firma Authenticode válida y publicar por el flujo manual verificado con hash SHA-256.
