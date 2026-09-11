# Exploración — HU-003: integración pública

## 1. Identificación, objetivo y decisiones de sesión

- **Cambio:** `hu003-integracion-publica`.
- **Producto:** RoomForge, SW1 2026-2, Grupo #12.
- **Trazabilidad:** `PB-003 → HU-003 → CU-003 → RF-033 → RNF-017 → Sprint 3`.
- **Objetivo:** completar únicamente las superficies públicas e integración diferidas del cambio archivado `hu003-verificacion-correo`.
- **Modo:** interactivo.
- **Almacén:** híbrido (OpenSpec + Engram).
- **Estrategia de entrega:** `ask-on-risk`; no se asume encadenamiento.
- **Presupuesto autorizado:** 600 líneas modificadas totales, dividido en dos slices acotados.
- **Idioma:** documentación en español profesional y neutral; código e identificadores en inglés.
- **Restricciones respetadas:** no se modificó el cambio archivado, código de producto, gitlinks, configuraciones, ramas, commits, remotes ni documentación de Sprint 3.

La exploración fue de solo lectura. No se ejecutaron tests, builds, migraciones, Docker, Flutter, npm ni investigación web externa.

## 2. Fuentes verificadas y método

### Fuentes del monorepo

- `README.md`: monorepo coordinador y repositorios individuales de backend, panel y cliente móvil.
- `AGENTS.md`: arquitectura multi-repo, convenciones, runners y estado declarado de las superficies.
- `openspec/config.yaml`: almacén híbrido, ejecución interactiva, idioma documental, límite configurado de 600 líneas y runners declarados.
- `openspec/project-context.md`: stack, restricciones y gap de inicialización de CodeGraph/Engram.
- `.gitmodules`: URLs y ramas declaradas para `backend`, `panel` y `apps/cliente_mobile`.
- `infra/docker/compose.postgres.yml`: PostgreSQL `postgres:16-alpine` publicado en `5434`; no contiene Mailpit.
- `openspec/changes/hu003-verificacion-correo/{explore,proposal,design,tasks}.md`: alcance archivado y trabajo backend diferido.

### Fuentes del backend independiente

- `backend/app/modules/identity/{router,service,schemas,models,repository,verification}.py`.
- `backend/app/core/config.py`, `backend/app/main.py`, `backend/pyproject.toml`.
- `backend/alembic/versions/0001...0006...py` y `backend/alembic/env.py`.
- `backend/tests/{test_registro,test_autenticacion,test_verificacion_correo}.py`.

### Fuentes del cliente móvil independiente

- `apps/cliente_mobile/README.md`, `pubspec.yaml`.
- `lib/data/services/auth_api_service.dart`.
- `lib/domain/models/auth_models.dart`.
- `lib/ui/features/auth/{views/login_screen,views/register_screen,view_models/auth_view_model}.dart`.
- `lib/app.dart`.
- `android/app/src/main/AndroidManifest.xml` y `ios/Runner/Info.plist`.

### Fuente del panel web independiente

- `panel/README.md`: declara React + TypeScript + Vite y estado de estructura inicial, sin código.

**CodeGraph:** se comprobó la ruta esperada `.codegraph/status.json`, pero no fue legible en este checkout. Conforme a la instrucción de fallback, la inspección estructural se realizó mediante documentación y lectura dirigida de fuentes; no se afirma disponibilidad de un índice CodeGraph.

## 3. Estado actual verificado

### 3.1 Backend: núcleo archivado parcialmente integrado, superficie pública ausente

El checkout actual contiene más que la línea base descrita en algunos documentos archivados:

- `Settings` ya define `email_verification_token_ttl_days`, cooldown y máximo de reenvíos, con defaults observados de 7 días, 15 minutos y 3 reenvíos.
- `models.py` ya contiene `EmailVerificationToken` y estados `active`, `invalidated`, `consumed`.
- `verification.py` ya contiene generación segura, hash SHA-256, emisión, reenvío, consumo y puertos de notificación.
- `repository.py` ya contiene `EmailVerificationRepository`, locks sobre usuario/token y consumo que marca `correo_verificado`.
- `0006_hu003_email_verification.py` existe y declara `down_revision = "0005"`. El head nominal observado es `0006`; debe verificarse con Alembic antes de aplicar cambios.
- `test_verificacion_correo.py` ya cubre el núcleo con fakes: token URL-safe, hash, TTL/settings, orden de persistencia-notificación, expiración y fallos de persistencia/entrega.

Sin embargo, el router y los servicios públicos observados todavía no integran HU-003:

- `identity/router.py` solo publica registro, login, refresh, logout y `me`.
- `IdentityService.registrar` crea usuario activo con `correo_verificado=False`, pero no coordina emisión/notificación.
- `AuthenticationService.login` valida credenciales/estado, pero no bloquea explícitamente el login no verificado ni dispara reenvío.
- `schemas.py` no contiene requests/responses públicos de solicitar, reintentar o consumir activación.
- No se identificó un adaptador SMTP/Mailpit ni settings de host, puerto, remitente, URL pública o scheme app.
- `main.py` registra el router de identidad existente; no hay router separado de activación.

Esto confirma que el trabajo público diferido no debe reimplementar el núcleo archivado, sino integrarlo con contrato HTTP, registro/login y entrega.

### 3.2 Cliente Flutter: auth existente, sin activación ni deep link

Hechos observados:

- `AuthApiService` usa `http`, una `API_BASE_URL` recibida por `--dart-define` y una base predeterminada `http://10.0.2.2:8000/api/v1`.
- `RegistrationResult` exige actualmente `id`, `correo`, `estado`, `correo_verificado` y `creado_en`; no contempla orientación a activación.
- `RegisterScreen` redirige a `/login` después del registro exitoso y muestra que la cuenta ya puede iniciar sesión.
- `LoginScreen` no ofrece solicitud/reenvío de activación.
- `AuthViewModel` solo conoce registro, login, restauración y logout.
- `app.dart` usa `go_router`; solo `/login`, `/register`, `/home` y `/` están declaradas, y el redirect trata login/registro como públicas.
- `pubspec.yaml` ya incluye `go_router` y `http`; no hay dependencia de deep linking específica.
- Android solo tiene el intent filter launcher; iOS no declara un URL scheme de RoomForge.

La arquitectura existente permite agregar una superficie separada de servicio/repositorio/ViewModel, pero la forma exacta del enlace, manejo de URI inicial y recepción en segundo plano son GAPs técnicos a confirmar durante design/apply. No se debe asumir que el handler predeterminado cubre todos los casos sin build/prueba.

### 3.3 Panel web: React/Vite declarado, scaffold no verificable

`panel/README.md` declara React, TypeScript y Vite, pero también indica estructura inicial sin código. No se verificó `package.json`, entrypoint, router, scripts, package manager ni configuración de API. Por tanto:

- El panel es una superficie candidata para una página web pública de activación.
- No es seguro prometer archivos, rutas de integración o comandos concretos antes de inspeccionar el repositorio individual.
- Si no existe scaffold materializado, crear uno dentro de este slice puede consumir el presupuesto y requiere una decisión explícita.

### 3.4 Infraestructura y entorno

- PostgreSQL local está documentado mediante Docker Compose, imagen `postgres:16-alpine` y puerto host `5434`.
- Mailpit no está presente en `infra/docker/compose.postgres.yml`.
- El backend declara pytest, Ruff y Pyright; el cliente declara `flutter test` y `flutter analyze`.
- No hay evidencia ejecutada en esta exploración sobre disponibilidad de Docker, PostgreSQL, Mailpit, SDK Flutter, Node/npm, servidor SMTP, emulador o dispositivo.
- La configuración del backend usa `.env` local ignorado para base de datos/JWT; no se deben agregar secretos al repositorio.

## 4. Resultado público objetivo de HU-003

El resultado objetivo es que un cliente pueda completar de manera comprobable el flujo que el núcleo ya prepara:

1. Registro de cuenta no verificada con respuesta que oriente a revisar el correo, sin exponer token ni contraseña.
2. Solicitud explícita y reintento genérico de activación.
3. Bloqueo de la creación de sesión antes de verificar el correo, si se mantiene la decisión heredada del cambio archivado.
4. Entrega visible en un Mailpit local o adaptador equivalente aprobado.
5. Consumo del enlace mediante una superficie web y, si la app existente lo soporta tras verificación, mediante deep link Flutter.
6. Activación de un solo uso, sin auto-login, con confirmación y camino claro hacia login.
7. Respuestas y UX que no revelen existencia de cuenta, estado del token, secreto, contraseña ni URL sensible en logs.

El punto 3 y los límites concretos deben tratarse como reglas heredadas del cambio archivado, pero su contrato observable debe ser revalidado en proposal/spec contra el código actual, porque el router actual todavía no los aplica.

## 5. Límite propuesto de dos slices y presupuesto

La división recomendada respeta el presupuesto total de 600 líneas y la independencia de repositorios:

### Slice 2A — Backend público e integración de entrega

**Presupuesto orientativo:** hasta 300 líneas modificadas. Es un límite de planificación, no un conteo medido.

Incluye solo:

- schemas y endpoints públicos de solicitar/reintentar/consumir activación;
- wiring del servicio archivado al registro y al login, incluyendo la política de login no verificado si la propuesta la confirma;
- adaptador de notificación y configuración mínima para Mailpit, sin secretos;
- integración mínima de Docker/SMTP solo si el archivo y el entorno ya soportan una extensión acotada;
- tests de contrato, regresión de registro/login y fake notifier; evidencia real de PostgreSQL/Mailpit únicamente si están disponibles.

No incluye UI web ni Flutter. El corte debe dejar una API utilizable y documentable para los dos clientes.

### Slice 2B — Cliente móvil, web y evidencia de integración

**Presupuesto orientativo:** hasta 300 líneas modificadas. GAP crítico: puede no ser suficiente si `panel/` requiere crear un scaffold.

Incluye solo si las superficies actuales lo permiten sin crear una aplicación web desde cero:

- modelos/servicio/repository/ViewModel y pantallas mínimas Flutter;
- rutas públicas y recepción del deep link, con fallback web si corresponde;
- página/ruta web mínima integrada al scaffold real del panel;
- tests de contrato/flujo disponibles para Flutter y web.

Si `panel/` no tiene scaffold real, la proposal debe decidir si se excluye temporalmente la UI web, se reemplaza por una página servida por otra superficie existente o se solicita presupuesto adicional. No se debe ocultar esa ampliación bajo el límite de 600.

## 6. Dependencias y orden

1. **Proposal:** cerrar alcance exacto de los dos slices, regla de login, contrato público y decisión sobre panel.
2. **Spec:** fijar endpoints, códigos, cuerpos, errores genéricos, URL/URI, seguridad y criterios de aceptación.
3. **Design:** confirmar seam backend existente, transacción registro-notificación, configuración Mailpit, integración Flutter y entrypoint web real.
4. **Slice 2A:** implementar y probar la API antes de cambiar clientes.
5. **Slice 2B:** integrar Flutter/web contra el contrato estable; no modificar gitlinks desde la coordinación.
6. **Verify:** ejecutar validaciones por repositorio y evidencia de entorno disponible.
7. **Archive:** actualizar trazabilidad y documentación únicamente con resultados reales.

El orden backend → clientes evita que cada repositorio invente contratos divergentes. Los cambios de producto deben vivir en `backend/`, `apps/cliente_mobile/` y `panel/` dentro de sus repositorios individuales; el root OpenSpec coordina dependencias y evidencia.

## 7. Reglas heredadas de seguridad, privacidad y negocio

Se heredan del cambio archivado, pero deben quedar formalizadas en la propuesta/especificación:

- token aleatorio de un solo uso; solo hash persistido; nunca token crudo en base de datos, respuestas o logs;
- TTL y límites configurados por HU-003, sin reutilizar silenciosamente `activation_ttl_days` de HU-004;
- un token activo por usuario y consumo atómico/concurrente;
- respuestas genéricas para correo inexistente, verificado, limitado, token inválido, expirado o consumido;
- no enviar contraseñas por correo;
- la entrega no debe marcar la cuenta como verificada antes del consumo válido;
- el registro/login no deben filtrar secretos ni convertir errores de proveedor en un oráculo de cuentas;
- mantener separado el contexto de activación de cliente respecto de la activación de onboarding de HU-004;
- no revocar automáticamente sesiones preexistentes ni rediseñar refresh/logout/me sin decisión explícita;
- no persistir ni imprimir query strings de activación en la interfaz o telemetría.

**Decisiones de producto heredadas que deben citarse, no reinventarse:** verificación previa al login, Mailpit para demo, confirmación sin auto-login, respuestas genéricas, reenvío automático condicionado a credenciales válidas y límites de 7 días/15 minutos/3 reenvíos, si siguen aprobadas por el estado archivado.

## 8. Estrategia de pruebas y evidencia

### Backend

- RED/GREEN con fakes para contrato HTTP, notifier, reloj y servicios.
- Regresión de `backend/tests/test_registro.py` y `test_autenticacion.py`.
- Suite declarada: `.venv/Scripts/python.exe -m pytest backend/tests -q` desde la raíz, o el runner equivalente documentado desde `backend/`.
- Ruff: `.venv/Scripts/ruff.exe check backend/app backend/tests` según el ejecutable disponible; confirmar path antes de afirmar resultado.
- Pyright: `.venv/Scripts/pyright.exe backend/app backend/tests`.
- PostgreSQL real: `.venv/Scripts/python.exe -m alembic -c backend/alembic.ini upgrade head` después de levantar `docker compose -f infra/docker/compose.postgres.yml up -d`; comprobar head y conservación de datos.
- Mailpit real: solo después de confirmar que Docker/imagen/puertos están disponibles; evidencia mínima debe mostrar mensaje y enlace sin capturar secretos.

### Flutter

- `flutter test` y `flutter analyze` desde `apps/cliente_mobile`.
- Tests de servicio con cliente HTTP grabador, repositorio/ViewModel y routing.
- Validar rutas públicas durante restauración de sesión, token ausente/alterado, éxito, error genérico y no persistencia del token.
- Validar deep link en la plataforma efectivamente disponible; no afirmar Android/iOS si no hay build o dispositivo.

### Web

- Primero identificar `package.json`, package manager, entrypoint y runner reales.
- Ejecutar solo scripts existentes y documentar `N/A` si no hay scaffold o herramienta.
- Validar extracción efímera del token, limpieza de URL, respuesta 200/errores genéricos, navegación a login y accesibilidad básica.

### Evidencia común

No se debe declarar PASS por presencia de archivos. Deben separarse pruebas fake, integración PostgreSQL, entrega Mailpit, cliente móvil y web. Si una herramienta o entorno no está disponible, registrar el gap y conservar el resultado no disponible.

## 9. No objetivos y trabajo explícitamente diferido

- No modificar `hu003-verificacion-correo` ni repetir su núcleo de modelos, política, repository, migración o tests salvo corrección imprescindible detectada por integración.
- No activar HU-004, HU-005 o HU-006 ni compartir sus tablas, rutas o reglas.
- No implementar recuperación/cambio de contraseña, MFA, cambio de correo, perfiles, roles, tenants, membresías, suscripciones ni notificaciones generales.
- No crear un proveedor productivo de correo, outbox distribuido, worker de reintentos ni observabilidad nueva.
- No implementar Universal Links/App Links productivos sin dominio, certificados, fingerprints y archivos verificables.
- No reconstruir `panel/` como aplicación nueva dentro de este presupuesto.
- No modificar `docs/diagramas/Diagrama1.eapx`, gitlinks, branches, commits, remotes ni secretos.
- No completar documentación Sprint 3 con resultados no ejecutados; cualquier actualización documental posterior requiere una fase autorizada y evidencia real.

## 10. Riesgos, gaps y decisiones para proposal

- **GAP-PUB-001 — Contrato HTTP:** nombres finales de endpoints, códigos, cuerpos y errores aún no están publicados en el código actual.
- **GAP-PUB-002 — Wiring de registro/login:** el núcleo existe, pero no está conectado al router; debe definirse si el registro responde éxito aunque Mailpit falle y cómo se comunica el reintento.
- **GAP-PUB-003 — Política de login:** el cambio archivado propone bloquear cuentas no verificadas y reintentar tras credenciales válidas; debe reconciliarse con tests/UX actuales y sesiones ya existentes.
- **GAP-PUB-004 — Mailpit:** no está en compose ni se verificó imagen, puertos, proveedor SMTP, host desde backend host/containerizado o disponibilidad de Docker.
- **GAP-PUB-005 — URL/URI:** falta decidir contrato canónico de enlace web y esquema app; no asumir `localhost`, puerto, dominio o scheme sin configuración existente.
- **GAP-PUB-006 — Panel:** README declara React/Vite, pero no se verificó scaffold, entrypoint, router, package manager ni runner. Puede hacer inviable Slice 2B dentro de 300 líneas.
- **GAP-PUB-007 — Deep link Flutter:** no se verificó recepción en cold start/resume ni compatibilidad real de Android/iOS; el manifest/plist actual no tienen la configuración de activación.
- **GAP-PUB-008 — Conteo:** los 300+300 son límites de planificación; no hay conteo de cambios porque no se implementó. Si un slice excede su límite, `ask-on-risk` debe detenerse y solicitar decisión, no comprimir seguridad o tests.
- **GAP-PUB-009 — Entorno:** disponibilidad de PostgreSQL, Mailpit, Flutter, Node y emuladores permanece sin ejecutar.

Decisiones que la proposal debe resolver: (a) si Slice 2B incluye web solo cuando el scaffold exista; (b) contrato público exacto; (c) configuración canónica de enlace; (d) estrategia de fallo de entrega; (e) criterios para considerar Mailpit una prueba real y no solo fake; (f) si se acepta una UI web posterior si el panel sigue vacío.

## 11. Topología SDD sugerida

Se recomienda conservar el cambio raíz `openspec/changes/hu003-integracion-publica/` para:

- propuesta, especificación, diseño y tareas de coordinación;
- presupuesto agregado, dependencias entre repositorios, trazabilidad y evidencia de integración;
- riesgos y decisiones de producto/contrato comunes.

Solo se justifican cambios hijos por repositorio si las herramientas/repositorios individuales admiten su propio ciclo SDD sin duplicar contrato:

- child change en `backend` para Slice 2A, si el repositorio backend tiene OpenSpec/Engram inicializado y necesita aplicar/verificar aisladamente;
- child change en `apps/cliente_mobile` para Slice 2B Flutter, si su repositorio puede persistir artefactos;
- child change en `panel` solo si existe scaffold y ciclo SDD propio.

Los hijos deben referenciar el contrato del root y no redefinir endpoints o reglas. Si no hay soporte SDD en un submódulo, el root mantiene la coordinación y las tareas deben indicar repositorio, superficie y evidencia esperada sin inventar artefactos hijos.

## 12. Recomendación siguiente

`next_recommended: proposal`.

La proposal debe convertir los gaps de contrato, Mailpit, panel y deep linking en decisiones aprobables, manteniendo dos slices dentro de 600 líneas totales y sin reabrir el núcleo archivado.
