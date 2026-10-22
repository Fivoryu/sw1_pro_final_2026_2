import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart' as codec;
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'package:wallet/wallet.dart' as wallet_types;

import '../models/reservation_models.dart';
import 'customer_booking_api.dart';
import 'local_wallet_connect.dart';
import 'pending_reservation_transaction_store.dart';

String localEscrowAddressForCurrency(
  String currency, {
  required String bobAddress,
  required String usdAddress,
  required String usdtAddress,
  required String legacyRftEscrowAddress,
}) {
  final normalized = currency.toUpperCase();
  final configured = switch (normalized) {
    'BOB' => bobAddress,
    'USD' => usdAddress,
    'USDT' => usdtAddress,
    _ => '',
  };
  final fallback = normalized == 'BOB' || normalized == 'USD'
      ? legacyRftEscrowAddress
      : '';
  final address = _isLocalAddress(configured) ? configured : fallback;
  if (!_isLocalAddress(address)) {
    throw StateError('Falta configurar el escrow local para $currency.');
  }
  return address;
}

bool _isLocalAddress(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);

/// Sends the customer-side allowance and deposit to the local Hardhat escrow,
/// then asks the backend to verify the mined receipt/event before UI state can
/// be treated as deposited.
class HardhatReservationExecutor {
  HardhatReservationExecutor({
    required CustomerBookingApi api,
    required LocalWalletConnect wallet,
    PendingReservationTransactionStore? pendingStore,
    http.Client? rpcClient,
    this.receiptTimeout = const Duration(seconds: 45),
  }) : _api = api,
       _wallet = wallet,
       _pendingStore =
           pendingStore ?? SecurePendingReservationTransactionStore(),
       _rpcClient = rpcClient ?? http.Client();

  static const String _rpcUrl = String.fromEnvironment(
    'ROOMFORGE_HARDHAT_RPC_URL',
    defaultValue: 'http://10.0.2.2:8545',
  );
  static const String _rftAddress = String.fromEnvironment(
    'ROOMFORGE_RFT_ADDRESS',
  );
  static const String _legacyRftEscrowAddress = String.fromEnvironment(
    'ROOMFORGE_RFT_ESCROW_ADDRESS',
  );
  static const String _bobEscrowAddress = String.fromEnvironment(
    'ROOMFORGE_ESCROW_BOB_ADDRESS',
  );
  static const String _usdEscrowAddress = String.fromEnvironment(
    'ROOMFORGE_ESCROW_USD_ADDRESS',
  );
  static const String _usdtAddress = String.fromEnvironment(
    'ROOMFORGE_USDT_ADDRESS',
  );
  static const String _usdtEscrowAddress = String.fromEnvironment(
    'ROOMFORGE_ESCROW_USDT_ADDRESS',
  );

  final CustomerBookingApi _api;
  final LocalWalletConnect _wallet;
  final PendingReservationTransactionStore _pendingStore;
  final http.Client _rpcClient;
  final Duration receiptTimeout;

  Future<Map<String, Object?>> deposit({
    required ReservationRecord reservation,
    required String currency,
  }) async {
    final existing = await _pendingFor(reservation.reservationId);
    if (existing != null) {
      if (existing.action != 'deposit') {
        throw StateError(
          'Hay otra acción on-chain pendiente para esta reserva.',
        );
      }
      return _reconcilePending(existing);
    }
    if (reservation.status != 'pending' || reservation.depositAmount == null) {
      throw StateError(
        'Esta reserva no tiene un depósito pendiente de enviar.',
      );
    }
    final token = _addressFor(currency, _rftAddress, _usdtAddress);
    final escrow = _escrowAddressFor(currency);
    final walletAddress = _wallet.address;
    if (walletAddress == null) {
      throw StateError('Conectá la wallet vinculada a la cuenta RoomForge.');
    }

    final permit = await _api.requestDepositPermit(reservation.reservationId);
    _validatePermit(permit, reservation, walletAddress);
    final amount = BigInt.from(permit.amount);

    final approveData = _erc20Abi().functions
        .singleWhere((function) => function.name == 'approve')
        .encodeCall([escrow, amount]);
    final approveHash = await _wallet.sendTransaction(
      to: token.with0x,
      data: '0x${codec.hex.encode(approveData)}',
    );
    await _waitForSuccessfulReceipt(approveHash);

    final action = [
      _bytes32(permit.reservationId),
      _bytes32(permit.listingId),
      wallet_types.EthereumAddress.fromHex(permit.customer),
      wallet_types.EthereumAddress.fromHex(permit.agency),
      wallet_types.EthereumAddress.fromHex(permit.actor),
      BigInt.from(permit.action),
      amount,
      BigInt.from(permit.deadline),
      BigInt.from(permit.nonce),
    ];
    final depositData = _escrowAbi().functions
        .singleWhere((function) => function.name == 'deposit')
        .encodeCall([action, _hexBytes(permit.signature)]);
    final transactionHash = await _wallet.sendTransaction(
      to: escrow.with0x,
      data: '0x${codec.hex.encode(depositData)}',
    );
    final pending = PendingReservationTransaction(
      reservationId: reservation.reservationId,
      action: 'deposit',
      transactionHash: transactionHash,
      nonce: permit.nonce,
    );
    await _pendingStore.write(pending);
    await _waitForSuccessfulReceipt(transactionHash);
    return _reconcilePending(pending);
  }

  Future<Map<String, Object?>> cancel({
    required ReservationRecord reservation,
    required String currency,
  }) async {
    final existing = await _pendingFor(reservation.reservationId);
    if (existing != null) {
      if (existing.action != 'cancel') {
        throw StateError(
          'Hay otra acción on-chain pendiente para esta reserva.',
        );
      }
      return _reconcilePending(existing);
    }
    if (reservation.status != 'pending') {
      throw StateError('Solo una reserva pendiente puede cancelarse.');
    }
    final escrow = _escrowAddressFor(currency);
    final walletAddress = _wallet.address;
    if (walletAddress == null) {
      throw StateError('Conectá la wallet vinculada a la cuenta RoomForge.');
    }
    final permit = ReservationPermit.fromJson(
      await _api.requestPermit(
        reservationId: reservation.reservationId,
        action: 'cancel',
      ),
    );
    if (permit.action != 3 ||
        permit.reservationId != reservation.reservationId ||
        permit.listingId != reservation.listingId ||
        permit.actor.toLowerCase() != walletAddress.toLowerCase() ||
        permit.customer.toLowerCase() != walletAddress.toLowerCase() ||
        !RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(permit.signature)) {
      throw StateError(
        'El permiso de cancelación no coincide con esta reserva/wallet.',
      );
    }
    final action = [
      _bytes32(permit.reservationId),
      _bytes32(permit.listingId),
      wallet_types.EthereumAddress.fromHex(permit.customer),
      wallet_types.EthereumAddress.fromHex(permit.agency),
      wallet_types.EthereumAddress.fromHex(permit.actor),
      BigInt.from(permit.action),
      BigInt.from(permit.amount),
      BigInt.from(permit.deadline),
      BigInt.from(permit.nonce),
    ];
    final cancelData = _escrowAbi().functions
        .singleWhere((function) => function.name == 'cancel')
        .encodeCall([action, _hexBytes(permit.signature)]);
    final transactionHash = await _wallet.sendTransaction(
      to: escrow.with0x,
      data: '0x${codec.hex.encode(cancelData)}',
    );
    final pending = PendingReservationTransaction(
      reservationId: reservation.reservationId,
      action: 'cancel',
      transactionHash: transactionHash,
      nonce: permit.nonce,
    );
    await _pendingStore.write(pending);
    await _waitForSuccessfulReceipt(transactionHash);
    return _reconcilePending(pending);
  }

  Future<Map<String, Object?>> expire({
    required ReservationRecord reservation,
    required String currency,
  }) async {
    if (reservation.status != 'pending' ||
        reservation.depositAmount == null ||
        reservation.depositConfirmedAt == null ||
        reservation.decisionDeadlineAt.isAfter(DateTime.now().toUtc())) {
      throw StateError(
        'Solo un depósito pendiente vencido puede expirar en cadena.',
      );
    }
    final existing = await _pendingFor(reservation.reservationId);
    if (existing != null) {
      if (existing.action != 'expire') {
        throw StateError(
          'Hay otra acción on-chain pendiente para esta reserva.',
        );
      }
      return _reconcilePending(existing);
    }
    final escrow = _escrowAddressFor(currency);
    if (_wallet.address == null) {
      throw StateError(
        'Conectá tu wallet EVM para enviar la transacción de expiración.',
      );
    }
    final reservationHash = keccakUtf8(reservation.reservationId);
    final abi = _escrowAbi();
    final nonce = await _readNonce(escrow, reservationHash, abi);
    final expireCall = abi.functions
        .singleWhere((function) => function.name == 'expire')
        .encodeCall([reservationHash]);
    final transactionHash = await _wallet.sendTransaction(
      to: escrow.with0x,
      data: '0x${codec.hex.encode(expireCall)}',
    );
    final pending = PendingReservationTransaction(
      reservationId: reservation.reservationId,
      action: 'expire',
      transactionHash: transactionHash,
      nonce: nonce,
    );
    await _pendingStore.write(pending);
    await _waitForSuccessfulReceipt(transactionHash);
    return _reconcilePending(pending);
  }

  Future<PendingReservationTransaction?> _pendingFor(
    String reservationId,
  ) async {
    for (final pending in await _pendingStore.readAll()) {
      if (pending.reservationId == reservationId) return pending;
    }
    return null;
  }

  Future<Map<String, Object?>> _reconcilePending(
    PendingReservationTransaction pending,
  ) async {
    await _waitForSuccessfulReceipt(pending.transactionHash);
    final result = await _api.reconcileTransaction(
      reservationId: pending.reservationId,
      action: pending.action,
      transactionHash: pending.transactionHash,
      nonce: pending.nonce,
    );
    await _pendingStore.remove(pending.reservationId);
    return result;
  }

  void _validatePermit(
    ReservationPermit permit,
    ReservationRecord reservation,
    String walletAddress,
  ) {
    if (permit.action != 0 ||
        permit.reservationId != reservation.reservationId ||
        permit.listingId != reservation.listingId ||
        permit.actor.toLowerCase() != walletAddress.toLowerCase() ||
        permit.customer.toLowerCase() != walletAddress.toLowerCase() ||
        permit.amount <= 0 ||
        !RegExp(r'^0x[0-9a-fA-F]{130}$').hasMatch(permit.signature)) {
      throw StateError(
        'El permiso de depósito no coincide con esta reserva/wallet.',
      );
    }
  }

  Future<void> _waitForSuccessfulReceipt(String transactionHash) async {
    final uri = Uri.parse(_rpcUrl);
    final deadline = DateTime.now().add(receiptTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final response = await _rpcClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'eth_getTransactionReceipt',
              'params': [transactionHash],
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        throw StateError('No pudimos consultar el recibo en Hardhat local.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?> || decoded['error'] != null) {
        throw StateError('Hardhat local rechazó la consulta del recibo.');
      }
      final receipt = decoded['result'];
      if (receipt is Map<String, Object?>) {
        if (receipt['status'] != '0x1') {
          throw StateError('La transacción fue minada pero revirtió.');
        }
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw TimeoutException(
      'La transacción sigue sin recibo. Conservá el hash para reconciliarla luego.',
      receiptTimeout,
    );
  }

  Future<int> _readNonce(
    wallet_types.EthereumAddress escrow,
    Uint8List reservationId,
    ContractAbi abi,
  ) async {
    final function = abi.functions.singleWhere(
      (candidate) => candidate.name == 'nonces',
    );
    final data = '0x${codec.hex.encode(function.encodeCall([reservationId]))}';
    final response = await _rpcClient
        .post(
          Uri.parse(_rpcUrl),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'eth_call',
            'params': [
              {'to': escrow.with0x, 'data': data},
              'latest',
            ],
          }),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw StateError('No pudimos consultar el nonce del escrow local.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?> ||
        decoded['error'] != null ||
        decoded['result'] is! String) {
      throw StateError('El escrow local no devolvió el nonce de reserva.');
    }
    final values = function.decodeReturnValues(decoded['result']! as String);
    final nonce = values.single;
    if (nonce is! BigInt || nonce > BigInt.from(0x7fffffffffffffff)) {
      throw StateError('El nonce de expiración está fuera de rango.');
    }
    return nonce.toInt();
  }

  wallet_types.EthereumAddress _addressFor(
    String currency,
    String rftAddress,
    String usdtAddress,
  ) {
    final address = currency == 'USDT' ? usdtAddress : rftAddress;
    if (!_isAddress(address)) {
      throw StateError(
        'Falta configurar el contrato token local para $currency.',
      );
    }
    return wallet_types.EthereumAddress.fromHex(address);
  }

  wallet_types.EthereumAddress _escrowAddressFor(String currency) {
    final address = localEscrowAddressForCurrency(
      currency,
      bobAddress: _bobEscrowAddress,
      usdAddress: _usdEscrowAddress,
      usdtAddress: _usdtEscrowAddress,
      legacyRftEscrowAddress: _legacyRftEscrowAddress,
    );
    return wallet_types.EthereumAddress.fromHex(address);
  }

  static bool _isAddress(String value) => _isLocalAddress(value);

  static Uint8List _bytes32(String value) {
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw StateError('El identificador firmado no tiene formato bytes32.');
    }
    return Uint8List.fromList(codec.hex.decode(value.substring(2)));
  }

  static Uint8List _hexBytes(String value) {
    if (!RegExp(r'^0x(?:[0-9a-fA-F]{2})+$').hasMatch(value)) {
      throw StateError('La firma del permiso tiene un formato inválido.');
    }
    return Uint8List.fromList(codec.hex.decode(value.substring(2)));
  }

  static ContractAbi _erc20Abi() => ContractAbi.fromJson(
    jsonEncode([
      {
        'type': 'function',
        'name': 'approve',
        'stateMutability': 'nonpayable',
        'inputs': [
          {'name': 'spender', 'type': 'address'},
          {'name': 'value', 'type': 'uint256'},
        ],
        'outputs': [
          {'name': '', 'type': 'bool'},
        ],
      },
    ]),
    'ERC20',
  );

  static ContractAbi _escrowAbi() => ContractAbi.fromJson(
    jsonEncode([
      {
        'type': 'function',
        'name': 'deposit',
        'stateMutability': 'nonpayable',
        'inputs': [
          {
            'name': 'action',
            'type': 'tuple',
            'components': [
              {'name': 'reservationId', 'type': 'bytes32'},
              {'name': 'listingId', 'type': 'bytes32'},
              {'name': 'customer', 'type': 'address'},
              {'name': 'agency', 'type': 'address'},
              {'name': 'actor', 'type': 'address'},
              {'name': 'action', 'type': 'uint8'},
              {'name': 'amount', 'type': 'uint256'},
              {'name': 'deadline', 'type': 'uint64'},
              {'name': 'nonce', 'type': 'uint256'},
            ],
          },
          {'name': 'signature', 'type': 'bytes'},
        ],
        'outputs': [],
      },
      {
        'type': 'function',
        'name': 'expire',
        'stateMutability': 'nonpayable',
        'inputs': [
          {'name': 'reservationId', 'type': 'bytes32'},
        ],
        'outputs': [],
      },
      {
        'type': 'function',
        'name': 'nonces',
        'stateMutability': 'view',
        'inputs': [
          {'name': 'reservationId', 'type': 'bytes32'},
        ],
        'outputs': [
          {'name': '', 'type': 'uint256'},
        ],
      },
      {
        'type': 'function',
        'name': 'cancel',
        'stateMutability': 'nonpayable',
        'inputs': [
          {
            'name': 'action',
            'type': 'tuple',
            'components': [
              {'name': 'reservationId', 'type': 'bytes32'},
              {'name': 'listingId', 'type': 'bytes32'},
              {'name': 'customer', 'type': 'address'},
              {'name': 'agency', 'type': 'address'},
              {'name': 'actor', 'type': 'address'},
              {'name': 'action', 'type': 'uint8'},
              {'name': 'amount', 'type': 'uint256'},
              {'name': 'deadline', 'type': 'uint64'},
              {'name': 'nonce', 'type': 'uint256'},
            ],
          },
          {'name': 'signature', 'type': 'bytes'},
        ],
        'outputs': [],
      },
    ]),
    'ReservationEscrow',
  );
}
