import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/review_models.dart';
import 'customer_auth_failure.dart';
import 'customer_booking_api.dart' show AccessTokenProvider;

/// Client for the review endpoints. Reading is public; reading one's own
/// review and writing need the customer session from [accessTokenProvider].
/// Failures reuse [CustomerAuthFailure]: 403 means the customer cannot rate
/// yet.
class CustomerReviewsApi {
  CustomerReviewsApi({
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

  Future<ListingReviews> listingReviews(String listingId) async {
    final body = await _send(
      'GET',
      '/api/v1/listings/${Uri.encodeComponent(listingId)}/reviews',
    );
    return _parse(() => ListingReviews.fromJson(body));
  }

  Future<AgencyReviews> agencyReviews(String agencyId) async {
    final body = await _send(
      'GET',
      '/api/v1/public/agencies/${Uri.encodeComponent(agencyId)}/reviews',
    );
    return _parse(() => AgencyReviews.fromJson(body));
  }

  Future<MyReview> myReview(String listingId) async {
    final body = await _send(
      'GET',
      '/api/v1/customer/reviews/listings/${Uri.encodeComponent(listingId)}',
      authenticated: true,
    );
    return _parse(() => MyReview.fromJson(body));
  }

  Future<Review> writeReview(
    String listingId, {
    required int listingRating,
    required int agencyRating,
    String? comment,
  }) async {
    final body = await _send(
      'PUT',
      '/api/v1/customer/reviews/listings/${Uri.encodeComponent(listingId)}',
      authenticated: true,
      body: {
        'listing_rating': listingRating,
        'agency_rating': agencyRating,
        if (comment != null) 'comment': comment,
      },
    );
    return _parse(() => Review.fromJson(body));
  }

  Future<Object?> _send(
    String method,
    String path, {
    bool authenticated = false,
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (authenticated)
        'Authorization': 'Bearer ${await accessTokenProvider()}',
    };
    try {
      final response = switch (method) {
        'GET' => await _client.get(uri, headers: headers).timeout(timeout),
        _ =>
          await _client
              .put(uri, headers: headers, body: jsonEncode(body))
              .timeout(timeout),
      };
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw failureFromResponse(
          statusCode: response.statusCode,
          body: utf8.decode(response.bodyBytes, allowMalformed: true),
        );
      }
      if (response.bodyBytes.isEmpty) return null;
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
