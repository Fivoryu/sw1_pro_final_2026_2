import 'dart:typed_data';

import 'package:captura_mobile/data/services/photo_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

Uint8List _bytes(List<int> head) =>
    Uint8List.fromList([...head, ...List.filled(16, 0)]);

class _RecordingPicker implements ImagePicker {
  _RecordingPicker(this.file);

  final XFile? file;
  Invocation? pickInvocation;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #pickImage) {
      pickInvocation = invocation;
      return Future<XFile?>.value(file);
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  test('detects JPEG, PNG, WebP, HEIC, and HEIF signatures', () {
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
    expect(
      detectPhotoContentType(_bytes('\x00\x00\x00\x18ftypheic'.codeUnits)),
      'image/heic',
    );
    expect(
      detectPhotoContentType(_bytes('\x00\x00\x00\x18ftypmif1'.codeUnits)),
      'image/heif',
    );
  });

  test('rejects other formats and truncated files', () {
    expect(detectPhotoContentType(_bytes('GIF89a'.codeUnits)), isNull);
    expect(
      detectPhotoContentType(_bytes('\x00\x00\x00\x18ftypxxxx'.codeUnits)),
      isNull,
    );
    expect(detectPhotoContentType(_bytes([0xFF, 0xD8])), isNull);
    expect(detectPhotoContentType(Uint8List(0)), isNull);
  });

  test(
    'uploads the exact picked bytes without requesting resize or re-encoding',
    () async {
      final original = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02]);
      final picker = _RecordingPicker(
        XFile.fromData(original, mimeType: 'image/jpeg'),
      );

      final picked = await ImagePickerPhotoSource(
        picker: picker,
      ).pick(PhotoOrigin.gallery);

      expect(picked?.bytes, orderedEquals(original));
      final arguments = picker.pickInvocation!.namedArguments;
      expect(arguments[const Symbol('maxWidth')], isNull);
      expect(arguments[const Symbol('maxHeight')], isNull);
      expect(arguments[const Symbol('imageQuality')], isNull);
    },
  );
}
