# Modular Software Engineering Documentation Standard

## Purpose and source-order rule

This reference defines a modular documentation system that follows the source document's index without changing its conceptual order. Split content into files for reading and review, but do not replace the model with generic groupings. Treat the repository as the source of truth and label every statement as **verified**, **derived**, **proposed**, or a documented **gap**.

The document sequence is:

`PAPS → PROCESO DE DESARROLLO SCRUM → CAPITULO 1 – REQUERIMIENTOS (Sprint 0) → CAPITULO 2 - PROCESO DE DESARROLLO DE SOFTWARE (Sprint 1, Sprint 2, Sprint 3) → BIBLIOGRAFIA → ANEXOS`

## Recommended modular tree

`docs/README.md` is navigation only. It must link every module, show its status, and identify its evidence scope; it must not reorder the content below.

```text
docs/
├── README.md
├── paps/
│   ├── 01-introduccion.md
│   ├── 02-descripcion-del-problema.md
│   ├── 03-metricas.md
│   ├── 04-definiciones-para-la-estimacion.md
│   ├── 05-metodos-de-estimacion.md
│   ├── 06-analisis-de-riesgos.md
│   ├── 07-planificacion-del-tiempo.md
│   ├── 08-recursos.md
│   ├── 09-organizacion-interna.md
│   └── 10-seguimiento-control.md
├── scrum/
│   ├── README.md                         # PROCESO DE DESARROLLO SCRUM
│   ├── sprint-0-requerimientos/           # CAPITULO 1 – REQUERIMIENTOS (Sprint 0)
│   │   ├── 01-proposito.md
│   │   ├── 02-ambito-objetivos-descripcion.md
│   │   ├── 03-equipo-scrum.md
│   │   ├── 04-requerimientos-iniciales.md
│   │   ├── 05-funciones.md
│   │   ├── 06-product-backlog-hu.md
│   │   ├── 07-casos-de-uso.md
│   │   ├── 08-planificacion-de-sprints.md
│   │   ├── 09-infraestructura.md
│   │   ├── 10-patron-de-desarrollo.md
│   │   ├── 11-modelos-iniciales.md
│   │   ├── 12-criterios-de-calidad.md
│   │   └── 13-conclusion.md
│   ├── sprint-1/
│   │   ├── 01-sprint-planning.md
│   │   ├── 02-proceso-por-hu.md
│   │   ├── 03-daily-scrum.md
│   │   ├── 04-sprint-review.md
│   │   ├── 05-sprint-retrospective.md
│   │   ├── 06-burndown-burnup.md
│   │   ├── 07-esfuerzo.md
│   │   └── 08-scrum-taskboard.md
│   ├── sprint-2/
│   │   ├── 01-sprint-planning.md
│   │   ├── 02-proceso-por-hu.md
│   │   ├── 03-daily-scrum.md
│   │   ├── 04-sprint-review.md
│   │   ├── 05-sprint-retrospective.md
│   │   ├── 06-burndown-burnup.md
│   │   ├── 07-esfuerzo.md
│   │   └── 08-scrum-taskboard.md
│   └── sprint-3/
│       ├── 01-sprint-planning.md
│       ├── 02-proceso-por-hu.md
│       ├── 03-daily-scrum.md
│       ├── 04-sprint-review.md
│       ├── 05-sprint-retrospective.md
│       ├── 06-burndown-burnup.md
│       ├── 07-esfuerzo.md
│       └── 08-scrum-taskboard.md
├── bibliografia.md                        # BIBLIOGRAFIA
└── anexos/                                # ANEXOS
    └── README.md
```

## Exact correspondence with the model index

| Source section | Canonical module(s) | Content boundary |
| --- | --- | --- |
| PAPS, chapters 1–10 | `docs/paps/01-introduccion.md` through `docs/paps/10-seguimiento-control.md` | Introduction; problem description; metrics for ActivityWach, Kimai and Worklenz (description, captures/prototypes, MOT, MOF); estimation definitions and methods; risk analysis; time planning; resources; internal organization; follow-up/control. |
| PROCESO DE DESARROLLO SCRUM | `docs/scrum/README.md` | Navigation and heading for the Scrum process; link to Sprint 0 and the three development sprints. |
| CAPITULO 1 – REQUERIMIENTOS (Sprint 0) | `docs/scrum/sprint-0-requerimientos/` | Exactly the 13 files shown in the tree: purpose; scope/objectives/description; Scrum team; initial requirements; functions; Product Backlog/HU; use cases; Sprint planning; infrastructure; development pattern; initial models; quality criteria; conclusion. |
| CAPITULO 2 - PROCESO DE DESARROLLO DE SOFTWARE | `docs/scrum/sprint-1/`, `docs/scrum/sprint-2/`, `docs/scrum/sprint-3/` | Each sprint repeats the same eight sections in the same order. Its HU process file contains Design (architecture, data, business logic), Implementation, and Tests. |
| BIBLIOGRAFIA | `docs/bibliografia.md` | Sources cited by the document, with stable references and access details when evidenced. |
| ANEXOS | `docs/anexos/` | Supporting material and raw-evidence references that belong at the end; link from the relevant module instead of duplicating explanations. |

A modular split may add an index or evidence file inside a listed folder, but it must not move a section before an earlier source section or merge the three sprint templates into one generic chapter.

## Module responsibility boundaries

| Module | Single source of truth |
| --- | --- |
| `docs/paps/` | Planning, problem, metrics, estimation, risks, time, resources, organization, and control in the PAPS order. |
| Sprint 0 | Requirements baseline, Product Backlog/HU, CU, initial models, infrastructure, development pattern, and quality criteria. |
| Sprint 1–3 | Timeboxed planning, HU process, ceremonies, metrics, effort, taskboard, test evidence, review, retrospective, and closure for that sprint only. |
| Bibliography | Cited sources and reference metadata. |
| Annexes | Supporting artifacts, captures, prototypes, raw evidence pointers, and reproducibility material. |

## Stable identifiers and traceability

Choose one project-wide syntax and never recycle an identifier. A practical convention is `OBJ-###`, `RF-###`, `RNF-###`, `BR-###`, `HU-###`, `CU-###`, `PB-###`, `SP-##`, `TASK-###`, `TC-###`, `REV-##`, and `GAP-###`. Record the final naming rule in `docs/README.md` or the Sprint 0 requirements module.

The traceability matrix must make this path explicit:

```text
PAPS problem/objectives → RF/RNF/BR → HU/CU/PB → SP/TASK → design element → implementation path → TC → REV/closure
```

Use one row per relationship, with source location, status, and evidence reference. Check both directions: every objective and requirement reaches a validation result, and every implementation task or test points back to an approved requirement or an explicitly marked technical task. Orphans, ambiguous many-to-many links, and missing IDs are findings, not formatting issues.

## User Story contract

Each HU is a small, independently traceable product slice. Use this minimum contract in Sprint 0 and link to the canonical HU from each sprint:

```markdown
### HU-### — <short outcome>
- Role: <actor>
- Need: <capability>
- Value: <business or user outcome>
- Priority: <ordered value or scheme>
- Sprint: <SP-## or planned>
- Related: <RF/RNF/BR/CU/PB IDs>
- Acceptance criteria:
  - Given <context>, when <action>, then <observable result>.
- Evidence: <path, command output, or GAP-###>
- Status: <proposed|ready|in progress|done|blocked>
```

Acceptance criteria must be observable and testable. Keep business intent in the story and behavior detail in criteria or a linked CU. If role, value, priority, or evidence is unknown, mark the gap rather than inferring it.

## Use Case contract

Use a CU when a flow needs actor/system interaction detail beyond a story:

```markdown
### CU-### — <goal>
- Primary actor: <actor>
- Supporting actors/systems: <list or none evidenced>
- Trigger: <event>
- Preconditions: <conditions>
- Main flow: 1. ... 2. ...
- Alternate and exception flows: A1..., E1...
- Postconditions: <observable result>
- Related: <HU/RF/RNF/TC IDs>
- Evidence/status: <reference and state>
```

Keep alternate flows and failure behavior explicit. Do not infer actors, permissions, or postconditions from a generic template; record them as gaps when the repository does not establish them.

## Repeating Sprint template

Create the same eight files/headings under each of `docs/scrum/sprint-1/`, `sprint-2/`, and `sprint-3/`:

1. **Sprint Planning:** selected HU/PB/TASK IDs, capacity or estimation source, Definition of Done, dependencies, and risks.
2. **Proceso/patrón por HU:** for every HU, preserve the following subsections: **Diseño** (arquitectura, datos, lógica de negocio), **Implementación**, and **Pruebas**.
3. **Daily Scrum:** dated entries only when real; otherwise mark the record unavailable.
4. **Sprint Review:** demonstrated items, acceptance outcomes, stakeholder feedback, and open findings.
5. **Sprint Retrospective:** what worked, what did not, actions, owners, and follow-up IDs; unknown owners are gaps.
6. **Burndown/BurnUp:** observed data or an explicit unavailable/not executed state; never invent points.
7. **Esfuerzo:** planned and actual effort only when sourced, with the measurement method and evidence.
8. **Scrum Taskboard:** snapshot or link, item states, carry-over, and evidence date when available.

Keep planned, in-progress, blocked, done, deferred, not executed, and unknown states distinct. A sprint can link to shared design, test, or metric material, but it must retain enough local references to remain auditable.

### Verified CAPITULO 2 formats (Grupo#12, via `docs/modelo_doc/guia-capitulo2-modelo.md`)

- **Sprint Planning §1**: narrative structure with objective general/específicos; then `INTEGRANTE \| ROL SCRUM`, per-HU cards (`HU-XX Título`; `Descripción: Como <rol>, quiero <capacidad>, para <valor>.`; `Prioridad: Alta/Media/Baja — Estimación: N PHU`; `Criterios de Aceptación`; `Desarrollador a cargo`; `Prototipo` label — no images), and Sprint Backlog header (`SPRINT BACKLOG / Objetivo / Sprint: N — Tiempo programado: 3 semanas / Fechas`) + table `ID \| TAREA \| ESTIMACIÓN \| RESPONSABLE \| ESTADO \| PLATAFORMA` (effort in HRS, e.g. `PB-01 \| Login escritorio \| 3 HRS \| <nombre> \| Hecho \| Desktop`).
- **Per-HU process §2**: 2.1.1 Architecture (2.1.1.1 Deployment, 2.1.1.2 Package; Sprint 3 adds the literal label "2.1.1.3 Diagrama de arquitectura general" with no UML type — GAP-CH2-005), 2.1.2 Data (Conceptual/Logical/Physical), 2.1.3 Business Logic (2.1.3.1 Communication, 2.1.3.2 Sequence), 2.1.4 Implementation (2.1.4.1 Component), 2.1.5 Tests: plan table `ID Prueba \| PB \| HU \| Funcionalidad evaluada \| Plataforma \| Responsable \| Estado` (`CP-XX`, counter resets per sprint); per-case metadata `CAMPO \| DESCRIPCIÓN` + steps `PASO \| ACCIÓN \| RESULTADO ESPERADO \| ESTADO` + `Responsable` + `Resultado de la prueba` + `Adjunto` only with evidence; report table `RESULTADO GENERAL \| VALOR` (totals, satisfactories, failures, %, Estado general del Sprint N).
- **Sections §3–§5, §7–§8**: no UML diagrams (GAP-CH2-001); Burndown/BurnUp are chart artifacts (GAP-CH2-002); §7 has both effort table and a "Gráfica de esfuerzo" label (GAP-CH2-003); §8 Taskboard is a visual snapshot (GAP-CH2-004). Model inconsistencies to note, never silently copy: GAP-CH2-006 (Sprint 3 plans CP-31..38, reports 6) and GAP-CH2-007 ("Estado general del Sprint 1" appears in Sprint 3's report).

## Black-box testing pattern

Test externally observable behavior without depending on internal implementation. For each `TC-###`, record:

| Field | Required content |
| --- | --- |
| Trace | HU/CU/RF/RNF IDs and sprint |
| Setup | Preconditions, actor, environment, and data |
| Input/action | Request, event, or user-visible steps |
| Expected | Observable result and business rule |
| Actual | Recorded output only after execution |
| Result | `pass`, `fail`, `blocked`, `not executed`, or `inconclusive` |
| Evidence | Test command, report, screenshot path, log, or GAP ID |

Cover normal, alternate, negative, boundary, and invalid-input partitions when the requirement warrants them. “Pass” requires observed evidence; a planned case is not a passed case. Preserve the raw result or a precise reference and link failures to a defect or open gap.

## Canonical model table formats (Grupo#12)

Verified against the official PDF with pdfplumber table extraction. Use exactly these columns; one row per artifact unless the model merges cells.

| Artifact | Format | Notes |
| --- | --- | --- |
| Functional requirements (4.3) | `CODE \| MODULE \| REQUIREMENT \| PRIORITY` | Full sentence, "The system must…"; Alta/Media/Baja |
| NFRs (4.4) | `CODE \| CATEGORY \| REQUIREMENT` | |
| Business rules (4.5) | Numbered list | Title + description, no table |
| Functions (5.x) | `FUNCTION \| DESCRIPTION \| BACKLOG` per surface | Backlog links PB-XX |
| Product Backlog (6.1) | Header block + `PB \| USER STORY \| DESCRIPTION \| PRIORITY` | One row per PB |
| User stories (6.2) | `ID \| ROLE \| USER STORY \| PRIORITY \| SPRINT \| PLATFORM` | Full sentence "As a …, I want … so that…" |
| Use cases (7) | `ID \| USE CASE` list + `ACTOR \| DESCRIPTION` + `FUNCTIONAL PACKAGE \| RELATED USE CASES \| DESCRIPTION` | Detailed flows belong to each sprint |
| Sprint duration (8.1) | `NRO \| SPRINT \| START DATE \| END DATE \| DURATION \| MAIN PURPOSE` + Gantt | |
| Division criteria (8.2) | `CRITERION \| APPLICATION IN THE PROJECT` | Six criteria, see model |
| Per-sprint (8.3–8.5) | Title `8.x. Sprint N — <name>`; `**Objective**: …` paragraph; `PB \| USER STORY \| PRIORITY \| EXPECTED RESULT` (one row per PB, story NAME not HU IDs); `**Main deliverable of Sprint N**: …` | |
| Per-HU design (CAPITULO 2) | 2.1.1 Architecture (Deployment + Packages); 2.1.2 Data (Conceptual/Logical/Physical); 2.1.3 Business Logic (Communication + Sequence); 2.1.4 Implementation (Components); 2.1.5 Tests (plan + black-box cases + report) | |

Priority scale: **Alta/Media/Baja** (map Must → Alta, Should → Media).

## Diagram reference rule

- Reference diagrams by **type** (plus name when applicable); never embed images.
- Sprint 0 types: **Gantt** (8.1), **Use Case** (7.2), initial models (11): **Context · Use Case · Class/ERD · Package/Component · Interfaces**. Each sprint (CAPITULO 2): **Deployment · Package · ERD (C/L/P) · Communication · Sequence · Component** + **Burndown/BurnUp charts** and **Taskboard**.
- The model does NOT use Statechart in Sprint 0; domain states appear in Communication/Sequence diagrams of CAPITULO 2. Sections 3/4/5/9/10 of Sprint 0 have no UML diagrams.

## Reading the model without vision

- `pdftotext -f A -l B -layout -enc UTF-8 model.pdf out.txt` for text; `pdfplumber` (`page.extract_tables()`) for real table cells including merged cells.
- Never claim model content without verification; printed page numbers may differ from physical ones (use the TOC).

## Evidence and absence handling

For every significant fact, record source path, section/symbol or command, capture date when relevant, and confidence/status. Use explicit labels:

- **Verified:** directly supported by repository content or an executed result.
- **Derived:** mechanically concluded from cited facts; explain the derivation.
- **Proposed:** a recommendation or future plan, never current state.
- **Gap:** expected information is absent, inaccessible, or contradictory.
- **Not executed:** a test, ceremony, metric, or review has no observed run.

Never fabricate screenshots, prototypes, dates, measurements, burndown/burnup points, effort, attendance, stakeholder approval, implementation paths, or test results. When evidence conflicts, preserve both references, mark the contradiction, and open a `GAP-###` or decision record instead of silently choosing one.

## Consistency checklist

Before publication, verify:

- [ ] The modular tree preserves the source order from PAPS through Bibliography and Annexes.
- [ ] `docs/README.md` links every PAPS, Sprint 0, Sprint 1, Sprint 2, Sprint 3, bibliography, and annex module.
- [ ] Sprint 0 contains all 13 named sections, and every development sprint contains the same eight sections.
- [ ] Each HU process preserves Design (architecture, data, business logic), Implementation, and Tests.
- [ ] IDs are stable and unique; the traceability matrix has no orphan IDs or broken references.
- [ ] Acceptance criteria are observable; black-box results are not marked pass without execution evidence.
- [ ] Planned, active, blocked, done, deferred, not executed, and unknown states are not conflated.
- [ ] Dates, metrics, effort, ceremonies, captures, prototypes, and approvals are sourced or explicitly unavailable.
- [ ] Repeated content has one canonical location and uses relative links elsewhere.
- [ ] Markdown tables render, local references resolve, and no section is empty without a documented reason.
