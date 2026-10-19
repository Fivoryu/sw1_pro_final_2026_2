import 'dart:async';

import 'package:augen/augen.dart';
import 'package:flutter/material.dart';

/// F07.1 spike: a bare ARCore session that detects floor and wall planes and
/// reports honest availability states. Per-frame session tracking quality is
/// not exposed by the plugin (declared limit, recorded in
/// docs/spikes/spk-07-arcore-depth.md); the panel shows session errors and
/// plane counts instead of inventing tracking measurements. The depth toggle
/// is the F07.6 probe: it re-initializes the session with depth data on and
/// observes the plugin's depth-backed occlusion status.
class ArcoreBasicScreen extends StatefulWidget {
  const ArcoreBasicScreen({super.key});

  @override
  State<ArcoreBasicScreen> createState() => _ArcoreBasicScreenState();
}

class _ArcoreBasicScreenState extends State<ArcoreBasicScreen> {
  AugenController? _controller;
  StreamSubscription<List<ARPlane>>? _planesSub;
  StreamSubscription<String>? _errorsSub;
  StreamSubscription<OcclusionStatus>? _occlusionSub;
  bool _supported = true;
  bool _starting = true;
  bool _depthEnabled = false;
  int _horizontalPlanes = 0;
  int _verticalPlanes = 0;
  OcclusionStatus? _occlusionStatus;
  String? _message;

  @override
  void dispose() {
    _planesSub?.cancel();
    _errorsSub?.cancel();
    _occlusionSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onViewReady(AugenController controller) async {
    _controller = controller;
    _planesSub = controller.planesStream.listen(_onPlanes);
    _errorsSub = controller.errorStream.listen(_onError);
    _occlusionSub = controller.occlusionStatusStream.listen((status) {
      if (mounted) setState(() => _occlusionStatus = status);
    });
    final supported = await controller.isARSupported();
    if (!mounted) return;
    if (!supported) {
      setState(() {
        _supported = false;
        _starting = false;
      });
      return;
    }
    await _startSession();
  }

  Future<void> _startSession() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.initialize(
        ARSessionConfig(planeDetection: true, depthData: _depthEnabled),
      );
      if (mounted) setState(() => _starting = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _message = 'No se pudo iniciar la sesión ARCore: $error';
        });
      }
    }
  }

  void _onPlanes(List<ARPlane> planes) {
    if (!mounted) return;
    setState(() {
      _horizontalPlanes = planes
          .where((plane) => plane.type == PlaneType.horizontal)
          .length;
      _verticalPlanes = planes
          .where((plane) => plane.type == PlaneType.vertical)
          .length;
    });
  }

  void _onError(String error) {
    if (!mounted) return;
    setState(() => _message = 'Error de la sesión ARCore: $error');
  }

  Future<void> _toggleDepth(bool enabled) async {
    final controller = _controller;
    if (controller == null || _starting) return;
    setState(() {
      _depthEnabled = enabled;
      _message = null;
    });
    await _startSession();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Captura espacial (prototipo ARCore)')),
    body: !_supported ? _unsupported(context) : _session(context),
  );

  Widget _unsupported(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.view_in_ar_outlined, size: 48),
          const SizedBox(height: 12),
          Card(
            key: const ValueKey('ar-unsupported'),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Este dispositivo no reportó soporte de ARCore. '
                'El resto de la app sigue funcionando sin captura espacial.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Volver'),
          ),
        ],
      ),
    ),
  );

  Widget _session(BuildContext context) => Stack(
    children: [
      AugenView(
        onViewCreated: _onViewReady,
        config: ARSessionConfig(
          planeDetection: true,
          depthData: _depthEnabled,
        ),
      ),
      Align(
        alignment: Alignment.bottomLeft,
        child: SafeArea(
          child: Card(
            margin: const EdgeInsets.all(12),
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado de la sesión',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _starting
                        ? 'Iniciando sesión ARCore…'
                        : (_horizontalPlanes + _verticalPlanes > 0
                              ? 'Detectando planos'
                              : 'Sin planos todavía: apuntá al piso y movete despacio'),
                  ),
                  Text(
                    key: const ValueKey('ar-plane-counts'),
                    'Piso: $_horizontalPlanes · Paredes: $_verticalPlanes',
                  ),
                  if (_message != null)
                    Text(
                      _message!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const Divider(height: 20),
                  SwitchListTile(
                    key: const ValueKey('ar-depth-toggle'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Modo profundidad (F07.6)'),
                    subtitle: Text(
                      _depthEnabled
                          ? 'Activo${_occlusionStatus == null ? '' : ': ${_occlusionStatus.runtimeType}'} — observando oclusión por profundidad'
                          : 'Inactivo',
                    ),
                    value: _depthEnabled,
                    onChanged: _toggleDepth,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
