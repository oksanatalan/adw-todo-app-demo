---
description: Planifica la resolución de un chore generando un plan detallado en plans/*.md
allowed-tools:
  - Skill
  - Read
  - Glob
  - Grep
  - Write
  - Bash
  - Task
---

# Planificación de Chore

Crea un nuevo plan en RUTA_PLAN para resolver el `Chore` usando exactamente el formato markdown `Formato del Plan`. Sigue las `Instrucciones` y el `Workflow` para crear el plan.

## Variables

RUTA_PLAN: Si el primer argumento de $ARGUMENTS es una ruta (contiene / o termina en .md), usarlo como ruta del plan. Si no, generar en plans/<kebab-case-descriptivo>.md
CHORE: El resto de $ARGUMENTS (excluyendo RUTA_PLAN si fue proporcionado como primer argumento)

## Instrucciones

- Estás escribiendo un plan para resolver un chore. Debe ser sencillo pero exhaustivo y preciso para que no se nos escape nada ni perdamos tiempo con una segunda ronda de cambios.
- Usa tu modelo de razonamiento: THINK HARD sobre el plan y los pasos para completar CHORE.
- IMPORTANTE: Reemplaza cada <placeholder> en el `Formato del Plan` con el valor solicitado. Añade todo el detalle necesario para completar CHORE.

## Workflow

### Paso 1: Preparar contexto
- Ejecuta el comando `/prime` para entender la estructura y contexto del codebase.
- Ejecuta el comando `/env:setup` para preparar el entorno de desarrollo.

### Paso 2: Investigar
- Investiga el codebase y elabora un plan para completar CHORE.

### Paso 3: Crear el plan
- Crea el plan en RUTA_PLAN (creando directorios intermedios si es necesario con `mkdir -p`).
- Usa el `Formato del Plan` de abajo para crear el plan.

## Formato del Plan

```md
# Chore: <nombre del chore>

## Descripción del Chore
<describe el chore en detalle>

## Archivos Relevantes
Usa estos ficheros para resolver el chore:

<encuentra y lista los ficheros relevantes para el chore y describe por qué son relevantes en viñetas. Si hay ficheros nuevos que necesitan crearse para completar el chore, lístalos en una sección h3 'Ficheros Nuevos'.>

## Tareas Paso a Paso
IMPORTANTE: Ejecuta cada paso en orden, de arriba a abajo.

<lista las tareas paso a paso como encabezados h3 más viñetas. Usa tantos encabezados h3 como sea necesario para completar el chore. El orden importa, empieza con los cambios fundamentales compartidos necesarios y luego pasa a los cambios específicos. Tu último paso debe ser ejecutar los `Comandos de Validación` para validar que el chore está completo sin regresiones.>

## Comandos de Validación
Ejecuta cada comando para validar que el chore está completo sin regresiones.

<lista los comandos que usarás para validar con 100% de confianza que el chore está completo sin regresiones. Cada comando debe ejecutarse sin errores, así que sé específico sobre lo que quieres ejecutar. No valides con comandos curl.>
- `cd backend && bin/rails test` - Ejecuta los tests del backend para validar que el chore está completo sin regresiones
- `cd frontend && npm test` - Ejecuta los tests del frontend para validar que el chore está completo sin regresiones

## Notas
<opcionalmente lista notas adicionales o contexto relevante para el chore que sean útiles para el desarrollador>
```

## Reporte

Al finalizar, muestra al usuario:
- La ruta del plan creado: RUTA_PLAN
- Sugiere ejecutar `/implement RUTA_PLAN` para implementar el plan.
