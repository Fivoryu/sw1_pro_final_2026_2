# Capturas de las superficies implementadas

Estas imágenes se generan durante una ejecución real del E2E del panel de personal. No son maquetas ni imágenes preparadas por separado.

## Inventario

| Archivo | Qué muestra | Fase del plan | Reproducción exacta | Dimensiones |
| --- | --- | --- | --- | --- |
| `f02-staff-login-initial.png` | Pantalla de acceso de personal antes de ingresar datos. | F02 — base y experiencia de usuario del panel. | `cd panel/staff-shell && npm run test:e2e` | 1600 × 1006 px |
| `f02-staff-login-filled.png` | Formulario con el correo ficticio de la prueba y la contraseña todavía enmascarada, justo antes de enviarlo. | F02 — base y experiencia de usuario del panel. | `cd panel/staff-shell && npm run test:e2e` | 1600 × 1006 px |
| `f03-staff-totp-verification.png` | Pantalla del segundo paso de verificación, antes de ingresar el código TOTP. | F03 — identidad y sesión. | `cd panel/staff-shell && npm run test:e2e` | 1600 × 1000 px |
| `f03-staff-protected-view-login.png` | Vista protegida de administración inmediatamente después de iniciar sesión. | F03 — identidad y sesión. | `cd panel/staff-shell && npm run test:e2e` | 1600 × 1000 px |
| `f03-staff-protected-view-reload.png` | La misma vista protegida luego de recargar la página; evidencia visual de la restauración de sesión. | F03 — identidad y sesión. | `cd panel/staff-shell && npm run test:e2e` | 1600 × 1000 px |
| `f04-staff-publication-api-docs.png` | **No disponible: no se generó PNG.** El intento contra `/docs` no logró mostrar en Swagger UI la ruta OpenAPI `/api/v1/staff/agencies/{agency_id}/listings/{listing_id}/deposit`, por lo que no se guardó una captura incompleta. | F04 — publicación de inmuebles (API, sin UI propia). | `cd panel/staff-shell && npm run test:e2e` | No aplica |

Desde la raíz del repositorio, el comando exacto de reproducción es:

```sh
cd panel/staff-shell && npm run test:e2e
```

El E2E guarda las imágenes en `docs/capturas/`. Se puede cambiar el destino con `ROOMFORGE_CAPTURE_DIR`; las rutas relativas se resuelven desde la raíz del repositorio. El nombre de cada captura es fijo y se sobrescribe en ejecuciones posteriores.

## Límites y alcance

- Las capturas corresponden al servidor de desarrollo de Vite y a una cuenta ficticia sembrada por la prueba, contra un contenedor PostgreSQL aislado y descartable. No representan un entorno desplegado ni datos reales.
- Las aplicaciones móviles no tienen capturas: en este entorno no hay un dispositivo ni un emulador disponible.
- F01 es infraestructura y F04 es una superficie de backend; ninguna tiene una UI propia. Para F04 solo se intentó capturar la documentación de la API en `/docs`, pero Swagger UI no mostró una de las rutas de publicación requeridas y no se produjo una imagen.
- Ninguna imagen fue retocada, recortada ni fabricada: las cinco PNG disponibles proceden directamente de la ejecución real del navegador.
- La contraseña solo aparece enmascarada en el formulario. No se capturan el secreto TOTP, JWT, token de acceso ni valor CSRF en texto claro.
