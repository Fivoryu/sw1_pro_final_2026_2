import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models/reservation_models.dart';
import '../data/services/customer_auth_failure.dart';
import '../data/services/customer_booking_api.dart';
import '../data/services/hardhat_reservation_executor.dart';
import '../data/services/local_wallet_connect.dart';
import '../data/services/stripe_card_payment_handler.dart';

class CustomerReservationsController extends ChangeNotifier {
  CustomerReservationsController({
    required CustomerBookingApi api,
    LocalWalletConnect? wallet,
    CardPaymentHandler? cardPaymentHandler,
  }) : _api = api,
       _executor = wallet == null
           ? null
           : HardhatReservationExecutor(api: api, wallet: wallet),
       _cardPaymentHandler = cardPaymentHandler ?? StripeCardPaymentHandler();

  final CustomerBookingApi _api;
  final HardhatReservationExecutor? _executor;
  final CardPaymentHandler _cardPaymentHandler;
  final Random _random = Random.secure();
  bool _busy = false;
  String? _message;
  QuoteSnapshot? _quote;
  List<ReservationRecord> _reservations = const [];
  final Set<String> _submittedCardPayments = {};

  bool get busy => _busy;
  String? get message => _message;
  QuoteSnapshot? get quote => _quote;
  List<ReservationRecord> get reservations => _reservations;

  bool isVerifyingCardPayment(ReservationRecord reservation) =>
      reservation.status == 'pending' &&
      reservation.depositConfirmedAt == null &&
      _submittedCardPayments.contains(reservation.reservationId);

  Future<QuoteSnapshot?> createQuote({
    required String listingId,
    required int offerVersion,
    required List<String> selectedExtraIds,
    required String targetCurrency,
  }) async {
    _busy = true;
    _message = null;
    _quote = null;
    notifyListeners();
    try {
      _quote = await _api.createQuote(
        listingId: listingId,
        offerVersion: offerVersion,
        selectedExtraIds: selectedExtraIds,
        targetCurrency: targetCurrency,
      );
      return _quote;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<ReservationRecord?> createReservation({
    required QuoteSnapshot quote,
    required CustomerWallet wallet,
  }) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final keyBytes = List<int>.generate(24, (_) => _random.nextInt(256));
      final key = keyBytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      final reservation = await _api.createReservation(
        listingId: quote.listingId,
        quoteId: quote.quoteId,
        walletId: wallet.id,
        idempotencyKey: key,
      );
      await _refreshAfterAction();
      return reservation;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      if (failure.statusCode == 409) {
        // A conflicting active reservation may already belong to this customer.
        // Refresh so the existing reservation is shown instead of leaving an
        // empty list under the conflict message.
        try {
          _reservations = await _api.listReservations();
        } on CustomerAuthFailure {
          // Keep the original conflict detail if the follow-up read also fails.
        }
      }
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<ReservationRecord?> createCardReservation({
    required QuoteSnapshot quote,
  }) async {
    if (_busy) return null;
    _busy = true;
    _message = null;
    notifyListeners();
    ReservationRecord? created;
    try {
      final key = List<int>.generate(
        24,
        (_) => _random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      final reservation = await _api.createCardReservation(
        listingId: quote.listingId,
        quoteId: quote.quoteId,
        idempotencyKey: key,
      );
      created = reservation;
      _reservations = [
        reservation,
        ..._reservations.where(
          (item) => item.reservationId != reservation.reservationId,
        ),
      ];
      await _presentCardPayment(reservation);
      return reservation;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      if (failure.statusCode == 409) {
        try {
          await _refreshReservations();
          for (final item in _reservations) {
            if (created == null &&
                item.listingId == quote.listingId &&
                item.status == 'pending') {
              _message =
                  'Ya tenés una solicitud para este inmueble. Podés retomarla en Mis reservas.';
              return item;
            }
          }
        } on CustomerAuthFailure {
          // Keep the original conflict detail if the follow-up read also fails.
        }
      }
      return created;
    } catch (_) {
      _message = created == null
          ? 'No se pudo confirmar la solicitud. Revisá Mis reservas antes de intentarlo de nuevo.'
          : 'La solicitud quedó guardada. Revisá el estado del pago en Mis reservas.';
      return created;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> payCardReservation(ReservationRecord reservation) async {
    if (_busy || isVerifyingCardPayment(reservation)) return false;
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      return await _presentCardPayment(reservation);
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      return false;
    } catch (_) {
      _message = 'No se pudo abrir el pago seguro con tarjeta.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _presentCardPayment(ReservationRecord reservation) async {
    final session = await _api.createCardPaymentIntent(
      reservation.reservationId,
    );
    final completed = await _cardPaymentHandler.present(session);
    if (completed) _submittedCardPayments.add(reservation.reservationId);
    _message = completed
        ? 'Pago enviado. Estamos verificando el depósito.'
        : 'La solicitud quedó guardada. Podés completar el pago desde Mis reservas.';
    try {
      await _refreshReservations();
    } on CustomerAuthFailure {
      // A failed refresh does not change the outcome of the payment sheet.
    }
    return completed;
  }

  Future<void> _refreshReservations() async {
    _reservations = await _api.listReservations();
    for (final reservation in _reservations) {
      if (reservation.status != 'pending' ||
          reservation.depositConfirmedAt != null) {
        _submittedCardPayments.remove(reservation.reservationId);
      }
    }
  }

  Future<void> _refreshAfterAction() async {
    try {
      await _refreshReservations();
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
    }
  }

  Future<List<CustomerWallet>?> loadWallets() async {
    _message = null;
    try {
      return await _api.listWallets();
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      notifyListeners();
      return null;
    }
  }

  Future<void> loadReservations() async {
    if (_busy) return;
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      await _refreshReservations();
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> deposit(ReservationRecord reservation, String currency) async {
    final executor = _executor;
    if (executor == null) {
      _message = 'WalletConnect no está configurado.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      await executor.deposit(reservation: reservation, currency: currency);
      await _refreshAfterAction();
      return true;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      return false;
    } on TimeoutException {
      _message =
          'La transacción no obtuvo recibo a tiempo. No la envíes de nuevo; actualizá la reserva.';
      return false;
    } on StateError catch (error) {
      _message = error.message;
      return false;
    } catch (_) {
      _message =
          'No se pudo completar o verificar el depósito. Actualizá el estado antes de reintentar.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> cancel(ReservationRecord reservation, String currency) async {
    if (reservation.paymentMethod == 'card') {
      return _closeCardReservation(reservation, expired: false);
    }
    final executor = _executor;
    if (executor == null) {
      _message = 'WalletConnect no está configurado.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      await executor.cancel(reservation: reservation, currency: currency);
      await _refreshAfterAction();
      return true;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      return false;
    } on TimeoutException {
      _message =
          'La transacción no obtuvo recibo a tiempo. Actualizá la reserva antes de reintentar.';
      return false;
    } on StateError catch (error) {
      _message = error.message;
      return false;
    } catch (_) {
      _message = 'No se pudo completar o verificar la cancelación.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> _closeCardReservation(
    ReservationRecord reservation, {
    required bool expired,
  }) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      if (expired) {
        await _api.expireCardReservation(reservation.reservationId);
      } else {
        await _api.cancelCardReservation(reservation.reservationId);
      }
      _reservations = await _api.listReservations();
      return true;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      return false;
    } catch (_) {
      _message = expired
          ? 'No se pudo procesar el vencimiento y reembolso de la reserva.'
          : 'No se pudo cancelar la reserva ni procesar el reembolso.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> expire(ReservationRecord reservation, String currency) async {
    if (reservation.paymentMethod == 'card') {
      return _closeCardReservation(reservation, expired: true);
    }
    final executor = _executor;
    if (executor == null) {
      _message = 'WalletConnect no está configurado.';
      notifyListeners();
      return false;
    }
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      await executor.expire(reservation: reservation, currency: currency);
      await _refreshAfterAction();
      return true;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      return false;
    } on TimeoutException {
      _message =
          'La transacción no obtuvo recibo a tiempo. Actualizá la reserva antes de reintentar.';
      return false;
    } on StateError catch (error) {
      _message = error.message;
      return false;
    } catch (_) {
      _message = 'No se pudo completar o verificar la expiración.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
