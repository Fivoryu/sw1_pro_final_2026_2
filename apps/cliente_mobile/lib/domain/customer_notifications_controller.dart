import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/notification_models.dart';
import '../data/services/customer_auth_failure.dart';
import '../data/services/customer_notifications_api.dart';

/// The customer's inbox and its unread counter.
///
/// While the app is open the inbox is refreshed on a timer (Firebase push is a
/// later delivery): [start] begins polling, [stop] ends it and clears the
/// counter so a signed-out device never shows a stale badge.
class CustomerNotificationsController extends ChangeNotifier {
  CustomerNotificationsController({
    required CustomerNotificationsApi api,
    this.pollInterval = const Duration(seconds: 30),
  }) : _api = api;

  final CustomerNotificationsApi _api;
  final Duration pollInterval;

  Timer? _timer;
  bool _disposed = false;
  bool _stopped = false;
  bool _loading = false;
  int _unread = 0;
  String? _message;
  List<AppNotification> _items = const [];

  int get unread => _unread;
  bool get loading => _loading;
  String? get message => _message;
  List<AppNotification> get items => _items;

  /// Loads the inbox now and keeps it fresh until [stop] or dispose.
  Future<void> start() async {
    if (_timer != null || _disposed) return;
    _stopped = false;
    _timer = Timer.periodic(pollInterval, (_) => refresh(quiet: true));
    await refresh();
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    _unread = 0;
    _items = const [];
    _message = null;
    _notify();
  }

  Future<void> refresh({bool quiet = false}) async {
    if (_loading || _disposed) return;
    _loading = !quiet;
    if (!quiet) _notify();
    try {
      final inbox = await _api.list();
      if (_stopped) return; // stopped while the request was in flight
      _items = inbox.items;
      _unread = inbox.unread;
      _message = null;
    } on CustomerAuthFailure catch (failure) {
      if (!quiet) _message = failure.detail;
    } catch (_) {
      if (!quiet) _message = kSafeFailureDetails[kInternalError];
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (notification.read) return;
    try {
      await _api.markRead(notification.id);
    } catch (_) {
      return; // the next refresh shows the real state
    }
    _items = [
      for (final item in _items)
        item.id == notification.id ? item.asRead() : item,
    ];
    if (_unread > 0) _unread -= 1;
    _notify();
  }

  Future<void> markAllRead() async {
    try {
      await _api.markAllRead();
    } catch (_) {
      return;
    }
    _items = [for (final item in _items) item.asRead()];
    _unread = 0;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
