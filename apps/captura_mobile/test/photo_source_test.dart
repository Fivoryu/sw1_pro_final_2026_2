import 'dart:typed_data';

import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> head) =>
    Uint8List.fromList([...head, ...List.filled(16, 0)]);

void main() {
  test('detects the supported formats from their signatures', () {
    expect(
      detectPhotoContentType(_bytes([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
    expect(
      detectPhotoContentType(
        _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      ),
      'image/png',
    );
    expect(
      detectPhotoContentType(_bytes('RIFF\x00\x00\x00\x00WEBP'.codeUnits)),
      'image/webp',
    );
  });

  test('rejects other formats and truncated files', () {
    expect(detectPhotoContentType(_bytes('GIF89a'.codeUnits)), isNull);
    expect(
      detectPhotoContentType(_bytes('\x00\x00\x00\x18ftypheic'.codeUnits)),
      isNull,
    );
    expect(detectPhotoContentType(Uint8List.fromList([0xFF, 0xD8])), isNull);
    expect(detectPhotoContentType(Uint8List(0)), isNull);
  });

  test('device photos are reduced before upload', () {
    expect(ImagePickerPhotoSource.maxDimension, 2560);
    expect(ImagePickerPhotoSource.imageQuality, 85);
  });
}
