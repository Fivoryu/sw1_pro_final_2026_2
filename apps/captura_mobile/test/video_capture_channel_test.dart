import 'package:captura_mobile/data/services/video_capture_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('roomforge/video_capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  final captured = {
    'outcome': 'captured',
    'capturePackage': {
      'zipPath': '/files/capture_packages/cap-1.zip',
      'captureId': 'cap-1',
      'sizeBytes': 1000,
      'keyframeCount': 900,
      'droppedKeyframes': 0,
      'failedKeyframes': 0,
      'rooms': [
        {'id': 'room-1', 'name': 'Sala'},
      ],
    },
    'hasReference': false,
    'durationMs': 300000,
    'reachedTimeLimit': true,
    'timestampSource': 'realtime',
  };

  test('recordVideo passes the listing and parses the package', () async {
    late MethodCall seen;
    answer((call) {
      seen = call;
      return captured;
    });

    final result = await MethodChannelVideoCapture().record(
      listingId: 'listing-1',
      firstRoomName: 'Sala',
    );

    expect(seen.method, 'recordVideo');
    expect(seen.arguments, {'listingId': 'listing-1', 'firstRoomName': 'Sala'});
    final video = result as VideoCaptured;
    expect(video.package.captureId, 'cap-1');
    expect(video.package.keyframeCount, 900);
    expect(video.hasReference, isFalse);
    expect(video.reachedTimeLimit, isTrue);
    expect(video.duration, const Duration(minutes: 5));
    expect(video.timestampSource, 'realtime');
  });

  test('maps cancelled and error outcomes', () async {
    answer((_) => {'outcome': 'cancelled'});
    expect(
      await MethodChannelVideoCapture().record(listingId: 'l'),
      isA<VideoCaptureCancelled>(),
    );

    answer(
      (_) => {
        'outcome': 'error',
        'code': 'package_too_large',
        'message': 'Pesa demasiado',
      },
    );
    final failed =
        await MethodChannelVideoCapture().record(listingId: 'l')
            as VideoCaptureFailed;
    expect(failed.code, 'package_too_large');
    expect(failed.message, 'Pesa demasiado');
  });

  test('a malformed package becomes a failure, not a crash', () async {
    answer(
      (_) => {
        'outcome': 'captured',
        'capturePackage': {'zipPath': ''},
      },
    );

    final result = await MethodChannelVideoCapture().record(listingId: 'l');

    expect((result as VideoCaptureFailed).code, 'invalid_package');
  });

  test('a platform without the module is reported as unsupported', () async {
    final result = await MethodChannelVideoCapture().record(listingId: 'l');

    expect((result as VideoCaptureFailed).code, 'unsupported');
  });
}
