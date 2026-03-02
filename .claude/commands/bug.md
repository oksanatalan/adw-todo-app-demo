---
description: Planifica la resolución de un bug generando un plan detallado en plans/*.md
allowed-tools:
  - Skill
  - Read
  - Glob
  - Grep
  - Write
  - Bash
  - Task
---

# Planificación de Bug

Crea un nuevo plan en RUTA_PLAN para resolver el `Bug` usando exactamente el formato markdown `Formato del Plan`. Sigue las `Instrucciones` y el `Workflow` para crear el plan.

## Variables

RUTA_PLAN: Si el primer argumento de $ARGUMENTS es una ruta (contiene / o termina en .md), usarlo como ruta del plan. Si no, generar en plans/<kebab-case-descriptivo>.md
BUG: El resto de $ARGUMENTS (excluyendo RUTA_PLAN si fue proporcionado como primer argumento)

## Instrucciones

- Estás escribiendo un plan para resolver un bug. Debe ser exhaustivo y preciso para que arreglemos la causa raíz y evitemos regresiones.
- Usa tu modelo de razonamiento: THINK HARD sobre BUG, su causa raíz y los pasos para solucionarlo correctamente.
- IMPORTANTE: Sé quirúrgico con la corrección del bug, resuelve el bug en cuestión y no te desvíes.
- IMPORTANTE: Queremos el mínimo número de cambios que corrijan y resuelvan el bug.
- IMPORTANTE: Reemplaza cada <placeholder> en el `Formato del Plan` con el valor solicitado. Añade todo el detalle necesario para corregir BUG.
- No uses decoradores. Mantenlo simple.
- Si necesitas una nueva gema Ruby, usa `bundle add` y asegúrate de reportarlo en la sección `Notas` del `Formato del Plan`.
- Si necesitas un nuevo paquete npm, usa `npm install` en el directorio frontend y asegúrate de reportarlo en la sección `Notas` del `Formato del Plan`.

## Workflow

### Paso 1: Preparar contexto
- Ejecuta el comando `/prime` para entender la estructura y contexto del codebase.
- Ejecuta el comando `/env:setup` para preparar el entorno de desarrollo.

### Paso 2: Investigar el bug
- Investiga el codebase para entender BUG, reproducirlo y elaborar un plan para solucionarlo.

### Paso 3: Crear el plan
- Crea el plan en RUTA_PLAN (creando directorios intermedios si es necesario con `mkdir -p`).
- Usa el `Formato del Plan` de abajo para crear el plan.

## Formato del Plan

```md
# Bug: <nombre del bug>

## Descripción del Bug
<describe el bug en detalle, incluyendo síntomas y comportamiento esperado vs actual>

## Planteamiento del Problema
<define claramente el problema específico que necesita ser resuelto>

## Propuesta de Solución
<describe el enfoque de solución propuesto para corregir el bug>

## Pasos para Reproducir
<lista los pasos exactos para reproducir el bug>

## Análisis de Causa Raíz
<analiza y explica la causa raíz del bug>

## Archivos Relevantes
Usa estos ficheros para corregir el bug:

<encuentra y lista los ficheros relevantes para el bug y describe por qué son relevantes en viñetas. Si hay ficheros nuevos que necesitan crearse para corregir el bug, lístalos en una sección h3 'Ficheros Nuevos'.>

## Tareas Paso a Paso
IMPORTANTE: Ejecuta cada paso en orden, de arriba a abajo.

<lista las tareas paso a paso como encabezados h3 más viñetas. Usa tantos encabezados h3 como sea necesario para corregir el bug. El orden importa, empieza con los cambios fundamentales compartidos necesarios para corregir el bug y luego pasa a los cambios específicos. Incluye tests que validen que el bug está corregido con cero regresiones. Tu último paso debe ser ejecutar los `Comandos de Validación` para validar que el bug está corregido sin regresiones.>

## Comandos de Validación
Ejecuta cada comando para validar que el bug está corregido sin regresiones.

<lista los comandos que usarás para validar con 100% de confianza que el bug está corregido sin regresiones. Cada comando debe ejecutarse sin errores, así que sé específico sobre lo que quieres ejecutar. Incluye comandos para reproducir el bug antes y después de la corrección.>
- `cd backend && bin/rails test` - Ejecuta los tests del backend para validar que el bug está corregido sin regresiones
- `cd frontend && npm test` - Ejecuta los tests del frontend para validar que el bug está corregido sin regresiones

## Notas
<opcionalmente lista notas adicionales o contexto relevante para el bug que sean útiles para el desarrollador>
```

## Reporte

Al finalizar, muestra al usuario:
- La ruta del plan creado: RUTA_PLAN
- Sugiere ejecutar `/implement RUTA_PLAN` para implementar el plan.
