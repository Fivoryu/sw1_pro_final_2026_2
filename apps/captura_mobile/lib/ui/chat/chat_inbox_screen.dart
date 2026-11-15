import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/staff_chat.dart';
import '../../data/services/staff_chat_api.dart';
import '../../domain/staff_chat_controller.dart';
import '../../domain/staff_session_controller.dart';
import 'chat_conversation_screen.dart';
import 'chat_format.dart';

/// Inbox refresh period while the screen is visible.
const Duration kInboxPollInterval = Duration(seconds: 15);

/// The staff member's conversations with customers (F14.6).
class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({
    super.key,
    required this.controller,
    required this.api,
    required this.session,
  });

  final StaffInboxController controller;
  final StaffChatApi api;
  final StaffSessionController session;

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.controller.load();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(kInboxPollInterval, (_) {
      widget.controller.refresh();
    });
  }

  Future<void> _open(StaffConversation conversation) async {
    // Polling pauses while the conversation covers the inbox.
    _timer?.cancel();
    final notice = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ChatConversationScreen(
          controller: StaffConversationController(
            api: widget.api,
            session: widget.session,
            conversation: conversation,
          ),
        ),
      ),
    );
    if (!mounted) return;
    _startPolling();
    if (notice != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(key: const ValueKey('inbox-notice'), content: Text(notice)),
      );
    }
    await widget.controller.refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Conversaciones')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.state == ChatLoadState.loading) {
          return const Center(
            child: CircularProgressIndicator(key: ValueKey('inbox-loading')),
          );
        }
        if (controller.state == ChatLoadState.failed) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.message ?? '',
                    key: const ValueKey('inbox-error'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey('inbox-retry'),
                    onPressed: controller.load,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }
        final conversations = controller.conversations;
        return Column(
          children: [
            if (controller.message != null)
              Container(
                key: const ValueKey('inbox-banner'),
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: Text(controller.message!),
              ),
            Expanded(
              child: conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'Todavía no hay conversaciones.',
                        key: ValueKey('inbox-empty'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: conversations.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) => _ConversationTile(
                        conversation: conversations[index],
                        onTap: () => _open(conversations[index]),
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final StaffConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final last = conversation.lastMessageAt;
    return ListTile(
      key: ValueKey('conversation-${conversation.id}'),
      onTap: onTap,
      title: Text(conversation.customerEmail),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Inmueble ${conversation.listingId}'),
            Chip(
              label: Text(
                conversation.mine
                    ? 'Mía'
                    : conversation.status == ConversationStatus.unclaimed
                    ? 'Sin responder'
                    : 'De otro agente',
              ),
              visualDensity: VisualDensity.compact,
            ),
            if (conversation.readOnly)
              const Chip(
                label: Text('Solo lectura'),
                visualDensity: VisualDensity.compact,
              ),
            if (conversation.needsAdmin)
              const Chip(
                label: Text('Requiere administrador'),
                visualDensity: VisualDensity.compact,
              ),
            if (conversation.overdue)
              const Chip(
                label: Text('Atrasada'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
      trailing: Text(last == null ? '' : formatChatTime(last)),
    );
  }
}
