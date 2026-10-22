import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models/reservation_models.dart';
import '../data/services/customer_auth_failure.dart';
import '../data/services/customer_booking_api.dart';
import '../data/services/hardhat_reservation_executor.dart';
import '../data/services/local_wallet_connect.dart';

class CustomerReservationsController extends ChangeNotifier {
  CustomerReservationsController({
    required CustomerBookingApi api,
    LocalWalletConnect? wallet,
  }) : _api = api,
       _executor = wallet == null
           ? null
           : HardhatReservationExecutor(api: api, wallet: wallet);

  final CustomerBookingApi _api;
  final HardhatReservationExecutor? _executor;
  final Random _random = Random.secure();
  bool _busy = false;
  String? _message;
  QuoteSnapshot? _quote;
  List<ReservationRecord> _reservations = const [];

  bool get busy => _busy;
  String? get message => _message;
  QuoteSnapshot? get quote => _quote;
  List<ReservationRecord> get reservations => _reservations;

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
      await loadReservations();
      return reservation;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      return null;
    } finally {
      _busy = false;
      notifyListeners();
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
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      _reservations = await _api.listReservations();
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
      await loadReservations();
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
      await loadReservations();
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

  Future<bool> expire(ReservationRecord reservation, String currency) async {
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
      await loadReservations();
      return true;
    } on CustomerAuthFailure catch (failure) {
      _message = failure.detail;
      return false;
    } on TimeoutException {
      _message = 'La transacción no obtuvo recibo a tiempo. Actualizá la reserva antes de reintentar.';
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
