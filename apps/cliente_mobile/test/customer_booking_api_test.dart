import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cliente_mobile/data/models/reservation_models.dart';
import 'package:cliente_mobile/data/services/customer_booking_api.dart';
import 'package:cliente_mobile/data/services/hardhat_reservation_executor.dart';

Map<String, Object?> quoteJson() => {
  'quote_id': 'quote-1',
  'listing_id': 'listing-1',
  'offer_version': 2,
  'operation': 'sale',
  'lines': [
    {
      'kind': 'base',
      'extra_id': null,
      'amount': '100.00',
      'currency': 'USD',
      'charge_period': 'one_time',
    },
  ],
  'one_time_total': {'amount': '100.00', 'currency': 'USD'},
  'monthly_total': {'amount': '0.00', 'currency': 'USD'},
  'created_at': '2026-10-06T12:00:00Z',
  'expires_at': '2026-10-06T12:15:00Z',
};

Map<String, Object?> reservationJson() => {
  'reservation_id': 'reservation-1',
  'listing_id': 'listing-1',
  'status': 'pending',
  'api_created_at': '2026-10-06T12:00:00Z',
  'decision_deadline_at': '2026-10-07T12:00:00Z',
  'quote_snapshot': {
    'quote_id': 'quote-1',
    'offer_version': 2,
    'operation': 'sale',
    'lines': [
      {
        'kind': 'base',
        'extra_id': null,
        'amount': '100.00',
        'currency': 'USD',
        'charge_period': 'one_time',
      },
    ],
    'one_time_total': {'amount': '100.00', 'currency': 'USD'},
    'monthly_total': {'amount': '0.00', 'currency': 'USD'},
  },
  'deposit_amount': '5.00',
  'deposit_confirmed_at': null,
};

void main() {

  test('local escrow mapping follows reservation currency with legacy fallback rules', () {
    const bob = '0x1111111111111111111111111111111111111111';
    const usd = '0x2222222222222222222222222222222222222222';
    const usdt = '0x3333333333333333333333333333333333333333';
    const legacy = '0x4444444444444444444444444444444444444444';

    expect(
      localEscrowAddressForCurrency(
        'BOB',
        bobAddress: bob,
        usdAddress: usd,
        usdtAddress: usdt,
        legacyRftEscrowAddress: legacy,
      ),
      bob,
    );
    expect(
      localEscrowAddressForCurrency(
        'USD',
        bobAddress: bob,
        usdAddress: usd,
        usdtAddress: usdt,
        legacyRftEscrowAddress: legacy,
      ),
      usd,
    );
    expect(
      localEscrowAddressForCurrency(
        'USDT',
        bobAddress: bob,
        usdAddress: usd,
        usdtAddress: usdt,
        legacyRftEscrowAddress: legacy,
      ),
      usdt,
    );
    expect(
      localEscrowAddressForCurrency(
        'BOB',
        bobAddress: '',
        usdAddress: '',
        usdtAddress: usdt,
        legacyRftEscrowAddress: legacy,
      ),
      legacy,
    );
    expect(
      localEscrowAddressForCurrency(
        'USD',
        bobAddress: '',
        usdAddress: '',
        usdtAddress: usdt,
        legacyRftEscrowAddress: legacy,
      ),
      legacy,
    );
    expect(
      () => localEscrowAddressForCurrency(
        'USDT',
        bobAddress: bob,
        usdAddress: usd,
        usdtAddress: '',
        legacyRftEscrowAddress: legacy,
      ),
      throwsStateError,
    );
  });

  test(
    'quote uses the server-selected currency without an auth token',
    () async {
      late http.Request captured;
      final api = CustomerBookingApi(
        baseUrl: 'https://api.example.test/',
        accessTokenProvider: () async => 'customer-access',
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(quoteJson()), 201);
        }),
      );

      final quote = await api.createQuote(
        listingId: 'listing-1',
        offerVersion: 2,
        selectedExtraIds: ['extra-2', 'extra-1'],
        targetCurrency: 'USD',
      );

      expect(captured.url.path, '/api/v1/quotes');
      expect(captured.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(captured.body), {
        'listing_id': 'listing-1',
        'offer_version': 2,
        'selected_extra_ids': ['extra-2', 'extra-1'],
        'target_currency': 'USD',
      });
      expect(quote.oneTimeTotal.amount, '100.00');
      expect(quote.oneTimeTotal.currency, 'USD');
    },
  );

  test(
    'reservation carries authenticated identity and idempotency key',
    () async {
      late http.Request captured;
      final api = CustomerBookingApi(
        baseUrl: 'https://api.example.test',
        accessTokenProvider: () async => 'access-token',
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode(reservationJson()), 201);
        }),
      );

      final reservation = await api.createReservation(
        listingId: 'listing-1',
        quoteId: 'quote-1',
        walletId: 'wallet-1',
        idempotencyKey: 'retry-safe-key',
      );

      expect(captured.url.path, '/api/v1/reservations');
      expect(captured.headers['authorization'], 'Bearer access-token');
      expect(captured.headers['idempotency-key'], 'retry-safe-key');
      expect(jsonDecode(captured.body), {
        'listing_id': 'listing-1',
        'quote_id': 'quote-1',
        'customer_wallet_id': 'wallet-1',
      });
      expect(reservation.status, 'pending');
      expect(reservation.depositAmount, '5.00');
    },
  );



  test('reservation parses the nullable deposit confirmation timestamp', () {
    final pending = ReservationRecord.fromJson(reservationJson());
    final deposited = ReservationRecord.fromJson({
      ...reservationJson(),
      'deposit_confirmed_at': '2026-10-06T12:30:00Z',
    });

    expect(pending.depositConfirmedAt, isNull);
    expect(
      deposited.depositConfirmedAt?.toUtc(),
      DateTime.utc(2026, 10, 6, 12, 30),
    );
  });

  test('wallet challenge maps the exact message and expiration', () async {
    final api = CustomerBookingApi(
      baseUrl: 'https://api.example.test',
      accessTokenProvider: () async => 'access-token',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/customer/wallet-challenges');
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({
            'challenge_id': 'challenge-1',
            'message': 'RoomForge wallet ownership challenge',
            'expires_at': '2026-10-06T12:05:00Z',
          }),
          201,
        );
      }),
    );

    final challenge = await api.createWalletChallenge(address: '0x${'a' * 40}');

    expect(challenge.challengeId, 'challenge-1');
    expect(challenge.message, 'RoomForge wallet ownership challenge');
    expect(challenge.expiresAt.toUtc(), DateTime.utc(2026, 10, 6, 12, 5));
  });
}
