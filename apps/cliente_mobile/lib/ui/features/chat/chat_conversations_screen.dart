import 'package:flutter/material.dart';

import '../../../data/models/chat_models.dart';
import '../../../data/services/customer_chat_api.dart';
import '../../../domain/customer_chat_controller.dart';
import '../../theme/andean_theme.dart';
import 'chat_conversation_screen.dart';

/// The customer's conversations; each row shows the agency name only.
class ChatConversationsScreen extends StatefulWidget {
  const ChatConversationsScreen({super.key, required this.api});

  final CustomerChatApi api;

  @override
  State<ChatConversationsScreen> createState() =>
      _ChatConversationsScreenState();
}

class _ChatConversationsScreenState extends State<ChatConversationsScreen> {
  late final CustomerConversationsController _controller =
      CustomerConversationsController(api: widget.api);

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(ChatConversation conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChatConversationScreen(api: widget.api, conversation: conversation),
      ),
    );
    if (mounted) _controller.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mis conversaciones'),
      actions: [
        IconButton(
          key: const ValueKey('refresh-conversations'),
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
          onPressed: _controller.load,
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            if (_controller.loading && _controller.conversations.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              key: const ValueKey('conversations-content'),
              padding: const EdgeInsets.all(16),
              children: [
                if (_controller.message != null)
                  Text(
                    _controller.message!,
                    key: const ValueKey('conversations-error'),
                    style: AndeanTypography.bodyMd.copyWith(
                      color: AndeanColors.onErrorContainer,
                    ),
                  ),
                if (_controller.message == null &&
                    _controller.conversations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Todavía no iniciaste conversaciones. Abrí un inmueble y tocá "Chatear con la inmobiliaria".',
                      key: ValueKey('conversations-empty'),
                    ),
                  ),
                for (final conversation in _controller.conversations)
                  Card(
                    key: ValueKey('conversation-${conversation.id}'),
                    child: ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(conversation.agencyName),
                      subtitle: Text(
                        conversation.readOnly ? 'Solo lectura' : 'Abierta',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(conversation),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
