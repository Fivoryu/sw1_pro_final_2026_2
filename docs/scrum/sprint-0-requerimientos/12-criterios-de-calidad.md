# Sprint 0 — Criterios de calidad

| Campo | Valor |
| --- | --- |
| Módulo | S0-12 — CAPITULO 1, apartado 12 |
| Estado | planned (criterios definidos; números dependientes de spike abiertos) |
| IDs | RNF-001..018; TC-###; GAP-065/066 |
| Fuentes | `docs/sprint-0/ids-trazabilidad.md` §4; riesgos R1/R2/R10 |

## Criterios por categoría

| Categoría | Criterio | Verificación |
| --- | --- | --- |
| Precisión | Medidas etiquetadas `estimadas`/`calibradas` con confianza visible; ocultamiento ante baja confianza | Tolerancia numérica **tras SPK-02** (GAP-065) -> RNF-001 |
| Rendimiento 3D | Reconstrucción por ambiente ≤ 30 min (objetivo) | SPK-01 (GAP-066) -> RNF-002 |
| Rendimiento API | Operaciones p95 ≤ 2 s | TC de rendimiento en CI |
| Visor 3D | 30 FPS objetivo / 24 FPS mínimo; primera vista ≤ 20 s | Perfil con datos reales (TC) |
| Disponibilidad | Servicios centrales recuperables ≤ 5 min en demo; jobs demorados continúan; degradación explícita | Ensayo de demo + TC de cola |
| Seguridad | TOTP administrativo; sesión inactiva 30 min; baseline multi-tenant; enlaces de un solo uso; jamás contraseñas por correo | TC de seguridad |
| Privacidad | Capturas crudas 30 días; derivados 7 días recuperables; difuminado + revisión humana; anonimización; logs 7 / auditoría 90 días | TC de retención (riesgo R10) |
| Compatibilidad | Android 10+ (64-bit, 4 GB); Chrome/Edge actuales; iOS declarado no verificado | Matriz en CI (emulador Android; navegadores) |
| Accesibilidad | WCAG 2.2 AA en panel; alternativa plano 2D + ficha | Auditoría accesibilidad (TC) |
| Observabilidad | Panel + correo con métricas accionables | Dashboards + alertas |

## Calidad de publicación (portal de calidad)

- Una publicación **no se publica** si la reconstrucción tiene defectos funcionales (BR-040).
- La publicación requiere revisión administrativa que incluye la **verificación del difuminado** (RNF-008, CU-025).
- Cada versión comercial preserva las reservas existentes (BR-036).

## Pruebas (contrato de caja negra)

Cada caso de prueba `TC-###` registra: trazabilidad (HU/CU/RF/RNF), setup, acción, esperado, real, resultado (`pass/fail/blocked/not executed/inconclusive`) y evidencia. Reglas:

- `pass` solo con evidencia de ejecución observada; un caso planificado no equivale a uno pasado.
- Cobertura de particiones normal, alterna, negativa y de límite cuando el requisito lo amerite.
- Los fallos se enlazan a `GAP-###` o defecto.

## Definition of Done (DoD) transversal

1. Criterios de aceptación de la HU cumplidos (GAP-070) y reglas BR vinculadas verificadas.
2. TC ejecutados y registrados (o `not executed` explícito con motivo).
3. CI en verde.
4. Sin regresiones en los RF ya implementados.

## Pendientes numéricos

| Criterio | Depende de | Estado |
| --- | --- | --- |
| Tolerancia de medidas (RNF-001) | SPK-02 | GAP-065 |
| Timeout/concurrencia de jobs (RNF-002) | SPK-01 | GAP-066 |
| Límites y precios de planes | SPK-01/04 | GAP-061 |
