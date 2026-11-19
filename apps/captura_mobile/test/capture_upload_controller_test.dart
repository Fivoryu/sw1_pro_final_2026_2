import 'dart:async';

import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_capture_api.dart';
import 'package:captura_mobile/domain/spatial/capture_upload.dart';
import 'package:captura_mobile/domain/spatial/capture_upload_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_capture_backend.dart';
import 'support/fake_staff_backend.dart';
import 'support/in_memory_upload_support.dart';

Future<StaffSessionController> signedIn() async {
  final session = StaffSessionController(
    api: StaffAuthApi(
      baseUrl: 'https://api.example.test',
      client: FakeStaffBackend().client,
    ),
    credentialStore: InMemoryStaffCredentialStore(),
  );
  await session.restore();
  await session.startLogin(email: 'agent@example.test', password: 'x');
  await session.submitCode('123456');
  return session;
}

const _zipPath = '/files/capture_packages/cap-1.zip';
final _zipBytes = List<int>.generate(100, (i) => i);

class _PausedPackageFiles extends FakePackageFiles {
  _PausedPackageFiles(super.files);

  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Stream<List<int>> open(String path) async* {
    if (path == _zipPath && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    yield* super.open(path);
  }
}

CapturePackageInfo _package({String id = 'cap-1', String path = _zipPath}) =>
    CapturePackageInfo(
      zipPath: path,
      captureId: id,
      sizeBytes: _zipBytes.length,
      keyframeCount: 12,
      droppedKeyframes: 0,
      failedKeyframes: 0,
      rooms: const [CapturePackageRoom(id: 'room-1', name: 'Estar')],
    );

typedef _Harness = ({
  CaptureUploadController controller,
  FakeCaptureBackend backend,
  InMemoryPendingUploadStore store,
  FakePackageFiles files,
  StaffSessionController session,
});

Future<_Harness> _build({
  FakeCaptureBackend? backend,
  InMemoryPendingUploadStore? store,
  FakePackageFiles? files,
  StaffSessionController? session,
  String listingId = 'listing-1',
}) async {
  final server = backend ?? FakeCaptureBackend();
  final pending = store ?? InMemoryPendingUploadStore();
  final local = files ?? FakePackageFiles({_zipPath: _zipBytes});
  final staff = session ?? await signedIn();
  final controller = CaptureUploadController(
    listingId: listingId,
    session: staff,
    api: StaffCaptureApi(
      baseUrl: 'https://api.example.test',
      client: server.client,
    ),
    store: pending,
    files: local,
    now: () => DateTime.utc(2026, 10, 21, 12),
  );
  await controller.load();
  return (
    controller: controller,
    backend: server,
    store: pending,
    files: local,
    session: staff,
  );
}

void main() {
  test('enqueue publishes the attempt before idle is observed', () async {
    final files = _PausedPackageFiles({_zipPath: _zipBytes});
    final h = await _build(files: files);
    addTearDown(() {
      if (!files.release.isCompleted) files.release.complete();
      return h.controller.idle;
    });

    expect(await h.controller.enqueue(_package()), isTrue);
    expect(h.controller.busy, isTrue);
    final attempt = h.controller.idle;
    var finished = false;
    unawaited(
      attempt.then<void>((_) {
        finished = true;
      }),
    );
    await files.entered.future;
    expect(finished, isFalse);
    expect(h.files.deleted, isEmpty);

    files.release.complete();
    await attempt;

    expect(h.controller.items.single.upload.stage, UploadStage.completed);
    expect(h.backend.putCalls, 1);
    expect(h.backend.completeCalls, 1);
    expect(h.controller.busy, isFalse);
  });

  test('idle includes a capture enqueued during an active upload', () async {
    const secondPath = '/files/capture_packages/cap-2.zip';
    final files = _PausedPackageFiles({
      _zipPath: _zipBytes,
      secondPath: _zipBytes,
    });
    final h = await _build(files: files);
    addTearDown(() {
      if (!files.release.isCompleted) files.release.complete();
      return h.controller.idle;
    });

    await h.controller.enqueue(_package());
    await files.entered.future;
    expect(
      await h.controller.enqueue(_package(id: 'cap-2', path: secondPath)),
      isTrue,
    );
    final allAttempts = h.controller.idle;
    expect(h.controller.busy, isTrue);
    expect(h.files.deleted, isEmpty);

    files.release.complete();
    await allAttempts;

    expect(h.controller.items, hasLength(2));
    expect(h.controller.items.every((item) => item.upload.isSent), isTrue);
    expect(
      (await h.store.list('staff-1')).every((upload) => upload.isSent),
      isTrue,
    );
    expect(h.backend.registerCalls, 2);
    expect(h.backend.putCalls, 2);
    expect(h.backend.completeCalls, 2);
    expect(h.backend.captures, hasLength(2));
    expect(h.controller.busy, isFalse);
  });

  test('another controller waits and reloads without a second PUT', () async {
    final files = _PausedPackageFiles({_zipPath: _zipBytes});
    final first = await _build(files: files);
    CaptureUploadController? secondController;
    addTearDown(() async {
      if (!files.release.isCompleted) files.release.complete();
      await first.controller.idle;
      await secondController?.idle;
    });

    await first.controller.enqueue(_package());
    await files.entered.future;
    final second = await _build(
      files: files,
      backend: first.backend,
      store: first.store,
      session: first.session,
    );
    secondController = second.controller;
    await second.controller.enqueue(_package());
    final allAttempts = second.controller.idle;
    expect(second.controller.busy, isTrue);
    expect(first.backend.registerCalls, 1);

    files.release.complete();
    await allAttempts;

    expect(second.controller.items.single.upload.stage, UploadStage.completed);
    expect(first.backend.registerCalls, 1);
    expect(first.backend.putCalls, 1);
    expect(first.backend.completeCalls, 1);
    expect(first.backend.captures, hasLength(1));
  });

  test(
    'unverified HTTP 202 retains the local ZIP and the uploaded stage',
    () async {
      final backend = FakeCaptureBackend()..verifyCompletion = false;
      final h = await _build(backend: backend);
      await h.controller.enqueue(_package());
      await h.controller.idle;
      expect(h.controller.items.single.upload.stage, UploadStage.uploaded);
      expect(h.files.files.containsKey(_zipPath), isTrue);
      expect(h.files.deleted, isEmpty);
    },
  );
  test('a missing remote object is repaired from the retained ZIP', () async {
    final backend = FakeCaptureBackend()..loseUploadsBeforeComplete = 1;
    final h = await _build(backend: backend);
    await h.controller.enqueue(_package());
    await h.controller.idle;
    expect(h.controller.items.single.upload.stage, UploadStage.completed);
    expect(backend.putCalls, 2);
    expect(backend.captures, hasLength(1));
  });

  test(
    'registers, uploads and completes, deleting the ZIP only at the end',
    () async {
      final h = await _build();

      await h.controller.enqueue(_package());
      await h.controller.idle;

      final item = h.controller.items.single;
      expect(item.upload.stage, UploadStage.completed);
      expect(item.upload.remoteStatus, RemoteCaptureStatus.queued);
      expect(item.upload.zipPath, isNull);
      expect(h.backend.captures['cap-1']!.uploaded, _zipBytes);
      expect(h.backend.captures['cap-1']!.status, 'queued');
      expect(h.files.deleted, [_zipPath]);
      // The order on the wire is register, PUT, complete.
      expect(
        [for (final r in h.backend.requests) '${r.method} ${r.url.path}'],
        [
          'POST /api/v1/staff/agencies/agency-1/listings/listing-1/captures',
          'PUT /upload/cap-1',
          'POST /api/v1/staff/agencies/agency-1/listings/listing-1/captures/cap-1/complete',
        ],
      );
      final stored = await h.store.list('staff-1');
      expect(stored.single.stage, UploadStage.completed);
    },
  );

  test('reports progress while uploading', () async {
    final h = await _build();
    final seen = <double?>[];
    h.controller.addListener(() {
      final item = h.controller.items.firstOrNull;
      if (item != null && item.phase == UploadPhase.uploading) {
        seen.add(item.progress);
      }
    });

    await h.controller.enqueue(_package());
    await h.controller.idle;

    expect(seen, isNotEmpty);
    expect(seen.every((p) => p != null && p >= 0 && p <= 1), isTrue);
    expect(seen.last, 1.0);
  });

  test(
    'a lost connection during the upload keeps the ZIP and resumes without registering again',
    () async {
      final h = await _build();
      h.backend.failPuts = 1;

      await h.controller.enqueue(_package());
      await h.controller.idle;

      var item = h.controller.items.single;
      expect(item.upload.stage, UploadStage.registered);
      expect(item.upload.zipPath, _zipPath);
      expect(item.upload.lastError, contains('Sin conexión'));
      expect(item.upload.lastError, contains('almacenamiento'));
      expect(item.upload.permanent, isFalse);
      expect(h.files.deleted, isEmpty);

      await h.controller.retry();

      item = h.controller.items.single;
      expect(item.upload.stage, UploadStage.completed);
      expect(item.upload.lastError, isNull);
      expect(h.backend.registerCalls, 1);
      expect(h.backend.putCalls, 2);
      expect(h.backend.captures, hasLength(1));
      expect(h.files.deleted, [_zipPath]);
    },
  );

  test(
    'offline at the start registers once when the connection returns',
    () async {
      final h = await _build();
      h.backend.offline = true;

      await h.controller.enqueue(_package());
      await h.controller.idle;
      expect(h.controller.items.single.upload.stage, UploadStage.local);
      expect(h.backend.captures, isEmpty);

      h.backend.offline = false;
      await h.controller.retry();

      expect(h.controller.items.single.upload.stage, UploadStage.completed);
      expect(h.backend.captures, hasLength(1));
      expect(h.backend.registerCalls, 1);
    },
  );

  test('a failed complete keeps the ZIP and does not upload twice', () async {
    final h = await _build();
    h.backend.failCompletes = 1;

    await h.controller.enqueue(_package());
    await h.controller.idle;

    var item = h.controller.items.single;
    expect(item.upload.stage, UploadStage.uploaded);
    expect(item.upload.zipPath, _zipPath);
    expect(h.files.deleted, isEmpty);

    await h.controller.retry();

    item = h.controller.items.single;
    expect(item.upload.stage, UploadStage.completed);
    expect(h.backend.putCalls, 1);
    expect(h.backend.completeCalls, 2);
    expect(h.files.deleted, [_zipPath]);
  });

  test('an expired signed URL registers again for a fresh one', () async {
    final h = await _build();
    h.backend.expirePuts = 1;

    await h.controller.enqueue(_package());
    await h.controller.idle;

    expect(h.controller.items.single.upload.stage, UploadStage.completed);
    expect(h.backend.registerCalls, 2);
    expect(h.backend.captures, hasLength(1));
    expect(h.backend.captures['cap-1']!.uploaded, _zipBytes);
  });

  test('resumes after an app restart from the last saved stage', () async {
    final first = await _build();
    first.backend.failPuts = 1;
    await first.controller.enqueue(_package());
    await first.controller.idle;
    expect(first.controller.items.single.upload.stage, UploadStage.registered);

    // New controller over the same store, files and server: a restart.
    final second = await _build(
      backend: first.backend,
      store: first.store,
      files: first.files,
      session: first.session,
    );
    expect(second.controller.items.single.upload.stage, UploadStage.registered);
    await second.controller.retry();

    expect(second.controller.items.single.upload.stage, UploadStage.completed);
    expect(first.backend.registerCalls, 1);
    expect(first.backend.captures, hasLength(1));
  });

  test('enqueueing the same capture twice does not duplicate it', () async {
    final h = await _build();

    await h.controller.enqueue(_package());
    await h.controller.enqueue(_package());
    await h.controller.idle;

    expect(h.controller.items, hasLength(1));
    expect(h.backend.registerCalls, 1);
    expect(h.backend.putCalls, 1);
  });

  test('two retries at once run the upload only once', () async {
    final h = await _build();
    h.backend.offline = true;
    await h.controller.enqueue(_package());
    await h.controller.idle;
    h.backend.offline = false;

    await Future.wait([h.controller.retry(), h.controller.retry()]);

    expect(h.backend.registerCalls, 1);
    expect(h.backend.putCalls, 1);
    expect(h.backend.completeCalls, 1);
  });

  test(
    'a rejection retrying cannot fix is permanent and is not retried',
    () async {
      final h = await _build();
      h.backend.rejectRegistration = true;

      await h.controller.enqueue(_package());
      await h.controller.idle;
      await h.controller.retry();

      final item = h.controller.items.single;
      expect(item.upload.permanent, isTrue);
      expect(item.upload.lastError, isNotNull);
      expect(h.backend.registerCalls, 1);
      expect(h.files.deleted, isEmpty);

      await h.controller.dismiss('cap-1');

      expect(h.controller.items, isEmpty);
      expect(await h.store.list('staff-1'), isEmpty);
      expect(h.files.deleted, [_zipPath]);
    },
  );

  test('a ZIP that is gone from the phone is a permanent failure', () async {
    final h = await _build(files: FakePackageFiles({}));

    await h.controller.enqueue(_package());
    await h.controller.idle;

    final item = h.controller.items.single;
    expect(item.upload.permanent, isTrue);
    expect(item.upload.lastError, contains('ya no está'));
    expect(h.backend.requests, isEmpty);
  });

  test(
    'without a session nothing is sent and the agent is told to sign in',
    () async {
      final session = StaffSessionController(
        api: StaffAuthApi(
          baseUrl: 'https://api.example.test',
          client: FakeStaffBackend().client,
        ),
        credentialStore: InMemoryStaffCredentialStore(),
      );
      final h = await _build(session: session);

      await h.controller.enqueue(_package());
      await h.controller.idle;

      expect(h.backend.requests, isEmpty);
      expect(h.controller.message, contains('sesión'));
    },
  );

  group('status', () {
    test('follows the reconstruction until it completes', () async {
      final h = await _build();
      await h.controller.enqueue(_package());
      await h.controller.idle;
      h.backend.statusScript
        ..add(('processing', null))
        ..add(('completed', null));

      await h.controller.retry();
      expect(
        h.controller.items.single.upload.remoteStatus,
        RemoteCaptureStatus.processing,
      );
      expect(h.controller.items.single.upload.isFinished, isFalse);

      await h.controller.retry();
      expect(
        h.controller.items.single.upload.remoteStatus,
        RemoteCaptureStatus.completed,
      );
      expect(h.controller.items.single.upload.isFinished, isTrue);
    });

    test('keeps the failure reason from the server', () async {
      final h = await _build();
      await h.controller.enqueue(_package());
      await h.controller.idle;
      h.backend.statusScript.add(('failed', 'Sin piso detectado'));

      await h.controller.retry();

      final upload = h.controller.items.single.upload;
      expect(upload.remoteStatus, RemoteCaptureStatus.failed);
      expect(upload.failureReason, 'Sin piso detectado');
      expect(upload.isFinished, isTrue);
    });

    test('does not poll once the server reached a final state', () async {
      final h = await _build();
      await h.controller.enqueue(_package());
      await h.controller.idle;
      h.backend.statusScript.add(('accepted', null));
      await h.controller.retry();
      final before = h.backend.requests.length;

      await h.controller.retry();

      expect(h.backend.requests.length, before);
    });

    test('a status check that fails keeps the last known state', () async {
      final h = await _build();
      await h.controller.enqueue(_package());
      await h.controller.idle;
      h.backend.offline = true;

      await h.controller.retry();

      final upload = h.controller.items.single.upload;
      expect(upload.remoteStatus, RemoteCaptureStatus.queued);
      expect(upload.lastError, contains('Sin conexión'));
    });
  });

  test('only shows the uploads of this listing', () async {
    final store = InMemoryPendingUploadStore();
    await store.save(
      'staff-1',
      PendingCaptureUpload(
        captureId: 'other',
        listingId: 'listing-2',
        zipPath: '/x.zip',
        sizeBytes: 1,
        keyframeCount: 1,
        createdAt: DateTime.utc(2026, 10, 21),
      ),
    );
    final h = await _build(store: store);

    expect(h.controller.items, isEmpty);
  });
}
