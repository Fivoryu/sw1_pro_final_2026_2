# Prepropuesta pendiente — Publicaciones HU-022 a HU-025

## Estado

- **Cambio:** `hu022-025-publicaciones`.
- **Fase:** prepropuesta pendiente de decisiones de producto; `proposal` no está habilitada todavía.
- **Historias:** HU-022 crear y editar borrador; HU-023 enviar a revisión; HU-024 aprobar o rechazar; HU-025 publicar o despublicar.
- **Superficie:** backend y contrato HTTP consumible por Web; sin implementación de panel, mobile, worker 3D ni contratos Solidity.
- **Artefactos:** OpenSpec.
- **Ejecución:** automática, con estrategia `auto-chain`, cadena `stacked-to-main` y presupuesto de revisión de 400 líneas.
- **Strict TDD:** RED → GREEN → TRIANGULATE → REFACTOR.
- **Restricción:** no modificar código de producto, no ejecutar `apply`/`verify`, no realizar commits ni pushes durante la planificación.

## Hechos confirmados

- El backend tiene un workflow interno de revisiones y un catálogo público, pero no tiene rutas HTTP administrativas para el workflow.
- Las revisiones y transiciones existentes son inmutables/append-only según el modelo y las migraciones observadas.
- HU-022..HU-025 están registradas como implementadas por superficie, no como completadas; CP-009..CP-012 continúan `not executed`.
- El contrato HTTP administrativo, la edición de borradores, las responsabilidades por rol y varios guards de negocio aún no están definidos de forma verificable.

## Decisiones requeridas antes de `proposal`

### 1. Edición de borradores (`GAP-HU022-EDIT`)

- **`revision-replacement`**: editar significa crear una nueva revisión borrador completa y conservar la revisión previa como historial inmutable.
- **`draft-entity`**: introducir una representación/entidad borrador editable y materializar una revisión inmutable al enviar a revisión.
- **`defer-edit`**: especificar y contratar creación/envío/revisión/publicación, pero dejar edición como gap explícito hasta contar con una decisión posterior.

### 2. Responsabilidad de aprobación/publicación (`GAP-HU024-HU025-RESPONSIBILITY`)

- **`admin-approval-publish`**: solo el administrador aprueba/rechaza y publica/despublica; el agente crea y envía a revisión.
- **`admin-approval-agent-publish`**: el administrador aprueba/rechaza; el agente o administrador ejecuta publicar/despublicar cuando la revisión está aprobada.
- **`separate-approval-publish`**: aprobar deja la revisión aprobada y publicar es una operación posterior separada, exclusiva del administrador.

### 3. Autorización del contrato (`GAP-HU023-ROLES`)

- **`existing-authorizer`**: reutilizar únicamente el authorizer server-owned actual, documentando sus seams y dejando RBAC detallado para HU-009.
- **`membership-seam`**: exigir además membresía `active` de HU-008 para actores agentes, sin implementar catálogo RBAC.
- **`rbac-blocked`**: no habilitar contrato administrativo hasta que HU-009 defina el catálogo de permisos.

### 4. Contenido y validación (`GAP-HU022-CONTENT` / `GAP-HU024-QUALITY`)

- **`existing-model`**: usar los campos completos y validaciones ya exigidos por `PublicationRevision`; registrar difuminado/calidad como dependencias externas verificables.
- **`minimal-acceptance`**: limitar el contrato inicial a título y operación de venta/alquiler, dejando el resto como gap explícito.
- **`quality-contract-first`**: bloquear aprobación/publicación hasta disponer de contratos verificables para difuminado y calidad de reconstrucción.

### 5. Guard de suscripción (`GAP-HU-SUBSCRIPTION`)

- **`reuse-hu006-policy`**: reutilizar la política de estados de suscripción de HU-006 mediante su seam existente.
- **`publication-read-only`**: permitir únicamente consultas cuando el tenant esté en estados restrictivos; bloquear mutaciones con error estable.
- **`defer-subscription-guard`**: dejar el guard como dependencia explícita y no cerrar el contrato mutador hasta definirlo.

## Decisiones confirmadas

El usuario confirmó los cinco tokens recomendados:

```text
edit=revision-replacement
responsibility=admin-approval-publish
authorization=existing-authorizer
content=existing-model
subscription=reuse-hu006-policy
```

Estas decisiones habilitan la fase `proposal`. La propuesta debe mantener el alcance backend-first, reutilizar el workflow y authorizer existentes, preservar revisiones inmutables y mantener CP-009..CP-012 como `not executed`.

## Decisiones de entrega confirmadas

El usuario confirmó `delivery=auto-chain` y `chain_strategy=stacked-to-main`. La implementación deberá dividirse en unidades revisables de hasta 400 líneas; no se autoriza inferir una excepción de tamaño.
