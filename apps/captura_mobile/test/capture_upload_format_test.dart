import 'package:captura_mobile/domain/spatial/capture_upload.dart';
import 'package:captura_mobile/domain/spatial/capture_upload_controller.dart';
import 'package:captura_mobile/ui/spatial/capture_upload_format.dart';
import 'package:flutter_test/flutter_test.dart';

PendingCaptureUpload _upload({
  UploadStage stage = UploadStage.local,
  RemoteCaptureStatus? remote,
  String? reason,
  String? error,
  bool permanent = false,
  int size = 3 * 1024 * 1024,
}) => PendingCaptureUpload(
  captureId: 'cap-1',
  listingId: 'listing-1',
  zipPath: stage == UploadStage.completed ? null : '/x.zip',
  sizeBytes: size,
  keyframeCount: 10,
  createdAt: DateTime.utc(2026, 10, 21),
  stage: stage,
  remoteStatus: remote,
  failureReason: reason,
  lastError: error,
  permanent: permanent,
);

CaptureUploadItem _item(
  PendingCaptureUpload upload, {
  UploadPhase phase = UploadPhase.idle,
  double? progress,
}) => CaptureUploadItem(upload: upload, phase: phase, progress: progress);

void main() {
  test('formats sizes in megabytes with a decimal comma', () {
    expect(megabytes(3 * 1024 * 1024), '3,0 MB');
    expect(megabytes(1536 * 1024), '1,5 MB');
    expect(megabytes(10 * 1024), '0,0 MB');
  });

  group('while the phone is sending', () {
    test('registering', () {
      final text = captureUploadText(_item(_upload(), phase: UploadPhase.registering));
      expect(text.title, 'Preparando la subida…');
    });

    test('uploading shows the percentage and the size', () {
      final text = captureUploadText(
        _item(_upload(stage: UploadStage.registered), phase: UploadPhase.uploading, progress: 0.425),
      );
      expect(text.title, 'Subiendo el recorrido…');
      expect(text.detail, '42 % de 3,0 MB');
      expect(text.progress, 0.425);
    });

    test('finishing and checking', () {
      expect(
        captureUploadText(_item(_upload(stage: UploadStage.uploaded), phase: UploadPhase.finishing)).title,
        'Confirmando la subida…',
      );
      expect(
        captureUploadText(_item(_upload(stage: UploadStage.completed, remote: RemoteCaptureStatus.queued), phase: UploadPhase.checking)).title,
        'Consultando el estado…',
      );
    });
  });

  group('before the server has it', () {
    test('waits on the phone and says it retries by itself', () {
      final text = captureUploadText(_item(_upload()));
      expect(text.title, 'Recorrido guardado en el teléfono');
      expect(text.detail, contains('Se sube cuando haya conexión (3,0 MB)'));
      expect(text.canRetry, isTrue);
    });

    test('shows the last problem', () {
      final text = captureUploadText(_item(_upload(stage: UploadStage.registered, error: 'Sin conexión.')));
      expect(text.detail, contains('Sin conexión.'));
      expect(text.canRetry, isTrue);
    });

    test('a permanent rejection cannot be retried, only removed', () {
      final text = captureUploadText(_item(_upload(permanent: true, error: 'El paquete es demasiado grande.')));
      expect(text.title, 'No se pudo subir el recorrido');
      expect(text.detail, contains('demasiado grande'));
      expect(text.canRetry, isFalse);
      expect(text.canDismiss, isTrue);
    });
  });

  group('reconstruction status', () {
    PendingCaptureUpload sent(RemoteCaptureStatus? status, {String? reason, String? error}) =>
        _upload(stage: UploadStage.completed, remote: status, reason: reason, error: error);

    test('queued', () {
      final text = captureUploadText(_item(sent(RemoteCaptureStatus.queued)));
      expect(text.title, 'En la cola de reconstrucción');
      expect(text.canRefresh, isTrue);
      expect(text.canDismiss, isFalse);
    });

    test('processing', () {
      final text = captureUploadText(_item(sent(RemoteCaptureStatus.processing)));
      expect(text.title, 'Reconstruyendo el ambiente');
      expect(text.canRefresh, isTrue);
    });

    test('completed points to the panel and promises no 3D on the phone', () {
      final text = captureUploadText(_item(sent(RemoteCaptureStatus.completed)));
      expect(text.title, 'Borrador listo');
      expect(text.detail, contains('panel'));
      expect(text.canRefresh, isFalse);
      expect(text.canDismiss, isTrue);
    });

    test('failed shows the server reason', () {
      final text = captureUploadText(_item(sent(RemoteCaptureStatus.failed, reason: 'Sin piso detectado')));
      expect(text.title, 'La reconstrucción falló');
      expect(text.detail, contains('Sin piso detectado'));
      expect(text.detail, contains('Volvé a capturar'));
      expect(text.canDismiss, isTrue);
    });

    test('failed without a reason says so instead of inventing one', () {
      final text = captureUploadText(_item(sent(RemoteCaptureStatus.failed)));
      expect(text.detail, contains('no indicó el motivo'));
    });

    test('accepted', () {
      expect(captureUploadText(_item(sent(RemoteCaptureStatus.accepted))).title, 'Borrador aceptado');
    });

    test('sent but not yet checked', () {
      final text = captureUploadText(_item(sent(null)));
      expect(text.title, 'Recorrido enviado');
      expect(text.canRefresh, isTrue);
    });

    test('a failed status check adds its problem to the last known state', () {
      final text = captureUploadText(_item(sent(RemoteCaptureStatus.processing, error: 'Sin conexión.')));
      expect(text.title, 'Reconstruyendo el ambiente');
      expect(text.detail, contains('Sin conexión.'));
    });
  });
}
