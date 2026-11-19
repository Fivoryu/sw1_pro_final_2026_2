# Lista exacta propuesta para el PR

Base/destino propuesto: `feat/f07-video-capture` en `46b092a312a360b690ba6a0ff7b5a53e516d3a4b`. Este listado es el delta de integración, no un PR creado ni archivos ya staged.

**102 rutas: 64 versionadas modificadas y 38 nuevas.** Incluye este manifiesto y los otros módulos del informe. `M` significa modificada respecto de la base; `A` indica nueva propuesta.

```text
M .gitignore
M apps/captura_mobile/android/app/src/main/AndroidManifest.xml
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/ConnectivityEvents.kt
M apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/MainActivity.kt
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/CaptureRecovery.kt
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/FrameTiming.kt
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/GuidanceCopyGate.kt
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/GuidanceSamplingPolicy.kt
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/GuidedCaptureProgress.kt
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/PreviewGuidanceSampler.kt
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/ReferenceCandidateOverlay.kt
M apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/VideoCaptureActivity.kt
M apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/VideoPackage.kt
M apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/VideoRecorder.kt
A apps/captura_mobile/android/app/src/main/kotlin/com/example/captura_mobile/video/VisualCaptureGuidance.kt
A apps/captura_mobile/android/app/src/test/kotlin/com/example/captura_mobile/video/CaptureRecoveryTest.kt
A apps/captura_mobile/android/app/src/test/kotlin/com/example/captura_mobile/video/FrameTimingTest.kt
A apps/captura_mobile/android/app/src/test/kotlin/com/example/captura_mobile/video/GuidanceCopyGateTest.kt
A apps/captura_mobile/android/app/src/test/kotlin/com/example/captura_mobile/video/GuidedCaptureProgressTest.kt
A apps/captura_mobile/android/app/src/test/kotlin/com/example/captura_mobile/video/VideoCaptureLifecycleTest.kt
M apps/captura_mobile/android/app/src/test/kotlin/com/example/captura_mobile/video/VideoPackageTest.kt
A apps/captura_mobile/android/app/src/test/kotlin/com/example/captura_mobile/video/VisualCaptureGuidanceTest.kt
M apps/captura_mobile/lib/data/services/ar_capture_channel.dart
M apps/captura_mobile/lib/data/services/capture_draft_store.dart
M apps/captura_mobile/lib/data/services/staff_capture_api.dart
M apps/captura_mobile/lib/data/services/staff_scene_api.dart
M apps/captura_mobile/lib/data/services/video_capture_channel.dart
M apps/captura_mobile/lib/domain/listing_drafts_controller.dart
M apps/captura_mobile/lib/domain/spatial/capture_upload.dart
M apps/captura_mobile/lib/domain/spatial/capture_upload_controller.dart
M apps/captura_mobile/lib/domain/spatial_capture_controller.dart
M apps/captura_mobile/lib/domain/video_capture_controller.dart
M apps/captura_mobile/lib/main.dart
M apps/captura_mobile/lib/ui/spatial/capture_upload_format.dart
M apps/captura_mobile/lib/ui/spatial/spatial_capture_screen.dart
M apps/captura_mobile/pubspec.lock
M apps/captura_mobile/test/capture_upload_controller_test.dart
M apps/captura_mobile/test/capture_upload_format_test.dart
M apps/captura_mobile/test/offline_mode_test.dart
M apps/captura_mobile/test/pending_upload_store_test.dart
M apps/captura_mobile/test/spatial_capture_upload_screen_test.dart
M apps/captura_mobile/test/staff_capture_api_test.dart
M apps/captura_mobile/test/staff_scene_api_test.dart
M apps/captura_mobile/test/support/fake_capture_backend.dart
M apps/captura_mobile/test/support/fake_video_capture.dart
M apps/captura_mobile/test/video_capture_controller_test.dart
A backend/alembic/versions/0036_capture_integrity.py
M backend/app/main.py
M backend/app/modules/catalog/router.py
M backend/app/modules/catalog/schemas.py
M backend/app/modules/catalog/service.py
M backend/app/modules/reconstruction/job_queue.py
M backend/app/modules/reconstruction/models.py
A backend/app/modules/reconstruction/package.py
M backend/app/modules/reconstruction/router.py
M backend/app/modules/reconstruction/schemas.py
M backend/app/modules/reconstruction/service.py
A backend/tests/test_capture_integrity_migration.py
A backend/tests/test_f07_integration.py
M backend/tests/test_reconstruction.py
A backend/tests/test_reconstruction_hardening.py
A backend/tests/test_reconstruction_residual.py
M backend/tests/test_reconstruction_v2.py
M backend/tests/test_scene_scale.py
M backend/tests/test_scene_scale_persistence.py
M docs/api/f06-scene-contract.md
M docs/api/f07-capture-package.md
A docs/integracion/f07-20261118/README.md
A docs/integracion/f07-20261118/archivos-pr.md
A docs/integracion/f07-20261118/plan-documentacion.md
A docs/integracion/f07-20261118/verificacion.md
A infra/docker/compose.reconstruction.yml
A infra/docker/inference/Dockerfile.reconstruction
A infra/docker/inference/requirements-reconstruction.txt
A openspec/changes/f07-integrity-hardening/design.md
A openspec/changes/f07-integrity-hardening/proposal.md
A openspec/changes/f07-integrity-hardening/spec.md
A openspec/changes/f07-integrity-hardening/tasks.md
M panel/staff-shell/src/application/captureReviewApi.test.ts
M panel/staff-shell/src/application/captureReviewApi.ts
M panel/staff-shell/src/application/sceneContract.ts
M panel/staff-shell/src/application/staffListingsApi.test.ts
M panel/staff-shell/src/application/staffListingsApi.ts
M panel/staff-shell/src/features/editor3d/CaptureDraftPanel.test.tsx
M panel/staff-shell/src/features/editor3d/CaptureDraftPanel.tsx
M panel/staff-shell/src/features/editor3d/SceneEditor.test.tsx
M panel/staff-shell/src/features/editor3d/SceneEditor.tsx
M worker3d/README.md
M worker3d/reconstruct_video.py
M worker3d/reconstruction_worker.py
A worker3d/runtime_smoke.py
M worker3d/tests/test_reconstruct_video.py
M worker3d/tests/test_reconstruct_video_cache.py
M worker3d/tests/test_reconstruct_video_detection.py
M worker3d/tests/test_reconstruct_video_rect.py
A worker3d/tests/test_reconstruct_video_runtime.py
A worker3d/tests/test_reconstruction_cache.py
A worker3d/tests/test_reconstruction_hardening.py
M worker3d/tests/test_reconstruction_worker.py
M worker3d/tests/test_review_sheet_contract.py
A worker3d/tests/test_video_component_selection.py
A worker3d/tests/test_video_hardening.py
```

## Cambios de Trevor ya presentes en la base

Los 26 commits `95a730e..46b092a` afectan estas 41 rutas. No se deben volver a añadir como un parche separado; algunas también aparecen en el delta anterior por la fusión local.

```text
apps/captura_mobile/lib/data/services/video_capture_channel.dart
apps/captura_mobile/lib/domain/video_capture_controller.dart
apps/captura_mobile/lib/ui/spatial/video_capture_screen.dart
apps/captura_mobile/test/video_capture_controller_test.dart
apps/captura_mobile/test/video_capture_screen_test.dart
backend/app/modules/catalog/schemas.py
backend/tests/test_scene_opening_source.py
backend/tests/test_scene_scale.py
backend/tests/test_scene_scale_persistence.py
docs/api/f06-scene-contract.md
docs/api/f07-capture-package-v2-borrador.md
odd/tasks/f07-aberturas-y-regularizacion.md
odd/tasks/f07-banco-sintetico-y-cache.md
odd/tasks/f07-planos-proporcionales.md
panel/staff-shell/src/application/captureWarnings.test.ts
panel/staff-shell/src/application/captureWarnings.ts
panel/staff-shell/src/application/sceneContract.ts
panel/staff-shell/src/features/editor3d/CaptureDraftPanel.test.tsx
panel/staff-shell/src/features/editor3d/CaptureDraftPanel.tsx
panel/staff-shell/src/features/editor3d/SceneEditor.tsx
worker3d/README.md
worker3d/opening_placement.py
worker3d/openings.py
worker3d/reconstruct.py
worker3d/reconstruct_video.py
worker3d/reconstruction_worker.py
worker3d/stage_cache.py
worker3d/tests/bench_synthetic.py
worker3d/tests/test_bench_synthetic.py
worker3d/tests/test_opening_placement.py
worker3d/tests/test_openings.py
worker3d/tests/test_openings_cache.py
worker3d/tests/test_openings_scene.py
worker3d/tests/test_pilot_wiring.py
worker3d/tests/test_proportional_scale.py
worker3d/tests/test_reconstruct_video.py
worker3d/tests/test_reconstruct_video_cache.py
worker3d/tests/test_regularization.py
worker3d/tests/test_robust_fitting.py
worker3d/tests/test_shared_walls.py
worker3d/tests/test_stage_cache.py
```

## Exclusiones

No incluir `F07_*` de raíz, herramientas temporales, `node_modules/`, cachés, builds, plugins copiados, `local.properties`, archivos privados, credenciales, capturas, videos, ZIP/APK ni logs de la fuente. No se modifica `docs/diagramas/Diagrama1.eapx`. La evidencia detallada permanece local; [los resultados](verificacion.md) identifican qué se ejecutó.
