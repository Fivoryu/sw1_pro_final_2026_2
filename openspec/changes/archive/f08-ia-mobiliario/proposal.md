# Proposal — Piloto de detección de mobiliario con IA preentrenada (F08.1–F08.3)

- **Cambio:** `f08-ia-mobiliario`
- **Fase del plan:** F08 (`docs/plan-maestro-roomforge.md` §F08), subfases F08.1, F08.2 y F08.3
- **Alcance posterior:** F08.4, F08.5 y F08.6 quedan fuera y no se simulan
- **Ejecución:** interactiva · **Almacén:** híbrido (OpenSpec + Engram)
- **Presupuesto de líneas modificadas:** 600 (límite del proyecto); el piloto es mayoritariamente documental y de configuración
- **Estado de evidencia:** propuesta. Sin pesos descargados, sin runtime instalado, sin mediciones, sin commits ni push

## 1. Resultado y propósito

RoomForge necesita saber, con evidencia propia, si un detector de objetos preentrenado puede sugerir mobiliario en una foto autorizada de un inmueble, y dónde conviene ejecutarlo. Esta unidad entrega tres resultados acotados:

1. **Una ficha de candidato** con nombre y versión exactos, licencia, clases útiles, clases ausentes y límites declarados. Sin compra de licencias ni contratación de servicios.
2. **Un servicio de inferencia reproducible** en `infra/docker`, de CPU y sin GPU, que ejecuta el detector sobre un conjunto autorizado y pequeño de fotos, y emite clases, cajas y puntuaciones como artefacto verificable.
3. **Una decisión documentada** de ubicación y empaquetado (teléfono offline frente a worker), apoyada en latencia y memoria medidas en este equipo, o declarada imposible de cerrar si no se pudieron medir.

La sugerencia es una propuesta, nunca un hecho: el agente confirma, corrige o descarta. El detector no inventa geometría métrica ni precio.

## 2. Por qué ahora

F08 está bloqueada en su parte integrada por F06, que no tiene implementación. Pero el plan autoriza explícitamente un arranque anticipado acotado: §1.5 regla 5 permite «F08 puede empezar con el piloto de inferencia antes de F05/F06». Esa excepción existe justamente porque el piloto no necesita ni el visor ni el contrato de escena.

Hacer el piloto ahora responde la pregunta que más puede cambiar el alcance: si el detector base no sirve, el producto necesita otra estrategia antes de invertir en la integración. Y la respuesta es barata: no requiere backend, ni migraciones, ni pantallas, ni embargo de superficies que F06 va a tocar.

## 3. Alcance

**Dentro:**

- Evaluación de candidatos con foco en licencia y clases, incluida la alternativa YOLO y el motivo explícito de su descarte o adopción.
- Servicio de inferencia en Docker, sólo CPU, con versiones fijadas y digest del artefacto registrado.
- Piloto sobre 20–40 fotos autorizadas, con revisión manual y separación entre aciertos, falsos positivos y omisiones.
- Registro honesto de latencia y memoria observadas; los campos que la herramienta no exponga se registran como **no medidos**.
- Decisión de ubicación y empaquetado, y la comparación PyTorch frente a ONNX sólo si se valida que la conversión conserva el comportamiento.

**Fuera:**

- Descargar COCO completo, pedir conjuntos masivos de fotos propias o presentar una puntuación como probabilidad calibrada.
- Ajuste fino, entrenamiento desde cero y cualquier adquisición de licencia.
- Endpoints de sugerencias en el backend, trabajos asíncronos, colas y reintentos (F08.4).
- Pantalla de confirmación de sugerencias, colocación en escena, inventario confirmado y enlace a F05/F06 (F08.5).
- Congelar el contrato «sugerencias de IA (F08 ↔ F05/F06)»: esta unidad sólo deja el borrador de campos que la integración futura necesitará, como insumo para esa decisión.

## 4. Riesgos y cómo se contienen

| Riesgo | Contención |
|---|---|
| Presentar el piloto como calidad estadística | 20–40 fotos son exploración con revisión manual; el documento lo declara y no extrapola. |
| Licencia incompatible con un SaaS | La ficha de candidato evalúa licencia primero; AGPL-3.0 queda registrada como bloqueo de producto, no como detalle. |
| Mezclar el runtime de IA con el entorno de la API | Servicio aparte en `infra/docker`; `.venv` del backend no se toca. |
| Citar métricas ajenas como propias | Prohibido por F08.3: sólo se reporta lo medido acá, con comando, versión y condiciones. |
| Adelantar trabajo de F06/F05 | La superficie autorizada excluye backend de producto, panel y apps. |

## 5. Trazabilidad

- Plan maestro: §F08 (F08.1–F08.3), §1.5 reglas 5 y 6, §5.4 (flujo SDD).
- Destino futuro de una sugerencia confirmada: `ListingExtra` (F05.1) y el contrato de escena de F06.
- El cierre de esta unidad **no** marca F08 completa: §1.4.1 y §F08 se actualizan declarando el límite.
