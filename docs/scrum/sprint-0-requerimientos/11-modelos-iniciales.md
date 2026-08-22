# Sprint 0 — Modelos iniciales

| Campo | Valor |
| --- | --- |
| Módulo | S0-11 — CAPITULO 1, apartado 11 |
| Estado | planned (modelos lógicos descritos; diagramas pendientes en GAP-088) |
| IDs | MODEL; GAP-088 |
| Fuentes | persistencia de escenas (obs-2395, 2406); auditoría BR; ids-trazabilidad |

## 1. Modelo de datos (PostgreSQL)

Entidades principales derivadas de las reglas de negocio y la línea base:

| Área | Entidades núcleo |
| --- | --- |
| Identidad | `usuario_global`, `tenant`, `membresia`, `invitacion`, `permiso`, `auditoria` |
| Planes | `suscripcion`, `plan`, `cuota`, `evento_facturacion` (firmado e idempotente) |
| Inmueble/3D | `inmueble`, `ambiente`, `reconstruccion` (job), `artefacto` (S3 refs), `escena` (jerarquía + TRS), `plano_2d` |
| Catálogo | `catalogo_maestro`, `elemento_catalogo`, `categoria`, `publicacion`, `version_publicacion` |
| Comercial | `configuracion_publicacion`, `ajuste_precio`, `reserva`, `escrow_tx`, `favorito`, `acceso_temporal`, `notificacion` |

- Los binarios (capturas, nubes, GLB, texturas, planos) viven en **S3**; PostgreSQL guarda claves S3, hashes, tamaños, versiones y referencias (obs-2395).
- Las escenas se persisten como **jerarquía + transformaciones locales TRS**; las matrices globales se derivan en runtime (obs-2406). JSONB queda como tipo opcional para metadatos variables.

## 2. Modelo de artefactos 3D

- GLB empaqueta escena, mallas, materiales, texturas y buffers → objeto S3 versionado.
- Intermedios (nubes PLY/LAZ, workspaces, profundidad) → S3, referenciados por el job.
- Plano 2D básico: proyección derivada de la reconstrucción aprobada (RF-039).

## 3. Modelo de eventos y colas (SQS)

- Mensajes con **identificadores y referencias** (nunca archivos): `job_id`, claves S3.
- Worker idempotente: visibility timeout/heartbeat; elimina el mensaje solo tras confirmar el resultado; tolera reentregas (BR-061).
- Persistencia del trabajo **antes** de encolar (frontera transaccional).

## 4. Modelo blockchain (escrow)

- Token ERC20 de prueba (OpenZeppelin) + contrato `EscrowRoomforge` con estados `pending → escrowed → released/refunded`.
- El contrato conoce `reservaId`, `inmuebleId` y el dueño (tenant); emite eventos `Deposited/Released/Refunded/Expired`.
- Listener en FastAPI actualiza PostgreSQL idempotentemente; el job de expiración reconcilia estados (BR-057). Detalle: [`blockchain-enfoque.md`](../../sprint-0/blockchain-enfoque.md).

## 5. Diagramas

Tipos de diagrama de los modelos iniciales según el modelo Grupo#12 §11 (ver [`tipos-diagramas-modelo.md`](../../sprint-0/tipos-diagramas-modelo.md)):

| Modelo inicial | Tipo de diagrama | Módulo |
| --- | --- | --- |
| Modelo de contexto | **Diagrama de contexto** (actores externos y componentes) | S0-11 |
| Modelo de casos de uso | **Use Case** | S0-11 |
| Modelo de datos | **Class / ERD** (conceptual) | S0-11 |
| Modelo de arquitectura | **Package / Component** | S0-11 |
| Modelo de interfaces principales | Esquema de interfaces | S0-11 |

> Los diagramas se referencian por tipo (no se embeben imágenes); se crean cuando se elaboren los modelos (GAP-088). Las secciones 1–4 de este módulo son la entrada conceptual.
