import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:captura_mobile/data/services/staff_auth_api.dart';
import 'package:captura_mobile/data/services/staff_scene_api.dart';
import 'package:captura_mobile/domain/spatial_capture_controller.dart';
import 'package:captura_mobile/domain/staff_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ar_capture.dart';
import 'fake_scene_backend.dart';
import 'fake_staff_backend.dart';
import 'in_memory_capture_draft_store.dart';

class FloorplanTracePhotoSource implements PhotoSource {
  FloorplanTracePhotoSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async =>
      PickedPhoto(bytes: bytes, contentType: 'image/png');
}

class FloorplanTraceHarness {
  const FloorplanTraceHarness(this.controller, this.store);

  final SpatialCaptureController controller;
  final InMemoryCaptureDraftStore store;
}

Future<Uint8List> floorplanTraceTestPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 100, 80),
    Paint()..color = Colors.white,
  );
  final image = await recorder.endRecording().toImage(100, 80);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<FloorplanTraceHarness> buildFloorplanTraceHarness(
  WidgetTester tester, {
  required PhotoSource traceSource,
}) async {
  final backend = FakeSceneBackend();
  final store = InMemoryCaptureDraftStore();
  late SpatialCaptureController controller;
  await tester.runAsync(() async {
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
    controller = SpatialCaptureController(
      listingId: 'listing-1',
      session: session,
      sceneApi: StaffSceneApi(
        baseUrl: 'https://api.example.test',
        client: backend.client,
      ),
      store: store,
      ar: FakeArCapture(),
      traceSource: traceSource,
    );
    await controller.load();
  });
  return FloorplanTraceHarness(controller, store);
}
