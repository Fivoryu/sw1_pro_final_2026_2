import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/staff_chat.dart';
import '../../domain/staff_chat_controller.dart';
import 'chat_format.dart';

/// Message refresh period while a conversation is open.
const Duration kConversationPollInterval = Duration(seconds: 3);

/// One conversation with a customer (F14.6).
///
/// Pops with a notice string when the conversation must leave the inbox
/// (another agent took it, or it is no longer visible).
class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({super.key, required this.controller});

  final StaffConversationController controller;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _input = TextEditingController();
  Timer? _timer;
  bool _leaving = false;

  StaffConversationController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_checkLeave);
    _controller.load();
    if (_controller.isAdmin) _controller.loadAgents();
    _timer = Timer.periodic(kConversationPollInterval, (_) {
      _controller.poll();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.removeListener(_checkLeave);
    _input.dispose();
    super.dispose();
  }

  void _checkLeave() {
    if (_leaving || !mounted) return;
    if (_controller.taken) {
      _leave('Otro agente ya tomó esa conversación.');
    } else if (_controller.unavailable) {
      _leave('La conversación ya no está disponible.');
    }
  }

  void _leave(String notice) {
    _leaving = true;
    _timer?.cancel();
    // Defer: the listener fires inside a build-adjacent notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(notice);
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    final sent = await _controller.send(text);
    if (sent) _input.clear();
  }

  Future<void> _report() async {
    final reason = await _askText(
      title: 'Reportar al cliente',
      hint: 'Motivo del reporte',
      action: 'Reportar',
      fieldKey: const ValueKey('report-reason'),
    );
    if (reason == null || !mounted) return;
    final ok = await _controller.reportCustomer(reason);
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reporte enviado a la agencia.')),
    );
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    required String action,
    required Key fieldKey,
  }) {
    final field = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: fieldKey,
          controller: field,
          maxLength: 2000,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('report-confirm'),
            onPressed: () {
              final value = field.text.trim();
              Navigator.of(context).pop(value.isEmpty ? null : value);
            },
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<void> _reassign() async {
    // An empty id is the "automatic" choice; a dismissal returns null.
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Reasignar conversación'),
        children: [
          SimpleDialogOption(
            key: const ValueKey('reassign-auto'),
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Automático (menos conversaciones)'),
          ),
          for (final agent in _controller.agents)
            SimpleDialogOption(
              key: ValueKey('reassign-${agent.id}'),
              onPressed: () => Navigator.of(context).pop(agent.id),
              child: Text(agent.email),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final ok = await _controller.reassign(
      agentId: choice.isEmpty ? null : choice,
    );
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Conversación reasignada.')));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final conversation = _controller.conversation;
      return Scaffold(
        appBar: AppBar(
          title: Text(conversation.customerEmail),
          actions: [
            if (_controller.isAdmin)
              IconButton(
                key: const ValueKey('reassign-action'),
                tooltip: 'Reasignar',
                icon: const Icon(Icons.swap_horiz),
                onPressed: _reassign,
              ),
            IconButton(
              key: const ValueKey('report-action'),
              tooltip: 'Reportar cliente',
              icon: const Icon(Icons.flag_outlined),
              onPressed: _report,
            ),
          ],
        ),
        body: SafeArea(child: _body(context)),
      );
    },
  );

  Widget _body(BuildContext context) {
    if (_controller.state == ChatLoadState.loading) {
      return const Center(
        child: CircularProgressIndicator(key: ValueKey('conversation-loading')),
      );
    }
    if (_controller.state == ChatLoadState.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _controller.message ?? '',
                key: const ValueKey('conversation-error'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('conversation-retry'),
                onPressed: _controller.load,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    final messages = _controller.messages;
    return Column(
      children: [
        if (_controller.message != null)
          Container(
            key: const ValueKey('conversation-notice'),
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(12),
            child: Text(_controller.message!),
          ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(12),
            itemCount: messages.length,
            itemBuilder: (context, index) =>
                _Bubble(message: messages[messages.length - 1 - index]),
          ),
        ),
        _composer(),
      ],
    );
  }

  Widget _composer() {
    if (_controller.readOnly) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Esta conversación es de solo lectura.',
          key: ValueKey('conversation-read-only'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('conversation-input'),
              controller: _input,
              maxLength: 2000,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Escribí tu respuesta',
                counterText: '',
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('conversation-send'),
            tooltip: 'Enviar',
            icon: const Icon(Icons.send),
            onPressed: _controller.sending ? null : _send,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final StaffChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final author = message.authorEmail;
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('message-${message.id}'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: message.mine
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (author != null)
              Text(
                author,
                key: ValueKey('message-author-${message.id}'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            Text(message.body),
            Text(
              '${_senderLabel(message.sender)} · '
              '${formatChatTime(message.createdAt)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _senderLabel(ChatSender sender) => switch (sender) {
    ChatSender.customer => 'Cliente',
    ChatSender.agent => 'Agente',
    ChatSender.admin => 'Administrador',
  };
}
