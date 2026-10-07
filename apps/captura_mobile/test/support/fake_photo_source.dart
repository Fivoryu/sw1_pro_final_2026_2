import 'dart:typed_data';

import 'package:captura_mobile/data/services/photo_source.dart';

/// Photo source double: returns [next] (or throws [error]) for every pick.
class FakePhotoSource implements PhotoSource {
  PickedPhoto? next = jpeg();
  Object? error;
  final List<PhotoOrigin> origins = [];

  /// A tiny photo with a JPEG signature.
  static PickedPhoto jpeg() => PickedPhoto(
    bytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]),
    contentType: 'image/jpeg',
  );

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async {
    origins.add(origin);
    final failure = error;
    if (failure != null) throw failure;
    return next;
  }
}
