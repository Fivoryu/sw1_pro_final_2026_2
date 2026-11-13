import 'package:flutter/material.dart';

import '../../../data/models/notification_models.dart';
import '../../../data/services/customer_chat_api.dart';
import '../../../domain/customer_notifications_controller.dart';
import '../../theme/andean_theme.dart';
import '../chat/chat_conversation_screen.dart';

/// Wording of a notice. The API never sends text, so the customer can only
/// ever read the agency's name, never an agent's identity.
String notificationTitle(AppNotification notification) {
  switch (notification.kind) {
    case NotificationKind.chatMessage:
      return 'Nuevo mensaje de la inmobiliaria';
    case NotificationKind.reservationStatus:
      return switch (notification.detail) {
        'accepted' => 'Tu reserva fue aceptada',
        'rejected' => 'Tu reserva fue rechazada',
        'cancelled' => 'Tu reserva fue cancelada',
        'expired' => 'Tu reserva venció',
        _ => 'Tu reserva cambió de estado',
      };
    case NotificationKind.other:
      return 'Novedad en tu cuenta';
  }
}

/// Bell button with the unread counter; opens the inbox.
class NotificationsBell extends StatelessWidget {
  const NotificationsBell({
    super.key,
    required this.controller,
    required this.onPressed,
  });

  final CustomerNotificationsController controller;
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

/// The inbox. Tapping a notice marks it read and opens its destination: the
/// conversation, or the reservations tab through [onOpenReservations].
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.controller,
    this.chatApi,
    this.onOpenReservations,
  });

  final CustomerNotificationsController controller;
  final CustomerChatApi? chatApi;
  final VoidCallback? onOpenReservations;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? _openError;

  @override
  void initState() {
    super.initState();
    widget.controller.refresh();
  }

  Future<void> _open(AppNotification notification) async {
    setState(() => _openError = null);
    await widget.controller.markRead(notification);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (notification.kind == NotificationKind.reservationStatus) {
      widget.onOpenReservations?.call();
      navigator.pop();
      return;
    }
    final api = widget.chatApi;
    final conversationId = notification.conversationId;
    if (notification.kind != NotificationKind.chatMessage ||
        api == null ||
        conversationId == null) {
      return;
    }
    try {
      final conversations = await api.listConversations();
      final matches = conversations.where((c) => c.id == conversationId);
      if (!mounted) return;
      if (matches.isEmpty) {
        setState(() => _openError = 'No encontramos esa conversación.');
        return;
      }
      await navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              ChatConversationScreen(api: api, conversation: matches.first),
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
                    style: AndeanTypography.bodyMd.copyWith(
                      color: AndeanColors.onErrorContainer,
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
                        notification.kind == NotificationKind.chatMessage
                            ? Icons.chat_bubble_outline
                            : Icons.event_note_outlined,
                      ),
                      title: Text(
                        notificationTitle(notification),
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
