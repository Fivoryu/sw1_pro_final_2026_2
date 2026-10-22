import 'dart:async';
import 'dart:convert';

import 'package:cliente_mobile/data/services/quote_api.dart';
import 'package:cliente_mobile/domain/quote_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _snapshot() => {
  'quote_id': 'quote-9',
  'listing_id': 'listing-1',
  'offer_version': 3,
  'operation': 'sale',
  'lines': <Object?>[],
  'one_time_total': {'amount': '350000.00', 'currency': 'BOB'},
  'monthly_total': {'amount': '0.00', 'currency': 'BOB'},
  'created_at': '2026-10-16T12:00:00Z',
  'expires_at': '2026-10-16T12:15:00Z',
};

QuoteController _controller(
  Future<http.Response> Function(http.Request request) handler,
) => QuoteController(
  api: QuoteApi(baseUrl: 'https://api.example.test', client: MockClient(handler)),
);

void main() {
  group('QuoteController', () {
    test('a created quote ends ready with its snapshot', () async {
      final controller = _controller((_) async => _json(_snapshot(), 201));

      final result = await controller.createQuote(
        listingId: 'listing-1',
        offerVersion: 3,
      );

      expect(result, isNull);
      expect(controller.state, QuoteState.ready);
      expect(controller.snapshot?.quoteId, 'quote-9');
    });

    test('a version mismatch ends failed with a user-facing message', () async {
      final controller = _controller(
        (_) async => _json({'detail': 'x', 'code': 'offer_version_mismatch'}, 409),
      );

      final result = await controller.createQuote(listingId: 'l', offerVersion: 1);

      expect(result, isNotNull);
      expect(controller.state, QuoteState.failed);
      expect(controller.message, 'El precio cambió mientras cotizabas. Volvé a intentarlo.');
    });

    test('a rate limit ends failed with a wait message', () async {
      final controller = _controller((_) async => _json({'detail': 'x'}, 429));

      await controller.createQuote(listingId: 'l', offerVersion: 1);

      expect(controller.state, QuoteState.failed);
      expect(controller.message, 'Estás cotizando demasiado rápido. Esperá un momento.');
    });

    test('a superseded quote request is discarded', () async {
      final completers = <Completer<http.Response>>[];
      final controller = QuoteController(
        api: QuoteApi(
          baseUrl: 'https://api.example.test',
          client: MockClient((_) {
            final completer = Completer<http.Response>();
            completers.add(completer);
            return completer.future;
          }),
        ),
      );

      final first = controller.createQuote(listingId: 'l', offerVersion: 1);
      final second = controller.createQuote(listingId: 'l', offerVersion: 2);
      await pumpEventQueue();
      completers[1].complete(_json(_snapshot(), 201));
      completers[0].complete(
        _json({..._snapshot(), 'quote_id': 'quote-stale'}, 201),
      );
      await first;
      await second;

      expect(controller.state, QuoteState.ready);
      expect(controller.snapshot?.quoteId, 'quote-9');
    });
  });
}
