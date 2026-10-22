import 'dart:convert';
import 'dart:io';

import 'package:captura_mobile/data/services/capture_draft_store.dart';
import 'package:captura_mobile/domain/spatial/capture_upload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FilePendingUploadStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pending-uploads-');
    store = FilePendingUploadStore(root: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  PendingCaptureUpload upload(String id, {int minute = 0}) =>
      PendingCaptureUpload(
        captureId: id,
        listingId: 'listing-1',
        zipPath: '/files/capture_packages/$id.zip',
        sizeBytes: 2048,
        keyframeCount: 12,
        createdAt: DateTime.utc(2026, 10, 21, 12, minute),
      );

  test('keeps records across store instances, as after a restart', () async {
    await store.save(
      'agent-1',
      upload('cap-1').copyWith(
        stage: UploadStage.registered,
        uploadUrl: 'https://storage.example.test/u',
      ),
    );

    final reopened = FilePendingUploadStore(root: () async => root);
    final records = await reopened.list('agent-1');

    expect(records, hasLength(1));
    expect(records.single.captureId, 'cap-1');
    expect(records.single.stage, UploadStage.registered);
    expect(records.single.uploadUrl, 'https://storage.example.test/u');
    expect(records.single.zipPath, '/files/capture_packages/cap-1.zip');
    expect(records.single.createdAt, DateTime.utc(2026, 10, 21, 12));
  });

  test(
    'saving the same capture again replaces it instead of duplicating',
    () async {
      await store.save('agent-1', upload('cap-1'));
      await store.save(
        'agent-1',
        upload('cap-1').copyWith(stage: UploadStage.uploaded),
      );

      final records = await store.list('agent-1');

      expect(records, hasLength(1));
      expect(records.single.stage, UploadStage.uploaded);
    },
  );

  test('lists oldest first and only the owner records', () async {
    await store.save('agent-1', upload('cap-2', minute: 5));
    await store.save('agent-1', upload('cap-1', minute: 1));
    await store.save('agent-2', upload('cap-3'));

    expect(
      [for (final r in await store.list('agent-1')) r.captureId],
      ['cap-1', 'cap-2'],
    );
    expect(
      [for (final r in await store.list('agent-2')) r.captureId],
      ['cap-3'],
    );
  });

  test('delete removes only that record', () async {
    await store.save('agent-1', upload('cap-1'));
    await store.save('agent-1', upload('cap-2', minute: 1));

    await store.delete('agent-1', 'cap-1');

    expect(
      [for (final r in await store.list('agent-1')) r.captureId],
      ['cap-2'],
    );
  });

  test('sets aside an unreadable record instead of discarding it', () async {
    final dir = Directory('${root.path}/capture_uploads/agent-1');
    await dir.create(recursive: true);
    await File('${dir.path}/cap-1.json').writeAsString('{not json');
    await File(
      '${dir.path}/cap-2.json',
    ).writeAsString(jsonEncode({'captureId': 'cap-2'}));

    expect(await store.list('agent-1'), isEmpty);
    expect(await File('${dir.path}/cap-1.json.corrupt').exists(), isTrue);
    expect(await File('${dir.path}/cap-2.json.corrupt').exists(), isTrue);
  });

  test('rejects identifiers that are not plain', () async {
    expect(() => store.save('../x', upload('cap-1')), throwsArgumentError);
    expect(() => store.delete('agent-1', '../cap'), throwsArgumentError);
  });

  group('PendingCaptureUpload.fromJson', () {
    Map<String, Object?> valid() => upload('cap-1').toJson();

    test('round-trips every field', () {
      final original = upload('cap-1').copyWith(
        stage: UploadStage.completed,
        remoteStatus: RemoteCaptureStatus.failed,
        failureReason: 'Sin piso detectado',
        lastError: 'x',
        permanent: true,
        clearZipPath: true,
      );

      final restored = PendingCaptureUpload.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.zipPath, isNull);
      expect(restored.isFinished, isTrue);
    });

    for (final key in [
      'captureId',
      'listingId',
      'sizeBytes',
      'createdAt',
      'stage',
    ]) {
      test('rejects a record without $key', () {
        expect(
          () => PendingCaptureUpload.fromJson({...valid()}..remove(key)),
          throwsFormatException,
        );
      });
    }

    test('rejects a wrong type, an unknown stage and a bad date', () {
      expect(
        () => PendingCaptureUpload.fromJson({...valid(), 'sizeBytes': 'big'}),
        throwsFormatException,
      );
      expect(
        () =>
            PendingCaptureUpload.fromJson({...valid(), 'stage': 'teleported'}),
        throwsFormatException,
      );
      expect(
        () => PendingCaptureUpload.fromJson({
          ...valid(),
          'createdAt': 'yesterday',
        }),
        throwsFormatException,
      );
    });
  });

  group('IoCapturePackageFiles', () {
    test('streams, reports and deletes a real file', () async {
      const files = IoCapturePackageFiles();
      final zip = File('${root.path}/cap-1.zip');
      await zip.writeAsBytes([1, 2, 3, 4, 5]);

      expect(await files.exists(zip.path), isTrue);
      final bytes = [
        for (final chunk in await files.open(zip.path).toList()) ...chunk,
      ];
      expect(bytes, [1, 2, 3, 4, 5]);

      await files.delete(zip.path);
      expect(await files.exists(zip.path), isFalse);
      // Deleting something already gone is not an error.
      await files.delete(zip.path);
    });
  });
}
