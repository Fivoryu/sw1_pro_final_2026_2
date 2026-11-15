import 'package:flutter/foundation.dart';

import '../data/models/staff_review.dart';
import '../data/services/staff_auth_api.dart';
import '../data/services/staff_reviews_api.dart';
import 'staff_chat_controller.dart' show chatFailureMessage;
import 'staff_session_controller.dart';

/// Spanish, user-facing text for a failed review call.
String reviewFailureMessage(StaffAuthFailure failure) {
  if (failure.statusCode == 409) {
    return failure.detail.contains('open report')
        ? 'Esta reseña ya tiene un reporte abierto.'
        : 'Esta reseña ya tiene una respuesta.';
  }
  if (failure.statusCode == 404) return 'La reseña ya no está disponible.';
  return chatFailureMessage(failure);
}

enum ReviewsLoadState { loading, ready, failed }

/// The agency's reviews. Agents only read them; agency administrators also
/// answer once per review and report the ones that break the rules.
class StaffReviewsController extends ChangeNotifier {
  StaffReviewsController({
    required StaffReviewsApi api,
    required StaffSessionController session,
  }) : _api = api,
       _session = session;

  final StaffReviewsApi _api;
  final StaffSessionController _session;

  bool _disposed = false;
  ReviewsLoadState _state = ReviewsLoadState.loading;
  String? _message;
  StaffReviewList? _list;

  ReviewsLoadState get state => _state;
  String? get message => _message;
  StaffReviewList? get list => _list;

  /// Only agency administrators can reply and report.
  bool get canModerate => _session.account?.role == 'agency_admin';

  Future<void> load() async {
    final token = _session.accessToken;
    if (token == null) {
      _state = ReviewsLoadState.failed;
      _message = 'Tu sesión expiró. Cerrá sesión y volvé a ingresar.';
      _notify();
      return;
    }
    _state = ReviewsLoadState.loading;
    _message = null;
    _notify();
    try {
      _list = await _api.list(accessToken: token);
      _state = ReviewsLoadState.ready;
    } on StaffAuthFailure catch (failure) {
      _state = ReviewsLoadState.failed;
      _message = reviewFailureMessage(failure);
    }
    _notify();
  }

  /// Returns true when the reply was recorded.
  Future<bool> reply(StaffReview review, String text) async {
    final body = text.trim();
    final token = _session.accessToken;
    if (body.isEmpty || token == null || !canModerate) return false;
    try {
      await _api.reply(accessToken: token, reviewId: review.id, body: body);
    } on StaffAuthFailure catch (failure) {
      _message = reviewFailureMessage(failure);
      _notify();
      return false;
    }
    _replace(review.withReply(body));
    return true;
  }

  /// Returns true when the report was filed.
  Future<bool> report(StaffReview review, String reason) async {
    final body = reason.trim();
    final token = _session.accessToken;
    if (body.isEmpty || token == null || !canModerate) return false;
    try {
      await _api.report(accessToken: token, reviewId: review.id, reason: body);
    } on StaffAuthFailure catch (failure) {
      _message = reviewFailureMessage(failure);
      _notify();
      return false;
    }
    _replace(review.asReported());
    return true;
  }

  void _replace(StaffReview updated) {
    final current = _list;
    if (current != null) {
      _list = StaffReviewList(
        summary: current.summary,
        reviews: [
          for (final item in current.reviews)
            item.id == updated.id ? updated : item,
        ],
      );
    }
    _message = null;
    _notify();
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
