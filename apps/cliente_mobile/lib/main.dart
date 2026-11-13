import 'package:flutter/material.dart';

import 'data/services/catalog_api.dart';
import 'data/services/customer_booking_api.dart';
import 'data/services/customer_chat_api.dart';
import 'data/services/customer_notifications_api.dart';
import 'data/services/customer_reviews_api.dart';
import 'data/services/local_wallet_connect.dart';
import 'data/services/customer_auth_api.dart';
import 'data/services/customer_token_store.dart';
import 'data/services/quote_api.dart';
import 'data/services/scene_api.dart';
import 'domain/catalog_controller.dart';
import 'domain/customer_notifications_controller.dart';
import 'domain/customer_reservations_controller.dart';
import 'domain/customer_session_controller.dart';
import 'ui/features/auth/views/customer_account_screen.dart';
import 'ui/features/catalog/views/catalog_screen.dart';
import 'ui/features/notifications/notifications_screen.dart';
import 'ui/features/reservations/customer_reservations_screen.dart';

import 'ui/theme/andean_theme.dart';

/// Backend used by the running app. Override it per environment with
/// `--dart-define=ROOMFORGE_API_BASE_URL=https://host`.
const _apiBaseUrl = String.fromEnvironment(
  'ROOMFORGE_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

void main() => runApp(
  RoomForgeApp(
    sessionController: _customerSession,
    catalogApi: CatalogApi(baseUrl: _apiBaseUrl),
    bookingApi: CustomerBookingApi(
      baseUrl: _apiBaseUrl,
      accessTokenProvider: () => _customerSession.obtainAccessToken(),
    ),
    sceneApi: SceneApi(baseUrl: _apiBaseUrl),
    quoteApi: QuoteApi(baseUrl: _apiBaseUrl),
    chatApi: CustomerChatApi(
      baseUrl: _apiBaseUrl,
      accessTokenProvider: () => _customerSession.obtainAccessToken(),
    ),
    notificationsApi: CustomerNotificationsApi(
      baseUrl: _apiBaseUrl,
      accessTokenProvider: () => _customerSession.obtainAccessToken(),
    ),
    reviewsApi: CustomerReviewsApi(
      baseUrl: _apiBaseUrl,
      accessTokenProvider: () => _customerSession.obtainAccessToken(),
    ),
  ),
);

late final CustomerSessionController _customerSession =
    CustomerSessionController(
      api: CustomerAuthApi(baseUrl: _apiBaseUrl),
      tokenStore: SecureCustomerTokenStore(),
    );

class RoomForgeApp extends StatelessWidget {
  const RoomForgeApp({
    super.key,
    required this.sessionController,
    required this.catalogApi,
    this.bookingApi,
    this.sceneApi,
    this.quoteApi,
    this.chatApi,
    this.notificationsApi,
    this.reviewsApi,
  });

  final CustomerSessionController sessionController;
  final CatalogApi catalogApi;
  final CustomerBookingApi? bookingApi;
  final SceneApi? sceneApi;
  final QuoteApi? quoteApi;
  final CustomerChatApi? chatApi;
  final CustomerNotificationsApi? notificationsApi;
  final CustomerReviewsApi? reviewsApi;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RoomForge',
    theme: andeanTheme(),
    home: CustomerShell(
      sessionController: sessionController,
      catalogApi: catalogApi,
      bookingApi: bookingApi,
      sceneApi: sceneApi,
      quoteApi: quoteApi,
      chatApi: chatApi,
      notificationsApi: notificationsApi,
      reviewsApi: reviewsApi,
    ),
  );
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({
    super.key,
    required this.sessionController,
    required this.catalogApi,
    this.bookingApi,
    this.sceneApi,
    this.quoteApi,
    this.chatApi,
    this.notificationsApi,
    this.reviewsApi,
  });

  final CustomerSessionController sessionController;
  final CatalogApi catalogApi;
  final CustomerBookingApi? bookingApi;
  final SceneApi? sceneApi;
  final QuoteApi? quoteApi;
  final CustomerChatApi? chatApi;
  final CustomerNotificationsApi? notificationsApi;
  final CustomerReviewsApi? reviewsApi;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _selectedIndex = 0;
  late final _catalog = CatalogController(api: widget.catalogApi);
  late final _reservations = widget.bookingApi == null
      ? null
      : CustomerReservationsController(
          api: widget.bookingApi!,
          wallet: _walletConnect,
        );
  late final _walletConnect = LocalWalletConnect(context: context);
  late final _notifications = widget.notificationsApi == null
      ? null
      : CustomerNotificationsController(api: widget.notificationsApi!);

  @override
  void initState() {
    super.initState();
    widget.sessionController.addListener(_syncNotifications);
    widget.sessionController.restore();
  }

  /// The inbox only polls while a customer is signed in.
  void _syncNotifications() {
    final notifications = _notifications;
    if (notifications == null) return;
    if (widget.sessionController.status == CustomerSessionStatus.signedIn) {
      notifications.start();
    } else {
      notifications.stop();
    }
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(
          controller: _notifications!,
          chatApi: widget.chatApi,
          onOpenReservations: () => setState(() => _selectedIndex = 1),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.sessionController.removeListener(_syncNotifications);
    _notifications?.dispose();
    _catalog.dispose();
    _reservations?.dispose();
    _walletConnect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('RoomForge', style: AndeanTypography.headlineLg),
      titleSpacing: 20,
      toolbarHeight: 72,
      actions: [
        if (_notifications != null)
          ListenableBuilder(
            listenable: widget.sessionController,
            builder: (context, _) =>
                widget.sessionController.status ==
                    CustomerSessionStatus.signedIn
                ? NotificationsBell(
                    controller: _notifications,
                    onPressed: _openNotifications,
                  )
                : const SizedBox.shrink(),
          ),
      ],
    ),
    body: IndexedStack(
      index: _selectedIndex,
      children: [
        CatalogScreen(
          controller: _catalog,
          reservationsController: _reservations,
          sessionController: widget.sessionController,
          sceneApi: widget.sceneApi,
          quoteApi: widget.quoteApi,
          chatApi: widget.chatApi,
          reviewsApi: widget.reviewsApi,
        ),
        CustomerReservationsScreen(
          controller: _reservations,
          sessionController: widget.sessionController,
          chatApi: widget.chatApi,
        ),
        CustomerAccountScreen(
          controller: widget.sessionController,
          bookingApi: widget.bookingApi,
          walletConnect: widget.bookingApi == null ? null : _walletConnect,
        ),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      height: 76,
      elevation: 0,
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.explore_outlined),
          selectedIcon: Icon(Icons.explore),
          label: 'Explorar',
        ),
        NavigationDestination(
          icon: Icon(Icons.event_note_outlined),
          selectedIcon: Icon(Icons.event_note),
          label: 'Reservas',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Cuenta',
        ),
      ],
    ),
  );
}
