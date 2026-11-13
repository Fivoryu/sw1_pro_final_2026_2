import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/staff_notification.dart';
import '../data/services/staff_auth_api.dart';
import '../data/services/staff_notifications_api.dart';
import 'staff_chat_controller.dart' show canUseStaffChat, chatFailureMessage;
import 'staff_session_controller.dart';

/// The staff member's inbox and unread counter.
///
/// While the app is open the inbox refreshes on a timer (Firebase push is a
/// later delivery). It only runs for agency staff with a signed-in session:
/// [sync] starts or stops it from the session state.
class StaffNotificationsController extends ChangeNotifier {
  StaffNotificationsController({
    required StaffNotificationsApi api,
    required StaffSessionController session,
    this.pollInterval = const Duration(seconds: 30),
  }) : _api = api,
       _session = session;

  final StaffNotificationsApi _api;
  final StaffSessionController _session;
  final Duration pollInterval;

  Timer? _timer;
  bool _disposed = false;
  bool _stopped = false;
  bool _loading = false;
  int _unread = 0;
  String? _message;
  List<StaffNotification> _items = const [];

  int get unread => _unread;
  bool get loading => _loading;
  String? get message => _message;
  List<StaffNotification> get items => _items;

  /// Whether this session may have an inbox at all.
  bool get available =>
      _session.status == StaffSessionStatus.signedIn &&
      canUseStaffChat(_session.account);

  /// Starts polling for an eligible session and stops it otherwise.
  void sync() {
    if (available) {
      start();
    } else {
      stop();
    }
  }

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
    final token = _session.accessToken;
    if (token == null) return;
    _loading = !quiet;
    if (!quiet) _notify();
    try {
      final inbox = await _api.list(accessToken: token);
      if (_stopped) return;
      _items = inbox.items;
      _unread = inbox.unread;
      _message = null;
    } on StaffAuthFailure catch (failure) {
      if (!quiet) _message = chatFailureMessage(failure);
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> markRead(StaffNotification notification) async {
    final token = _session.accessToken;
    if (notification.read || token == null) return;
    try {
      await _api.markRead(accessToken: token, id: notification.id);
    } on StaffAuthFailure {
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
    final token = _session.accessToken;
    if (token == null) return;
    try {
      await _api.markAllRead(accessToken: token);
    } on StaffAuthFailure {
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
