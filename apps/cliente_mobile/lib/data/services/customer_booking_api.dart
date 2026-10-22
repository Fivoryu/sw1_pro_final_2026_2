import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/reservation_models.dart';
import 'customer_auth_failure.dart';

typedef AccessTokenProvider = Future<String> Function();

/// Client for customer quotes, verified wallets, and reservation endpoints.
/// Quote requests are public; every wallet and reservation operation uses the
/// authenticated customer session supplied by [accessTokenProvider].
class CustomerBookingApi {
  CustomerBookingApi({
    required String baseUrl,
    required this.accessTokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  final String _baseUrl;
  final AccessTokenProvider accessTokenProvider;
  final http.Client _client;
  final Duration timeout;

  Future<QuoteSnapshot> createQuote({
    required String listingId,
    required int offerVersion,
    required List<String> selectedExtraIds,
    required String targetCurrency,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/quotes',
      body: {
        'listing_id': listingId,
        'offer_version': offerVersion,
        'selected_extra_ids': selectedExtraIds,
        'target_currency': targetCurrency,
      },
    );
    return _parse(() => QuoteSnapshot.fromJson(body));
  }

  Future<List<CustomerWallet>> listWallets() async {
    final body = await _send(
      'GET',
      '/api/v1/customer/wallets',
      authenticated: true,
    );
    return _parse(() {
      if (body is! List<Object?>) {
        throw const FormatException('Wallet list is invalid');
      }
      return body.map(CustomerWallet.fromJson).toList(growable: false);
    });
  }

  Future<CustomerWalletChallenge> createWalletChallenge({
    required String address,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/customer/wallet-challenges',
      body: {'address': address},
      authenticated: true,
    );
    return _parse(() => CustomerWalletChallenge.fromJson(body));
  }

  Future<CustomerWallet> linkWallet({
    required String challengeId,
    required String signature,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/customer/wallets',
      body: {'challenge_id': challengeId, 'signature': signature},
      authenticated: true,
    );
    return _parse(() => CustomerWallet.fromJson(body));
  }

  Future<ReservationRecord> createReservation({
    required String listingId,
    required String quoteId,
    required String walletId,
    required String idempotencyKey,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/reservations',
      body: {
        'listing_id': listingId,
        'quote_id': quoteId,
        'customer_wallet_id': walletId,
      },
      authenticated: true,
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return _parse(() => ReservationRecord.fromJson(body));
  }

  Future<ReservationRecord> createCardReservation({
    required String listingId,
    required String quoteId,
    required String idempotencyKey,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/reservations',
      body: {
        'listing_id': listingId,
        'quote_id': quoteId,
        'payment_method': 'card',
      },
      authenticated: true,
      headers: {'Idempotency-Key': idempotencyKey},
    );
    return _parse(() => ReservationRecord.fromJson(body));
  }

  Future<CardPaymentSession> createCardPaymentIntent(
    String reservationId,
  ) async {
    final body = await _send(
      'POST',
      '/api/v1/reservations/${Uri.encodeComponent(reservationId)}/card-payment-intent',
      authenticated: true,
    );
    return _parse(() => CardPaymentSession.fromJson(body));
  }

  Future<void> cancelCardReservation(String reservationId) async {
    await _send(
      'POST',
      '/api/v1/reservations/${Uri.encodeComponent(reservationId)}/card-cancel',
      authenticated: true,
    );
  }

  Future<void> expireCardReservation(String reservationId) async {
    await _send(
      'POST',
      '/api/v1/reservations/${Uri.encodeComponent(reservationId)}/card-expire',
      authenticated: true,
    );
  }

  Future<List<ReservationRecord>> listReservations() async {
    final body = await _send(
      'GET',
      '/api/v1/reservations',
      authenticated: true,
    );
    return _parse(() {
      if (body is! List<Object?>) {
        throw const FormatException('Reservation list is invalid');
      }
      return body.map(ReservationRecord.fromJson).toList(growable: false);
    });
  }

  Future<ReservationRecord> getReservation(String reservationId) async {
    final body = await _send(
      'GET',
      '/api/v1/reservations/${Uri.encodeComponent(reservationId)}',
      authenticated: true,
    );
    return _parse(() => ReservationRecord.fromJson(body));
  }

  Future<Map<String, Object?>> requestPermit({
    required String reservationId,
    required String action,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/reservations/${Uri.encodeComponent(reservationId)}/permit',
      body: {'action': action},
      authenticated: true,
    );
    return _parse(() => _object(body));
  }

  Future<ReservationPermit> requestDepositPermit(String reservationId) async {
    final body = await requestPermit(
      reservationId: reservationId,
      action: 'deposit',
    );
    return _parse(() => ReservationPermit.fromJson(body));
  }

  Future<Map<String, Object?>> reconcileTransaction({
    required String reservationId,
    required String action,
    required String transactionHash,
    required int nonce,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/reservations/${Uri.encodeComponent(reservationId)}/chain-transactions',
      body: {
        'action': action,
        'transaction_hash': transactionHash,
        'nonce': nonce,
      },
      authenticated: true,
    );
    return _parse(() => _object(body));
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = false,
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final token = authenticated ? await accessTokenProvider() : null;
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      ...headers,
    };
    try {
      final response = switch (method) {
        'GET' =>
          await _client.get(uri, headers: requestHeaders).timeout(timeout),
        _ =>
          await _client
              .post(
                uri,
                headers: requestHeaders,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(timeout),
      };
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw failureFromResponse(
          statusCode: response.statusCode,
          body: utf8.decode(response.bodyBytes, allowMalformed: true),
        );
      }
      if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
    } on CustomerAuthFailure {
      rethrow;
    } on FormatException {
      throw malformedResponseFailure();
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
  }

  Map<String, Object?> _object(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Response is invalid');
    }
    return value;
  }

  T _parse<T>(T Function() build) {
    try {
      return build();
    } on FormatException {
      throw malformedResponseFailure();
    } on TypeError {
      throw malformedResponseFailure();
    }
  }
}
