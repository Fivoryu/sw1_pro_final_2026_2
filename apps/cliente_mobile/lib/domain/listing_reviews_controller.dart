import 'package:flutter/foundation.dart';

import '../data/models/review_models.dart';
import '../data/services/customer_auth_failure.dart';
import '../data/services/customer_reviews_api.dart';

/// Reviews of one listing: the public ratings and, for a signed-in customer,
/// their own review and whether they may write one.
class ListingReviewsController extends ChangeNotifier {
  ListingReviewsController({
    required CustomerReviewsApi api,
    required this.listingId,
    required bool Function() isSignedIn,
  }) : _api = api,
       _isSignedIn = isSignedIn;

  final CustomerReviewsApi _api;
  final String listingId;
  final bool Function() _isSignedIn;

  bool _disposed = false;
  bool _loading = false;
  bool _submitting = false;
  String? _message;
  ListingReviews? _reviews;
  MyReview? _mine;

  bool get loading => _loading;
  bool get submitting => _submitting;

  /// User-facing notice for the last failure, if any.
  String? get message => _message;
  ListingReviews? get reviews => _reviews;
  MyReview? get mine => _mine;

  Future<void> load() async {
    _loading = true;
    _message = null;
    _notify();
    try {
      _reviews = await _api.listingReviews(listingId);
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
    } catch (_) {
      _message = kSafeFailureDetails[kInternalError];
    }
    if (_isSignedIn()) {
      try {
        _mine = await _api.myReview(listingId);
      } catch (_) {
        // The public ratings still show; the form just stays unavailable.
        _mine = null;
      }
    } else {
      _mine = null;
    }
    _loading = false;
    _notify();
  }

  /// Saves the review. Returns true when it was accepted; otherwise [message]
  /// explains why and the caller keeps what the customer typed.
  Future<bool> submit({
    required int listingRating,
    required int agencyRating,
    String? comment,
  }) async {
    if (_submitting) return false;
    _submitting = true;
    _message = null;
    _notify();
    try {
      await _api.writeReview(
        listingId,
        listingRating: listingRating,
        agencyRating: agencyRating,
        comment: comment,
      );
    } on CustomerAuthFailure catch (failure) {
      _message = failure.statusCode == 403
          ? 'Todavía no podés calificar este inmueble.'
          : failure.detail;
      _submitting = false;
      _notify();
      return false;
    } catch (_) {
      _message = kSafeFailureDetails[kInternalError];
      _submitting = false;
      _notify();
      return false;
    }
    _submitting = false;
    await load();
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The agency's profile with all its reviews.
class AgencyReviewsController extends ChangeNotifier {
  AgencyReviewsController({
    required CustomerReviewsApi api,
    required this.agencyId,
  }) : _api = api;

  final CustomerReviewsApi _api;
  final String agencyId;

  bool _disposed = false;
  bool _loading = false;
  String? _message;
  AgencyReviews? _reviews;

  bool get loading => _loading;
  String? get message => _message;
  AgencyReviews? get reviews => _reviews;

  Future<void> load() async {
    _loading = true;
    _message = null;
    _notify();
    try {
      _reviews = await _api.agencyReviews(agencyId);
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
    } catch (_) {
      _message = kSafeFailureDetails[kInternalError];
    } finally {
      _loading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
