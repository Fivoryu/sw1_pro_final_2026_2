# Tasks — Detector de mobiliario preentrenado (F08.1–F08.3)

Cada tarea cierra con su verificación y con un commit de unidad de trabajo **sólo cuando el dueño lo autorice** (AGENTS.md regla dura 1).

## F08T-T1 — F08.1 Ficha de candidato

- **Specs:** R1 (licencia verificable), R7 (alcance).
- **Entrega:** `docs/ai/f08-ficha-candidato.md` con licencia citada, clases útiles y ausentes, límites y el descarte o adopción explícito de la alternativa YOLO.
- **Verificación:** la ficha cita la fuente de cada afirmación de licencia; ningún término no declarado por el proyecto que publica los pesos se escribe como permiso; no se compró ni contrató nada.
- **Commit:** pendiente de autorización.

## F08T-T2 — F08.2 Servicio de inferencia y piloto

- **Specs:** R2 (reproducible), R3 (fotos autorizadas), R4 (resultados separados), R5 (medición o *no medido*), R7.
- **Entrega:** overlay Compose, Dockerfile con versiones exactas, `worker3d/detect.py`, pruebas del contrato de salida, bitácora de corridas en `docs/ai/`.
- **Verificación:** pruebas del contrato en RED y luego en GREEN; build desde cero; corrida real sobre el conjunto autorizado; informe con aciertos, falsos positivos y omisiones.
- **Bloqueo:** requiere las fotos autorizadas del dueño del producto. Sin ellas se puede construir y verificar la estructura, pero R3–R5 quedan pendientes y se declaran así.
- **Commit:** pendiente de autorización.

## F08T-T3 — F08.3 Decisión de ubicación y empaquetado

- **Specs:** R6.
- **Entrega:** `docs/ai/f08-decision-empaquetado.md` con la comparación teléfono offline frente a worker, y PyTorch frente a ONNX si se valida la conversión.
- **Verificación:** la decisión se apoya en las mediciones de F08T-T2 o declara por qué no pudo cerrarse, con el desbloqueo nombrado.
- **Commit:** pendiente de autorización.

## F08T-T4 — Verificación integrada y trazabilidad

- **Specs:** R7, R8.
- **Entrega:** `docs/plan-maestro-roomforge.md` (§1.4.1 y §F08) y `worker3d/README.md` actualizados; registro de ejecución en `odd/tasks/f08-furniture-ai.md`.
- **Verificación:** sólo `infra/docker/`, `worker3d/`, `docs/ai/`, artefactos SDD y registro ODD tocados; F08 declarada pendiente con el piloto documentado, no completa; sin commit ni push.
- **Commit:** pendiente de autorización.

## Fuera de estas tareas

F08.4 (trabajos asíncronos), F08.5 (confirmación humana e inventario) y F08.6 (mejora opcional). No se crean sus artefactos ni se declaran ejecutadas.
