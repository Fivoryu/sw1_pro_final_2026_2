import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:captura_mobile/data/services/guided_capture_store.dart';
import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_listing_photos_api.dart';
import 'package:captura_mobile/data/services/staff_listings_api.dart';
import 'package:captura_mobile/domain/guided_capture/capture_checklist.dart';
import 'package:captura_mobile/domain/guided_capture/photo_quality.dart';
import 'package:captura_mobile/domain/listing_drafts_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:captura_mobile/ui/listings/listings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_listings_backend.dart';
import 'support/fake_photo_source.dart';
import 'support/fake_staff_backend.dart';
import 'support/fake_tile_provider.dart';

const _good = PhotoMeasurements(
  width: 3000,
  height: 4000,
  brightness: 120,
  sharpness: 300,
);

const _dark = PhotoMeasurements(
  width: 3000,
  height: 4000,
  brightness: 20,
  sharpness: 300,
);

CaptureChecklist _allChecked(CaptureChecklist checklist) => CaptureChecklist([
  for (final room in checklist.rooms)
    room.copyWith(checks: RoomCheck.values.toSet()),
]);

void main() {
  group('CaptureChecklist', () {
    test('derives rooms from the card in the suggested order', () {
      final checklist = CaptureChecklist.derive(bedrooms: 2, bathrooms: 1);

      expect([for (final room in checklist.rooms) room.label], [
        'Living',
        'Cocina',
        'Dormitorio 1',
        'Dormitorio 2',
        'Baño',
      ]);
    });

    test('re-deriving keeps room state and extra rooms, and drops rooms '
        'beyond the new counts', () {
      final first = CaptureChecklist.derive(bedrooms: 2, bathrooms: 1);
      final living = first.rooms.first.copyWith(
        checks: {RoomCheck.lighting},
        photoIds: ['p1'],
      );
      final withExtra = CaptureChecklist([
        ...first.replace(living).rooms,
        const CaptureRoom(id: 'extra-1', kind: RoomKind.extra, label: 'Patio'),
      ]);

      final second = CaptureChecklist.derive(
        bedrooms: 1,
        bathrooms: 1,
        previous: withExtra,
      );

      expect([for (final room in second.rooms) room.id], [
        'living',
        'kitchen',
        'bedroom-1',
        'bathroom-1',
        'extra-1',
      ]);
      expect(second.rooms.first.photoIds, ['p1']);
      expect(second.rooms.first.checks, {RoomCheck.lighting});
      expect(second.rooms[2].label, 'Dormitorio');
    });

    test('problems list each room without a live photo or with checks '
        'missing, and skipped rooms do not count', () {
      final base = _allChecked(
        CaptureChecklist.derive(bedrooms: 0, bathrooms: 0),
      );
      final living = base.rooms.first.copyWith(photoIds: ['p1', 'gone']);
      final kitchen = base.rooms[1].copyWith(
        skippedReason: () => 'Monoambiente',
      );
      final checklist = base.replace(living).replace(kitchen);

      expect(checklist.problems({'p1'}), isEmpty);
      expect(checklist.problems({'other'}), [
        'Living: falta una foto que pase la validación de calidad.',
      ]);
      expect(checklist.progress({'p1'}), (finished: 2, total: 2));

      final unchecked = checklist.replace(living.copyWith(checks: {}));
      expect(unchecked.problems({'p1'}).single, startsWith('Living: falta confirmar'));
    });

    test('at least one room must apply', () {
      final checklist = CaptureChecklist([
        const CaptureRoom(
          id: 'living',
          kind: RoomKind.living,
          label: 'Living',
          skippedReason: 'No',
        ),
      ]);
      expect(checklist.problems(const {}), ['Fotografiá al menos un ambiente.']);
    });

    test('round-trips through JSON', () {
      final checklist = CaptureChecklist.derive(bedrooms: 1, bathrooms: 1)
          .replace(
            const CaptureRoom(
              id: 'kitchen',
              kind: RoomKind.kitchen,
              label: 'Cocina',
              checks: {RoomCheck.privacy},
              photoIds: ['p9'],
              skippedReason: null,
            ),
          );
      final again = CaptureChecklist.fromJson(checklist.toJson());
      expect(again.toJson(), checklist.toJson());
      expect(() => CaptureChecklist.fromJson({'version': 2}), throwsFormatException);
    });
  });

  group('photo quality', () {
    test('a good photo passes', () {
      expect(assessPhoto(_good), isEmpty);
    });

    test('each rule explains its failure', () {
      expect(
        assessPhoto(
          const PhotoMeasurements(
            width: 640,
            height: 480,
            brightness: 240,
            sharpness: 3,
          ),
        ),
        [
          contains('muy chica (640×480 px)'),
          contains('sobreexpuesta'),
          contains('movida o desenfocada'),
        ],
      );
      expect(assessPhoto(_dark).single, contains('muy oscura'));
    });

    test('measureLuma tells a flat image from a detailed one', () {
      final flat = measureLuma(8, 8, Uint8List(64)..fillRange(0, 64, 100));
      final checker = Uint8List.fromList([
        for (var y = 0; y < 8; y++)
          for (var x = 0; x < 8; x++) (x + y).isEven ? 0 : 255,
      ]);
      final detailed = measureLuma(8, 8, checker);

      expect(flat.brightness, 100);
      expect(flat.sharpness, 0);
      expect(detailed.brightness, closeTo(127.5, 0.01));
      expect(detailed.sharpness, greaterThan(1000));
    });

    testWidgets('analyzePhotoBytes decodes a real PNG and rejects garbage', (
      tester,
    ) async {
      final png = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawRect(
          const ui.Rect.fromLTWH(0, 0, 40, 30),
          ui.Paint()..color = const ui.Color(0xFF808080),
        );
        final image = await recorder.endRecording().toImage(40, 30);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });

      final measured = await tester.runAsync(() => analyzePhotoBytes(png!));
      expect(measured!.width, 40);
      expect(measured.height, 30);
      expect(measured.brightness, closeTo(128, 2));
      expect(measured.sharpness, closeTo(0, 0.01));

      Object? failure;
      await tester.runAsync(() async {
        try {
          await analyzePhotoBytes(FakePhotoSource.jpeg().bytes);
        } catch (error) {
          failure = error;
        }
      });
      expect(failure, isA<PhotoAnalysisFailure>());
    });
  });

  group('guided capture in the listing editor', () {
    Future<
      ({
        FakeListingsBackend backend,
        InMemoryGuidedCaptureStore store,
        FakePhotoSource source,
      })
    >
    pumpEditor(
      WidgetTester tester, {
      PhotoMeasurements measured = _good,
      void Function(InMemoryGuidedCaptureStore store)? seedStore,
    }) async {
      // A tall surface keeps every room of the guide on screen.
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      final backend = FakeListingsBackend()
        ..seed(id: 'listing-1')
        ..seedPhoto('listing-1', photoId: 'photo-a');
      final store = InMemoryGuidedCaptureStore();
      seedStore?.call(store);
      final source = FakePhotoSource();
      final controller = ListingDraftsController(
        api: StaffListingsApi(
          baseUrl: 'https://api.example.test',
          client: backend.client,
        ),
        session: session,
        photosApi: StaffListingPhotosApi(
          baseUrl: 'https://api.example.test',
          client: backend.client,
        ),
        photoSource: source,
        guidedStore: store,
        photoAnalyzer: (_) async => measured,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ListingsScreen(
            controller: controller,
            mapConfig: FakeTileProvider().config,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('listing-item-listing-1')));
      await tester.pumpAndSettle();
      return (backend: backend, store: store, source: source);
    }

    Future<void> scrollTo(WidgetTester tester, String key) async {
      final target = find.byKey(ValueKey(key));
      if (target.evaluate().isEmpty) {
        await tester.dragUntilVisible(
          target,
          find.byType(ListView).last,
          const Offset(0, -200),
        );
      }
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    FilledButton submitButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.byKey(const ValueKey('listing-submit-button')),
    );

    testWidgets('a draft with photos is not sent until the guide is complete', (
      tester,
    ) async {
      await pumpEditor(tester);
      await scrollTo(tester, 'listing-submit-button');

      expect(submitButton(tester).onPressed, isNull);
      expect(
        find.textContaining('Completá la captura guiada para enviar a revisión'),
        findsOneWidget,
      );
      expect(find.text('0 de 7 ambientes listos.'), findsOneWidget);
    });

    testWidgets('a complete guide enables sending to review', (tester) async {
      final checklist = CaptureChecklist.derive(bedrooms: 3, bathrooms: 2);
      final done = CaptureChecklist([
        for (final room in checklist.rooms)
          room.id == 'living'
              ? room.copyWith(
                  checks: RoomCheck.values.toSet(),
                  photoIds: ['photo-a'],
                )
              : room.copyWith(skippedReason: () => 'Prueba'),
      ]);
      final result = await pumpEditor(
        tester,
        seedStore: (store) => store.entries['staff-1/listing-1'] = done.toJson(),
      );
      await scrollTo(tester, 'listing-submit-button');

      expect(find.text('Completa: 7 de 7 ambientes listos.'), findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('listing-submit-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('listing-submit-confirm')));
      await tester.pumpAndSettle();
      expect(result.backend.listings['listing-1']!['approval_status'], 'pending');
    });

    testWidgets('a photo that passes is uploaded and assigned to its room', (
      tester,
    ) async {
      final result = await pumpEditor(tester);
      await scrollTo(tester, 'open-guided-capture');
      await tester.tap(find.byKey(const ValueKey('open-guided-capture')));
      await tester.pumpAndSettle();

      for (final check in RoomCheck.values) {
        await tester.tap(find.byKey(ValueKey('guided-check-living-${check.name}')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('guided-camera-living')));
      // The progress bar animates until the upload ends on the real loop.
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(result.source.origins, [PhotoOrigin.camera]);
      expect(result.backend.confirmedPhotos('listing-1'), hasLength(2));
      expect(find.text('1 foto aprobada'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('guided-status-living'))).data,
        'Listo',
      );
      final stored = CaptureChecklist.fromJson(
        result.store.entries['staff-1/listing-1'],
      );
      expect(stored.rooms.first.photoIds, hasLength(1));
      expect(stored.rooms.first.checks, RoomCheck.values.toSet());
    });

    testWidgets('a photo that fails the quality check is not uploaded and '
        'says why', (tester) async {
      final result = await pumpEditor(tester, measured: _dark);
      await scrollTo(tester, 'open-guided-capture');
      await tester.tap(find.byKey(const ValueKey('open-guided-capture')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guided-gallery-living')));
      await tester.pumpAndSettle();

      expect(result.backend.confirmedPhotos('listing-1'), hasLength(1));
      expect(
        find.text('La foto está muy oscura. Encendé las luces o abrí las cortinas.'),
        findsOneWidget,
      );
      expect(find.text('Sin fotos aprobadas todavía.'), findsWidgets);
    });

    testWidgets('a room that does not apply needs a reason, and an extra room '
        'can be added and removed', (tester) async {
      final result = await pumpEditor(tester);
      await scrollTo(tester, 'open-guided-capture');
      await tester.tap(find.byKey(const ValueKey('open-guided-capture')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guided-skip-kitchen')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guided-skip-reason-confirm')));
      await tester.pumpAndSettle();
      // A blank reason keeps the dialog open.
      expect(find.byKey(const ValueKey('guided-skip-reason')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('guided-skip-reason')),
        'Cocina integrada al living',
      );
      await tester.tap(find.byKey(const ValueKey('guided-skip-reason-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('No aplica: Cocina integrada al living'), findsOneWidget);

      await scrollTo(tester, 'guided-add-room');
      await tester.tap(find.byKey(const ValueKey('guided-add-room')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('guided-room-name')), 'Patio');
      await tester.tap(find.byKey(const ValueKey('guided-room-name-confirm')));
      await tester.pumpAndSettle();

      var stored = CaptureChecklist.fromJson(result.store.entries['staff-1/listing-1']);
      final patio = stored.rooms.last;
      expect(patio.label, 'Patio');
      expect(stored.rooms[1].skippedReason, 'Cocina integrada al living');

      await scrollTo(tester, 'guided-remove-${patio.id}');
      await tester.tap(find.byKey(ValueKey('guided-remove-${patio.id}')));
      await tester.pumpAndSettle();
      stored = CaptureChecklist.fromJson(result.store.entries['staff-1/listing-1']);
      expect(stored.rooms.map((room) => room.label), isNot(contains('Patio')));
    });
  });
}
