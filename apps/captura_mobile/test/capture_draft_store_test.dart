import 'dart:convert';
import 'dart:io';

import 'package:captura_mobile/data/services/capture_draft_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FileCaptureDraftStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('capture-drafts-');
    store = FileCaptureDraftStore(root: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  const draft = <String, Object?>{
    'listingId': 'listing-1',
    'rooms': [
      {'id': 'r1', 'name': 'Estar'},
    ],
  };

  test(
    'keeps a draft across store instances, as after an app restart',
    () async {
      await store.write('agent-1', 'listing-1', draft);

      final reopened = FileCaptureDraftStore(root: () async => root);

      expect(await reopened.read('agent-1', 'listing-1'), draft);
    },
  );

  test('returns null for a listing without a local draft', () async {
    expect(await store.read('agent-1', 'listing-1'), isNull);
  });

  test('separates drafts per staff account', () async {
    await store.write('agent-1', 'listing-1', draft);

    expect(await store.read('agent-2', 'listing-1'), isNull);
    expect(await store.listingIds('agent-1'), ['listing-1']);
    expect(await store.listingIds('agent-2'), isEmpty);
  });

  test('replaces a draft without leaving temporary files behind', () async {
    await store.write('agent-1', 'listing-1', draft);
    await store.write('agent-1', 'listing-1', {...draft, 'rooms': <Object?>[]});

    expect(await store.read('agent-1', 'listing-1'), {
      ...draft,
      'rooms': <Object?>[],
    });
    final names = await Directory(
      '${root.path}/spatial_captures/agent-1',
    ).list().map((entry) => entry.uri.pathSegments.last).toList();
    expect(names, ['listing-1.json']);
  });

  test('reports the bytes used by one account', () async {
    await store.write('agent-1', 'listing-1', draft);
    await store.write('agent-1', 'listing-2', draft);

    expect(
      await store.sizeBytes('agent-1'),
      utf8.encode(jsonEncode(draft)).length * 2,
    );
    expect(await store.sizeBytes('agent-2'), 0);
  });

  test('deletes only the requested draft', () async {
    await store.write('agent-1', 'listing-1', draft);
    await store.write('agent-1', 'listing-2', draft);

    await store.delete('agent-1', 'listing-1');

    expect(await store.read('agent-1', 'listing-1'), isNull);
    expect(await store.read('agent-1', 'listing-2'), draft);
  });

  test('sets aside an unreadable draft instead of discarding it', () async {
    final dir = Directory('${root.path}/spatial_captures/agent-1');
    await dir.create(recursive: true);
    await File('${dir.path}/listing-1.json').writeAsString('{not json');

    expect(await store.read('agent-1', 'listing-1'), isNull);
    expect(await File('${dir.path}/listing-1.json.corrupt').exists(), isTrue);
  });

  test('rejects identifiers that could escape the drafts folder', () async {
    expect(
      () => store.write('agent-1', '../listing-1', draft),
      throwsArgumentError,
    );
    expect(() => store.read('..', 'listing-1'), throwsArgumentError);
  });
}
