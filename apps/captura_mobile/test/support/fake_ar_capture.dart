import 'package:captura_mobile/data/services/ar_capture_channel.dart';

/// Scripted native capture: each call consumes the next queued result.
class FakeArCapture implements ArCapture {
  ArAvailability available = ArAvailability.supported;
  final List<ArCaptureResult> results = [];
  final List<String> names = [];
  final List<CaptureMode> modes = [];
  final List<String?> listingIds = [];

  @override
  Future<ArAvailability> availability() async => available;

  @override
  Future<ArCaptureResult> captureRoom(
    String roomName, {
    CaptureMode mode = CaptureMode.walls,
    String? listingId,
  }) async {
    names.add(roomName);
    modes.add(mode);
    listingIds.add(listingId);
    return results.removeAt(0);
  }
}

/// A walkthrough of a 4 × 3 room whose walls were seen only in part;
/// [walls] limits how many of the four walls ARCore detected.
ArCaptured walkthrough({int walls = 4}) {
  Map<String, Object?> wall(double x1, double z1, double x2, double z2) => {
    'start': {'x': x1, 'z': z1},
    'end': {'x': x2, 'z': z2},
    'area': 2.0,
    'minY': -1.2,
    'maxY': 0.6,
  };
  final all = [
    wall(0.6, 0, 3.2, 0),
    wall(4, 0.4, 4, 2.5),
    wall(3.5, 3, 0.8, 3),
    wall(0, 2.6, 0, 0.3),
  ];
  return ArCaptured({
    'outcome': 'captured',
    'corners': <Object?>[],
    'height': {'value': 2.5, 'source': 'ceiling_plane'},
    'boxes': <Object?>[],
    'metrics': {
      'durationMs': 60000,
      'trackingLossCount': 0,
      'depthSupported': true,
      'cornerHitDistances': <Object?>[],
      'floorY': -1.3,
      'method': 'walkthrough',
    },
    'observations': {
      'floorY': -1.3,
      'walls': all.take(walls).toList(),
      'floors': [
        [
          {'x': 0.5, 'z': 0.5},
          {'x': 3.5, 'z': 0.5},
          {'x': 3.5, 'z': 2.5},
          {'x': 0.5, 'z': 2.5},
        ],
      ],
      'trajectory': [
        {'x': 1.0, 'z': 1.0},
        {'x': 3.0, 'z': 2.0},
      ],
    },
  });
}

/// A rectangle in ARCore world metres, as the native screen returns it.
ArCaptured rectangle(
  double width,
  double depth, {
  Map<String, Object?>? height = const {
    'value': 2.5,
    'source': 'ceiling_plane',
  },
}) => ArCaptured({
  'outcome': 'captured',
  'corners': [
    {'x': 10.0, 'z': 5.0},
    {'x': 10.0 + width, 'z': 5.0},
    {'x': 10.0 + width, 'z': 5.0 + depth},
    {'x': 10.0, 'z': 5.0 + depth},
  ],
  'height': height,
  'boxes': <Object?>[],
  'metrics': {
    'durationMs': 42000,
    'trackingLossCount': 1,
    'depthSupported': true,
    'cornerHitDistances': [1.2, 1.4, 1.1, 1.3],
    'floorY': -1.3,
  },
});
