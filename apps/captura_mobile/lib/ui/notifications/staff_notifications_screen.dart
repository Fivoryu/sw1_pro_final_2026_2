import 'package:flutter/material.dart';

import '../../data/models/staff_notification.dart';
import '../../data/services/staff_chat_api.dart';
import '../../domain/staff_chat_controller.dart';
import '../../domain/staff_notifications_controller.dart';
import '../../domain/staff_session_controller.dart';
import '../chat/chat_conversation_screen.dart';

/// Wording of a notice. The API sends ids and a kind only.
String staffNotificationTitle(StaffNotification notification) {
  switch (notification.kind) {
    case StaffNotificationKind.chatMessage:
      return 'Nuevo mensaje de un cliente';
    case StaffNotificationKind.chatAssigned:
      return 'Te asignaron una conversación';
    case StaffNotificationKind.chatNeedsAdmin:
      return 'Una conversación quedó sin agente disponible';
    case StaffNotificationKind.chatOverdue:
      return 'Una conversación lleva más de 24 h sin respuesta';
    case StaffNotificationKind.reservationStatus:
      return switch (notification.detail) {
        'accepted' => 'Una reserva fue aceptada',
        'rejected' => 'Una reserva fue rechazada',
        'cancelled' => 'Una reserva fue cancelada',
        'expired' => 'Una reserva venció',
        _ => 'Una reserva cambió de estado',
      };
    case StaffNotificationKind.other:
      return 'Novedad en tu cuenta';
  }
}

/// Bell button with the unread counter; opens the inbox.
class StaffNotificationsBell extends StatelessWidget {
  const StaffNotificationsBell({
    super.key,
    required this.controller,
    required this.onPressed,
  });

  final StaffNotificationsController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => IconButton(
      key: const ValueKey('notifications-bell'),
      tooltip: controller.unread == 0
          ? 'Notificaciones'
          : 'Notificaciones, ${controller.unread} sin leer',
      onPressed: onPressed,
      icon: Badge(
        key: const ValueKey('notifications-badge'),
        isLabelVisible: controller.unread > 0,
        label: Text('${controller.unread}'),
        child: const Icon(Icons.notifications_none),
      ),
    ),
  );
}

/// The inbox. Tapping a notice marks it read and, when it points at a
/// conversation, opens it.
class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({
    super.key,
    required this.controller,
    required this.chatApi,
    required this.session,
  });

  final StaffNotificationsController controller;
  final StaffChatApi chatApi;
  final StaffSessionController session;

  @override
  State<StaffNotificationsScreen> createState() =>
      _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen> {
  String? _openError;

  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  Future<void> _open(StaffNotification notification) async {
    setState(() => _openError = null);
    await widget.controller.markRead(notification);
    final conversationId = notification.conversationId;
    final token = widget.session.accessToken;
    if (!mounted || conversationId == null || token == null) return;
    final navigator = Navigator.of(context);
    try {
      final conversations = await widget.chatApi.listConversations(
        accessToken: token,
      );
      final matches = conversations.where((c) => c.id == conversationId);
      if (!mounted) return;
      if (matches.isEmpty) {
        setState(() => _openError = 'Esa conversación ya no está disponible.');
        return;
      }
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChatConversationScreen(
            controller: StaffConversationController(
              api: widget.chatApi,
              session: widget.session,
              conversation: matches.first,
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _openError = 'No pudimos abrir la conversación.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Notificaciones'),
      actions: [
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => TextButton(
            key: const ValueKey('notifications-read-all'),
            onPressed: widget.controller.unread == 0
                ? null
                : widget.controller.markAllRead,
            child: const Text('Marcar todo como leído'),
          ),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final controller = widget.controller;
            if (controller.loading && controller.items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              key: const ValueKey('notifications-content'),
              padding: const EdgeInsets.all(16),
              children: [
                if (controller.message != null || _openError != null)
                  Text(
                    controller.message ?? _openError!,
                    key: const ValueKey('notifications-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (controller.message == null && controller.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No tenés notificaciones.',
                      key: ValueKey('notifications-empty'),
                    ),
                  ),
                for (final notification in controller.items)
                  Card(
                    key: ValueKey('notification-${notification.id}'),
                    child: ListTile(
                      leading: Icon(
                        notification.opensConversation
                            ? Icons.chat_bubble_outline
                            : Icons.event_note_outlined,
                      ),
                      title: Text(
                        staffNotificationTitle(notification),
                        style: notification.read
                            ? null
                            : const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        notification.createdAt.toLocal().toString().substring(
                          0,
                          16,
                        ),
                      ),
                      trailing: notification.read
                          ? null
                          : const Icon(Icons.circle, size: 10),
                      onTap: () => _open(notification),
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
