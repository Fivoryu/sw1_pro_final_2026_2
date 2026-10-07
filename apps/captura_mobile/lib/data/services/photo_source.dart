import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Where the agent takes a photo from.
enum PhotoOrigin { camera, gallery }

/// A photo chosen on the device, ready to upload.
class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;

  /// Detected from the bytes, never from the file name.
  final String contentType;
}

/// Thrown when the chosen file is not a JPEG, PNG or WebP image.
class UnsupportedPhotoFormat implements Exception {
  const UnsupportedPhotoFormat();
}

/// Source of device photos; replaced by a fake in tests.
abstract interface class PhotoSource {
  /// The chosen photo, or null when the agent cancels.
  Future<PickedPhoto?> pick(PhotoOrigin origin);
}

/// Content type of [bytes] from its file signature, or null when it is not
/// one of the formats the API accepts.
String? detectPhotoContentType(Uint8List bytes) {
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith('RIFF'.codeUnits) && startsWith('WEBP'.codeUnits, 8)) {
    return 'image/webp';
  }
  return null;
}

/// Device camera and gallery through `image_picker`.
///
/// Photos are reduced on the device so they upload faster and stay well under
/// the API's 5 MB limit; the API still validates and cleans every photo.
class ImagePickerPhotoSource implements PhotoSource {
  ImagePickerPhotoSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  static const double maxDimension = 2560;
  static const int imageQuality = 85;

  final ImagePicker _picker;

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async {
    final file = await _picker.pickImage(
      source: origin == PhotoOrigin.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: maxDimension,
      maxHeight: maxDimension,
      imageQuality: imageQuality,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final contentType = detectPhotoContentType(bytes);
    if (contentType == null) throw const UnsupportedPhotoFormat();
    return PickedPhoto(bytes: bytes, contentType: contentType);
  }
}
