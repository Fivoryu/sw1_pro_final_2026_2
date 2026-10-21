import 'dart:convert';

import 'package:cliente_mobile/ui/features/viewer/logic/viewer_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ViewerBridgeMessage.tryParse', () {
    test('parses the ready signal', () {
      final message = ViewerBridgeMessage.tryParse(
        jsonEncode({'type': 'ready'}),
      );

      expect(message, isA<ViewerReady>());
    });

    test('parses scene_loaded with its object ids', () {
      final message = ViewerBridgeMessage.tryParse(
        jsonEncode({'type': 'scene_loaded', 'objects': ['a', 'b']}),
      ) as SceneLoaded;

      expect(message.objectIds, ['a', 'b']);
    });

    test('parses a load error with its detail', () {
      final message = ViewerBridgeMessage.tryParse(
        jsonEncode({'type': 'load_error', 'detail': 'Unsupported scene version.'}),
      ) as ViewerLoadError;

      expect(message.detail, 'Unsupported scene version.');
    });

    test('parses an object selection', () {
      final message = ViewerBridgeMessage.tryParse(
        jsonEncode({'type': 'selection', 'objectId': 'ref_cube_1'}),
      ) as ViewerSelection;

      expect(message.objectId, 'ref_cube_1');
    });

    test('parses clearing the selection with a null object id', () {
      final message = ViewerBridgeMessage.tryParse(
        jsonEncode({'type': 'selection', 'objectId': null}),
      ) as ViewerSelection;

      expect(message.objectId, isNull);
    });

    test('a malformed JSON line is ignored, never a crash', () {
      expect(ViewerBridgeMessage.tryParse('not json'), isNull);
    });

    test('an unknown message type is ignored', () {
      expect(
        ViewerBridgeMessage.tryParse(jsonEncode({'type': 'something_else'})),
        isNull,
      );
    });

    test('a non-object payload is ignored', () {
      expect(ViewerBridgeMessage.tryParse('[1, 2, 3]'), isNull);
    });

    test('a scene_loaded without an object list is ignored', () {
      expect(
        ViewerBridgeMessage.tryParse(jsonEncode({'type': 'scene_loaded'})),
        isNull,
      );
    });

    test('a load_error without a string detail is ignored', () {
      expect(
        ViewerBridgeMessage.tryParse(jsonEncode({'type': 'load_error', 'detail': 7})),
        isNull,
      );
    });
  });
}
