# Proposal — Enable the 14-Day Trial and Monthly Subscription (HU-005)

- **Change:** `hu005-trial-suscripcion`
- **Product Backlog:** PB-005
- **User story:** HU-005 — As an administrator, I want to activate the 14-day trial and subscribe monthly so that I can operate my tenant.
- **Use case:** CU-005 — Trial activation and signed subscription conversion
- **Test case:** CP-004
- **Priority / sprint / platform:** High / Sprint 1 / Web and Backend
- **Document language:** English, as explicitly requested for this proposal
- **Artifact store:** Hybrid (OpenSpec + Engram)
- **Execution mode:** Interactive
- **Changed-line budget:** exactly 400 modified lines; no automatic exception
- **Evidence status:** Proposal only. No tests, migrations, review, commits, or pushes are claimed.

## 1. Outcome and purpose

RoomForge will let an authenticated administrator of an already provisioned tenant activate one trial exactly once, observe its dates, and convert it to a monthly subscription through the signed simulator event established by HU-004. The backend will own the tenant, plan, state, dates, authorization, and idempotency decisions; the Web client will consume the API contract without requiring a UI change in this slice.

The outcome is a small, auditable subscription boundary:

1. An active tenant administrator activates the trial and receives `trialing`, a persisted start instant, and a persisted end instant exactly 14 × 24 hours later.
2. A valid monthly simulator event, authenticated through HU-004's shared HMAC boundary, converts only the eligible `trialing` subscription to `active`.
3. The contracted HU-004 plan is preserved; the event cannot change `plan_id`.
4. Exact authenticated replays return HTTP `200` with the original result, while conflicting reuse of an idempotency key returns HTTP `409` without changing state.
5. The result and the persisted billing event are observable; no email, notifier, or real payment provider is introduced.

## 2. Why this change is worth doing now

The Sprint 1 increment needs the subscription trial and conversion flow before the tenant can operate as a demonstrable SaaS customer. Without this slice, HU-004 can provision a tenant and an initial plan, but the administrator cannot safely start the trial or complete the next signed billing step. The current behavior leaves the most important subscription effects vulnerable to cross-tenant access, incorrect plan data, non-atomic writes, and replay races.

## 3. Current-state gap (repository facts)

The completed exploration and HU-004 artifacts establish the following facts and boundaries:

- Sprint 1 defines HU-005/PB-005 as a high-priority, 8-PHU Web/Backend item. Its acceptance criteria require a 14-day trial, a signed-event conversion to `active`, and ordered subscription states.
- CP-004 has three observable steps: activate the trial, send the signed subscription event, and replay it without duplicate state or records. CP-004 is currently `not executed`.
- The tenant router already exposes `POST /api/v1/tenant/activar-prueba` and `POST /api/v1/tenant/suscribir`.
- The current activation request relies on a body `tenant_id`; the current subscription request accepts `tenant_id`, `plan_id`, an opaque signed payload, and an idempotency key.
- The current service calculates `trial_fin` from the current time but does not persist an explicit trial start. It also does not demonstrate the full state-machine or authorization rules required here.
- The current subscription path performs an isolated idempotency lookup, changes the subscription, and records the event through separate operations. This is a check-then-insert/concurrency risk and does not establish atomic recovery of the original result.
- The current HU-005 path does not use the HU-004 HMAC verifier and does not demonstrate server-owned correlation of tenant, plan, and amount.
- The current subscription model already contains `tenant_id`, `plan_id`, `estado`, `trial_fin`, `periodo_fin`, and `cancelado_en`, but it lacks an explicit trial start and the minimal administrator association needed for tenant-scoped authorization.
- HU-004 provides the tenant, the contracted plan, an initial subscription in `active`, the billing-event persistence boundary, and the shared signed-webhook contract. HU-005 must not reinterpret that initial `active` row as a completed monthly conversion.
- The Sprint 0 model includes a complete future subscription lifecycle, but HU-006 owns quotas, plan changes, payment-failure/grace handling, cancellation, suspension, and purge. Those behaviors are not implemented by this proposal.

These are repository observations, not claims that the current behavior satisfies HU-005.

## 4. Approved product decisions

The following decisions are approved inputs and are not reopened by this proposal:

| Area | Approved rule |
| --- | --- |
| Authorization | Use JWT plus a minimal tenant–administrator association created by HU-005. Only an active tenant administrator may activate or inspect a subscription. A body-supplied tenant ID is never an authorization source. Full RBAC and general memberships remain out of scope. |
| Trial timing | The trial lasts exactly 14 × 24 hours from activation. Persist both start and end. The trial is expired when `now >= trial_end`. |
| Activation | Trial activation is one-time. A second activation is an explicit conflict and makes no changes. |
| Conversion | Accept the signed monthly conversion only from `trialing` to `active`. Do not convert HU-004's initial `active` directly and do not implement expired/grace/suspended paths. |
| Monthly period | It begins at conversion and ends on the same calendar date in the following month, clamped to that month's last day, using `America/La_Paz`. |
| Signed event | Reuse HU-004's common HMAC contract, including raw-byte verification and its timestamp-tolerance boundary. Use a distinct monthly event type and HU-005 correlation/state checks. |
| Plan | Preserve HU-004's contracted plan. The event cannot change `plan_id`; plan changes belong to HU-006. |
| Idempotency | An exact replay returns HTTP `200` and the original result. The same key with different data returns HTTP `409` and preserves the original state. Processing is atomic and concurrency-safe. |
| Notification | Expose the API result and persist the event only. Do not add email, push, in-app notification, or a notifier provider. |

The approved HU-004 catalog remains authoritative. HU-005 reads the existing plan and its server-owned price/quotas; it does not seed new prices or invent a second catalog. The approved HU-004 reference values are Basic `199.00` BOB, Professional `449.00` BOB, and Enterprise `899.00` BOB, with the quotas already defined by HU-004.

## 5. Proposed first slice

### 5.1 Authorization and minimal administrator association

Add one narrow `tenant_administrator` association for an authenticated global user and a tenant. It should contain only the identifiers, active/inactive status, and lifecycle timestamps required to authorize this story. The association is not a general membership table, does not define arbitrary roles or permissions, and does not replace HU-007's membership model.

The recommended bootstrap seam is a single authenticated operation tied to the HU-004 first-administrator activation record: the JWT principal must match the normalized administrator identity already associated with that activation, and the operation creates the minimal active association atomically. No password is accepted or generated by HU-005. This seam exists only to make the approved authorization rule usable without introducing full RBAC; its final HTTP composition must be fixed in the spec/design phase.

For every activation or inspection request:

- derive the principal from the JWT and resolve the tenant from the active association;
- do not accept `tenant_id` in the request body as an authority value;
- reject missing, inactive, cross-tenant, or insufficiently associated principals without revealing another tenant's subscription;
- return only the authorized tenant's subscription projection.

The signed simulator webhook is a separate machine-to-machine boundary. It uses HMAC authentication and server-side correlation; it does not impersonate the administrator and does not grant tenant access.

### 5.2 API surface

The proposal keeps the existing tenant route family where possible and closes its unsafe contracts:

| Operation | Proposed contract | Expected result |
| --- | --- | --- |
| Admin bootstrap | One minimal authenticated association operation linked to the HU-004 activation record; no general membership endpoint | Creates or returns the active tenant-admin association without creating roles or memberships |
| `POST /api/v1/tenant/activar-prueba` | JWT only; no client-controlled `tenant_id` | `200` with subscription ID, `trialing`, trial start/end, and null monthly period; `409` on second activation or an invalid subscription state |
| `GET /api/v1/tenant/suscripcion` | JWT only; tenant derived from the active association | `200` with plan ID, state, trial dates, monthly period dates, and no event payload or secret |
| `POST /api/v1/tenant/webhook` | HU-004 HMAC headers and raw body; distinct monthly event type | `201` for a new conversion, `200` for an exact replay, and explicit `401`/`409` errors for authentication, correlation, state, or idempotency conflicts |

The existing `POST /api/v1/tenant/suscribir` must not remain a bypass around HMAC, tenant authorization, or state validation. If compatibility requires retaining the route, it becomes a thin adapter to the same signed-event use case and cannot accept client-supplied tenant or plan authority. No new public event-query-by-key endpoint is needed.

The proposed monthly event contains only a stable subscription correlation, the contracted `plan_id`, the simulator amount, `event_type`, and `idempotency_key`; all values are checked against server state. The proposed distinct event type is `subscription.monthly.succeeded`, subject to exact contract naming in spec/design. The event never changes the stored plan and never supplies tenant authorization.

### 5.3 Shared HMAC boundary

Reuse the HU-004 verifier rather than creating a second cryptographic implementation. The monthly event must follow the established boundary:

- verify the HMAC over `ASCII(timestamp) + b"." + raw_body`;
- use the HU-004 versioned signature format and headers;
- read the request body bytes once and do not reserialize JSON before verification;
- enforce the existing timestamp tolerance for a new event, including its exact boundary behavior;
- authenticate before looking up idempotency or correlating business data;
- permit an already-authenticated exact replay to recover its original result even if the replay arrives outside the new-event timestamp window;
- compare a hash of the exact received bytes for replay/conflict detection;
- never log or return the raw body, complete signature, secret, or sensitive event content.

After authentication, validate the monthly event type, schema, subscription correlation, server-owned plan, amount, and current subscription state. A cryptographically valid event with incompatible business data is not accepted.

### 5.4 State and date invariants

The minimum HU-005 state graph is:

```text
HU-004 initial active --activate trial--> trialing --valid monthly event--> active
```

The following invariants apply:

1. Trial activation is valid only for the HU-004 initial `active` subscription with no prior trial start/end. It writes `trial_inicio = activation_time` and `trial_fin = activation_time + 336 hours` in one transaction.
2. A second activation is a conflict, regardless of whether the first trial is still open or has reached its end. It does not update dates, state, or events.
3. Trial validity is evaluated at the boundary `now >= trial_fin`; the conversion handler rejects an expired trial without inventing a new persistent `expired` state. Expired/grace/suspended lifecycle handling belongs to HU-006.
4. A monthly event is accepted only when the locked subscription is `trialing`, the trial is still valid, the event type is monthly, the correlation matches, and the server-owned plan and amount agree with the event.
5. An event received while the subscription is the HU-004 initial `active`, already converted `active`, or in any unsupported lifecycle state is rejected without mutation, except for an exact previously committed replay.
6. Monthly `periodo_inicio` is the conversion instant projected into `America/La_Paz`; `periodo_fin` is the same local calendar date in the following month, clamped to the last day of that month. The resulting instants are stored as timezone-aware timestamps.
7. HU-005 does not create `past_due`, `suspended`, `canceled_read_only`, `purged`, grace, quota, upgrade, downgrade, or renewal transitions.

### 5.5 Atomic idempotency and persistence

Use the existing `EventoFacturacion` boundary and a single repository transaction for state and event effects:

```text
BEGIN
  authenticate raw request bytes
  lock/find event by idempotency key
  if key exists: compare exact-payload hash and return original result or conflict
  lock subscription resolved from the signed event correlation
  validate state, trial boundary, plan, amount, and event type
  compute period dates using the injected clock and America/La_Paz
  update subscription state and dates
  insert the monthly event with type, key, payload hash, correlation, and result references
COMMIT
```

The database uniqueness constraint remains authoritative under concurrency. A unique-key race is recovered by a clean read of the committed event and its original result; it is not treated as a generic error. If any write fails, the subscription update and event insert roll back together. A different key for an already-converted subscription is a state conflict, not a second conversion.

Add only the data needed by the approved rules:

- `suscripcion.trial_inicio` (additive) while retaining the existing `trial_fin` field;
- `suscripcion.periodo_inicio` so the monthly period start is inspectable, while retaining `periodo_fin`;
- the minimal `tenant_administrator` association table and its active-association indexes/foreign keys;
- any event type/correlation/hash columns not already supplied by the completed HU-004 event boundary, without duplicating that boundary or storing a second raw secret/payload contract.

Existing HU-004 subscriptions in initial `active` with null trial dates are preserved. No synthetic trial is backfilled and no plan is changed.

## 6. Scope and non-goals

### In scope

- Backend/API contract for the minimal admin association, trial activation, subscription inspection, and signed monthly conversion.
- JWT-derived tenant authorization for activation and inspection.
- Reuse of HU-004 HMAC verification, raw-byte tolerance, event persistence, and result recovery.
- The HU-005 state/date rules, `America/La_Paz` calendar calculation, one-time activation, atomic event/state persistence, and concurrency-safe idempotency.
- Additive SQLAlchemy/Alembic changes required for these invariants.
- Contract, service, repository, concurrency, migration, and regression tests for CP-004 and the listed security boundaries.
- API responses that expose subscription state and dates without secrets or event payloads.

### Explicitly out of scope

- React/Web UI, Flutter, navigation, copy, or generated client changes.
- Real payment processing, external billing providers, checkout changes, or real invoices.
- New plans, prices, quotas, quota enforcement, or any modification to the HU-004 catalog.
- Full subscription lifecycle: `past_due`, grace periods, suspension, cancellation, read-only mode, purge, or expiry remediation.
- Upgrade/downgrade and plan changes.
- General RBAC, memberships, invitations for agents, or a reusable membership service.
- Email, push, in-app notifications, outbox, notifier providers, or delivery retries.
- Subscription usage, tenant limits, publication, catalog, S3/SQS, worker, or unrelated tenant refactoring.
- A public event history/query API beyond the subscription projection and persisted event record.
- Changes to `docs/diagramas/Diagrama1.eapx`, branch state, unrelated untracked metadata, commits, pushes, or root/submodule cleanup.

## 7. Dependencies and compatibility

### HU-004 dependency

HU-005 depends on a provisioned tenant, an existing subscription in HU-004's initial `active` state, the contracted plan, the billing-event table, and the shared HMAC verifier/configuration. The monthly event must use a distinct event type from HU-004 onboarding (the onboarding event documented by HU-004 is not a monthly payment event). HU-005 must reuse the verifier's raw-byte and tolerance behavior and must not fork a second signature implementation.

The minimal administrator association must be established from a server-owned HU-004 first-admin activation record and the authenticated global identity. It must not turn HU-005 into a general membership implementation.

### HU-006 dependency

HU-006 will consume the stable subscription state and date projection produced here. It owns later lifecycle transitions, quotas, plan changes, cancellation, grace, suspension, and purge. HU-005 must leave those states representable and must not preemptively implement their behavior. Any state constraint introduced by HU-005 must be coordinated with the state catalog expected by HU-006 and existing HU-004 data.

### Identity dependency

The existing JWT/session capability from HU-002 is reused as the principal source. JWT validity alone is insufficient: authorization requires an active `tenant_administrator` row. This is deliberately narrower than general RBAC and is not a claim that all future tenant membership behavior exists.

## 8. Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Bootstrap association is accidentally implemented as general membership/RBAC | High; scope and authorization drift | Use a dedicated, minimal association table and one HU-004-linked bootstrap seam; no role catalog, invitations, or permissions. |
| HU-004's initial `active` is confused with a converted monthly `active` | High; invalid direct conversion | Require `trialing` plus persisted trial dates for new conversion events; reject initial `active` events. |
| HMAC body handling is reimplemented or normalized | High; signatures and replay behavior diverge | Reuse the HU-004 verifier and test exact raw bytes, tolerance boundary, authentication-before-lookup, and exact replay. |
| Check-then-insert races create duplicate or partial results | High; financial-state inconsistency | Unique persistent idempotency key, row locks, one transaction, clean recovery of the committed original result, and concurrent tests. |
| Same-key payload conflict is silently treated as replay | High; data integrity/security | Store/compare exact-byte payload hash and return `409` without mutation when it differs. |
| Month-end or timezone calculation is inconsistent | Medium/high; incorrect renewal date | Use timezone-aware values and `ZoneInfo("America/La_Paz")`; test January/February, leap years, month ends, and exact trial boundary. |
| Additive migration conflicts with legacy rows or HU-006 constraints | High; rollout failure | Keep new columns nullable where legacy data requires it, do not backfill synthetic trials, inspect existing event fields, and coordinate state constraints before migration. |
| Work exceeds the 400-line budget | High; review and delivery risk | Reuse HU-004 components, exclude UI/lifecycle/RBAC, keep one focused test module, and stop for an explicit scope decision if tasks forecast more than 400 lines. No exception is implicit. |

## 9. Test and evidence strategy

Strict TDD applies. The next phases must write failing contract/service tests before implementation and then add the minimum code needed to satisfy them. The following is an evidence plan, not completed evidence.

### CP-004 acceptance evidence

| CP-004 step / criterion | Evidence expected | Current status |
| --- | --- | --- |
| 1. Activate trial | Authenticated active admin; no body tenant authority; state becomes `trialing`; `trial_inicio` is persisted; `trial_fin - trial_inicio` is exactly 336 hours; response exposes dates | Not executed |
| 2. Convert monthly | Valid HU-004-signed monthly event; only `trialing` converts to `active`; contracted `plan_id` is unchanged; period start/end use `America/La_Paz` calendar rules | Not executed |
| 3. Replay event | Exact authenticated replay returns HTTP `200` with original IDs/result; no duplicate event or state change; same key with different bytes returns HTTP `409` | Not executed |
| State order | Initial HU-004 `active` → `trialing` → converted `active`; direct initial-`active` conversion and unsupported states are rejected without mutation | Not executed |

### Required focused evidence

- JWT missing/invalid, inactive association, wrong tenant, and non-admin access; verify no cross-tenant existence leak.
- Request bodies containing `tenant_id` or other authority fields; verify rejection or that such fields are never used for authorization.
- Second trial activation, concurrent activation, activation with missing subscription, and activation in an unsupported state.
- Valid HMAC, missing/invalid signature, altered raw body, malformed headers, missing secret, stale timestamp, future timestamp, and exact tolerance-boundary timestamp.
- Monthly event type distinction from HU-004 onboarding, mismatched subscription/plan/amount, inactive/missing plan, event before trial, event after the trial boundary, and event after conversion.
- Sequential exact replay, concurrent exact replay, same key with different payload, different key for an already-converted subscription, and failure/rollback during the combined state/event transaction.
- Calendar cases for 31st-to-shorter-month conversion, February/leap year, and the `now == trial_fin` boundary.
- API responses and logs contain no raw signed body, signature, secret, JWT, password, token, token hash, or unrelated tenant data.
- Migration upgrade from the HU-004 schema, preservation of existing initial-active rows, required indexes/foreign keys, and safe downgrade behavior in a disposable database only.
- Full backend regression, lint, type, and migration gates as required by the project. No command is claimed to have run in this proposal.

The documented project commands for later apply/verify phases are:

```text
.venv/Scripts/python.exe -m pytest backend/tests -q
.venv/Scripts/python.exe -m ruff check backend/app backend/tests
.venv/Scripts/pyright.exe backend/app backend/tests
.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head
```

Fake-clock and repository tests are useful for deterministic rules, but they do not replace PostgreSQL evidence for locks, unique constraints, transaction rollback, or migration behavior. CP-004 must remain `not executed` until real evidence is captured.

## 10. Observability and rollback

### Observability

Record safe, aggregate signals for:

- trial activation success, explicit second-activation conflicts, and authorization denials;
- signed-event authentication failures, correlation/state conflicts, idempotent replays, idempotency conflicts, successful conversions, and transactional failures;
- conversion and inspection latency, with error rates by stable error code;
- migration version and subscription-state counts during rollout, without exposing payloads.

Logs may include route, outcome code, event type, correlation ID, and irreversibly shortened identifiers. They must not contain raw request bodies, complete signatures, HMAC secrets, JWTs, passwords, activation tokens/hashes, full administrator email addresses, or SQL error details. The persisted billing event is the audit record for the monthly event; no notification record/provider is added.

### Rollback

1. Disable the monthly webhook route or its feature/configuration gate if signature, correlation, or conversion behavior is unsafe. Do not disable JWT-protected inspection or delete valid subscription history as a first response.
2. Roll back application code only to a version compatible with the additive schema. Preserve committed subscription/event rows for investigation and exact replay recovery.
3. Prefer a forward fix for any database that contains HU-005 associations, trial dates, monthly periods, or monthly events. Do not run a destructive downgrade against such data.
4. In a disposable empty database, verify the downgrade order and constraints before executing it. Existing HU-004 tenants and subscriptions must not be deleted by rollback.
5. After correction, retry a valid event with the same idempotency key; the stored result must be returned rather than creating another conversion.

No rollback, migration, or operational change has been performed.

## 11. Success criteria and release boundary

The change is ready for later verification only when all of the following are evidenced:

- [ ] CP-004 steps 1–3 pass against the API contract, with CP-004 no longer described as executed merely because this proposal exists.
- [ ] Only an active JWT-backed tenant administrator can activate or inspect; no body `tenant_id` grants access.
- [ ] Trial start/end are persisted and exactly 336 hours apart; the expiry boundary is enforced.
- [ ] Only `trialing` converts to `active`; the HU-004 initial `active` cannot be directly converted.
- [ ] Monthly period dates follow the `America/La_Paz` calendar rule and preserve the contracted plan.
- [ ] HMAC verification reuses HU-004's raw-byte/tolerance boundary and distinguishes monthly events.
- [ ] Exact replay is HTTP `200` with the original result; conflicting key reuse is HTTP `409`; concurrent processing is atomic and duplicate-free.
- [ ] Failure rolls back the subscription and event together.
- [ ] No notification provider, UI, full lifecycle, quota, plan-change, RBAC, or membership scope has been added.
- [ ] Migration and quality evidence are captured, and the implementation forecast remains at or below the exact 400-line budget.

## 12. Unresolved gaps versus pending evidence

### Product gaps

None at proposal level. The authorization, trial, conversion, period, signature, plan, idempotency, and notification decisions were supplied as approved product inputs.

### Technical details to close before tasks

- The exact name and HTTP composition of the HU-004-linked bootstrap association operation must be fixed in spec/design. The recommendation is one narrowly scoped operation, not a general membership API.
- The exact monthly event field names and event-type token must be fixed in spec/design while preserving the proposed distinction from `tenant.onboarding.succeeded` and the HU-004 HMAC contract.
- The implementation must verify which event correlation/hash columns were delivered by HU-004 before adding migration columns; no duplicate boundary should be created.
- The migration revision, legacy-data handling, and state constraints must be reconciled with the actual backend submodule and HU-006's future state model.

These are implementation-resolution items, not permission to invent new product scope. Tests, migration runs, review, commits, and pushes remain pending evidence.

## 13. Changed-line forecast and budget control

The hard budget is **400 modified lines**. This forecast is intentionally below the cap and assumes reuse of HU-004's HMAC, event, JWT, and repository infrastructure:

| Area | Forecast |
| --- | ---: |
| Subscription/admin association models and additive migration | 40–50 |
| Request/response schemas and thin routes | 30–40 |
| Service state/date/auth orchestration | 60–75 |
| Repository transaction, locks, idempotency recovery | 65–80 |
| HU-004 HMAC/event integration and safe error mapping | 15–25 |
| Focused CP-004, security, concurrency, and migration tests | 90–110 |
| **Total forecast** | **300–380** |

The forecast stays below the hard maximum, with 20 lines of maximum reserve. Before `sdd-apply`, tasks must preserve the **400-line** ceiling; if the concrete estimate exceeds it, reduce the slice or split delivery for an explicit scope decision. No exception is silently approved or raised. UI, notifier, full lifecycle, general membership, and unrelated refactoring are the first exclusions; HU-005's approved invariants are not silently dropped.

## 14. Source traceability

| Proposal element | Source / status |
| --- | --- |
| HU-005, PB-005, priority, 8 PHU, Sprint 1, Web/Backend | `docs/scrum/sprint-1/01-sprint-planning.md` and `docs/scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md` |
| CP-004 steps and `not executed` status | `docs/scrum/sprint-1/02-proceso-por-hu.md` |
| RF-007, subscription lifecycle baseline, and BR numbering | `docs/scrum/sprint-0-requerimientos/04-requerimientos-iniciales.md` and `docs/sprint-0/ids-trazabilidad.md` |
| BR-B1–BR-B9, multi-tenant authorization boundary, plans, lifecycle limits | `docs/sprint-0/auditoria-br.md` |
| CU-005 actor and use-case relationship | `docs/scrum/sprint-0-requerimientos/07-casos-de-uso.md` |
| Router → service → repository, PostgreSQL authority, signed events, state refinement | `docs/scrum/sprint-0-requerimientos/10-patron-de-desarrollo.md` and `11-modelos-iniciales.md` |
| HU-004 initial `active`, shared HMAC/raw-byte/tolerance boundary, event persistence and compatibility constraints | `openspec/changes/hu004-alta-inmobiliaria/{explore,proposal,specs/tenant-onboarding/spec,design,tasks}.md` and the completed HU-004 backend boundary |
| Current HU-005 routes, body authority, missing trial start, separate writes, and missing HMAC/correlation | `openspec/changes/hu005-trial-suscripcion/explore.md` and its Engram mirror `sdd/hu005-trial-suscripcion/explore` |
| Stack, strict TDD, commands, hybrid store, repository restrictions | `openspec/project-context.md` and `openspec/config.yaml` |
| Approved HU-005 product decisions | Orchestrator/user-provided approved inputs for this proposal |

## Proposal question round

The product decisions needed to finalize this proposal were supplied as approved inputs, so no additional product question blocks this artifact. The next phase should resolve only the explicitly listed technical contract details and must preserve the approved scope, invariants, and 400-line hard limit.
