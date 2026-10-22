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

    test(
      'passes the listing id so the package manifest can carry it',
      () async {
        late MethodCall seen;
        answer((call) {
          seen = call;
          return {'outcome': 'cancelled'};
        });

        await MethodChannelArCapture().captureRoom(
          'Estar',
          mode: CaptureMode.walkthrough,
          listingId: 'listing-1',
        );

        expect(seen.arguments, {
          'roomName': 'Estar',
          'mode': 'walkthrough',
          'listingId': 'listing-1',
        });
      },
    );
  });

  group('capture package', () {
    Map<String, Object?> captured(Map<String, Object?> extra) => {
      'outcome': 'captured',
      'corners': <Object?>[],
      'height': null,
      'boxes': <Object?>[],
      'metrics': {'durationMs': 1000, 'method': 'walkthrough'},
      ...extra,
    };

    Map<String, Object?> package({Map<String, Object?> override = const {}}) =>
        {
          'zipPath': '/data/user/0/app/files/capture_packages/cap-1.zip',
          'captureId': 'cap-1',
          'sizeBytes': 2097152,
          'keyframeCount': 40,
          'droppedKeyframes': 2,
          'failedKeyframes': 0,
          'rooms': [
            {'id': 'room-1', 'name': 'Estar'},
            {'id': 'room-2', 'name': 'Ambiente 2'},
          ],
          ...override,
        };

    test('parses the additive capturePackage result', () async {
      answer((_) => captured({'capturePackage': package()}));

      final result =
          await MethodChannelArCapture().captureRoom('Estar') as ArCaptured;

      final info = result.capturePackage!;
      expect(info.zipPath, '/data/user/0/app/files/capture_packages/cap-1.zip');
      expect(info.captureId, 'cap-1');
      expect(info.sizeBytes, 2097152);
      expect(info.keyframeCount, 40);
      expect(info.droppedKeyframes, 2);
      expect(info.rooms.map((r) => r.name), ['Estar', 'Ambiente 2']);
      expect(result.packageProblem, isNull);
      // The existing fields are untouched.
      expect(result.payload['metrics'], {
        'durationMs': 1000,
        'method': 'walkthrough',
      });
    });

    test('a result without a package behaves as before', () async {
      answer((_) => captured({}));

      final result =
          await MethodChannelArCapture().captureRoom('Estar') as ArCaptured;

      expect(result.capturePackage, isNull);
      expect(result.packageProblem, isNull);
    });

    test('relays why the native side could not build the package', () async {
      answer((_) => captured({'capturePackageError': 'Sin espacio.'}));

      final result =
          await MethodChannelArCapture().captureRoom('Estar') as ArCaptured;

      expect(result.capturePackage, isNull);
      expect(result.packageProblem, 'Sin espacio.');
    });

    for (final (label, bad) in <(String, Object?)>[
      ('not a map', 'zip'),
      ('without zipPath', {...package()}..remove('zipPath')),
      ('with an empty captureId', package(override: {'captureId': ''})),
      ('with a non-numeric size', package(override: {'sizeBytes': 'big'})),
      ('with a zero size', package(override: {'sizeBytes': 0})),
      (
        'with a negative keyframe count',
        package(override: {'keyframeCount': -1}),
      ),
      ('with rooms that are not a list', package(override: {'rooms': 'x'})),
      (
        'with a room without a name',
        package(
          override: {
            'rooms': [
              {'id': 'room-1'},
            ],
          },
        ),
      ),
    ]) {
      test('keeps the room but flags a malformed package ($label)', () async {
        answer((_) => captured({'capturePackage': bad}));

        final result =
            await MethodChannelArCapture().captureRoom('Estar') as ArCaptured;

        expect(result.capturePackage, isNull);
        expect(result.packageProblem, contains('incompleto'));
        expect(result.payload['outcome'], 'captured');
      });
    }

    test(
      'CapturePackageInfo.fromJson throws FormatException when malformed',
      () {
        expect(
          () =>
              CapturePackageInfo.fromJson({...package()}..remove('captureId')),
          throwsFormatException,
        );
        expect(
          () => CapturePackageInfo.fromJson(
            package(override: {'rooms': <Object?>[]}),
          ),
          throwsFormatException,
        );
      },
    );
  });
}
