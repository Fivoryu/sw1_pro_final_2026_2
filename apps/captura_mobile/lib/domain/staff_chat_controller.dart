import 'package:flutter/foundation.dart';

import '../data/models/staff_chat.dart';
import '../data/services/staff_auth_api.dart';
import '../data/services/staff_chat_api.dart';
import 'staff_session_controller.dart';

/// Staff roles that can use the agency chat.
bool canUseStaffChat(StaffAccount? account) =>
    account != null &&
    (account.role == 'agent' || account.role == 'agency_admin');

/// Spanish, user-facing text for a failed chat call.
String chatFailureMessage(StaffAuthFailure failure) {
  if (failure.isNetworkFailure) return failure.detail;
  return switch (failure.statusCode) {
    401 => 'Tu sesión expiró. Cerrá sesión y volvé a ingresar.',
    403 => 'Tu cuenta no tiene permisos para esta conversación.',
    404 => 'La conversación ya no está disponible.',
    409 when failure.detail.contains('already taken') =>
      'Otro agente ya tomó esta conversación.',
    409 => 'La conversación es de solo lectura.',
    422 => 'Revisá los datos enviados.',
    _ => 'Ocurrió un error inesperado. Intentá de nuevo.',
  };
}

enum ChatLoadState { loading, ready, failed }

/// Owns the agent's inbox: conversations visible to this staff member.
///
/// The screen calls [refresh] on a timer; a failed refresh keeps the last list.
class StaffInboxController extends ChangeNotifier {
  StaffInboxController({
    required StaffChatApi api,
    required StaffSessionController session,
  }) : _api = api,
       _session = session;

  final StaffChatApi _api;
  final StaffSessionController _session;

  ChatLoadState _state = ChatLoadState.loading;
  List<StaffConversation> _conversations = const [];
  String? _message;
  bool _refreshing = false;

  ChatLoadState get state => _state;
  List<StaffConversation> get conversations => _conversations;
  String? get message => _message;

  /// First load: shows the loading state.
  Future<void> load() async {
    _state = ChatLoadState.loading;
    _message = null;
    notifyListeners();
    await _fetch();
  }

  /// Background refresh: keeps the current list while the request runs.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _fetch();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _fetch() async {
    final token = _session.accessToken;
    if (token == null) {
      _fail('Tu sesión expiró. Cerrá sesión y volvé a ingresar.');
      return;
    }
    try {
      _conversations = await _api.listConversations(accessToken: token);
      _state = ChatLoadState.ready;
      _message = null;
      notifyListeners();
    } on StaffAuthFailure catch (failure) {
      _fail(chatFailureMessage(failure));
    }
  }

  void _fail(String message) {
    // Keep the last known list so a transient failure does not blank the inbox.
    if (_state != ChatLoadState.ready) _state = ChatLoadState.failed;
    _message = message;
    notifyListeners();
  }
}

/// Owns one open conversation: history, polling, sending, claiming and the
/// admin actions.
class StaffConversationController extends ChangeNotifier {
  StaffConversationController({
    required StaffChatApi api,
    required StaffSessionController session,
    required StaffConversation conversation,
  }) : _api = api,
       _session = session,
       _conversation = conversation,
       _readOnly = conversation.readOnly;

  final StaffChatApi _api;
  final StaffSessionController _session;

  StaffConversation _conversation;
  bool _readOnly;
  final List<StaffChatMessage> _messages = [];
  ChatLoadState _state = ChatLoadState.loading;
  bool _sending = false;
  bool _taken = false;
  bool _unavailable = false;
  bool _polling = false;
  String? _message;
  List<ChatAgent> _agents = const [];

  StaffConversation get conversation => _conversation;
  List<StaffChatMessage> get messages => List.unmodifiable(_messages);
  ChatLoadState get state => _state;
  bool get readOnly => _readOnly;
  bool get sending => _sending;

  /// Another agent answered first: the screen must return to the inbox.
  bool get taken => _taken;

  /// The conversation is no longer visible to this staff member.
  bool get unavailable => _unavailable;

  String? get message => _message;
  List<ChatAgent> get agents => _agents;
  bool get isAdmin => _session.account?.role == 'agency_admin';

  int get _lastId => _messages.isEmpty ? 0 : _messages.last.id;

  /// Loads the full history.
  Future<void> load() async {
    _state = ChatLoadState.loading;
    _message = null;
    notifyListeners();
    final token = _session.accessToken;
    if (token == null) {
      _failLoad('Tu sesión expiró. Cerrá sesión y volvé a ingresar.');
      return;
    }
    try {
      final page = await _api.listMessages(
        accessToken: token,
        conversationId: _conversation.id,
      );
      _messages
        ..clear()
        ..addAll(page.messages);
      _readOnly = page.readOnly;
      _state = ChatLoadState.ready;
      notifyListeners();
    } on StaffAuthFailure catch (failure) {
      if (failure.statusCode == 404) _unavailable = true;
      _failLoad(chatFailureMessage(failure));
    }
  }

  /// Fetches messages after the last known id and appends only the new ones.
  Future<void> poll() async {
    final token = _session.accessToken;
    if (_polling || token == null || _state != ChatLoadState.ready) return;
    _polling = true;
    try {
      final page = await _api.listMessages(
        accessToken: token,
        conversationId: _conversation.id,
        after: _lastId,
      );
      var changed = page.readOnly != _readOnly;
      _readOnly = page.readOnly;
      for (final incoming in page.messages) {
        if (incoming.id > _lastId) {
          _messages.add(incoming);
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } on StaffAuthFailure catch (failure) {
      // The conversation vanished (another agent took it, or it was
      // reassigned): stop polling and let the screen leave.
      if (failure.statusCode == 404) {
        _unavailable = true;
        _message = chatFailureMessage(failure);
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  /// Sends [body]; returns true when the message was accepted.
  ///
  /// Answering an unclaimed conversation claims it for this agent.
  Future<bool> send(String body) async {
    final text = body.trim();
    final token = _session.accessToken;
    if (text.isEmpty || _sending || _readOnly || token == null) return false;
    _sending = true;
    _message = null;
    notifyListeners();
    try {
      final sent = await _api.sendMessage(
        accessToken: token,
        conversationId: _conversation.id,
        body: text,
      );
      if (sent.id > _lastId) _messages.add(sent);
      if (_conversation.status == ConversationStatus.unclaimed) {
        _conversation = _conversation.copyWith(
          status: ConversationStatus.claimed,
          mine: true,
        );
      }
      return true;
    } on StaffAuthFailure catch (failure) {
      _message = chatFailureMessage(failure);
      if (failure.statusCode == 409) {
        if (failure.detail.contains('already taken')) {
          _taken = true;
        } else {
          _readOnly = true;
        }
      }
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Loads the agency's agents for the reassignment picker (admin only).
  Future<void> loadAgents() async {
    final token = _session.accessToken;
    if (!isAdmin || token == null) return;
    try {
      _agents = [
        for (final agent in await _api.listAgents(accessToken: token))
          if (agent.active) agent,
      ];
    } on StaffAuthFailure catch (failure) {
      _message = chatFailureMessage(failure);
    }
    notifyListeners();
  }

  /// Reassigns the conversation (admin); null agent means automatic.
  Future<bool> reassign({String? agentId}) async {
    final token = _session.accessToken;
    if (!isAdmin || token == null) return false;
    try {
      _conversation = await _api.reassign(
        accessToken: token,
        conversationId: _conversation.id,
        agentId: agentId,
      );
      _message = null;
      notifyListeners();
      return true;
    } on StaffAuthFailure catch (failure) {
      _message = chatFailureMessage(failure);
      notifyListeners();
      return false;
    }
  }

  /// Reports the customer to the agency admin and the platform.
  Future<bool> reportCustomer(String reason) async {
    final token = _session.accessToken;
    final text = reason.trim();
    if (token == null || text.isEmpty) return false;
    try {
      await _api.reportCustomer(
        accessToken: token,
        conversationId: _conversation.id,
        reason: text,
      );
      _message = null;
      return true;
    } on StaffAuthFailure catch (failure) {
      _message = chatFailureMessage(failure);
      return false;
    } finally {
      notifyListeners();
    }
  }

  void _failLoad(String message) {
    _state = ChatLoadState.failed;
    _message = message;
    notifyListeners();
  }
}
