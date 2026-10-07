# AulaGuard

**AulaGuard** es una herramienta para administrar y proteger computadoras de aulas de informática con Windows 10/11 Pro.

## Versión actual

**v0.2.0**

La versión 0.2 introduce un motor modular de políticas, diagnóstico del equipo, administración de perfiles estándar, modo de simulación y controles reales de Windows.

## Funciones actuales

- Consola administrativa con panel de estado.
- Detección de perfiles locales y separación entre administradores y usuarios estándar.
- Modo **Auditoría / Simulación** antes de modificar Windows.
- Bloqueo de cambio de fondo de escritorio.
- Restricción de personalización.
- Bloqueo opcional de Panel de control.
- Bloqueo opcional del Editor del Registro.
- Bloqueo opcional del Administrador de tareas.
- Lista blanca de sitios web para Microsoft Edge y Google Chrome.
- Protección de accesos directos del escritorio público.
- Perfil configurable por aula.
- Importación y exportación de configuraciones JSON.
- Backups automáticos antes de guardar cambios.
- Bitácora estructurada JSONL.
- Diagnóstico de compatibilidad.
- Función para retirar las políticas administradas por AulaGuard.

## Seguridad operativa

AulaGuard aplica las políticas a perfiles de usuario estándar y excluye las cuentas identificadas como administradoras locales.

La aplicación inicia en modo **Auditoría / Simulación**. Para modificar Windows el administrador debe seleccionar explícitamente **Aplicar protección** y confirmar la operación.

Antes de desplegar una política en todas las computadoras del laboratorio, se recomienda probarla en un equipo de prueba.

## Instalación

1. Descargue o clone el repositorio.
2. Ejecute `Instalar.cmd` como administrador.
3. AulaGuard se instalará en `%ProgramData%\AulaGuard`.
4. Se creará un acceso directo en el escritorio público.
5. Abra AulaGuard como administrador.
6. Configure las protecciones.
7. Pruebe primero en modo Auditoría.
8. Cambie a Aplicar protección cuando la configuración esté validada.

## Arquitectura

```
aulaguard/
├── src/
│   ├── AulaGuard.ps1
│   ├── AulaGuard.Core.psm1
│   ├── AulaGuard.Policy.psm1
│   └── AulaGuard.Diagnostics.psm1
├── config/
│   └── default.json
├── docs/
│   └── ROADMAP.md
├── Instalar.cmd
├── .gitignore
└── README.md
```

### Core

Configuración, almacenamiento, backups, perfiles y auditoría.

### Policy

Aplicación y retirada de políticas de Windows sobre perfiles estándar.

### Diagnostics

Inventario básico del equipo, usuarios y comprobaciones de compatibilidad.

## Próxima fase

El siguiente componente importante será el **motor de control de aplicaciones** mediante AppLocker/WDAC con modo auditoría, reglas seguras para Windows y registro de intentos bloqueados.

## Alcance

AulaGuard está pensado para laboratorios escolares, aulas TIC y equipos compartidos donde el administrador necesita mantener un entorno estable sin impedir la administración legítima del equipo.
