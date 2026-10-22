import 'package:flutter/material.dart';

import '../../../../data/models/reservation_models.dart';
import '../../../../domain/customer_reservations_controller.dart';
import '../../../../domain/customer_session_controller.dart';

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
      if (controller.busy && controller.reservations.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (controller.message != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              controller.message!,
              key: const ValueKey('reservations-error'),
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
    final deposit = item.depositAmount == null
        ? 'Sin depósito configurado'
        : 'Depósito: ${item.depositAmount} $currency';
    return Card(
      key: ValueKey('reservation-${item.reservationId}'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reserva ${item.reservationId}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(_statusLabel(item.status))),
              ],
            ),
            Text(
              'Inmueble ${item.listingId} · oferta v${snapshot.offerVersion}',
            ),
            const SizedBox(height: 8),
            if (snapshot.oneTimeTotal.amount != '0.00')
              Text(
                'Pago único: ${snapshot.oneTimeTotal.amount} ${snapshot.oneTimeTotal.currency}',
              ),
            if (snapshot.monthlyTotal.amount != '0.00')
              Text(
                'Mensual: ${snapshot.monthlyTotal.amount} ${snapshot.monthlyTotal.currency}',
              ),
            Text(deposit),
            Text('Plazo de respuesta: ${item.decisionDeadlineAt.toLocal()}'),
            if (item.status == 'pending')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Pendiente no significa depósito confirmado. La confirmación requiere verificar la transacción en la red local.',
                ),
              ),
            if (item.status == 'pending') ...[
              const SizedBox(height: 12),
              if (item.depositAmount != null &&
                  item.depositConfirmedAt != null &&
                  !item.decisionDeadlineAt.isAfter(DateTime.now().toUtc()))
                SizedBox(
                  width: double.infinity,
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
                  item.decisionDeadlineAt.isAfter(DateTime.now().toUtc()))
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: ValueKey('deposit-${item.reservationId}'),
                    onPressed: controller.busy
                        ? null
                        : () => _confirmDeposit(
                            context,
                            controller,
                            item,
                            currency,
                          ),
                    icon: const Icon(Icons.lock_outline),
                    label: Text('Depositar ${item.depositAmount} $currency'),
                  ),
                ),
              if (item.decisionDeadlineAt.isAfter(DateTime.now().toUtc()))
                SizedBox(
                  width: double.infinity,
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
            if (item.status == 'accepted')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Reserva aceptada. El depósito se transfiere a la wallet verificada de la agencia; el cierre legal ocurre fuera de RoomForge.',
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
        content: const Text(
          'La cancelación requiere una transacción firmada por tu wallet. '
          'Si ya depositaste, el escrow enviará el reembolso y la API confirmará el evento.',
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
          'La agencia no respondió antes del plazo. Tu wallet enviará la transacción expire al escrow Hardhat para solicitar el reembolso de ${reservation.depositAmount} $currency.',
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
