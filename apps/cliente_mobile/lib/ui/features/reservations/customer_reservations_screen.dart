import 'package:flutter/material.dart';

import '../../../../data/models/reservation_models.dart';
import '../../../../domain/customer_reservations_controller.dart';
import '../../../../domain/customer_session_controller.dart';
import '../../theme/andean_theme.dart';
import '../../theme/andean_widgets.dart';

class CustomerReservationsScreen extends StatefulWidget {
  const CustomerReservationsScreen({
    super.key,
    required this.controller,
    required this.sessionController,
  });

  final CustomerReservationsController? controller;
  final CustomerSessionController sessionController;

  @override
  State<CustomerReservationsScreen> createState() =>
      _CustomerReservationsScreenState();
}

class _CustomerReservationsScreenState
    extends State<CustomerReservationsScreen> {
  bool _requestedInitialLoad = false;

  @override
  void initState() {
    super.initState();
    widget.sessionController.addListener(_sessionChanged);
    _sessionChanged();
  }

  @override
  void dispose() {
    widget.sessionController.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (!_requestedInitialLoad &&
        widget.sessionController.status == CustomerSessionStatus.signedIn &&
        widget.controller != null) {
      _requestedInitialLoad = true;
      widget.controller!.loadReservations();
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListenableBuilder(
        listenable: widget.sessionController,
        builder: (context, _) {
          final session = widget.sessionController.status;
          if (session == CustomerSessionStatus.restoring) {
            return const Center(child: CircularProgressIndicator());
          }
          if (session != CustomerSessionStatus.signedIn) {
            return _message(
              context,
              'Iniciá sesión para consultar tus reservas.',
              key: const ValueKey('reservations-sign-in-required'),
            );
          }
          final controller = widget.controller;
          if (controller == null) {
            return _message(
              context,
              'El servicio de reservas no está configurado.',
              key: const ValueKey('reservations-unavailable'),
            );
          }
          return ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _content(context, controller),
          );
        },
      ),
    ),
  );

  Widget _content(
    BuildContext context,
    CustomerReservationsController controller,
  ) => ListView(
    key: const ValueKey('customer-reservations-content'),
    padding: const EdgeInsets.all(20),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Mis reservas',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          IconButton(
            key: const ValueKey('refresh-reservations'),
            tooltip: 'Actualizar',
            onPressed: controller.busy ? null : controller.loadReservations,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const AndeanNoticeBanner(
        title: 'ENTORNO INSTITUCIONAL',
        badge: 'Hardhat 31337',
        icon: Icons.terminal,
        message:
            'Red de Pruebas Hardhat (Chain 31337) · Fondos y tokens RFT de prueba local. No se custodia moneda fiduciaria ni se realiza compraventa final dentro de la app.',
      ),
      const SizedBox(height: 12),
      if (controller.busy && controller.reservations.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (controller.message != null)
        Card(
          color: AndeanColors.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              controller.message!,
              key: const ValueKey('reservations-error'),
              style: AndeanTypography.bodyMd.copyWith(
                color: AndeanColors.onErrorContainer,
              ),
            ),
          ),
        ),
      if (!controller.busy &&
          controller.message == null &&
          controller.reservations.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Todavía no tenés reservas. Explorá un inmueble y solicitá una reserva para verla acá.',
            key: ValueKey('reservations-empty'),
          ),
        ),
      for (final reservation in controller.reservations)
        _reservationCard(context, reservation, controller),
    ],
  );

  Widget _reservationCard(
    BuildContext context,
    ReservationRecord item,
    CustomerReservationsController controller,
  ) {
    final snapshot = item.quoteSnapshot;
    final currency = snapshot.lines.isEmpty
        ? snapshot.oneTimeTotal.currency
        : snapshot.lines.first.currency;
    final isCardPayment = item.paymentMethod == 'card';
    final deposit = item.depositAmount == null
        ? 'Sin depósito configurado'
        : 'Depósito: ${item.depositAmount} $currency';

    final (statusBg, statusFg) = switch (item.status) {
      'pending' => (AndeanColors.warningBg, AndeanColors.warningText),
      'accepted' => (AndeanColors.successBg, AndeanColors.successText),
      'cancelled' => (AndeanColors.criticalBg, AndeanColors.criticalText),
      'rejected' => (AndeanColors.criticalBg, AndeanColors.criticalText),
      _ => (AndeanColors.surfaceContainerHigh, AndeanColors.onSurface),
    };

    return Card(
      key: ValueKey('reservation-${item.reservationId}'),
      margin: const EdgeInsets.only(top: 14),
      color: AndeanColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AndeanColors.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Reserva ${item.reservationId}',
                    style: AndeanTypography.headlineSm.copyWith(fontSize: 17),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    _statusLabel(item.status),
                    style: AndeanTypography.labelSm.copyWith(
                      color: statusFg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Inmueble ${item.listingId} · oferta v${snapshot.offerVersion}',
              style: AndeanTypography.bodySm,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AndeanColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (snapshot.oneTimeTotal.amount != '0.00') ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Pago único:',
                          style: AndeanTypography.bodySm,
                        ),
                        Text(
                          '${snapshot.oneTimeTotal.amount} ${snapshot.oneTimeTotal.currency}',
                          style: AndeanTypography.monoData.copyWith(
                            color: AndeanColors.primaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (snapshot.monthlyTotal.amount != '0.00') ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Mensual:', style: AndeanTypography.bodySm),
                        Text(
                          '${snapshot.monthlyTotal.amount} ${snapshot.monthlyTotal.currency}',
                          style: AndeanTypography.monoData.copyWith(
                            color: AndeanColors.primaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isCardPayment
                            ? 'Depósito con tarjeta:'
                            : 'Depósito en Escrow:',
                        style: AndeanTypography.bodySm,
                      ),
                      Text(
                        deposit,
                        style: AndeanTypography.monoData.copyWith(
                          color: AndeanColors.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Plazo de respuesta: ${item.decisionDeadlineAt.toLocal()}',
              style: AndeanTypography.bodySm,
            ),
            if (item.status == 'pending')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AndeanColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AndeanColors.secondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isCardPayment
                              ? item.depositConfirmedAt == null
                                    ? 'Pago pendiente. Stripe confirmará el depósito cuando el servidor reciba y valide el webhook.'
                                    : 'Pago con tarjeta confirmado por Stripe; aguardá la decisión de la inmobiliaria.'
                              : item.depositConfirmedAt == null
                              ? 'Pendiente no significa depósito confirmado. La confirmación requiere verificar la transacción en la red local.'
                              : 'Depósito local confirmado; aguardá la decisión de la inmobiliaria.',
                          style: AndeanTypography.bodySm,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (item.status == 'pending') ...[
              const SizedBox(height: 12),
              if (item.depositAmount != null &&
                  (isCardPayment || item.depositConfirmedAt != null) &&
                  !item.decisionDeadlineAt.isAfter(DateTime.now().toUtc()))
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    key: ValueKey('expire-${item.reservationId}'),
                    onPressed: controller.busy
                        ? null
                        : () => _confirmExpiration(
                            context,
                            controller,
                            item,
                            currency,
                          ),
                    icon: const Icon(Icons.timer_off_outlined),
                    label: const Text('Solicitar reembolso por vencimiento'),
                  ),
                ),
              if (item.depositAmount != null &&
                  item.decisionDeadlineAt.isAfter(DateTime.now().toUtc()) &&
                  (item.depositConfirmedAt == null))
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    key: ValueKey('deposit-${item.reservationId}'),
                    onPressed: controller.busy
                        ? null
                        : isCardPayment
                        ? () => controller.payCardReservation(item)
                        : () => _confirmDeposit(
                            context,
                            controller,
                            item,
                            currency,
                          ),
                    icon: Icon(
                      isCardPayment ? Icons.credit_card : Icons.lock_outline,
                    ),
                    label: Text(
                      isCardPayment
                          ? 'Pagar ${item.depositAmount} $currency con tarjeta'
                          : 'Depositar ${item.depositAmount} $currency',
                    ),
                  ),
                ),
              if (item.decisionDeadlineAt.isAfter(DateTime.now().toUtc())) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton.icon(
                    key: ValueKey('cancel-${item.reservationId}'),
                    onPressed: controller.busy
                        ? null
                        : () => _confirmCancellation(
                            context,
                            controller,
                            item,
                            currency,
                          ),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar solicitud'),
                  ),
                ),
              ],
            ],
            if (item.status == 'accepted')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  item.paymentMethod == 'card'
                      ? 'Reserva aceptada. El depósito de tarjeta se transfiere a la cuenta Stripe Connect de la inmobiliaria; el cierre legal ocurre fuera de RoomForge.'
                      : 'Reserva aceptada. El depósito se transfiere a la wallet verificada de la agencia; el cierre legal ocurre fuera de RoomForge.',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeposit(
    BuildContext context,
    CustomerReservationsController controller,
    ReservationRecord reservation,
    String currency,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar depósito de prueba'),
        content: Text(
          'Se solicitará a tu wallet externa aprobar el token local y depositar '
          '${reservation.depositAmount} $currency en el escrow Hardhat. RoomForge no guarda tus claves.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (accepted == true) await controller.deposit(reservation, currency);
  }

  Future<void> _confirmCancellation(
    BuildContext context,
    CustomerReservationsController controller,
    ReservationRecord reservation,
    String currency,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar solicitud'),
        content: Text(
          reservation.paymentMethod == 'card'
              ? 'La reserva se cancelará y, si el pago fue confirmado, Stripe procesará el reembolso de prueba.'
              : 'La cancelación requiere una transacción firmada por tu wallet. Si ya depositaste, el escrow enviará el reembolso y la API confirmará el evento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar cancelación'),
          ),
        ],
      ),
    );
    if (accepted == true) await controller.cancel(reservation, currency);
  }

  Future<void> _confirmExpiration(
    BuildContext context,
    CustomerReservationsController controller,
    ReservationRecord reservation,
    String currency,
  ) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Solicitar reembolso'),
        content: Text(
          reservation.paymentMethod == 'card'
              ? 'Venció el plazo de respuesta. Stripe procesará el reembolso del depósito de prueba si el pago fue confirmado.'
              : 'La agencia no respondió antes del plazo. Tu wallet enviará la transacción expire al escrow Hardhat para solicitar el reembolso de ${reservation.depositAmount} $currency.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Solicitar reembolso'),
          ),
        ],
      ),
    );
    if (accepted == true) await controller.expire(reservation, currency);
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'Pendiente',
    'accepted' => 'Aceptada',
    'rejected' => 'Rechazada',
    'cancelled' => 'Cancelada',
    'expired' => 'Vencida',
    _ => 'Estado desconocido',
  };

  Widget _message(BuildContext context, String text, {required Key key}) =>
      ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Mis reservas',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(text, key: key),
        ],
      );
}
