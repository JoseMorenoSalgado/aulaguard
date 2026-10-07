# Control de aplicaciones de AulaGuard

AulaGuard v0.3 utiliza AppLocker como motor de control de ejecución.

## Principio de seguridad

La política debe comenzar siempre en **AuditOnly**. Este modo evalúa las reglas y escribe eventos sin impedir la ejecución. Cuando el administrador haya revisado los eventos y confirmado que todos los programas necesarios están autorizados, puede cambiar la colección a **Enabled**.

## Usuarios afectados

AulaGuard crea y mantiene el grupo local:

`AulaGuardStudents`

El grupo contiene usuarios locales habilitados que no pertenecen al grupo integrado de administradores. Las cuentas integradas especiales se excluyen.

## Programas autorizados

Los ejecutables seleccionados en AulaGuard se procesan con información AppLocker. Se intenta crear reglas de editor y, cuando no existe información suficiente de firma, reglas de hash.

Los componentes de Windows se agregan mediante la opción segura `AllowWindows` del generador de políticas.

## Copias de seguridad

Antes de escribir una política local, AulaGuard exporta la política AppLocker existente a:

`%ProgramData%\AulaGuard\backup\applocker-YYYYMMDD-HHMMSS.xml`

La interfaz permite restaurar la copia más reciente.

## Eventos

AulaGuard consulta los registros:

- Microsoft-Windows-AppLocker/EXE and DLL
- Microsoft-Windows-AppLocker/MSI and Script
- Microsoft-Windows-AppLocker/Packaged app-Execution

Estos eventos se muestran en la pestaña **Control de apps** para que el administrador pueda revisar qué aplicaciones fueron evaluadas.

## Despliegue recomendado

No active Enforcement directamente en todos los equipos. Use un equipo piloto, ejecute las actividades habituales de los estudiantes y docentes, revise la auditoría y ajuste la lista antes de activar el bloqueo.
