# F14.5 — Búsqueda de inmuebles por zona

**Objetivo:** el cliente encuentra inmuebles cercanos a su ubicación o dentro de un radio alrededor de un punto que elige. **Plan:** `docs/plan-maestro-roomforge.md` F14.5. **Issue:** #76.
**Rama:** `feat/f14-zone-search` desde `main` actualizado. **Entrega:** `ask-on-risk`.
**Ejecutores de pruebas:** `backend` con `<raiz>/.venv/Scripts/python.exe -m pytest`, Ruff y Pyright; apps con `flutter test` y `flutter analyze`; `panel` con `vitest`.

## Specs

Las citas entre comillas son texto literal del dueño del repositorio. **[Propuesta]** = planteada por el asistente en la sesión de diseño y no objetada por el usuario; confirmar ante cualquier duda.

- **S1 — Búsqueda por cercanía o por punto y radio.** «En si el cliente ve todos los inmuebles de las agencias, la idea es que vea por zonas que esten cerca de su ubicación o que pueda seleccionar una ubicación y poner un rango de km y visualizar los inmuebles que estan en dicha zona.»
  - Aceptación: con un punto y un radio, el catálogo público devuelve solo los inmuebles publicados dentro de ese radio; sin esos parámetros el catálogo se comporta igual que hoy.
- **S2 — Coordenadas del inmueble.** El agente marca el punto en un mapa al crear o editar el inmueble. Los inmuebles publicados sin coordenadas no aparecen en la búsqueda por zona y siguen apareciendo en el catálogo general. El catálogo público expone la ubicación del inmueble.
- **S3 — Sin permiso de ubicación. [Propuesta]** El cliente elige un punto en el mapa o una ciudad.
- **S4 — Privacidad. [Propuesta]** La ubicación del cliente viaja solo como parámetro de la consulta y no se guarda.
- **S5 — Distancia y radio. [Propuesta]** Distancia en línea recta; radio de 1 a 50 km, 5 km por defecto.
- **S6 — Mapa. [Propuesta]** OpenStreetMap, sin clave de pago. Verificar licencia y condiciones de uso de la librería y del servidor de teselas antes de elegir.

## Tasks

Estado: ☐ pendiente. Ruta por defecto: en línea.

| ID | Tarea | Specs | Ruta | Estado | Commit / evidencia |
| --- | --- | --- | --- | --- | --- |
| T1 | Backend: coordenadas opcionales en el inmueble (migración Alembic, un solo head, GAP-093), validación de rangos y exposición en borrador, revisión y catálogo. | S2 | en línea | ☐ | — |
| T2 | Backend: filtro por punto y radio en el catálogo público, con orden por distancia y pruebas de borde (radio mínimo y máximo, inmueble sin coordenadas, parámetros incompletos). | S1, S4, S5 | en línea | ☐ | — |
| T3 | App de captura y panel: marcar y corregir el punto del inmueble en un mapa. | S2, S6 | en línea | ☐ | — |
| T4 | App cliente: permiso de ubicación, selector de punto y radio, y resultados por zona con estados vacío, carga y error. | S1, S3, S5, S6 | en línea | ☐ | — |
| T5 | Cierre: documentación, contrato de API y filas del plan maestro. | — | en línea | ☐ | — |

**Riesgo previsto:** T1 puede nombrar el ítem 1 (migración) y T3/T4 el ítem 5 (dependencia nueva de mapas).

**Estado verificado (2026-11-12, `main` en `9981b49`, búsqueda por palabras clave, no auditoría):** `backend/app/modules/catalog/models.py` no tiene latitud ni longitud; no se encontró ninguna librería de mapas en `apps/*/pubspec.yaml` ni en el `package.json` del panel. No se ejecutó ninguna suite.

## Log

- **L1 (2026-11-12, usuario):** «En si el cliente ve todos los inmuebles de las agencias, la idea es que vea por zonas que esten cerca de su ubicación o que pueda seleccionar una ubicación y poner un rango de km y visualizar los inmuebles que estan en dicha zona.»
- **L2 (2026-11-12):** el asistente propuso S2–S6 para cubrir huecos; el usuario no los objetó ni los confirmó de forma expresa. A la pregunta de agregar las funcionalidades al plan y crear los documentos respondió «5. Si». Siguiente paso: T1.
- **L3 (usuario):** «Vamos papu» en respuesta a la propuesta de que el agente marque el punto y que los inmuebles sin coordenadas aparezcan en el catálogo general, pero no en búsquedas por radio.
- **L4 (usuario):** «QUe exponga la ubicacion del inmueble» en respuesta a si el catálogo público expone la ubicación exacta.
