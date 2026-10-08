# Control de memorias USB y preparación Premium

## Control local de discos extraíbles — AulaGuard 0.4.0

En **Memorias USB**, el administrador puede activar el interruptor **Bloquear** y aplicar políticas en **Protección activa**. En modo **Auditoría** no se bloquea ningún dispositivo.

La implementación usa las directivas de usuario de Windows 10/11 Pro para la clase **Removable Disks**: `Software\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}` con `Deny_Read=1` y `Deny_Write=1`. Esta política solo afecta a perfiles estándar detectados por AulaGuard; no bloquea el controlador USB ni el teclado, ratón u otros periféricos HID. Windows puede clasificar algunas unidades USB como discos fijos, que no están cubiertos por esta directiva específica. Tampoco reemplaza la protección antivirus, controles físicos o políticas de dominio.

### Seguridad y reversibilidad

- AulaGuard no modifica `HKLM\SYSTEM\CurrentControlSet\Services\USBSTOR`.
- Antes de modificar cada perfil, guarda los valores preexistentes en `%ProgramData%\AulaGuard\config\usb-policy-state.json` con autenticación HMAC-SHA-256 y permisos solo para administradores/SYSTEM.
- Al restaurar, modifica únicamente los valores registrados como gestionados por AulaGuard; conserva otras restricciones administrativas o de dominio.
- La política se sincroniza al iniciar Windows y al iniciar sesión mediante tareas SYSTEM. La aplicación puede tardar en hacerse efectiva hasta que la sesión del estudiante se reinicie.
- Restaurar acceso USB requiere credenciales elevadas y confirmación. **No desinstale AulaGuard antes de restaurar las políticas** si desea dejar los USB accesibles.
- La comprobación de unidades visibles usa `Win32_LogicalDisk` con `DriveType=2`. Esto no es un inventario completo de dispositivos externos.

Referencia oficial: [Microsoft, Removable Storage Access ADMX](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-removablestorage).

## Arquitectura futura del servidor Premium

**Estado actual: sin servidor, sin sincronización, sin telemetría.** La pantalla Servidor Premium es solo informativa y el perfil incluye un campo `premium.serverMode='LocalOnly'`; no existe conexión operativa ni se guardan credenciales de servidor.

Para una futura consola desde una computadora principal, la arquitectura prevista es:

1. **Agente local:** tareas de aplicación de políticas y recopilación limitada de eventos, con cuenta de servicio protegida.
2. **Servidor central:** API HTTPS con TLS, gestión por institución (multi-tenant), base de datos y colas; autenticación por dispositivo con claves/certificados por equipo y revocación.
3. **Consola administrativa:** inventario de equipos, conectividad online/offline, avisos de cambios de política y auditoría; permisos de acceso por rol.
4. **Entrega de políticas:** perfiles versionados y firmados asimétricamente; el agente verifica procedencia y aplica solo políticas autorizadas, incluso sin conexión.
5. **Privacidad y seguridad:** minimización de datos de estudiantes, cifrado en tránsito y reposo, registro de acciones, límites de retención y controles de acceso. No abrir puertos de administración entrantes en PC de estudiantes; conexiones salientes autenticadas.

La **versión gratuita** mantiene la administración local y la **Premium**, cuando exista un backend y una implementación verificable, podrá habilitar monitoreo central según licencias y permisos. El paquete actual no contiene facturación, planes remotos ni servidores activos.

## Pruebas de despliegue

Antes de desplegar por un laboratorio completo:

- Crear sesión de prueba con **usuario estándar** y confirmar que los discos extraíbles no se pueden leer/escribir en modo Enforce.
- Confirmar que el administrador conserva acceso y que teclados/ratones siguen funcionando.
- Restaurar acceso y confirmar valores previos de registro.
- Confirmar que otra directiva de dominio no sobrescribe el estado.
- Probar la reentrada del usuario tras cerrar la sesión.
