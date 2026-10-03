import 'package:captura_mobile/data/models/staff_listing.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_listings_api.dart';
import 'package:captura_mobile/domain/listing_drafts_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_listings_backend.dart';
import 'support/fake_staff_backend.dart';

const _input = ListingDraftInput(
  operation: ListingOperation.sale,
  basePrice: '350000000.00',
  city: 'Medellín',
  zone: 'El Poblado',
  bedrooms: 3,
  bathrooms: 2,
  description: null,
  exactAddress: 'Calle privada 123',
);

Future<({ListingDraftsController controller, FakeListingsBackend backend})>
_build({bool signedIn = true}) async {
  final session = StaffSessionController(
    api: StaffAuthApi(
      baseUrl: 'https://api.example.test',
      client: FakeStaffBackend().client,
    ),
    credentialStore: InMemoryStaffCredentialStore(),
  );
  await session.restore();
  if (signedIn) {
    await session.startLogin(email: 'agent@example.test', password: 'x');
    await session.submitCode('123456');
  }
  final backend = FakeListingsBackend();
  return (
    controller: ListingDraftsController(
      api: StaffListingsApi(
        baseUrl: 'https://api.example.test',
        client: backend.client,
      ),
      session: session,
    ),
    backend: backend,
  );
}

void main() {
  group('load', () {
    test('loads the drafts of the session agency by default', () async {
      final harness = await _build();
      harness.backend.seed(id: 'draft-1');
      harness.backend.seed(id: 'pending-1', status: 'pending');

      await harness.controller.load();

      expect(harness.controller.tab, ListingStatus.draft);
      expect(harness.controller.loadState, ListingsLoadState.ready);
      expect(harness.controller.listings.map((l) => l.listingId), ['draft-1']);
      expect(
        harness.backend.requests.single.url.path,
        '/api/v1/staff/agencies/agency-1/listings',
      );
    });

    test('switches tabs and loads that status', () async {
      final harness = await _build();
      harness.backend.seed(id: 'draft-1');
      harness.backend.seed(id: 'pending-1', status: 'pending');

      await harness.controller.load(ListingStatus.pending);

      expect(harness.controller.tab, ListingStatus.pending);
      expect(harness.controller.listings.single.listingId, 'pending-1');
    });

    test('reports a network failure with a retryable state', () async {
      final harness = await _build();
      harness.backend.offline = true;

      await harness.controller.load();

      expect(harness.controller.loadState, ListingsLoadState.failed);
      expect(harness.controller.message, contains('conexión'));
      expect(harness.controller.listings, isEmpty);
    });

    test('asks to sign in again when the API rejects the session', () async {
      final harness = await _build();
      harness.backend.failWithStatus = 401;

      await harness.controller.load();

      expect(harness.controller.loadState, ListingsLoadState.failed);
      expect(harness.controller.message, contains('sesión'));
    });

    test('does not call the API without a session agency', () async {
      final harness = await _build(signedIn: false);

      await harness.controller.load();

      expect(harness.controller.loadState, ListingsLoadState.failed);
      expect(harness.backend.requests, isEmpty);
    });
  });

  group('save and submit', () {
    test('creates a draft and then edits the same listing', () async {
      final harness = await _build();

      final created = await harness.controller.save(input: _input);
      final edited = await harness.controller.save(
        listingId: created!.listingId,
        input: const ListingDraftInput(
          operation: ListingOperation.sale,
          basePrice: '360000000.00',
          city: 'Medellín',
          zone: 'Laureles',
          bedrooms: 3,
          bathrooms: 2,
          description: null,
          exactAddress: null,
        ),
      );

      expect(created.status, ListingStatus.draft);
      expect(edited!.listingId, created.listingId);
      expect(edited.zone, 'Laureles');
      expect(harness.backend.requests.map((r) => r.method), ['POST', 'PUT']);
    });

    test('submits a draft for review', () async {
      final harness = await _build();
      harness.backend.seed(id: 'draft-1');

      final submitted = await harness.controller.submit('draft-1');

      expect(submitted, isTrue);
      expect(
        harness.backend.listings['draft-1']!['approval_status'],
        'pending',
      );
      expect(harness.controller.message, isNull);
    });

    test('explains a state conflict when submitting', () async {
      final harness = await _build();
      harness.backend.seed(id: 'pending-1', status: 'pending');

      final submitted = await harness.controller.submit('pending-1');

      expect(submitted, isFalse);
      expect(harness.controller.message, contains('cambió de estado'));
    });

    test('keeps the failure message when saving fails', () async {
      final harness = await _build();
      harness.backend.offline = true;

      final saved = await harness.controller.save(input: _input);

      expect(saved, isNull);
      expect(harness.controller.message, contains('conexión'));
    });
  });

  group('rejection reason', () {
    test('returns the observation of the latest rejection', () async {
      final harness = await _build();
      harness.backend.seed(
        id: 'rejected-1',
        status: 'rejected',
        rejectionReason: 'Faltan datos de la zona',
      );

      final reason = await harness.controller.latestRejectionReason(
        'rejected-1',
      );

      expect(reason, 'Faltan datos de la zona');
    });

    test('returns null when the listing was never rejected', () async {
      final harness = await _build();
      harness.backend.seed(id: 'draft-1');

      expect(await harness.controller.latestRejectionReason('draft-1'), isNull);
    });
  });
}
