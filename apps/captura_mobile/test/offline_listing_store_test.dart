import 'dart:io';

import 'package:captura_mobile/data/services/offline_listing_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FileOfflineListingStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('offline_listings_test');
    store = FileOfflineListingStore(root: () async => root);
  });

  tearDown(() => root.deleteSync(recursive: true));

  const a = OfflineListing(listingId: 'l-1', label: 'A');
  const b = OfflineListing(listingId: 'l-2', label: 'B');

  test('keeps buckets, dedupes and replaces a bucket', () async {
    await store.write('staff-1', 'draft', [a]);
    await store.write('staff-1', 'pending', [a, b]);
    expect((await store.read('staff-1')).map((l) => l.listingId), [
      'l-1',
      'l-2',
    ]);

    await store.write('staff-1', 'pending', [b]);
    expect((await store.read('staff-1')).map((l) => l.listingId), [
      'l-1',
      'l-2',
    ]);
    await store.write('staff-1', 'draft', const []);
    expect((await store.read('staff-1')).map((l) => l.listingId), ['l-2']);
  });

  test('is per account and clear wipes every account', () async {
    await store.write('staff-1', 'draft', [a]);
    await store.write('staff-2', 'draft', [b]);
    expect((await store.read('staff-1')).single.listingId, 'l-1');
    expect((await store.read('staff-2')).single.listingId, 'l-2');

    await store.clear();

    expect(await store.read('staff-1'), isEmpty);
    expect(await store.read('staff-2'), isEmpty);
  });

  test('rejects unsafe owner ids and tolerates a corrupt file', () async {
    await expectLater(store.read('../x'), throwsArgumentError);
    await store.write('staff-1', 'draft', [a]);
    File('${root.path}/offline_listings/staff-1.json').writeAsStringSync('{');
    expect(await store.read('staff-1'), isEmpty);
  });
}
