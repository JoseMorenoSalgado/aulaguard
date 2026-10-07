# AulaGuard

**AulaGuard** es una herramienta de administración para aulas de informática con Windows 10/11 Pro.

Su objetivo es permitir que el administrador defina qué puede utilizar un usuario estándar dentro de los equipos del aula, manteniendo el escritorio controlado y registrando intentos de acciones no permitidas.

## Estado actual

Versión inicial reconstruida: **v0.1.1**

Esta versión incluye la consola de administración y la persistencia de configuración. La aplicación efectiva de políticas de Windows se desarrollará en la siguiente fase.

## Funciones incluidas

- Ejecución exclusiva para administradores.
- Lista de programas permitidos.
- Lista de sitios web permitidos.
- Selección de fondo de escritorio institucional.
- Definición de accesos directos protegidos.
- Configuración almacenada en JSON.
- Bitácora local de acciones administrativas.
- Diagnóstico de inicio mediante `startup-error.txt`.
- Instalador básico para Windows.

## Objetivo funcional

AulaGuard está diseñado para evolucionar hacia un sistema que pueda:

- Bloquear juegos y aplicaciones no autorizadas.
- Limitar el acceso web.
- Impedir cambios de fondo de escritorio.
- Evitar que estudiantes renombren o eliminen accesos directos protegidos.
- Aplicar políticas a usuarios no administradores.
- Registrar intentos de acciones prohibidas.
- Permitir al administrador cambiar programas, accesos, sitios y fondo sin reinstalar el sistema.

## Requisitos

- Windows 10 Pro o Windows 11 Pro.
- PowerShell 5.1 o posterior.
- Cuenta con privilegios de administrador para configurar AulaGuard.

## Ejecutar

1. Descarga o clona el repositorio.
2. Ejecuta `Instalar.cmd` como administrador.
3. Inicia AulaGuard desde la ruta instalada o ejecuta `src\AulaGuard.ps1` con PowerShell.

## Estructura

```
aulaguard/
├─ src/
│  └─ AulaGuard.ps1
├─ config/
│  └─ default.json
├─ docs/
│  └─ ROADMAP.md
├─ Instalar.cmd
├─ .gitignore
└─ README.md
```

## Seguridad

AulaGuard no debe utilizarse como sustituto de las cuentas estándar de Windows, permisos NTFS, AppLocker/WDAC, directivas de grupo u otras funciones de seguridad del sistema. Su propósito es centralizar y simplificar la administración de un aula.

## Proyecto

Desarrollado para la administración de equipos de aulas de informática.
