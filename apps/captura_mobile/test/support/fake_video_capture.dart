import 'package:captura_mobile/data/services/ar_capture_channel.dart';
import 'package:captura_mobile/data/services/video_capture_channel.dart';

/// Scripted native recorder: each call consumes the next queued result.
class FakeVideoCapture implements VideoCapture {
  final List<VideoCaptureResult> results = [];
  final List<String> listingIds = [];
  Future<void> Function()? beforeReturn;

  @override
  Future<VideoCaptureResult> record({
    required String listingId,
    String? ownerId,
    String? firstRoomName,
  }) async {
    listingIds.add(listingId);
    await beforeReturn?.call();
    return results.removeAt(0);
  }
}

VideoCaptured videoCaptured({
  String id = 'cap-video-1',
  String path = '/files/capture_packages/cap-video-1.zip',
  int sizeBytes = 100,
  bool hasReference = true,
  bool reachedTimeLimit = false,
}) => VideoCaptured(
  package: CapturePackageInfo(
    zipPath: path,
    captureId: id,
    sizeBytes: sizeBytes,
    keyframeCount: 900,
    droppedKeyframes: 0,
    failedKeyframes: 0,
    rooms: const [CapturePackageRoom(id: 'room-1', name: 'Sala')],
  ),
  hasReference: hasReference,
  duration: const Duration(seconds: 30),
  reachedTimeLimit: reachedTimeLimit,
  timestampSource: 'realtime',
);
