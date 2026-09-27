# CI inicial de F02 (T5)

El workflow [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) corre en `pull_request`, en `push` a `main` y mediante `workflow_dispatch`. Sus tres jobs son independientes; cada uno usa un runner Ubuntu y no depende de servicios ni de resultados de los otros jobs. El permiso global es solo `contents: read`.

## Equivalentes locales

Ejecutá cada bloque desde el directorio indicado. Las versiones reproducen las fijadas por el workflow.

### Backend — Python 3.11

Desde `backend/`:

```bash
python -m pip install ".[dev]"
python -m pytest tests -q
ruff check app tests
pyright app tests
```

No se configura `ROOMFORGE_R6_DATABASE_URL` ni se levanta una base de datos.

### Panel de personal — Node 22

Desde `panel/staff-shell/`:

```bash
npm ci
npm run test
npm run build
```

La prueba de navegador/E2E del panel no forma parte de este slice.

### App cliente — Flutter 3.41.8

Desde `apps/cliente_mobile/`:

```bash
flutter pub get
flutter test
flutter analyze
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

El build Android usa el ejemplo HTTPS no secreto documentado por la app; no contacta ni despliega a ese servicio.

## Exclusiones y límites

- `apps/captura_mobile` se omite porque no tiene manifiesto ni código Flutter.
- No se incluyen Docker/Compose, PostgreSQL ni pruebas E2E con base de datos. La paridad E2E queda diferida mientras F02 T3b siga pausada; este cambio no autoriza servicios de base de datos en CI.
- No hay secretos configurados ni se configura protección de ramas como parte de este cambio.
- El workflow no despliega ni usa permisos de escritura o `pull_request_target`.
