# AulaGuard

**AulaGuard** es una herramienta para administrar y proteger computadoras de aulas de informática con Windows 10/11 Pro.

## Versión actual

**v0.3.0**

La versión 0.3 incorpora control avanzado de aplicaciones con AppLocker, auditoría previa al bloqueo, eventos de ejecución, aislamiento de cuentas administradoras y sincronización automática de políticas al iniciar Windows.

## Funciones actuales

- Consola administrativa con panel de estado.
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
- Bitácora JSONL.
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

## Instalación

1. Descargue o clone el repositorio.
2. Ejecute `Instalar.cmd` como administrador.
3. AulaGuard se instalará en `%ProgramData%\AulaGuard`.
4. Se copiarán los módulos de políticas, diagnóstico y control de aplicaciones.
5. Se registrará la tarea `AulaGuard\PolicySync` para revalidar las políticas generales al iniciar Windows.
6. Abra AulaGuard como administrador.
7. Pruebe primero en modo auditoría.

## Arquitectura

```
aulaguard/
├── src/
│   ├── AulaGuard.ps1
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

## Próximas fases

- Reglas por carpeta/editor/hash configurables desde la UI.
- Plantillas por laboratorio y grado.
- Restauración automática de accesos directos.
- Agente central y consola multi-equipo.
- Distribución remota de políticas.
- Reportes consolidados.
