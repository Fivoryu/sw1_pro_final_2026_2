# Explore — Detector de mobiliario preentrenado (F08.1–F08.3)

- **Cambio:** `f08-ia-mobiliario`
- **Fase del plan:** F08 (`docs/plan-maestro-roomforge.md` §F08)
- **Almacén:** híbrido (OpenSpec + Engram)
- **Ejecución:** interactiva, fondo de rama `feat/f08-furniture-ai-pilot`
- **Estado de evidencia:** exploración. No se descargaron pesos, no se instaló ningún runtime, no se compró ni contrató nada, no hay mediciones.

## Qué existe hoy (verificado 2026-10-14)

| Superficie | Estado real |
|---|---|
| `worker3d/` | Sólo `README.md`. Sin detector, sin pesos, sin trabajos asíncronos. |
| `.venv` raíz | Python 3.12.13. **No** tiene `torch` ni `ultralytics`. |
| `contracts/` | Escrow de reservas (F09). Sin relación con F08. |
| `backend/` | Módulos `identity`, `customer_identity`, `customer_wallet`, `agencies`, catálogo, cotizaciones y reservas. Sin endpoint de sugerencias de IA. |
| Inventario de mobiliario (F05) | `ListingExtra` con ID estable, nombre, precio, categoría, habitación, dimensiones, procedencia, vínculo visual y cantidad. Es el destino natural de una sugerencia confirmada. |
| Escena 3D (F06) | **Sin implementación integrada.** La rama `origin/feat/f06-modelo-editable` (`43f629e`, nueve commits, sin integrar, siete commits detrás de `origin/main`) trae un borrador de contrato en `docs/api/f06-scene-contract.md` y un visor en `panel/staff-shell/src/features/editor3d/SceneViewer.tsx`. No trae F06.3 (editor de correcciones) ni F06.5. |

## Restricciones que condicionan el alcance

1. **Dependencia dura de F06 para la integración.** F08.5 pide «colocar formas en escena» sobre F05/F06 y F08.4 persiste trabajos por API. Ninguna de las dos puede cerrarse contra superficies que no existen.
2. **Excepción acotada y explícita del plan.** §1.5 regla 5 autoriza *sólo* el piloto de inferencia antes de F05/F06. El alcance de esta unidad se apoya en esa excepción y no la extiende.
3. **Contrato compartido sin congelar.** §1.5 regla 6 exige congelar «sugerencias de IA (F08 ↔ F05/F06)» antes de que cada rama implemente. El borrador de `objects[]` de F06 no tiene campos de sugerencia, confianza ni procedencia: **el contrato no existe todavía**.
4. **Licencias.** Sin compra de licencias ni contratación de servicios. Una licencia que obligue a liberar el código completo del SaaS no es una dependencia «permitida para la modalidad elegida» (F08.1).
5. **Sin runtime de IA en el entorno del backend.** Instalar `torch` en `.venv` mezclaría un runtime de cómputo pesado con el entorno de la API. El usuario decidió un servicio aparte en `infra/docker`.

## Preguntas abiertas

| # | Pregunta | Quién decide | Cuándo |
|---|---|---|---|
| P1 | ¿Qué 20–40 fotos autorizadas se usan como entrada del piloto, y con qué permiso? | Dueño del producto | Antes de F08.2 |
| P2 | ¿Se acepta la exclusión de puertas, ventanas y escritorios, dado que COCO no los contiene? | Dueño del producto | Antes de cerrar F08.1 |
| P3 | ¿Se confirma `torchvision` como candidato, o se quiere reconsiderar YOLO pagando licencia Enterprise (requiere autorización de compra)? | Dueño del producto | F08.1 |
| P4 | ¿Móvil offline o worker en PC/AWS? | Dueño del producto, con los datos de F08.2 | F08.3 |

## Hipótesis a validar, no afirmaciones

- Que un detector COCO preentrenado sin ajuste rinde lo suficiente para *sugerir* mobiliario en una foto de inmueble. La precisión real es **desconocida** hasta que F08.2 la mida; no se extrapola desde ningún benchmark ajeno.
- Que la decisión de empaquetado pueda tomarse con latencia y memoria medidas en hardware propio. Sin esas mediciones, F08.3 no puede cerrarse.
