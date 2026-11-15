import 'package:flutter/material.dart';

import '../../../data/models/chat_models.dart';
import '../../../data/services/customer_auth_failure.dart';
import '../../../data/services/customer_chat_api.dart';
import '../../../domain/customer_chat_controller.dart';
import '../../theme/andean_theme.dart';

/// Opens (or recovers) the customer's conversation for [listingId] and shows
/// it. Returns the failure text when it could not be opened, otherwise null.
Future<String?> openListingChat(
  BuildContext context, {
  required CustomerChatApi api,
  required String listingId,
}) async {
  final navigator = Navigator.of(context);
  final ChatConversation conversation;
  try {
    conversation = await api.openConversation(listingId);
  } on CustomerAuthFailure catch (failure) {
    return failure.statusCode == 403
        ? 'La inmobiliaria no está aceptando mensajes de tu cuenta.'
        : failure.detail;
  } catch (_) {
    return 'No pudimos abrir el chat. Iniciá sesión e intentá de nuevo.';
  }
  await navigator.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChatConversationScreen(api: api, conversation: conversation),
    ),
  );
  return null;
}

/// One conversation with an agency. Only the agency name is shown: replies
/// never identify the agent who wrote them.
class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({
    super.key,
    required this.api,
    required this.conversation,
    this.pollInterval = const Duration(seconds: 3),
  });

  final CustomerChatApi api;
  final ChatConversation conversation;
  final Duration pollInterval;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  late final CustomerChatController _controller = CustomerChatController(
    api: widget.api,
    conversation: widget.conversation,
    pollInterval: widget.pollInterval,
  );
  final TextEditingController _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    final sent = await _controller.send(text);
    // A failed send keeps the typed text so the customer can retry.
    if (sent && mounted && _input.text == text) _input.clear();
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReportDialog(),
    );
    if (reason == null || !mounted) return;
    final ok = await _controller.report(reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Reporte enviado a la inmobiliaria.'
              : (_controller.message ?? 'No se pudo enviar el reporte.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.conversation.agencyName),
      actions: [
        IconButton(
          key: const ValueKey('chat-report'),
          tooltip: 'Reportar conversación',
          icon: const Icon(Icons.flag_outlined),
          onPressed: _report,
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            children: [
              Expanded(child: _messages(context)),
              if (_controller.message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Text(
                    _controller.message!,
                    key: const ValueKey('chat-error'),
                    style: AndeanTypography.bodySm.copyWith(
                      color: AndeanColors.onErrorContainer,
                    ),
                  ),
                ),
              _composer(context),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _messages(BuildContext context) {
    if (_controller.loading && _controller.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _controller.messages.reversed.toList(growable: false);
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no hay mensajes. Escribí tu consulta a la inmobiliaria.',
            key: ValueKey('chat-empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('chat-messages'),
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) => _bubble(context, items[index]),
    );
  }

  Widget _bubble(BuildContext context, ChatMessage message) {
    final mine = message.sender == ChatSender.customer;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('chat-message-${message.id}'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: mine
              ? AndeanColors.primaryContainer
              : AndeanColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              mine ? 'Vos' : widget.conversation.agencyName,
              style: AndeanTypography.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: mine ? Colors.white : AndeanColors.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message.body,
              style: TextStyle(color: mine ? Colors.white : null),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    if (!_controller.canSend) {
      return Container(
        key: const ValueKey('chat-read-only'),
        width: double.infinity,
        color: AndeanColors.surfaceContainer,
        padding: const EdgeInsets.all(16),
        child: Text(
          _controller.blocked
              ? 'La inmobiliaria no está aceptando mensajes de tu cuenta.'
              : 'Esta conversación es de solo lectura: el inmueble ya no está disponible para consultas.',
          style: AndeanTypography.bodySm,
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('chat-input'),
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Escribí un mensaje',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('chat-send'),
              tooltip: 'Enviar',
              onPressed: _controller.sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Reportar conversación'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'El reporte llega a la inmobiliaria, que revisará lo ocurrido.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('chat-report-reason'),
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          maxLength: 2000,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Motivo',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Volver'),
      ),
      FilledButton(
        key: const ValueKey('chat-report-submit'),
        onPressed: _reason.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _reason.text.trim()),
        child: const Text('Enviar reporte'),
      ),
    ],
  );
}
