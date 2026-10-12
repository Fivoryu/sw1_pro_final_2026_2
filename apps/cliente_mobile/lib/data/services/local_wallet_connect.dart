import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';

/// WalletConnect/Reown bridge restricted to the local Hardhat EVM.
/// Project ID and RPC endpoint are public runtime configuration; no wallet key
/// or signing secret is stored by the application.
class LocalWalletConnect extends ChangeNotifier {
  LocalWalletConnect({required BuildContext context}) {
    final rpcUrl = _hardhatRpcUrl;
    _network = ReownAppKitModalNetworkInfo(
      name: 'RoomForge Hardhat local',
      chainId: '31337',
      currency: 'ETH',
      rpcUrl: rpcUrl,
      explorerUrl: rpcUrl,
      isTestNetwork: true,
    );
    ReownAppKitModalNetworks.addSupportedNetworks('eip155', [_network]);
    final projectId = _projectId;
    if (projectId.isEmpty) return;
    _modal = ReownAppKitModal(
      context: context,
      projectId: projectId,
      metadata: const PairingMetadata(
        name: 'RoomForge',
        description: 'Reservas inmobiliarias RoomForge en Hardhat local',
        url: 'https://roomforge.local',
        icons: [],
        redirect: Redirect(native: 'roomforge-client://'),
      ),
      optionalNamespaces: {
        'eip155': RequiredNamespace(
          chains: const ['eip155:31337'],
          methods: const ['personal_sign', 'eth_sendTransaction'],
          events: const ['accountsChanged', 'chainChanged'],
        ),
      },
      enableAnalytics: false,
      disconnectOnDispose: false,
    );
    _initialization = _modal!.init().then((_) {
      _initialized = true;
      _modal!.onModalConnect.subscribe((_) => notifyListeners());
      _modal!.onModalUpdate.subscribe((_) => notifyListeners());
      _modal!.onModalDisconnect.subscribe((_) => notifyListeners());
      _modal!.onModalNetworkChange.subscribe((_) => notifyListeners());
      notifyListeners();
    });
  }

  static const String _projectId = String.fromEnvironment(
    'ROOMFORGE_REOWN_PROJECT_ID',
  );
  static const String _hardhatRpcUrl = String.fromEnvironment(
    'ROOMFORGE_HARDHAT_RPC_URL',
    defaultValue: 'http://10.0.2.2:8545',
  );

  late final ReownAppKitModalNetworkInfo _network;
  ReownAppKitModal? _modal;
  Future<void>? _initialization;
  bool _initialized = false;
  String? _error;

  bool get isConfigured => _projectId.isNotEmpty;
  bool get isInitialized => _initialized;
  bool get isConnected => _modal?.isConnected ?? false;
  String? get error => _error;
  String? get address {
    final modal = _modal;
    if (modal?.session == null) return null;
    return modal!.session!.getAddress('eip155');
  }

  Future<void> initialize() async {
    if (!isConfigured) {
      _error = 'Falta ROOMFORGE_REOWN_PROJECT_ID para habilitar WalletConnect.';
      notifyListeners();
      return;
    }
    await _initialization;
  }

  Future<void> openConnect() async {
    await initialize();
    if (_modal == null || !_initialized) return;
    _error = null;
    await _modal!.openModalView();
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (_modal?.isConnected ?? false) await _modal!.disconnect();
    notifyListeners();
  }

  Future<String> signPersonalMessage(String message) async {
    final modal = await _readyModal();
    final address = _requireAddress(modal);
    final session = modal.session!;
    final chainId = await _ensureLocalChain(modal);
    final bytes = utf8.encode(message);
    final hexMessage = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final result = await modal.request(
      topic: session.topic,
      chainId: chainId,
      request: SessionRequestParams(
        method: 'personal_sign',
        params: ['0x$hexMessage', address],
      ),
    );
    if (result is! String || !result.startsWith('0x')) {
      throw StateError('The connected wallet did not return a signature.');
    }
    return result;
  }

  Future<String> sendTransaction({
    required String to,
    required String data,
  }) async {
    final modal = await _readyModal();
    final from = _requireAddress(modal);
    final chainId = await _ensureLocalChain(modal);
    final session = modal.session!;
    final result = await modal.request(
      topic: session.topic,
      chainId: chainId,
      request: SessionRequestParams(
        method: 'eth_sendTransaction',
        params: [
          {'from': from, 'to': to, 'data': data, 'value': '0x0'},
        ],
      ),
    );
    if (result is! String || !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(result)) {
      throw StateError('The wallet did not return a transaction hash.');
    }
    return result;
  }

  Future<ReownAppKitModal> _readyModal() async {
    await initialize();
    final modal = _modal;
    if (modal == null || !modal.isConnected) {
      throw StateError('Conectá una wallet externa antes de continuar.');
    }
    return modal;
  }

  String _requireAddress(ReownAppKitModal modal) {
    final address = modal.session?.getAddress('eip155');
    if (address == null || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) {
      throw StateError('La wallet no tiene una cuenta EVM autorizada.');
    }
    return address;
  }

  Future<String> _ensureLocalChain(ReownAppKitModal modal) async {
    if (modal.getApprovedChains()?.contains('eip155:31337') != true) {
      throw StateError('La wallet no autorizó la red local Hardhat 31337.');
    }
    if (modal.selectedChain?.chainId != 'eip155:31337') {
      await modal.requestSwitchToChain(_network);
    }
    return 'eip155:31337';
  }
}
