# Roadmap de AulaGuard

## v0.2.0 — Motor de políticas y administración avanzada

- [x] Arquitectura modular: Core, Policy y Diagnostics.
- [x] Panel de resumen del equipo.
- [x] Inventario de perfiles de usuario locales.
- [x] Identificación y exclusión de cuentas administradoras.
- [x] Modo Auditoría / Simulación antes de aplicar cambios.
- [x] Aplicación de políticas a perfiles estándar, incluso sin sesión iniciada.
- [x] Bloqueo de cambio de fondo.
- [x] Restricción de personalización.
- [x] Bloqueo opcional de Panel de control.
- [x] Bloqueo opcional de Editor del Registro.
- [x] Bloqueo opcional de Administrador de tareas.
- [x] Lista blanca web por usuario para Edge y Chrome.
- [x] Protección de accesos del escritorio público.
- [x] Importar y exportar perfiles JSON.
- [x] Backups automáticos de configuración.
- [x] Bitácora JSONL con nivel, equipo, usuario y fecha.
- [x] Retirada controlada de las políticas administradas por AulaGuard.
- [x] Diagnóstico de compatibilidad.

## v0.2.x — Endurecimiento

- [ ] Restauración automática del fondo y accesos si son alterados.
- [ ] Validación visual de cada política aplicada.
- [ ] Programar aplicación de políticas al iniciar Windows.
- [ ] Captura de eventos de seguridad relevantes.
- [ ] Mejorar el sistema de actualización.

## v0.3 — Control de aplicaciones

- [ ] Motor AppLocker/WDAC con modo auditoría.
- [ ] Reglas seguras para componentes esenciales de Windows.
- [ ] Lista de aplicaciones permitidas por ruta, editor o hash.
- [ ] Registro de intentos de ejecución bloqueados.
- [ ] Plantillas por laboratorio, grado o grupo.

## v0.4 — Administración central

- [ ] Consola central para múltiples computadoras.
- [ ] Agente AulaGuard por equipo.
- [ ] Estado en línea/offline.
- [ ] Distribución remota de políticas.
- [ ] Inventario de hardware/software.
- [ ] Reportes y alertas.
- [ ] Políticas por horario.
