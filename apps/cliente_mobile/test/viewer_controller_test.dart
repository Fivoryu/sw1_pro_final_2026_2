import 'dart:async';
import 'dart:convert';

import 'package:cliente_mobile/data/services/scene_api.dart';
import 'package:cliente_mobile/domain/viewer_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _sceneDocument() => {
  'version': '1.0',
  'unit': 'meters',
  'rooms': <Object?>[],
  'objects': <Object?>[],
};

ViewerController _controller(
  Future<http.Response> Function(http.Request request) handler,
) => ViewerController(
  api: SceneApi(
    baseUrl: 'https://api.example.test',
    client: MockClient(handler),
  ),
);

void main() {
  group('ViewerController', () {
    test('a scene loads and ends ready with its document', () async {
      final controller = _controller(
        (_) async => _json(_sceneDocument(), 200),
      );

      await controller.load('listing-1');

      expect(controller.state, ViewerLoadState.ready);
      expect(controller.document, isNotNull);
      expect(controller.message, isNull);
    });

    test('a listing without a scene ends honestly not defined', () async {
      final controller = _controller(
        (_) async => _json({
          'detail': 'Scene is not defined for this listing',
          'code': 'scene_not_defined',
        }, 404),
      );

      await controller.load('listing-1');

      expect(controller.state, ViewerLoadState.notDefined);
      expect(controller.document, isNull);
    });

    test('a failed load ends failed with a user-facing message', () async {
      final controller = _controller(
        (_) async => http.Response('boom', 500),
      );

      await controller.load('listing-1');

      expect(controller.state, ViewerLoadState.failed);
      expect(controller.message, isNotEmpty);
    });

    test('a stale response from a superseded load is discarded', () async {
      final requests = <http.Request>[];
      final completers = <Completer<http.Response>>[];
      final controller = ViewerController(
        api: SceneApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((request) async {
            requests.add(request);
            final completer = Completer<http.Response>();
            completers.add(completer);
            return completer.future;
          }),
        ),
      );

      final first = controller.load('listing-1');
      final second = controller.load('listing-2');
      // The mock client dispatches handlers in later microtasks; let both
      // requests reach the handler before completing them out of order.
      await pumpEventQueue();
      completers[0].complete(_json(_sceneDocument(), 200));
      completers[1].complete(_json(_sceneDocument(), 200));
      await first;
      await second;

      expect(controller.state, ViewerLoadState.ready);
      final request = requests.last;
      expect(request.url.pathSegments[3], 'listing-2');
    });
  });
}
