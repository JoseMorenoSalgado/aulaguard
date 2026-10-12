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
- [x] Modo mantenimiento temporal con expiración.
- [ ] Pruebas automatizadas de políticas antes de Enforcement.

## v0.5.1 — Experiencia profesional

- [x] Dashboard adaptable y orientado a estado.
- [x] Navegación y sistema visual coherentes.
- [x] Internet, Escritorio y Registro sin coordenadas fijas.
- [x] Estados de USB y diagnóstico reflejados visualmente.
- [x] Prueba automática de estructura responsiva.
- [ ] Prueba visual manual en Windows 10 y 11 con escalado 100%, 125% y 150%.
- [ ] Revisión de accesibilidad por teclado y contraste.

## v0.5 — Profesionalización local

- [x] Diagnóstico previo del equipo y del motor de políticas.
- [x] Bloqueo de operaciones cuando faltan requisitos críticos.
- [x] Estados reales de éxito, simulación, advertencia y error.
- [x] Sincronización verificada del grupo AulaGuardStudents.
- [x] Exportación de diagnóstico técnico para soporte.
- [ ] Validación funcional automatizada de cada restricción en un Windows de laboratorio.
- [x] Modo mantenimiento con expiración y restauración automática.
- [ ] Reglas para aplicaciones Microsoft Store.
- [ ] Firma Authenticode y pipeline de publicación con Microsoft Defender activo.

## v0.5.2 — Mantenimiento seguro

- [x] Suspensión temporal limitada de restricciones administradas por AulaGuard.
- [x] Duración acotada entre 5 y 480 minutos.
- [x] Conservación firmada del estado previo de Protección y AppLocker.
- [x] Restauración automática al iniciar Windows cuando el plazo venció.
- [x] Controles de inicio/finalización desde Estado del sistema.
- [x] Eventos de auditoría para inicio, expiración, finalización y errores.
- [x] Pruebas CI del estado y de invariantes de seguridad.

## v0.6 — Administración central

- [ ] Agente AulaGuard por equipo.
- [ ] Consola central.
- [ ] Equipos online/offline.
- [ ] Distribución remota de políticas.
- [ ] Inventario de hardware y software.
- [ ] Reportes y alertas.
- [ ] Políticas por horario.
- [ ] Perfiles por aula, grado o grupo.
