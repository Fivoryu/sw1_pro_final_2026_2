import 'dart:convert';

import 'package:cliente_mobile/data/services/quote_api.dart';
import 'package:cliente_mobile/data/services/customer_auth_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _baseUrl = 'https://api.example.test';

http.Response _json(Object body, int status, [Map<String, String> headers = const {}]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json', ...headers},
    );

Map<String, Object?> _snapshot() => {
  'quote_id': 'quote-9',
  'listing_id': 'listing-1',
  'offer_version': 3,
  'operation': 'sale',
  'lines': [
    {
      'kind': 'base',
      'extra_id': null,
      'amount': '350000.00',
      'currency': 'BOB',
      'charge_period': 'one_time',
    },
  ],
  'one_time_total': {'amount': '350000.00', 'currency': 'BOB'},
  'monthly_total': {'amount': '0.00', 'currency': 'BOB'},
  'created_at': '2026-10-16T12:00:00Z',
  'expires_at': '2026-10-16T12:15:00Z',
};

QuoteApi _build(Future<http.Response> Function(http.Request request) handler) => QuoteApi(
  baseUrl: '$_baseUrl/',
  client: MockClient(handler),
);

void main() {
  group('QuoteApi success', () {
    test('creates a quote with extras and display currency', () async {
      final requests = <http.Request>[];
      final api = QuoteApi(
        baseUrl: '$_baseUrl/',
        client: MockClient((request) async {
          requests.add(request);
          return _json(_snapshot(), 201);
        }),
      );

      final snapshot = await api.createQuote(
        listingId: 'listing-1',
        offerVersion: 3,
        extraIds: const ['extra-1'],
        displayCurrency: 'USD',
      );

      expect(snapshot.quoteId, 'quote-9');
      expect(snapshot.oneTimeTotal.currency, 'BOB');
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/quotes');
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body, {
        'listing_id': 'listing-1',
        'offer_version': 3,
        'selected_extra_ids': ['extra-1'],
        'target_currency': 'USD',
      });
    });
  });

  group('QuoteApi failures', () {
    test('a 409 offer-version mismatch is reported with its code', () async {
      final api = _build((_) async => _json({'detail': 'x', 'code': 'offer_version_mismatch'}, 409));

      final failure = await _capture(() => api.createQuote(listingId: 'l', offerVersion: 1));

      expect(failure.statusCode, 409);
    });

    test('a 429 rate limit reports the rate-limited code', () async {
      final api = _build((_) async => _json({'detail': 'x', 'code': 'rate_limited'}, 429));

      final failure = await _capture(() => api.createQuote(listingId: 'l', offerVersion: 1));

      expect(failure.code, kRateLimited);
    });

    test('a 404 unknown listing reports not found', () async {
      final api = _build((_) async => _json({'detail': 'x', 'code': 'not_found'}, 404));

      final failure = await _capture(() => api.createQuote(listingId: 'l', offerVersion: 1));

      expect(failure.code, kNotFound);
    });

    test('a malformed snapshot is never trusted as a quote', () async {
      final api = _build((_) async => http.Response('not json', 201));

      final failure = await _capture(() => api.createQuote(listingId: 'l', offerVersion: 1));

      expect(failure.code, kInternalError);
    });

    test('a transport failure is safe to retry', () async {
      final api = QuoteApi(
        baseUrl: _baseUrl,
        client: MockClient((_) async => throw http.ClientException('closed')),
      );

      final failure = await _capture(() => api.createQuote(listingId: 'l', offerVersion: 1));

      expect(failure.isNetworkFailure, isTrue);
    });
  });
}

Future<CustomerAuthFailure> _capture(Future<Object?> Function() action) async {
  try {
    await action();
  } on CustomerAuthFailure catch (failure) {
    return failure;
  }
  fail('expected the call to fail');
}
