# Riesgos consolidados — RoomForge (Sprint 0)

| Campo | Valor |
| --- | --- |
| Artefacto | Registro de riesgos del proyecto (entrada para PAPS y Sprint 0) |
| Estado | Aprobado por el equipo (2026-08-22) |
| Convención | `R-###` provisional; escala: Prob. Baja/Media/Alta; Impacto Bajo/Medio/Alto |

| # | Riesgo | Prob. | Impacto | Respuesta | Mitigación | Seguimiento |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | Reconstrucción 3D más lenta que 30 min o falla en GPU | Media | Alto | Mitigar | SPK-01 define timeout real; degradación explícita; cola asíncrona | Resultados SPK-01 → timeout y concurrencia |
| R2 | Precisión de medidas fuera de tolerancia | Media | Alto | Mitigar | SPK-02; UI `estimada`/`calibrada`; ocultar medidas de baja confianza | Resultados SPK-02 → tolerancia RNF |
| R3 | Worker RTX 4050 como punto único | Media | Alto | Mitigar | SPK-03 valida GTX; jobs persisten en cola; catálogo/reservas aislados | Inventario GPU; prueba GTX en Monstree |
| R4 | Créditos/cuenta AWS sin confirmar | Media | Alto | Mitigar | Despliegue diferido; Floci local; presupuesto estimado post-spikes | Confirmar cuenta/créditos/región antes de la semana de despliegue |
| R5 | Disponibilidad del equipo (20 h base) | Alta | Medio | Aceptar/Mitigar | Capacidad base conservadora; spikes paralelos; priorización estricta | Revisar capacidad en cada Sprint Planning |
| R6 | Despliegue de última hora antes de la presentación | Alta | Medio | Mitigar | Smoke test SPK-05; CI temprana; ensayo de despliegue 1 semana antes | SPK-05 por integrante; calendario de ensayo |
| R7 | Contenido privado en capturas (falsos negativos del difuminado) | Media | Medio | Mitigar | Revisión humana obligatoria antes de publicar (BR-G4) | Checklist de revisión en workflow de publicación |
| R8 | Dependencia de GPU cloud no aprobada (evitada por diseño) | Baja | Medio | Evitar | Worker híbrido local como ruta sin costo | Revisar solo si el pool NVIDIA falla |
| R9 | iOS no verificado (sin Mac/Xcode) | Alta | Bajo | Aceptar | Solo Android obligatorio; iOS como gap declarado | No prometer compatibilidad verificada |
| R10 | Pérdida de datos por purgas/errores de retención | Baja | Medio | Mitigar | Períodos definidos (30d/7d); derivados recuperables; pruebas de retención | Pruebas de retención en CI |

## Plan de respuesta

- **Evitar**: eliminar la causa (R8: no depender de GPU cloud).
- **Mitigar**: reducir probabilidad o impacto (R1–R4, R6, R7, R10).
- **Aceptar**: costo conocido y asumible (R5 con capacidad base, R9).
- **Transferir**: no aplica en el alcance actual (sin proveedores externos de riesgo).

## Próximo seguimiento

- Tras SPK-01/02/03: actualizar R1, R2, R3 con datos medidos.
- Antes de la semana de despliegue: cerrar R4 (cuenta/créditos/región) y ejecutar R6 (ensayo).
