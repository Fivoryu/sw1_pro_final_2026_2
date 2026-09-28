# F02-T4 — Panel: cola de revisión en estado vacío

## Objetivo

Extender el prototipo web del panel para que `agency_admin` pueda reconocer dónde se revisarán solicitudes, con un estado vacío honesto y accesible. No implementar revisión real ni detalle de inmuebles.

## Base y autoridad

- Worktree: `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f02-base-ux-automation-wt`.
- Rama `feat/f02-base-ux-automation`; base `3fcc5c3`, worktree limpio al inicio.
- Requisitos: `docs/redefinicion-roomforge.md`, `docs/plan-maestro-roomforge.md` y mapa UX aprobado `docs/ux/f02-surface-map.md`.
- Scout confirmó que `ProtectedStaffShell` ya controla roles y sesión; el panel tiene Vitest y build. El README está desactualizado y no es autoridad para el comportamiento.

## Alcance

- Limitar escritura a:
  - `panel/staff-shell/src/features/auth/ProtectedStaffShell.tsx`
  - `panel/staff-shell/src/features/auth/ProtectedStaffShell.test.tsx`
  - `panel/staff-shell/src/App.test.tsx` (actualizar expectativa de rol en el shell)
  - `panel/staff-shell/src/styles.css`
- Reemplazar el placeholder de `agency_admin` con entrada/cola prototipo y estado vacío claro; conservar las vistas y el logout de otros roles.
- No mostrar inmuebles sintéticos, valores de precio/moneda ni detalles de disponibilidad. No conectar API ni realizar acciones de aprobar/rechazar.
- Mantener navegación, contraste, foco de teclado y responsive consistentes con el panel existente. No tocar E2E, backend, manifiestos ni lockfile.
- T4d (detalle de inmueble) sigue diferido hasta datos de muestra autorizados.

## Tareas

- [x] Explorar mapa UX aprobado, shell, pruebas y límites del panel.
- [x] RED: prueba específica de cola vacía para `agency_admin`; la primera suite completa expuso una expectativa obsoleta para ese rol.
- [x] Adaptar la expectativa app-level en `src/App.test.tsx` sin cambiar las de otros roles.
- [x] GREEN/REFACTOR: implementar shell/estado vacío y estilos accesibles en las cuatro rutas autorizadas.
- [x] `npm run test`, `npm run build`, `git diff --check` y presupuesto <400 verificados de forma independiente.
- [ ] Crear commit convencional con código y pruebas; luego registrar hash/evidencia en el tracker F02.

## Criterios de aceptación

- Solo `agency_admin` ve la entrada/cola de revisión en este corte; otros roles conservan su navegación y logout existentes.
- Sin solicitudes se muestra un estado vacío explícito; no se implican decisiones reales, datos conectados ni propiedades de muestra.
- El nuevo flujo está cubierto por tests, usable por teclado y adaptable a viewport estrecho.
- La suite completa `npm run test`, `npm run build` y `git diff --check` pasan; total de cambios <400 líneas.
- Commit local en la rama F02; no push ni PR.

## Evidencia actual

- RED: la prueba nueva falló como se esperaba por falta de `Cola de revisión`; después, la suite completa reveló una aserción antigua para `agency_admin` en `App.test.tsx`.
- GREEN focal: `npm exec -- vitest run src/features/auth/ProtectedStaffShell.test.tsx` pasó 5/5.
- Suite completa final: `npm run test` pasó en 6 archivos, 52/52 pruebas.
- Build: `npm run build` pasó (`tsc --noEmit`; Vite transformó 35 módulos).
- Diff staged final: 181 líneas cambiadas (169 añadidas, 12 eliminadas) en seis rutas, bajo 400; incluye 127 líneas de código, este task file y el tracker base. `git diff --cached --check` pasó; sin manifiestos/lockfile.
- Commit: pendiente; las seis rutas verificadas están staged.
