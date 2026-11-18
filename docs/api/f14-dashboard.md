# API del dashboard de métricas (F14.4)

Contrato de `GET /api/v1/staff/agencies/{agency_id}/metrics` (`backend/app/modules/agencies/router.py`, servicio `get_agency_metrics`). Es de solo lectura: no agrega acciones ni cambia estados. Los errores tienen la forma `{ "detail": "...", "code": "..." }`.

## Autorización

Solo el `agency_admin` de la agencia de la URL, con sesión de personal (`Authorization: Bearer`).

| Actor | Respuesta |
| --- | --- |
| `agency_admin` de la agencia | `200` |
| `agent` de la agencia | `403` |
| Personal de otra agencia | `403` |
| `platform_admin` | `403` (las métricas de plataforma están fuera de alcance) |
| Agencia inexistente | `403`, con el mismo cuerpo que otra agencia |
| Sin sesión, token inválido o token de cliente | `401` |

## Respuesta `200`

```json
{
  "listings": {
    "draft": 1,
    "in_review": 2,
    "published": 2,
    "approved_unpublished": 1,
    "rejected": 1,
    "total": 7
  },
  "active_quotes": 2,
  "reservations": {
    "pending": 1,
    "accepted": 1,
    "rejected": 0,
    "cancelled": 1,
    "expired": 1
  }
}
```

- **`listings`:** los inmuebles de la agencia según su estado guardado. Cada inmueble cae en exactamente un grupo, así que la suma de los cinco grupos es `total`.

  | Grupo | Estado en la base |
  | --- | --- |
  | `draft` | `approval_status = draft` |
  | `in_review` | `pending` |
  | `published` | `approved` con `is_published = true` |
  | `approved_unpublished` | `approved` con `is_published = false` |
  | `rejected` | `rejected` |

- **`active_quotes`:** cotizaciones de los inmuebles de la agencia cuyo vencimiento (`expires_at`) es posterior al momento de la consulta.
- **`reservations`:** reservas de los inmuebles de la agencia por estado (`pending`, `accepted`, `rejected`, `cancelled`, `expired`).

Ningún dato de otra agencia entra en los conteos.

## Pruebas

`backend/tests/test_agency_metrics.py`:

- conteos contra la base, con la suma de los grupos igual al total y cotizaciones vigentes y vencidas;
- aislamiento por actor (agente, otra agencia y `platform_admin`), agencia inexistente igual a otra agencia, y sesión ausente, inválida o de cliente.

Panel: `src/application/agencyMetricsApi.test.ts` y `src/features/agencies/AgencyDashboard.test.tsx`.
