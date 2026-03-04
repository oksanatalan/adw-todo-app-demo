---
description: Genera un nombre de rama git, crea la rama y reporta el nombre
allowed-tools:
  - Bash
---

# Crear Rama Git

Genera un nombre de rama descriptivo y crea la rama git desde main.

## Variables

ISSUE_CLASS: $1 - Tipo de issue (feat, bug, chore)
ADW_ID: $2 - Identificador del workflow ADW
ISSUE: $3 - JSON de la issue de Github

## Instrucciones

- Extrae el numero de issue, titulo y cuerpo del JSON de ISSUE.
- Genera el nombre de rama con el formato: `<ISSUE_CLASS>-<issue_number>-<ADW_ID>-<nombre_conciso>`
- El `<nombre_conciso>` debe ser:
  - 3-6 palabras maximo
  - Todo en minusculas
  - Palabras separadas por guiones
  - Descriptivo de la tarea principal
  - Sin caracteres especiales excepto guiones
- Ejemplos: `feat-123-a1b2c3d4-add-user-auth`, `bug-456-e5f6g7h8-fix-login-error`

## Workflow

### Paso 1: Generar nombre de rama
- Analiza ISSUE y genera el nombre de rama siguiendo el formato de las instrucciones.

### Paso 2: Crear la rama
- Ejecuta `git checkout main` para cambiar a la rama principal.
- Ejecuta `git pull` para obtener los ultimos cambios.
- Ejecuta `git branch <nombre_rama>` para crear la rama sin cambiar a ella.

## Reporte

Responde EXCLUSIVAMENTE con el nombre de la rama creada (sin texto adicional).
