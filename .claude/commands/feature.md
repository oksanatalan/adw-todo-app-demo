---
description: Planifica la implementación de una nueva funcionalidad generando un plan detallado en plans/*.md
allowed-tools:
  - Skill
  - Read
  - Glob
  - Grep
  - Write
  - Bash
  - Task
---

# Planificación de Feature

Crea un nuevo plan en RUTA_PLAN para implementar el `Feature` usando exactamente el formato markdown `Formato del Plan`. Sigue las `Instrucciones` y el `Workflow` para crear el plan.

## Variables

RUTA_PLAN: Si el primer argumento de $ARGUMENTS es una ruta (contiene / o termina en .md), usarlo como ruta del plan. Si no, generar en plans/<kebab-case-descriptivo>.md
FEATURE: El resto de $ARGUMENTS (excluyendo RUTA_PLAN si fue proporcionado como primer argumento)

## Instrucciones

- Estás escribiendo un plan para implementar una nueva funcionalidad que aportará valor a la aplicación.
- Usa tu modelo de razonamiento: THINK HARD sobre los requisitos de FEATURE, el diseño y el enfoque de implementación.
- IMPORTANTE: Reemplaza cada <placeholder> en el `Formato del Plan` con el valor solicitado. Añade todo el detalle necesario para implementar FEATURE con éxito.
- Sigue los patrones y convenciones existentes en el codebase. No reinventes la rueda.
- Diseña para extensibilidad y mantenibilidad.
- Si necesitas una nueva gema Ruby, usa `bundle add` y asegúrate de reportarlo en la sección `Notas` del `Formato del Plan`.
- Si necesitas un nuevo paquete npm, usa `npm install` en el directorio frontend y asegúrate de reportarlo en la sección `Notas` del `Formato del Plan`.

## Workflow

### Paso 1: Preparar contexto
- Ejecuta el comando `/prime` para entender la estructura y contexto del codebase.
- Ejecuta el comando `/env:setup` para preparar el entorno de desarrollo.

### Paso 2: Investigar
- Investiga el codebase para entender los patrones existentes, la arquitectura y las convenciones antes de planificar FEATURE.

### Paso 3: Crear el plan
- Crea el plan en RUTA_PLAN (creando directorios intermedios si es necesario con `mkdir -p`).
- Usa el `Formato del Plan` de abajo para crear el plan.

## Formato del Plan

```md
# Feature: <nombre de la funcionalidad>

## Descripción de la Funcionalidad
<describe la funcionalidad en detalle, incluyendo su propósito y valor para los usuarios>

## Historia de Usuario
Como <tipo de usuario>
Quiero <acción/objetivo>
Para que <beneficio/valor>

## Planteamiento del Problema
<define claramente el problema específico u oportunidad que aborda esta funcionalidad>

## Propuesta de Solución
<describe el enfoque de solución propuesto y cómo resuelve el problema>

## Archivos Relevantes
Usa estos ficheros para implementar la funcionalidad:

<encuentra y lista los ficheros relevantes para la funcionalidad y describe por qué son relevantes en viñetas. Si hay ficheros nuevos que necesitan crearse para implementar la funcionalidad, lístalos en una sección h3 'Ficheros Nuevos'.>

## Plan de Implementación
### Fase 1: Fundamentos
<describe el trabajo fundacional necesario antes de implementar la funcionalidad principal>

### Fase 2: Implementación Principal
<describe el trabajo principal de implementación de la funcionalidad>

### Fase 3: Integración
<describe cómo la funcionalidad se integrará con la funcionalidad existente>

## Tareas Paso a Paso
IMPORTANTE: Ejecuta cada paso en orden, de arriba a abajo.

<lista las tareas paso a paso como encabezados h3 más viñetas. Usa tantos encabezados h3 como sea necesario para implementar la funcionalidad. El orden importa, empieza con los cambios fundamentales compartidos y luego pasa a la implementación específica. Incluye la creación de tests a lo largo del proceso de implementación. Tu último paso debe ser ejecutar los `Comandos de Validación` para validar que la funcionalidad funciona correctamente sin regresiones.>

## Estrategia de Testing
### Tests Unitarios
<describe los tests unitarios necesarios para la funcionalidad>

### Tests de Integración
<describe los tests de integración necesarios para la funcionalidad>

### Casos Límite
<lista los casos límite que necesitan ser probados>

## Criterios de Aceptación
<lista criterios específicos y medibles que deben cumplirse para que la funcionalidad se considere completa>

## Comandos de Validación
Ejecuta cada comando para validar que la funcionalidad funciona correctamente sin regresiones.

<lista los comandos que usarás para validar con 100% de confianza que la funcionalidad está implementada correctamente sin regresiones. Cada comando debe ejecutarse sin errores, así que sé específico sobre lo que quieres ejecutar. Incluye comandos para probar la funcionalidad de extremo a extremo.>
- `cd backend && bin/rails test` - Ejecuta los tests del backend para validar que la funcionalidad funciona sin regresiones
- `cd frontend && npm test` - Ejecuta los tests del frontend para validar que la funcionalidad funciona sin regresiones

## Notas
<opcionalmente lista notas adicionales, consideraciones futuras o contexto relevante para la funcionalidad que sean útiles para el desarrollador>
```

## Reporte

Al finalizar, muestra al usuario:
- La ruta del plan creado: RUTA_PLAN
- Sugiere ejecutar `/implement RUTA_PLAN` para implementar el plan.
