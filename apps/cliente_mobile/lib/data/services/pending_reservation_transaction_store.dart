import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingReservationTransaction {
  const PendingReservationTransaction({
    required this.reservationId,
    required this.action,
    required this.transactionHash,
    required this.nonce,
  });

  factory PendingReservationTransaction.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['reservation_id'] is! String ||
        json['action'] is! String ||
        json['transaction_hash'] is! String ||
        json['nonce'] is! int) {
      throw const FormatException('Pending transaction fields are invalid');
    }
    return PendingReservationTransaction(
      reservationId: json['reservation_id']! as String,
      action: json['action']! as String,
      transactionHash: json['transaction_hash']! as String,
      nonce: json['nonce']! as int,
    );
  }

  final String reservationId;
  final String action;
  final String transactionHash;
  final int nonce;

  Map<String, Object?> toJson() => {
    'reservation_id': reservationId,
    'action': action,
    'transaction_hash': transactionHash,
    'nonce': nonce,
  };
}

abstract interface class PendingReservationTransactionStore {
  Future<List<PendingReservationTransaction>> readAll();

  Future<void> write(PendingReservationTransaction transaction);

  Future<void> remove(String reservationId);
}

class SecurePendingReservationTransactionStore
    implements PendingReservationTransactionStore {
  SecurePendingReservationTransactionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'roomforge.customer.pending_chain_transactions';
  final FlutterSecureStorage _storage;

  @override
  Future<List<PendingReservationTransaction>> readAll() async {
    final value = await _storage.read(key: _key);
    if (value == null || value.isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List<Object?>) {
      throw const FormatException('Stored pending transactions are invalid');
    }
    return decoded
        .map(PendingReservationTransaction.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> write(PendingReservationTransaction transaction) async {
    final items = await readAll();
    final next = [
      for (final item in items)
        if (item.reservationId != transaction.reservationId) item,
      transaction,
    ];
    await _storage.write(
      key: _key,
      value: jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  }

  @override
  Future<void> remove(String reservationId) async {
    final items = await readAll();
    final next = items
        .where((item) => item.reservationId != reservationId)
        .toList(growable: false);
    if (next.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(
        key: _key,
        value: jsonEncode(next.map((item) => item.toJson()).toList()),
      );
    }
  }
}
