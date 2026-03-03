---
description: Revisa que la implementacion cumple los requisitos de la issue con evidencia visual
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
---

# Revision contra la Issue con Evidencia Visual

Revisa que los cambios implementados cumplen con los requisitos de la issue original, verificando visualmente la aplicacion y tomando capturas de pantalla como evidencia.

## Variables

ISSUE: $1 - JSON de la issue de Github
PLAN_PATH: $2 - Ruta al fichero del plan de implementacion

## Instrucciones

- Lee la issue y el plan para entender los requisitos esperados.
- Analiza los cambios realizados en la rama actual respecto a main.
- Verifica visualmente que la aplicacion implementa lo que la issue pedia.
- Toma entre 1 y 5 capturas de pantalla que demuestren la funcionalidad.
- Evalua si la implementacion cumple los requisitos (plan_adherence).
- IMPORTANTE: Devuelve SOLO el JSON con los resultados.
  - IMPORTANTE: No incluyas texto adicional, explicaciones ni formato markdown.
  - Ejecutaremos JSON.parse() directamente sobre la salida, asi que asegurate de que sea JSON valido.

## Workflow

### Paso 1: Obtener contexto
- Lee la issue (ISSUE) para extraer los requisitos y criterios de aceptacion.
- Lee el plan de implementacion (PLAN_PATH) para entender que se esperaba construir.
- Ejecuta `git diff origin/main...HEAD --stat` para ver los ficheros cambiados.

### Paso 2: Preparar entorno de screenshots
- Verifica si Playwright esta disponible: `npx --yes playwright --version`
- Si no hay navegadores instalados: `npx playwright install chromium`
- Extrae el numero de issue del JSON de ISSUE.
- Crea el directorio de evidencia: `mkdir -p .issues/{issue_number}/evidences`

### Paso 3: Verificar que la aplicacion esta corriendo
- Comprueba si el backend responde: `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/tasks`
- Comprueba si el frontend responde: `curl -s -o /dev/null -w "%{http_code}" http://localhost:5173`
- Si alguno no responde, intenta arrancarlo:
  - Backend: `cd backend && bin/dev &` (background, esperar 10s)
  - Frontend: `cd frontend && bin/dev &` (background, esperar 10s)
- Reintenta las comprobaciones.
- Si aun no responde, reporta error en el JSON de salida.

### Paso 4: Tomar capturas de pantalla
- Crea un script temporal de Node.js en `.issues/{issue_number}/adw_review_issue.js` que use Playwright para:
  1. Abrir el navegador Chromium en modo headless.
  2. Navegar a http://localhost:5173 (pagina principal).
  3. Esperar a que la pagina cargue completamente (networkidle).
  4. Tomar una captura de pantalla de pantalla completa.
  5. Si el plan o la issue mencionan interacciones especificas (crear tarea, completar tarea, filtrar, etc.), realizarlas y tomar capturas adicionales.
  6. Guardar cada captura en `.issues/{issue_number}/evidences/01_desc.png`, `02_desc.png`, etc.
  7. Cerrar el navegador.
- Ejecuta el script: `node .issues/{issue_number}/adw_review_issue.js`
- IMPORTANTE: Apunta hacia 1-5 capturas enfocadas en la funcionalidad critica.
- IMPORTANTE: Usa nombres descriptivos: `01_vista_principal.png`, `02_formulario_tarea.png`, etc.

### Paso 5: Evaluar adherencia al plan
- Compara los requisitos de la issue con lo implementado (diff + capturas).
- Evalua si todos los criterios de aceptacion se cumplen.
- Marca como PASS si la implementacion cumple con los requisitos.
- Marca como FAIL si faltan funcionalidades o no se cumplen criterios.

### Paso 6: Verificar resultados
- Comprueba que las capturas se crearon correctamente.
- Lista los ficheros en `.issues/{issue_number}/evidences/`.

## Reporte

- IMPORTANTE: Devuelve resultados exclusivamente como un objeto JSON basado en la seccion `Estructura de Salida`.

### Estructura de Salida

```json
{
  "success": true,
  "summary": "string - resumen de 2-4 frases describiendo lo construido y si cumple los requisitos",
  "plan_adherence": {
    "result": "PASS | FAIL",
    "severity": "info | warning | critical",
    "details": "string - justificacion de la evaluacion"
  },
  "review_issues": [
    {
      "issue_number": 1,
      "screenshot_path": "string - ruta absoluta a la captura que muestra el problema",
      "description": "string - descripcion del problema encontrado",
      "resolution": "string - sugerencia de resolucion",
      "severity": "skippable | tech_debt | blocker"
    }
  ],
  "screenshots": [
    {
      "filename": "string - nombre del fichero",
      "path": "string - ruta absoluta a la captura",
      "description": "string - descripcion de lo que muestra la captura"
    }
  ],
  "errors": ["string - errores si los hay"]
}
```

### Ejemplo de Salida

```json
{
  "success": true,
  "summary": "La funcionalidad de hora limite en las tareas se implemento correctamente. El formulario incluye el campo de hora y las tareas muestran la hora limite en la lista. La implementacion cumple con todos los requisitos de la issue.",
  "plan_adherence": {
    "result": "PASS",
    "severity": "info",
    "details": "Todos los requisitos de la issue estan implementados: campo de hora en formulario, visualizacion en lista, persistencia en base de datos."
  },
  "review_issues": [],
  "screenshots": [
    {
      "filename": "01_lista_tareas.png",
      "path": ".issues/10/evidences/01_lista_tareas.png",
      "description": "Vista principal mostrando las tareas con la hora limite visible"
    },
    {
      "filename": "02_formulario_crear.png",
      "path": ".issues/10/evidences/02_formulario_crear.png",
      "description": "Formulario de creacion de tarea con el nuevo campo de hora limite"
    }
  ],
  "errors": []
}
```
