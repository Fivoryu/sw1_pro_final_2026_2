# Defectos heredados en la CI de `main` (pyright y revision ids)

**Contexto:** el merge de F02 (PR #6, `98ce894b97356e5c1808f8f9be0814495ad30697`) trajo a `main` el workflow `.github/workflows/ci.yml`, que hasta entonces solo existía en la rama F02. Su primera ejecución real sobre `main` (run `36594625038`) dejó 3 de 4 jobs en verde —captura, cliente y panel— y el job de backend falló **solo** en el paso `pyright app tests`, con `pytest` y `ruff` en verde.

Tanto esos errores de tipos como dos revision ids de Alembic demasiado largos son defectos **preexistentes** de la línea catálogo/reservas (PR #4): no los introdujo el merge ni el trabajo F02. Se corrigen acá para que la CI de `main` quede verde.

## Defecto 1 — 15 errores de pyright

| Archivo | Errores | Causa | Corrección |
|---|---:|---|---|
| `backend/app/modules/catalog/router.py` | 4 | `operation` se almacena como `str` y la respuesta exige `Literal["sale", "rent"]`; `Query(ge=Decimal("0"))` no coincide con `float \| None` | alias único `ListingOperation` en `schemas.py`, `cast` explícito al leer de la base y `ge=0` en los dos filtros de precio |
| `backend/tests/test_catalog_migration.py` | 7 | acceso a `.precision`/`.scale` sobre `TypeEngine[Any]` y a la clave `options` de un `TypedDict` de reflexión | `cast(Numeric, ...)` y `cast(Mapping[str, Any], ...)` |
| `backend/tests/test_customer_identity.py` | 4 | dobles de prueba tipados con `object` y una factory falsa pasada como `sessionmaker[Session]` | firmas con `Any` y `cast("sessionmaker[Session]", ...)` |

Sin cambios de comportamiento: las mismas 398 pruebas siguen pasando, la respuesta HTTP conserva el mismo envelope y el guard SQLite sigue cubierto por `test_catalog.py::test_create_session_factory_protects_sqlite_guard_writes`. El alias `ListingOperation` elimina la triple repetición del literal y el `cast` documenta que el dominio lo garantiza el `CHECK` de la base y lo valida el propio modelo de respuesta en tiempo de ejecución.

## Defecto 2 — revision ids que no caben en `alembic_version.version_num VARCHAR(32)`

PostgreSQL rechazaría el `stamp` de estas revisiones (el mismo límite que ya había obligado al fix de T3b sobre `0004`):

- `0009_agency_wallets_listing_deposit` (35 caracteres) → **`0009_agency_wallets_deposit`** (27), con el archivo renombrado igual.
- `0011_reservation_chain_transactions` (35) → **`0011_reservation_chain_txns`** (27), con el archivo renombrado igual.

Referencias actualizadas: `revision` y docstring de `0009` y `0011`, `down_revision` y docstring de `0010`, `test_catalog.py`, `test_catalog_migration.py`, `test_reservations.py`, `test_reservations_migration.py` y `docs/api/catalog-reservations-v1.md`. El test de límite de T3b (`test_staff_identity_migration.py`) volvió a su forma estricta, sin excepciones conocidas.

Cadena verificada con Alembic: 11 revisiones lineales, `0001_staff_identity → 0002_staff_identity_align → 0003_agency_registry → 0004_pending_staff_email_uniq → 0005_customer_identity → 0006_customer_wallet → 0007_catalog_offers → 0008_quote_snapshots → 0009_agency_wallets_deposit → 0010_reservations → 0011_reservation_chain_txns`, head `0011_reservation_chain_txns`, y **todas** las longitudes ≤ 32.

**Consecuencia declarada:** una base SQLite de desarrollo stampada con un id viejo debe re-stamparse (`alembic stamp 0009_agency_wallets_deposit` y `alembic stamp 0011_reservation_chain_txns`); en PostgreSQL esos ids no podían escribirse, por lo que no hay base afectada. La evidencia histórica de la otra sesión en `odd/tasks/cliente-catalog.md` no se reescribe.

## Verificación

- Backend: **398 passed, 2 skipped** (pytest 9.1.1 / Python 3.12.13), Ruff 0.16.4 `All checks passed!`, Pyright 1.1.411 **0 errores, 0 warnings, 0 informations**.
- Alembic: cadena lineal y límite de 32 caracteres aplicado sin excepciones.
- Sin cambios en el workflow, el panel ni las apps Flutter: sus jobs ya estaban en verde en el run `36594625038` y este cambio no los toca.
- **Validación adicional en PostgreSQL real:** el E2E del panel (`npm run test:e2e`) corrió después sobre `main` en `881e5c5` y pasó; su `alembic upgrade head` sobre una base PostgreSQL 16 vacía verifica los revision ids renombrados contra el motor real, no solo contra SQLite (head `0011_reservation_chain_txns`).
