# Conversión de submódulos a un único repositorio

## Objetivo y decisiones

Convertir los cuatro submódulos actuales en directorios normales del repositorio principal, usando su contenido local actual sin importar los historiales Git hijos. El usuario autorizó commit y push directo a `main`.

El usuario pidió retirar OpenSpec de la conversión y eligió **quitar solo las copias de producto** `backend/openspec/` y `panel/openspec/`, preservando intacta la carpeta canónica raíz `openspec/` y sus cambios locales.

## Límites de seguridad

- Preservar archivos presentes, incluidas modificaciones, eliminaciones y archivos sin seguimiento; no hacer `checkout`, `reset`, `clean` ni restaurar contenido eliminado.
- Los directorios `.git` hijos se archivan localmente dentro de `.git/legacy-submodule-repos/`; esos metadatos no se importan ni se incluyen en el repositorio principal.
- Las copias OpenSpec actuales de backend y panel se archivan localmente bajo `.git/legacy-openspec/` antes de excluirlas del snapshot principal. La OpenSpec raíz no se modifica ni se stagea.
- Eliminar `.gitmodules`, los cuatro gitlinks y las secciones locales residuales `submodule.*` de `.git/config`; incluir al índice principal solo el snapshot actual no ignorado, respetando los `.gitignore`. No agregar cambios raíz ajenos a estos paths.
- `README.md` y `AGENTS.md` describen el repositorio único. Se conservan documentos históricos fuera de las copias retiradas.
- No ejecutar `git submodule deinit/update`, no descargar repositorios, no hacer force push.

## Estado inicial observado

- Gitlinks raíz: `backend` → `93c54ce`; `panel` → `46950ed` (el HEAD local del hijo era `5bde17d`); `apps/captura_mobile` → `9acce4d`; `apps/cliente_mobile` → `865a88d`.
- Los cuatro directorios tenían su propio `.git` como directorio.
- Estado local: backend 18 modificados, 90 eliminados, 32 sin seguimiento; panel 40 eliminados y 23 sin seguimiento; cliente móvil 1 modificado, 92 eliminados y 1 sin seguimiento; captura móvil limpio.
- La raíz contiene cambios y archivos sin seguimiento en `infra/`, `openspec/`, `docs/`, `odd/`, `.pi/` y otros; preservarlos.
- Auditoría de ignores: 5,615 archivos ignorados/no seguidos dentro de los hijos (41 backend, 5,570 panel, 0 captura, 4 cliente) también están cubiertos por ignores raíz; ninguno debe agregarse accidentalmente.

## Tareas

- [x] Inspeccionar `.gitmodules`, gitlinks, HEADs y estados; confirmar con el usuario snapshot actual sin historiales.
- [x] Archivar localmente los cuatro `.git`, retirar `.gitmodules` y gitlinks, y convertir los snapshots a rutas normales.
- [x] Actualizar `README.md` y `AGENTS.md` para describir repositorio único y clonado normal.
- [x] Archivar localmente y excluir `backend/openspec/` y `panel/openspec/`; mantener intacto y sin stagear `openspec/` raíz.
- [x] Retirar las secciones locales `submodule.*`; verificar staging/ignores/secretos y confirmar que los cambios raíz ajenos siguen intactos.
- [ ] **En curso:** cambiar a `main`, hacer commit convencional, registrar su hash aquí y hacer push a `origin/main` sin force.

## Criterios de cierre

1. `.gitmodules` ya no existe, no hay entradas modo `160000`, `git submodule status` no muestra submódulos y `.git/config` no tiene secciones `submodule.*` activas.
2. Las cuatro carpetas son normales e incorporan el contenido actual no ignorado, excepto las copias OpenSpec de producto retiradas.
3. Metadatos Git hijos y OpenSpec de producto quedan archivados localmente bajo `.git/`, fuera del árbol versionado; los historiales no se importan.
4. `openspec/` raíz y sus modificaciones permanecen intactas y no staged.
5. README/AGENTS documentan un solo repositorio y los cambios raíz no relacionados se preservan.
6. Un commit convencional queda en `main` y se publica a `origin/main`; sin force push.

## Evidencia antes del commit

Staging final: 70 paths, 12,344 inserciones y 77 eliminaciones; `git diff --cached --check` pasó. No hay `.gitmodules`, entradas modo `160000`, marcadores `.git` anidados ni configuración local `submodule.*`. Las copias `backend/openspec/` y `panel/openspec/` están archivadas en `.git/legacy-openspec/{backend,panel}` y no staged; `openspec/` raíz y sus cambios locales permanecen intactos y unstaged.

La verificación confirmó que los paths staged están limitados a la conversión aprobada, no hay secretos confirmados ni cachés/build/.env real, y los cambios raíz ajenos conservan su estado. El escáner heurístico tuvo coincidencias de strings de prueba, sin valor confirmado como credencial activa. No se ejecutaron pruebas/build después de la conversión estructural. Git emitió avisos LF→CRLF al agregar archivos; no se reescribió el árbol de trabajo.

## Siguiente paso

Cambiar a `main`, refrescar el staging con paths explícitos, ejecutar el commit convencional, registrar su hash en este documento y publicar a `origin/main` sin force.