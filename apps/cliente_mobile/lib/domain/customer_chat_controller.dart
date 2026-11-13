import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/chat_models.dart';
import '../data/services/customer_auth_failure.dart';
import '../data/services/customer_chat_api.dart';

const _pageSize = 50;

/// One open conversation: loads the history, polls for new messages while it
/// is alive, sends text and reports the conversation to the agency.
///
/// Polling is the contract's transport (no websockets): the timer starts in
/// [start] and is cancelled in [dispose].
class CustomerChatController extends ChangeNotifier {
  CustomerChatController({
    required CustomerChatApi api,
    required ChatConversation conversation,
    this.pollInterval = const Duration(seconds: 3),
  }) : _api = api,
       _conversation = conversation,
       _readOnly = conversation.readOnly;

  final CustomerChatApi _api;
  final ChatConversation _conversation;
  final Duration pollInterval;

  Timer? _timer;
  bool _disposed = false;
  bool _polling = false;
  bool _loading = false;
  bool _sending = false;
  bool _readOnly;
  bool _blocked = false;
  bool _started = false;
  int _cursor = 0;
  String? _message;
  List<ChatMessage> _messages = const [];

  ChatConversation get conversation => _conversation;
  List<ChatMessage> get messages => _messages;
  bool get loading => _loading;
  bool get sending => _sending;

  /// The conversation no longer accepts customer messages.
  bool get readOnly => _readOnly;

  /// The agency blocked this customer; sending is impossible.
  bool get blocked => _blocked;
  bool get canSend => !_readOnly && !_blocked;

  /// User-facing notice for the last failure, if any.
  String? get message => _message;

  /// Loads the full history and starts polling.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _loading = true;
    _message = null;
    _notify();
    try {
      await _fetchNew(allPages: true);
    } on CustomerAuthFailure catch (failure) {
      _handleFailure(failure);
    } catch (_) {
      _message = kSafeFailureDetails[kInternalError];
    } finally {
      _loading = false;
      _notify();
    }
    if (_disposed) return;
    _timer = Timer.periodic(pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (_polling || _disposed || _sending) return;
    _polling = true;
    try {
      await _fetchNew(allPages: false);
      _message = null;
    } on CustomerAuthFailure catch (failure) {
      _handleFailure(failure);
    } catch (_) {
      // Keep the screen as it is; the next tick retries.
    } finally {
      _polling = false;
      _notify();
    }
  }

  Future<void> _fetchNew({required bool allPages}) async {
    while (true) {
      final page = await _api.listMessages(
        _conversation.id,
        after: _cursor,
        limit: _pageSize,
      );
      if (_disposed) return;
      _readOnly = page.readOnly;
      if (page.messages.isNotEmpty) {
        _cursor = page.messages.last.id;
        _merge(page.messages);
      }
      if (!allPages || page.messages.length < _pageSize) return;
    }
  }

  void _merge(List<ChatMessage> incoming) {
    final known = {for (final m in _messages) m.id};
    final fresh = incoming.where((m) => !known.contains(m.id)).toList();
    if (fresh.isEmpty) return;
    _messages = [..._messages, ...fresh]..sort((a, b) => a.id.compareTo(b.id));
  }

  void _handleFailure(CustomerAuthFailure failure) {
    if (failure.statusCode == 403) {
      _blocked = true;
      _message = 'La inmobiliaria no está aceptando mensajes de tu cuenta.';
    } else if (failure.statusCode == 409) {
      _readOnly = true;
      _message = null;
    } else {
      _message = failure.detail;
    }
  }

  /// Sends [text]. Returns true when it was accepted; on any failure the
  /// caller keeps the typed text so nothing is lost.
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !canSend || _sending) return false;
    _sending = true;
    _message = null;
    _notify();
    try {
      final sent = await _api.sendMessage(_conversation.id, trimmed);
      _merge([sent]);
      return true;
    } on CustomerAuthFailure catch (failure) {
      _handleFailure(failure);
      return false;
    } catch (_) {
      _message = kSafeFailureDetails[kInternalError];
      return false;
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// Reports the conversation to the agency. Returns true on success.
  Future<bool> report(String reason) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return false;
    _message = null;
    try {
      await _api.reportConversation(_conversation.id, trimmed);
      return true;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      _notify();
      return false;
    } catch (_) {
      _message = kSafeFailureDetails[kInternalError];
      _notify();
      return false;
    }
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

/// The customer's conversations, one row per listing.
class CustomerConversationsController extends ChangeNotifier {
  CustomerConversationsController({required CustomerChatApi api}) : _api = api;

  final CustomerChatApi _api;
  bool _loading = false;
  String? _message;
  List<ChatConversation> _conversations = const [];

  bool get loading => _loading;
  String? get message => _message;
  List<ChatConversation> get conversations => _conversations;

  Future<void> load() async {
    _loading = true;
    _message = null;
    notifyListeners();
    try {
      _conversations = await _api.listConversations();
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
    } catch (_) {
      _message = kSafeFailureDetails[kInternalError];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
