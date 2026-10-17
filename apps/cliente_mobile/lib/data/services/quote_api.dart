import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/quote_models.dart';
import 'customer_auth_failure.dart';

/// HTTP client for the public quote endpoint, `POST /api/v1/quotes` (F05).
///
/// The quote needs no session: it is a public, rate-limited snapshot call,
/// so no credentials are sent.
class QuoteApi {
  QuoteApi({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  /// Requests a snapshot quote; the server decides every conversion.
  Future<QuoteSnapshot> createQuote({
    required String listingId,
    required int offerVersion,
    List<String> extraIds = const [],
    String? displayCurrency,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/quotes');
    final body = jsonEncode({
      'listing_id': listingId,
      'offer_version': offerVersion,
      'selected_extra_ids': extraIds,
      'target_currency': ?displayCurrency,
    });
    try {
      final response = await _client
          .post(
            uri,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(timeout);
      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw failureFromResponse(statusCode: response.statusCode, body: text);
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) {
        throw malformedResponseFailure();
      }
      return QuoteSnapshot.fromJson(decoded);
    } on CustomerAuthFailure {
      rethrow;
    } on FormatException {
      throw malformedResponseFailure();
    } on TypeError {
      throw malformedResponseFailure();
    } on TimeoutException {
      throw networkFailure();
    } on SocketException {
      throw networkFailure();
    } on http.ClientException {
      throw networkFailure();
    }
  }
}
