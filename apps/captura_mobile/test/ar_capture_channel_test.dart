import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('roomforge/ar_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('availability', () {
    for (final (wire, expected) in [
      ('supported', ArAvailability.supported),
      ('supported_not_installed', ArAvailability.supportedNotInstalled),
      ('unsupported', ArAvailability.unsupported),
      ('unknown', ArAvailability.unknown),
    ]) {
      test('maps $wire', () async {
        answer((_) => {'status': wire});

        expect(await MethodChannelArCapture().availability(), expected);
      });
    }

    test('treats a platform without the module as unsupported', () async {
      expect(
        await MethodChannelArCapture().availability(),
        ArAvailability.unsupported,
      );
    });
  });

  group('captureRoom', () {
    test('passes the room name and returns the raw capture', () async {
      late MethodCall seen;
      final payload = {
        'outcome': 'captured',
        'corners': [
          {'x': 0.0, 'z': 0.0},
          {'x': 4.0, 'z': 0.0},
          {'x': 4.0, 'z': 3.0},
        ],
        'height': null,
        'boxes': <Object?>[],
        'metrics': {'durationMs': 1000},
      };
      answer((call) {
        seen = call;
        return payload;
      });

      final result = await MethodChannelArCapture().captureRoom('Estar');

      expect(seen.method, 'captureRoom');
      expect(seen.arguments, {'roomName': 'Estar', 'mode': 'walls'});
      expect(result, isA<ArCaptured>());
      expect((result as ArCaptured).payload['corners'], payload['corners']);
    });

    test('reports a cancelled capture', () async {
      answer((_) => {'outcome': 'cancelled'});

      expect(
        await MethodChannelArCapture().captureRoom('Estar'),
        isA<ArCaptureCancelled>(),
      );
    });

    test(
      'explains a denied camera permission without failing the app',
      () async {
        answer(
          (_) => {
            'outcome': 'error',
            'code': 'camera_permission_denied',
            'message': 'denied',
          },
        );

        final result = await MethodChannelArCapture().captureRoom('Estar');

        expect(result, isA<ArCaptureFailed>());
        expect((result as ArCaptureFailed).code, 'camera_permission_denied');
        expect(result.message, contains('permiso de cámara'));
      },
    );

    test('turns a missing native module into a failure', () async {
      final result = await MethodChannelArCapture().captureRoom('Estar');

      expect(result, isA<ArCaptureFailed>());
      expect((result as ArCaptureFailed).code, 'arcore_unavailable');
    });
    test('asks the native screen for a walkthrough', () async {
      late MethodCall seen;
      answer((call) {
        seen = call;
        return {'outcome': 'cancelled'};
      });

      await MethodChannelArCapture().captureRoom(
        'Estar',
        mode: CaptureMode.walkthrough,
      );

      expect(seen.arguments, {'roomName': 'Estar', 'mode': 'walkthrough'});
    });
  });
}
