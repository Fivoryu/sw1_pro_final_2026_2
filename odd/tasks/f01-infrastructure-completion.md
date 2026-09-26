# Completar F01 — Infraestructura local con Docker y Floci

## Objetivo

Cerrar F01.1–F01.4 de `docs/plan-maestro-roomforge.md` con evidencia local reproducible, sin confundir trabajo del checkout con integración en `origin/main` ni con el corte histórico del plan.

## Estado inicial y alcance

- El checkout raíz inició en `main`, nueve commits detrás de `origin/main`, con cambios staged/unstaged/untracked preexistentes. Se movió temporalmente a la rama F01 durante la coordinación y se restauró a `main` sin limpiar ni revertir archivos.
- Para aislar la continuación se creó y registró `D:/Universidad/Proyectos/2doSemestre2026/sw1/proyecto_final-f01-infrastructure-wt` sobre `feat/f01-infrastructure-completion` en `848f28c`. Se copiaron allí únicamente archivos de infraestructura y contexto F01; el checkout raíz debe permanecer intacto.
- Existe `infra/docker/compose.local.yml` para PostgreSQL y Floci, `infra/docker/local-env.example` y documentación en `infra/README.md`. La tarea previa reporta un smoke exitoso, pero no prueba salud actual ni persistencia tras reinicio.
- F01.2 no tiene aprovisionamiento reproducible/idempotente de recursos S3/SQS.
- F01.3 documenta volúmenes y parada segura, pero no registra una prueba observada de retención tras reinicio.
- El backend FastAPI y `panel/staff-shell` tienen código ejecutable en el checkout, pero no están incluidos en el Compose local. No se encontró worker implementado: no inventarlo ni agregar un contenedor ficticio. Las apps móviles siguen ejecutándose en Android.
- La eliminación preexistente de `infra/docker/compose.postgres.yml` en el checkout raíz permanece intacta. La nueva worktree parte del commit `848f28c`, donde ese archivo está versionado; F01 no lo agrega, elimina ni modifica y no debe trasladar esa diferencia ajena al feature diff.
- Mantener Floci como emulador exclusivamente local de S3/SQS; AWS, despliegue, contratos, worker y cambios de comportamiento del producto quedan fuera de alcance.

## Límites de seguridad y entrega

- Nunca incluir credenciales AWS reales; la plantilla usa solo valores ficticios.
- No ejecutar `down -v`, `prune`, limpiezas globales, migraciones sobre datos existentes ni comandos que eliminen volúmenes. No borrar recursos ajenos; identificar de forma única cualquier dato temporal propio y confirmar su limpieza si se crea.
- No tocar el binario EA, ni restaurar o revertir cambios preexistentes.
- La regla inicial era no hacer commit ni push; el 2026-09-26 el usuario autorizó explícitamente actualizar/entregar F01 en `origin/main`. La autorización se limita a los archivos de F01 y al plan maestro; no incluye cambios preexistentes del checkout raíz, F02 ni otros worktrees.
- El apartado 1.4 del plan es un corte histórico de integración; conservarlo. Registrar el estado local nuevo en F01 sin declarar integración/merge.

## Modo de trabajo y verificación

- Flujo ODD, no SDD: el usuario no seleccionó OpenSpec.
- TDD: no aplicable a la configuración de infraestructura; antecedente explícito en `odd/tasks/local-infrastructure.md`. Verificación prevista con validación/build de Compose y smoke tests reales de dependencias. Si se modifica lógica de aplicación más allá de configuración necesaria para el entorno, detenerse y reevaluar el modo antes de ampliar.
- Ruta: mapeo de 4+ archivos delegado a `gentle-ai-explore`; tareas multiarchivo a un único escritor `gentle-ai-worker`, secuencialmente; verificación de comandos a `gentle-ai-verify` cuando lo determine el plan de `gentle_review assess` y, en cualquier caso, el padre repetirá un check reportado.
- Pronóstico inicial: aproximadamente 250–350 líneas editadas por el autor, excluyendo archivos generados; incertidumbre media. Al iniciar F01 no había autorización para commits; la autorización posterior está registrada en la sección de entrega.

## Tareas

- [x] **F01-T1 — Aprovisionar recursos locales idempotentemente.** Definir nombres de desarrollo para bucket/cola y endpoints en la plantilla local; añadir una preparación repetible con Floci/AWS CLI y documentarla. No duplicar recursos ni requerir credenciales reales.
- [x] **F01-T2 — Incorporar API y panel al Compose.** Empaquetar el backend y `panel/staff-shell` reales, conectar API→PostgreSQL y el acceso de red de API a Floci, enrutar panel→API dentro de Compose y definir healthchecks de aplicación con significado. No agregar worker ausente ni mover apps móviles a Compose. Mantener los cambios de código mínimos y solo para configurar el entorno local.
- [x] **F01-T3 — Verificar persistencia y apagado seguro.** Usar exclusivamente el proyecto aislado `-p roomforge-f01-verify` con puertos `55434`, `14566`, `18000` y `15173`, y sus propios volúmenes nombrados. Confirmar API/panel saludables y datos marcadores de PostgreSQL/S3/SQS antes/después del reinicio; después detener solo esos contenedores con `stop`. No tocar el stack habitual ni eliminar contenedores/volúmenes; registrar cualquier limitación y el espacio local que queda reservado.
- [x] **F01-T4 — Actualizar F01 y cerrar evidencia.** Registrar estado local, procedimientos, comandos observados, límites (incluido worker ausente) y resultados en `infra/README.md` y `docs/plan-maestro-roomforge.md`; preservar el corte histórico. Ejecutar el gate final autorizado y reportar qué no se pudo comprobar.

## Superficies preliminares

- F01-T1: `infra/docker/compose.local.yml`, `infra/docker/local-env.example`, nuevo helper bajo `infra/docker/`, `infra/README.md`.
- F01-T2: `infra/docker/compose.local.yml`, `infra/README.md`, nuevos Dockerfiles acotados para `backend/` y `panel/staff-shell/`, y solo la configuración Vite necesaria para el proxy del servicio API.
- F01-T3: sin cambios de producto; evidencia runtime y, si hace falta, instrucciones bajo `infra/README.md`.
- F01-T4: `infra/README.md`, `docs/plan-maestro-roomforge.md`, este archivo y su espejo Engram.

## Evidencia por tarea

### F01-T1 — completada

- **Rutas:** `infra/docker/compose.local.yml`, `infra/docker/local-env.example`, `infra/docker/init-local-resources.ps1`, `infra/README.md`.
- **Resultado:** nombres locales `roomforge-local-assets` y `roomforge-local-events`, endpoints de Floci separados para host/red Compose y un inicializador que crea solo los recursos configurados cuando faltan. La plantilla usa credenciales ficticias.
- **Verificación del escritor:** Compose `config --quiet` pasó; el parser PowerShell no reportó errores; `compose ps` mostró los servicios existentes `floci` y `postgres` saludables. La primera ejecución creó el bucket/cola; la segunda los omitió como existentes.
- **Verificación independiente:** en la worktree dedicada, Compose `config --quiet` pasó; ambos servicios continuaron `Up`/`healthy`; dos ejecuciones del inicializador informaron que bucket y cola ya existían y los dejaron sin cambios; parser PowerShell sin errores.
- **Spot-check del padre:** `docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml config --quiet` pasó en la worktree F01.
- **RDD:** `gentle_review assess` devolvió riesgo `unassessable` porque el candidato contiene archivos untracked; prescribió autoverificación más verificación independiente. La verificación independiente anterior cumplió ese plan. No se inició review nativo.
- **Límite runtime:** no se iniciaron, detuvieron ni recrearon servicios; tampoco se borraron recursos o volúmenes. No se ejecutaron pruebas de API/panel ni persistencia tras reinicio.
- **Entrega:** sin commit/push por la restricción explícita del proyecto. Los cambios previos del checkout raíz permanecen sin atribución; la continuación F01 está aislada en la worktree.

### F01-T2 — completada

- **Rutas:** `infra/docker/compose.local.yml`, `infra/docker/local-env.example`, `infra/README.md`, `backend/Dockerfile`, `panel/staff-shell/Dockerfile`. `panel/staff-shell/vite.config.ts` se leyó y verificó; no requirió cambios.
- **Resultado:** Compose declara `postgres`, `floci`, `api` y `panel`. Los puertos publicados son configurables y se enlazan a `127.0.0.1`; `api` usa `postgres:5432` y endpoints internos de Floci `http://floci:4566`; el panel usa `api:8000` dentro de Compose y conserva el valor predeterminado del proxy Vite en host (`http://127.0.0.1:8000`). Se documenta `-p roomforge-f01-verify` y puertos alternativos para probar aislado.
- **Verificación del escritor:** Compose `config --quiet` y `config --services` pasaron; `build api panel` construyó ambas imágenes. El escritor informó dos avisos moderados npm audit del conjunto de dependencias existente.
- **Verificación independiente:** inspección estructural de los archivos autorizados confirmó cuatro servicios, loopback, endpoints internos y configuración de aislamiento. `config --quiet` no mostró error; `config --services` listó los cuatro servicios; `build api panel` terminó `Built` para ambas imágenes. La salida capturada no mostró avisos npm audit y `npm ci` apareció en caché; no se infiere una auditoría nueva.
- **Spot-check del padre:** `docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml config --services` listó `postgres`, `api`, `floci`, `panel`.
- **Healthchecks añadidos:** API valida HTTP `/openapi.json`, consulta `SELECT 1` y conectividad TCP a Floci; panel valida que la raíz Vite responda con HTTP exitoso. `panel` espera a que `api` esté saludable.
- **Verificación de healthchecks:** `config --quiet` y `config --services` pasaron; la configuración JSON confirma probes y dependencias `floci→api→panel`. El verificador no inició contenedores ni afirma salud runtime.
- **Spot-check del padre:** `docker compose --env-file infra/docker/local-env.example -f infra/docker/compose.local.yml config --quiet` pasó después de agregar los probes.
- **RDD:** assess `unassessable` por archivos untracked; dos verificaciones independientes cubrieron build/config y los probes/dependencias configurados. No se inició review nativo.
- **Límite runtime:** no se iniciaron, detuvieron ni recrearon contenedores. La conectividad real API/panel y la persistencia quedan para F01-T3.
- **Entrega:** sin commit/push por la restricción del proyecto.

### F01-T3 — completada; runtime verificado en proyecto aislado

#### Intento 1 — bloqueado por Docker Engine

- **Preflight:** `roomforge-f01-verify` no tenía contenedores ni volúmenes; los puertos alternativos `55434`, `14566`, `18000` y `15173` estaban libres. El primer chequeo de puertos falló porque Bash expandió variables `$` de PowerShell; el mismo chequeo escapado pasó al reintentarlo. El stack habitual `roomforge-local-dev` estaba saludable.
- **Arranque aislado:** `up -d --build --wait --wait-timeout 180` terminó correctamente; API, panel, PostgreSQL y Floci alcanzaron `healthy`. Se crearon `roomforge-f01-verify_postgres_data` y `roomforge-f01-verify_floci_data`.
- **Floci aislado:** se crearon el bucket `roomforge-local-assets` y la cola `roomforge-local-events`.
- **Bloqueo:** la creación inicial del marcador PostgreSQL falló sin resultado SQL por `500 Internal Server Error` del Docker Desktop Linux Engine al resolver `containers/json`; el DDL/INSERT quedó incierto. El test se detuvo antes de los marcadores de persistencia y del proxy.
- **Parada:** se detuvo solo el proyecto F01; sus cuatro contenedores quedaron `Exited (255)` y los volúmenes se conservaron. No se usaron comandos de eliminación.

#### Intento 2 — API/panel, PostgreSQL y SQS verificados

- Docker Desktop se inició a solicitud del usuario; el Engine quedó disponible como servidor 29.8.0. El proyecto `roomforge-f01-verify` arrancó sin rebuild y sus cuatro servicios alcanzaron salud; ningún comando operó `roomforge-local-dev`.
- El proxy del panel llegó a FastAPI y devolvió el 404 JSON esperado para la ruta de prueba.
- La tabla `f01_persistence_probe_20260926` no existía al inspeccionarla. Se creó idempotentemente; `f01-persist-20260926` se confirmó tras reiniciar PostgreSQL.
- Se confirmó que el bucket y la cola previos seguían disponibles. El mensaje `f01-persist-20260926` se recibió, sin borrarlo, tras reiniciar Floci.
- **S3 pendiente:** se creó el archivo local, pero `put-object --body /tmp/f01-persistence-marker` falló con código 252, `ParamValidation: Blob values must be a path to a file`. Tras reiniciar Floci, `get-object` devolvió `NoSuchKey`; no hay evidencia de persistencia S3. El intento siguiente probó `fileb:///tmp/f01-persistence-marker` y también fue rechazado; ver intento 3.
- **Parada y datos retenidos:** se detuvo solo `roomforge-f01-verify`; sus cuatro contenedores están detenidos y ambos volúmenes permanecen. Bucket, cola, fila PostgreSQL y mensaje SQS de prueba se conservan; no se borró ningún recurso. En ese momento S3 seguía pendiente; quedó resuelto en el intento 7.
- **RAM:** el reporte del intento 2 no incluyó los valores de `docker stats`; la medición del intento 3 sí está registrada abajo.
- **Stack habitual:** la lectura anterior al reinicio encontró PostgreSQL/Floci de `roomforge-local-dev` en `Exited (255)`; no se atribuye causa y los verificadores no lo iniciaron ni modificaron. Al finalizar T3 quedó detenido; no se restauró para minimizar consumo de RAM.
- **RDD:** assess previo `unassessable`; no hubo nueva conclusión del review. Sin commit/push.

#### Intento 3 — solo Floci; parámetro S3 aún rechazado

- **Preflight:** Engine `29.8.0`; ningún contenedor estaba activo; los cuatro contenedores y dos volúmenes aislados esperados seguían presentes. No se tocó `roomforge-local-dev`.
- **Recursos:** se inició solo el servicio Floci, sin build; Floci quedó healthy y los otros tres servicios permanecieron detenidos. La recreación del archivo marcador local terminó correctamente.
- **Memoria:** `docker stats` midió `94.28 MiB / 5.786 GiB` para Floci.
- **Bloqueo S3:** `s3api put-object --body fileb:///tmp/f01-persistence-marker` falló de nuevo con código 252 y `ParamValidation: Blob values must be a path to a file`. No se ejecutaron lectura, reinicio ni comparación; no se afirma persistencia S3. La causa exacta del parser no está confirmada. En la continuación diagnosticar versión/ayuda del AWS CLI y validar `aws s3 cp ... --dryrun` sin mutación antes del upload real.
- **Parada:** se detuvo solo Floci. Los cuatro contenedores siguen detenidos y se conservaron `roomforge-f01-verify_floci_data` y `roomforge-f01-verify_postgres_data`; no se borraron recursos.

#### Intento 4 — ayuda del CLI ausente; sin operaciones S3

- **Preflight:** Engine `29.8.0`; no había contenedores activos; los cuatro contenedores aislados y ambos volúmenes esperados estaban presentes. Se inició únicamente Floci sin build y quedó healthy.
- **Diagnóstico del CLI:** `aws --version` reportó `aws-cli/2.36.24 Python/3.14.6 Linux/6.18.33.2-microsoft-standard-WSL2 exe/x86_64.rhel.9`. `aws s3 cp help` falló con `No such file or directory` para `/usr/local/aws-cli/v2/2.36.24/dist/awscli/examples/global_synopsis.rst` (código 1).
- **Límite:** conforme al plan de diagnóstico, no se recreó el archivo marcador, no se ejecutó `--dryrun` y no se realizó ninguna operación S3. La ayuda local incompleta no demuestra que falle la transferencia; el canal de datos sigue sin diagnóstico.
- **Parada:** Floci se detuvo; los cuatro contenedores permanecen detenidos y ambos volúmenes se conservaron. No se ejecutó limpieza ni se tocó otro proyecto.
- **RAM:** este diagnóstico no generó medición nueva; la última medición de Floci fue 94.28 MiB / 5.786 GiB.

#### Intento 5 — MSYS reescribió la ruta local; sin mutación S3

- **Preflight:** Engine `29.8.0`; no había contenedores activos; los cuatro contenedores aislados y ambos volúmenes permanecían. Se inició solo Floci sin build y quedó healthy.
- **Dry-run:** la fuente entregada como `/tmp/f01-persistence-marker` llegó al CLI dentro del contenedor como `C:/Users/HP/AppData/Local/Temp/f01-persistence-marker` y falló con `The user-provided path ... does not exist` (código 255). El marcador temporal se recreó sin error; la evidencia apunta a conversión de argumentos POSIX de Bash/MSYS a ruta de Windows antes de invocar Docker. No se ejecutó ninguna escritura S3.
- **Parada:** se detuvo solo Floci; los cuatro contenedores y ambos volúmenes quedaron preservados. La medición de memoria de este intento se omitió tras el fallo; la última válida sigue siendo 94.28 MiB / 5.786 GiB.
- **Corrección confirmada en intento 6:** anteponer `MSYS_NO_PATHCONV=1` evitó la reescritura de la ruta al ejecutar Docker desde Bash/MSYS; el dry-run pasó sin mutar S3.

#### Intento 6 — dry-run S3 correcto; carga real pendiente

- **Preflight:** Engine `29.8.0`; no había contenedores corriendo; el proyecto aislado tenía los cuatro contenedores detenidos y ambos volúmenes presentes.
- **Ejecución de bajo consumo:** se inició solo Floci, sin build; quedó healthy y los demás servicios continuaron detenidos.
- **Dry-run:** `MSYS_NO_PATHCONV=1 docker compose ... exec -T floci aws s3 cp /tmp/f01-persistence-marker s3://roomforge-local-assets/f01/persistence-probe-20260926.txt --endpoint-url http://127.0.0.1:4566 --dryrun` terminó con código 0 y `(dryrun) upload: ../tmp/f01-persistence-marker to s3://roomforge-local-assets/f01/persistence-probe-20260926.txt`. No se realizó transferencia real ni se inspeccionó objeto.
- **Memoria:** Floci usó `86.42 MiB / 5.786 GiB` en `docker stats`.
- **Parada:** se detuvo solo Floci; los cuatro contenedores continúan detenidos y los dos volúmenes se conservaron. Sin modificación de otro proyecto.

#### Intento 7 — objeto S3 persistió tras reinicio; T3 completa

- **Preflight:** Docker Engine `29.8.0`; no había contenedores activos; los cuatro contenedores `roomforge-f01-verify` estaban detenidos y existían los dos volúmenes aislados.
- **Ejecución de bajo consumo:** se inició solo Floci, sin build; alcanzó `healthy` y los demás servicios permanecieron detenidos. Las rutas Linux se enviaron con `MSYS_NO_PATHCONV=1` para evitar la reescritura de Git Bash/MSYS.
- **Carga real:** `aws s3 cp` transfirió 20 bytes al objeto `s3://roomforge-local-assets/f01/persistence-probe-20260926.txt` y terminó con `Completed 20 Bytes/20 Bytes`.
- **Persistencia:** la descarga y comparación exacta con `f01-persist-20260926` pasó antes y después de `docker compose ... restart floci`; tras el reinicio Floci volvió a `healthy`.
- **Memoria y parada:** `docker stats` reportó `38.37 MiB / 5.786 GiB` para Floci. Después se detuvo solo Floci; los cuatro contenedores quedaron detenidos y se conservaron `roomforge-f01-verify_floci_data` y `roomforge-f01-verify_postgres_data`.
- **Datos conservados:** bucket, cola, marcadores PostgreSQL/SQS y objeto S3 permanecen en el proyecto aislado. No se ejecutaron limpiezas, no se tocó `roomforge-local-dev` y no se editaron archivos durante las verificaciones runtime.

### F01-T4 — completada

- **Rutas:** `infra/README.md` y `docs/plan-maestro-roomforge.md`; el registro completo de ejecución permanece en este archivo.
- **README:** se documentaron los cuatro healthchecks y el orden de dependencias, comandos de comprobación API/panel, modo de bajo consumo (solo PostgreSQL y Floci), resultados runtime T3, datos/volúmenes retenidos, workaround `MSYS_NO_PATHCONV=1` para Git Bash/MSYS y los límites de no equivalencia AWS/no operaciones de aplicación.
- **Plan maestro:** se añadió el estado local fechado de F01-T1–T3 dentro de la sección F01. La tabla/corte histórico de §1.4 y F02+ se conservaron sin cambios; se distinguió la rama local sin commit de la integración en `origin/main`.
- **Verificación del escritor y padre:** `git diff --check` pasó para `infra/README.md`; el plan maestro untracked se revisó con `git diff --no-index --check -- /dev/null docs/plan-maestro-roomforge.md`, sin errores de whitespace. Ambos mostraron advertencias LF/CRLF no bloqueantes; el exit 1 del no-index es el esperado para un archivo distinto de `/dev/null`.
- **Verificación independiente:** no encontró hallazgos bloqueantes. Confirmó que README coincide con Compose y la evidencia T3; comparó la copia del plan previa en el checkout raíz y encontró únicamente la inserción F01, con §1.4 y el resto sin cambios. La comparación fue de solo lectura.
- **RDD:** `gentle_review assess` resultó `unassessable` por archivos no rastreados y prescribió autoverificación más verificación independiente; ambas se completaron. No se inició review nativo.
- **Límites:** no se repitieron pruebas runtime ni se ejecutaron comandos Docker durante T4. Docker Desktop quedó iniciado; el proyecto aislado y `roomforge-local-dev` quedaron detenidos. No se hizo commit/push, limpieza ni operación AWS.

## Estado de implementación antes de la entrega

F01-T1–T4 están completas en la worktree local `feat/f01-infrastructure-completion`, basada en `848f28c`. En la comprobación previa a la nueva autorización, los cambios seguían sin commit y no estaban integrados en `origin/main`. Persisten los volúmenes y marcadores de `roomforge-f01-verify`; los cuatro contenedores de prueba permanecen detenidos. No se incorporó worker, código móvil, cambios funcionales ni credenciales reales.

## Continuación: entrega a `origin/main` (autorizada 2026-09-26)

**Autorización:** el usuario indicó: actualizar el plan maestro, hacer commit y push, e integrar F01 en `main`. Usar solo `proyecto_final-f01-infrastructure-wt`; no tocar el checkout raíz (rama `main` antigua con cambios staged/unstaged/untracked preexistentes), el worktree móvil ni F02.

**Preflight observado:** la rama F01 está en `848f28ce204295d88bac7f517de6536c5ef08721`; `origin/main` local y remoto estaban en `b6a468a20888b5c3272fdea1d4815a27897232ba`, nueve commits por delante. El estado inicial de entrega no tenía cambios staged; después del primer audit se dejaron staged los ocho archivos F01 principales. `docs/plan-maestro-roomforge.md` no existe en `origin/main`; para cumplir la solicitud se agregará el documento maestro local completo, con §1.4 conservada como corte histórico. El auditor encontró que el plan enlaza `docs/redefinicion-roomforge.md` y `odd/tasks/local-infrastructure.md`, ausentes de `origin/main`; el usuario eligió explícitamente incluir ambos documentos. Sus referencias anidadas apuntan a documentos ya rastreados en `origin/main`. El peer F02 confirmó que no hay push/merge activo y que no publicará durante esta integración.

**Scope exacto que se propone incluir:** `backend/Dockerfile`, `panel/staff-shell/Dockerfile`, `infra/README.md`, `infra/docker/compose.local.yml`, `infra/docker/init-local-resources.ps1`, `infra/docker/local-env.example`, `docs/plan-maestro-roomforge.md`, `odd/tasks/f01-infrastructure-completion.md`, y los dos documentos de apoyo autorizados por el usuario: `docs/redefinicion-roomforge.md` y `odd/tasks/local-infrastructure.md`. Estos dos se incluirán sin modificar su contenido para resolver referencias del plan. Excluir todo otro cambio del checkout raíz y cualquier artefacto F02.

### Tareas de entrega

- [x] **F01-D1 — Reconciliar alcance y base.** Confirmar autorización, branch/remote tip y archivos exactos; identificar que la rama F01 requiere sincronizarse con los nueve commits de `origin/main`.
- [x] **F01-D2 — Crear commit de trabajo F01.** Se creó `e10d4ec79e848648bd40b4e19319a52b0b38b5d1` (`feat(infra): complete local Docker and Floci stack`) con los diez paths autorizados; no se incluyeron otros documentos o recursos.
- [ ] **F01-D3 — Rebasar y revalidar.** Obtener nuevamente el último `origin/main`, rebasar el commit de F01 y repetir validaciones proporcionales (Compose/build); resolver conflictos únicamente dentro del scope autorizado. No usar force push. El hash puede cambiar al reescribirse; registrar el hash final al terminar.
- [ ] **F01-D4 — Integrar en `main`.** Verificar que no haya otra integración en curso, empujar el branch F01 a `origin/main` solo si es fast-forward y confirmar el hash remoto. No mover la rama local `main` ni alterar su worktree con cambios preexistentes.
- [ ] **F01-D5 — Cerrar evidencia de entrega.** Actualizar el plan maestro y este registro para mostrar la integración posterior al corte §1.4 con los hashes observados; registrar que se incluyeron los dos documentos de apoyo autorizados; crear/push el commit documental de cierre si hace falta y sincronizar el espejo Engram.

**Seguimiento:** el estado final, los hashes de commit y la salida de validación se agregarán tras observar cada operación. Si `origin/main` cambia o la integración concurrente del worktree F02 impide un fast-forward seguro, detenerse y coordinar; nunca forzar el push.
