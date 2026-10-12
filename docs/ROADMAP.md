# Roadmap de AulaGuard

## v0.3.0 — Control de aplicaciones

- [x] Motor AppLocker integrado.
- [x] Auditoría antes del bloqueo.
- [x] Generación automática de políticas para Windows y programas autorizados.
- [x] Reglas por editor/hash para los ejecutables seleccionados.
- [x] Grupo local AulaGuardStudents.
- [x] Exclusión de administradores del control de aplicaciones.
- [x] Identificación de grupos integrados por SID para Windows en cualquier idioma.
- [x] Activación y comprobación del servicio Application Identity.
- [x] Copia de seguridad de la política AppLocker existente.
- [x] Restauración de la política anterior.
- [x] Visualización de eventos AppLocker.
- [x] Confirmación adicional antes de activar Enforcement.
- [x] Sincronización de políticas generales al iniciar Windows.

## v0.3.x — Endurecimiento

- [ ] Selector de tipo de regla: editor, hash o carpeta.
- [ ] Analizador de dependencias de aplicaciones.
- [ ] Plantilla automática para navegadores y herramientas educativas comunes.
- [ ] Filtro visual de eventos: auditado, permitido y bloqueado.
- [ ] Exportar reporte de incidentes.
- [ ] Restauración automática de fondo y accesos si son alterados.
- [ ] Modo mantenimiento temporal con expiración.
- [ ] Pruebas automatizadas de políticas antes de Enforcement.

## v0.5.1 — Interfaz profesional y despliegue explícito

- [x] Inicio responsivo con estado general y acciones principales.
- [x] Separar configuración guardada de política realmente aplicada.
- [x] Snapshot de despliegue firmado para políticas generales y USB.
- [x] Estado aplicado visible en Protección, USB y navegación lateral.
- [x] Validación sin escritura para Protección y USB.
- [x] Pruebas de interfaz en resoluciones 1080×680, 1280×720 y 1600×900.
- [x] Reconstrucción del pipeline profesional de publicación firmada y escaneada.
- [ ] Migrar Internet y Escritorio a la misma arquitectura responsiva.
- [ ] Añadir plantillas visuales de perfiles de aula.
- [ ] Sustituir gradualmente la interfaz WinForms por cliente .NET nativo.

## v0.5 — Profesionalización local

- [x] Diagnóstico previo del equipo y del motor de políticas.
- [x] Bloqueo de operaciones cuando faltan requisitos críticos.
- [x] Estados reales de éxito, simulación, advertencia y error.
- [x] Sincronización verificada del grupo AulaGuardStudents.
- [x] Exportación de diagnóstico técnico para soporte.
- [ ] Validación funcional automatizada de cada restricción en un Windows de laboratorio.
- [ ] Modo mantenimiento con expiración y restauración automática.
- [ ] Reglas para aplicaciones Microsoft Store.
- [ ] Firma Authenticode y pipeline de publicación con Microsoft Defender activo.

## v0.6 — Administración central

- [ ] Agente AulaGuard por equipo.
- [ ] Consola central.
- [ ] Equipos online/offline.
- [ ] Distribución remota de políticas.
- [ ] Inventario de hardware y software.
- [ ] Reportes y alertas.
- [ ] Políticas por horario.
- [ ] Perfiles por aula, grado o grupo.
