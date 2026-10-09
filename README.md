# AulaGuard

**AulaGuard** es una herramienta para administrar y proteger computadoras de aulas de informática con Windows 10/11 Pro.

## Descargar AulaGuard (.exe) desde main

**[Abrir carpeta de instaladores verificados](downloads/README.md)**

La descarga se mostrará directamente aquí cuando el instalador corregido
haya pasado las comprobaciones de Microsoft Defender y firma digital.
**Actualmente no hay un .exe verificado de v0.4.3**: no descargues v0.4.0
para probar las correcciones.

El archivo final quedará en `main/downloads/AulaGuard-Setup-vX.Y.Z.exe`,
junto con un enlace directo y su SHA-256. No se publicará desde compilaciones
de prueba sin revisión antivirus.

## Versión actual

**v0.4.3 (código corregido, pendiente de firma y revisión antivirus del instalador)**

El proyecto incorpora control USB por usuario estándar, la vista de Servidor Premium (preparación sin conexión real), interfaz verde y la desinstalación para retirar los directorios del programa en Program Files y corrige la carga de módulos del programa compilado y mantiene la corrección del error de elevación 740. Incluye DPAPI, HMAC-SHA-256, auditoría encadenada, permisos NTFS restrictivos y validación de integridad. Mantiene el control avanzado de aplicaciones con AppLocker, auditoría previa al bloqueo, eventos de ejecución, aislamiento de cuentas administradoras y sincronización automática de políticas al iniciar Windows.

## Fondo institucional seguro (v0.4.3)

La imagen seleccionada por el administrador ya no se usa directamente desde Descargas, Escritorio o una ruta privada. Al guardar, AulaGuard verifica y convierte imágenes JPG, PNG y BMP a JPEG y las coloca en `%ProgramData%\AulaGuardAssets\institutional.jpg`. La carpeta concede a los estudiantes solo lectura y ejecución, y reserva escritura para administradores y SYSTEM. Si la imagen es inválida o no puede publicarse, se muestra un error y no se aplican políticas que la utilicen.

**Recuperación de fondo negro en versiones anteriores:** abra AulaGuard como administrador, vaya a **Protección → Retirar políticas**. Si se solicita, confirme, cierre la sesión del estudiante y vuelva a entrar. El alumno podrá escoger un fondo de Windows desde Personalización; si la ruta de AulaGuard seguía seleccionada, la restauración intenta utilizar el fondo predeterminado de Windows. Si desea bloquear nuevamente el cambio de fondo, elija la imagen institucional, guarde, aplique la protección y pruebe en un usuario estándar.

Si no está disponible un instalador firmado y analizado, **no desactive Defender para forzar la actualización**.

## Nuevo inventario de programas (v0.4.3)

- La sección **Programas** detecta aplicaciones Win32 en el Registro de Windows, entradas **App Paths**, accesos directos del menú Inicio y paquetes Microsoft Store.
- Cada programa compatible aparece con **interruptor verde**. Al activarlo, se añade su ejecutable verificable a la lista blanca **pendiente de guardar**; no se activan restricciones automáticamente.
- Incluye **búsqueda**, filtro por estado, contador, botón **Detectar apps**, y **Agregar EXE** para instalaciones que Windows no registre correctamente.
- Los paquetes Microsoft Store aparecen en el inventario con estado **N/D**; no se pueden autorizar mediante el mismo mecanismo de EXE hasta que AulaGuard implemente reglas AppLocker de aplicaciones empaquetadas.
- **Control de apps** y **Programas** usan paneles adaptables, sin anchuras absolutas que oculten los controles. Protección reorganiza sus dos tarjetas en pantallas estrechas.
- Mantenga primero **Modo auditoría** y valide las reglas antes de aplicar bloqueos. Los programas no detectados no son necesariamente desautorizados por Windows hasta que una política AppLocker válida se aplique.
- Para conservar las selecciones, use **Guardar cambios**. Para afectar el equipo, utilice **Aplicar control** y confirme expresamente.

El instalador v0.4.3 **no se distribuye hasta superar las verificaciones de Defender y contar con una firma Authenticode válida**.

## Funciones actuales

- Consola administrativa con panel de estado y separación fija de navegación y contenidos.
- Política de lectura/escritura de discos extraíbles por usuario estándar, con restauración de valores anteriores y estado autenticado mediante HMAC.
- Sección Servidor Premium preparada para una futura consola central (sin telemetría ni conexión activa).
- Detección de perfiles locales.
- Identificación de administradores por SID, compatible con Windows en distintos idiomas.
- Aplicación de políticas únicamente sobre usuarios estándar.
- Grupo local administrado por AulaGuard: `AulaGuardStudents`.
- Modo Auditoría / Simulación.
- Bloqueo del cambio de fondo de escritorio.
- Restricción de personalización.
- Bloqueo opcional de Panel de control.
- Bloqueo opcional del Editor del Registro.
- Bloqueo opcional del Administrador de tareas.
- Lista blanca de sitios para Microsoft Edge y Google Chrome.
- Protección de accesos directos del escritorio público.
- Importación y exportación de perfiles JSON.
- Backups automáticos.
- Bitácora JSONL autenticada con HMAC-SHA-256 y verificación de encadenamiento.
- Configuración firmada localmente con clave protegida por DPAPI.
- ACL restrictivas de ProgramData para Administradores y SYSTEM.
- Diagnóstico del sistema.
- Sincronización de políticas en el arranque mediante tarea programada.

## Control de aplicaciones v0.3

AulaGuard utiliza AppLocker para construir políticas de control de aplicaciones.

### Flujo recomendado

1. Agregue los programas autorizados en la pestaña **Programas**.
2. Abra **Control de apps**.
3. Seleccione **Solo auditoría**.
4. Valide y aplique la política.
5. Utilice normalmente el equipo de prueba.
6. Revise los eventos de AppLocker en AulaGuard.
7. Agregue cualquier programa legítimo que falte.
8. Solo después de validar el aula, cambie a **Aplicar bloqueo**.

En modo auditoría los programas no autorizados siguen ejecutándose, pero AppLocker registra los eventos. En modo de bloqueo, las aplicaciones no permitidas por la política pueden ser impedidas de ejecutar.

AulaGuard crea una copia de seguridad de la política AppLocker local antes de sustituirla y permite restaurar la copia más reciente desde la interfaz.

## Protección del administrador

Las reglas de control de aplicaciones no se crean para `Everyone`. AulaGuard mantiene un grupo local denominado `AulaGuardStudents` con las cuentas locales estándar habilitadas y excluye las cuentas que pertenecen al grupo integrado de administradores.

## Aviso de seguridad: Microsoft Defender

Si Windows Defender detecta AulaGuard, **no lo instale ni desactive el antivirus**. Registre el nombre exacto de la detección desde **Seguridad de Windows → Historial de protección**. La advertencia azul de SmartScreen por programa desconocido es distinta de una detección de malware. Consulte [la guía de investigación](docs/DEFENDER.md).

Las nuevas compilaciones requieren un análisis activo con Microsoft Defender del ejecutable y del instalador para publicarse automáticamente. Una comprobación satisfactoria no garantiza ausencia de amenazas ni aprobación de reputación SmartScreen. La firma digital de código sigue requiriendo un certificado real.

## Instalador público: publicación suspendida

**No se recomienda instalar la versión v0.4.0** hasta investigar el aviso antivirus reportado en un equipo Windows. Una advertencia SmartScreen de reputación no es lo mismo que una detección real de Microsoft Defender; todavía falta el nombre exacto de la amenaza.

El código de **v0.4.3** conserva los cambios para exigir:

- Certificado Authenticode real (instalador y EXE) con clave privada protegida en Windows.
- Versión **ps2exe 1.0.18** fijada explícitamente.
- Análisis antivirus con Defender activo en un ejecutor de publicación Windows administrado por el editor.
- Publicación manual aprobada. La compilación pública de GitHub solo valida código; **no publica binarios sin revisar**.

Cuando el editor complete estos requisitos, la versión verificada aparecerá en [GitHub Releases](https://github.com/JoseMorenoSalgado/aulaguard/releases). Una firma y un escaneo satisfactorios no garantizan que el programa carezca de malware.

Para revisar una detección y preparar el entorno, lea [Investigación con Defender](docs/DEFENDER.md).

## Instalación

1. Espere a que la revisión antivirus se complete y aparezca un instalador firmado de v0.4.3 o posterior en [Releases](https://github.com/JoseMorenoSalgado/aulaguard/releases). No instale una versión que Defender haya puesto en cuarentena.
2. Ejecute el instalador con permisos de administrador en Windows 10/11 Pro.
3. Los binarios se instalan en `Program Files`; la configuración privada se almacena en `%ProgramData%\\AulaGuard`.
4. Se instalarán los módulos de políticas, diagnóstico, seguridad y control de aplicaciones.
5. Se registrará la tarea `AulaGuard\\PolicySync` para revalidar las políticas generales al iniciar Windows.
6. Abra AulaGuard como administrador y pruebe primero en modo auditoría.

**Actualizaciones desde v0.3.2 o anteriores:** revise [las instrucciones de migración segura](docs/SECURITY.md) antes de instalar.

## Arquitectura

```
aulaguard/
├── src/
│   ├── AulaGuard.ps1
│   ├── AulaGuard.Security.psm1
│   ├── AulaGuard.Initialize.ps1
│   ├── AulaGuard.Core.psm1
│   ├── AulaGuard.Policy.psm1
│   ├── AulaGuard.Diagnostics.psm1
│   ├── AulaGuard.AppControl.psm1
│   └── AulaGuard.Startup.ps1
├── config/
│   └── default.json
├── docs/
│   ├── ROADMAP.md
│   └── APP_CONTROL.md
├── Instalar.cmd
├── .gitignore
└── README.md
```

## Seguridad operativa

El modo de auditoría es el valor predeterminado. AppLocker puede afectar inmediatamente la ejecución de aplicaciones cuando una colección está en modo `Enabled`, por lo que AulaGuard exige una confirmación adicional antes de activar el bloqueo.

La primera implantación debe realizarse en un equipo de prueba antes de desplegarla en todo el laboratorio.

**Configuraciones anteriores:** deben migrarse expresamente después de una revisión. Lea [Seguridad y migración](docs/SECURITY.md). No existe garantía de invulnerabilidad frente a personas con permisos de administrador o acceso físico; la seguridad presupone estudiantes con cuentas estándar.

**Firma del instalador:** el checksum SHA-256 publicado por CI permite verificar bytes, pero no reemplaza una firma Authenticode emitida por una entidad de confianza. No se debe asumir que el instalador está firmado digitalmente.

## Próximas fases

- Reglas por carpeta/editor/hash configurables desde la UI.
- Plantillas por laboratorio y grado.
- Restauración automática de accesos directos.
- Agente central y consola multi-equipo.
- Distribución remota de políticas.
- Reportes consolidados.


## Instalador profesional

El proyecto tiene preparado el código de un instalador de Windows:

`AulaGuard-Setup-v0.4.3.exe` (pendiente de firma y verificación antivirus; no disponible todavía)

Características del instalador:

- Identidad visual propia de AulaGuard.
- Asistente en español.
- Acceso directo opcional en escritorio.
- Acceso directo opcional en menú Inicio.
- Apertura de AulaGuard al finalizar con el token elevado del instalador (evita error 740).
- Acceso alternativo desde el menú Inicio para ejecutar la interfaz como script PowerShell, con elevación UAC, si el ejecutable empaquetado no abre.
- Conservación de la configuración de `ProgramData` durante actualizaciones.
- Registro automático de la tarea `AulaGuard\PolicySync`.
- Desinstalador desde Aplicaciones instaladas de Windows, que limpia los archivos de la aplicación en `Program Files` y elimina la tarea programada.\n- Conservación por defecto de los datos y políticas administrativas almacenados en `%ProgramData%\\AulaGuard`.
- Validación automática de sintaxis antes de compilar.

La compilación de pruebas no publica el instalador. La publicación se realiza únicamente mediante el flujo manual **Publish verified AulaGuard**, con certificado Authenticode válido y Microsoft Defender activo, en una máquina controlada por el editor.

## Desinstalación y limpieza

Desde Windows, abra **Configuración → Aplicaciones → Aplicaciones instaladas → AulaGuard → Desinstalar**. El desinstalador elimina los componentes en `C:\\Program Files\\AulaGuard`, incluidos residuos de versiones anteriores dentro de `src`, `docs` y `config`, y la tarea programada `AulaGuard\\PolicySync`. No elimina automáticamente `%ProgramData%\\AulaGuard`: contiene claves DPAPI, configuraciones, registros y backups, y puede necesitarse para reinstalar sin perder la información. La desinstalación del programa **no revierte automáticamente las políticas de Windows ni los bloqueos de AppLocker ya aplicados**; deben desactivarse desde AulaGuard antes de desinstalar si desea retirar los bloqueos.

Por seguridad, no se realiza un borrado indiscriminado de `{app}` ni de otras carpetas de Windows. Si se conservaron archivos ajenos al instalador directamente en la raíz personalizada, se deberán revisar manualmente.

## Memorias USB y monitoreo Premium

En **Memorias USB** el administrador puede permitir o restringir lectura y escritura de unidades de almacenamiento extraíbles para perfiles estándar (Windows 10/11 Pro). Primero seleccione **Protección activa**, configure el interruptor, guarde y aplique; el modo **Auditoría** no bloquea dispositivos. **Restaurar acceso USB** recupera únicamente las directivas que AulaGuard haya registrado como propias. No cambia controladores USB ni deshabilita teclados, ratones o cuentas administrativas. La detección de unidades muestra las reconocidas por Windows como extraíbles; algunos discos USB pueden ser reportados como fijos y requieren otro control para bloquearlos. Revise [USB y Premium](docs/USB-PREMIUM.md).

**Servidor Premium** es una pantalla informativa: todavía no hay servidor, conexión, agentes remotos ni transmisión de datos. El diseño futuro contempla una PC principal o servidor central con autenticación por dispositivo, comunicación TLS, permisos por institución y envío controlado de eventos, además de políticas por laboratorio.
