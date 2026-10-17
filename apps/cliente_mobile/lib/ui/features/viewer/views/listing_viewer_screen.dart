import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../data/services/scene_api.dart';
import '../../../../domain/viewer_controller.dart';
import '../logic/viewer_bridge.dart';

/// How long the viewer page has to signal `ready` before we stop trusting a
/// silent WebView and show an honest error instead.
const _viewerReadyTimeout = Duration(seconds: 10);

/// First-person walkthrough of one published listing (F06.4/F06.5).
///
/// The page is a local asset (no network content), and the scene document is
/// fetched here with [SceneApi] and injected into the page: no credentials
/// and no remote page ever share the WebView.
class ListingViewerScreen extends StatefulWidget {
  const ListingViewerScreen({
    super.key,
    required this.sceneApi,
    required this.listingId,
    this.onObjectSelected,
  });

  final SceneApi sceneApi;
  final String listingId;

  /// Hotspot callback: the customer tapped an object (null clears it).
  final ValueChanged<String?>? onObjectSelected;

  @override
  State<ListingViewerScreen> createState() => _ListingViewerScreenState();
}

class _ListingViewerScreenState extends State<ListingViewerScreen> {
  late final ViewerController _controller;
  WebViewController? _webController;
  bool _webViewBuilt = false;
  bool _viewerReady = false;
  bool _sceneDelivered = false;
  bool _sceneRendered = false;
  bool _viewerFailed = false;
  bool _pageFinished = false;
  Timer? _readyWatchdog;

  @override
  void initState() {
    super.initState();
    _controller = ViewerController(api: widget.sceneApi);
    _controller.addListener(_onControllerChanged);
    _controller.load(widget.listingId);
  }

  @override
  void dispose() {
    _readyWatchdog?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.state == ViewerLoadState.ready) {
      _deliverScene();
    }
  }

  /// Sends the scene document once both sides are prepared: the page booted
  /// (`ready`) and the document arrived (`ready` state on the controller).
  void _deliverScene() {
    final document = _controller.document;
    final webController = _webController;
    if (document == null || webController == null) return;
    if (!_viewerReady || !_pageFinished || _sceneDelivered) return;
    _sceneDelivered = true;
    _readyWatchdog?.cancel();
    webController.runJavaScript(
      'window.viewerHost.loadScene(${jsonEncode(document)})',
    );
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    final parsed = ViewerBridgeMessage.tryParse(message.message);
    if (parsed == null) return; // Unknown traffic is dropped, never trusted.
    if (!mounted) return;
    switch (parsed) {
      case ViewerReady():
        _viewerReady = true;
        _armReadyWatchdog();
        _deliverScene();
      case SceneLoaded():
        _readyWatchdog?.cancel();
        setState(() {
          _sceneRendered = true;
          _viewerFailed = false;
        });
      case ViewerLoadError():
        _readyWatchdog?.cancel();
        setState(() => _viewerFailed = true);
      case ViewerSelection(:final objectId):
        widget.onObjectSelected?.call(objectId);
    }
  }

  void _armReadyWatchdog() {
    // The watchdog only matters while the document has not been delivered:
    // once the page booted, delivery either happens or fails explicitly.
    if (_sceneDelivered) return;
    _readyWatchdog?.cancel();
    _readyWatchdog = Timer(_viewerReadyTimeout, () {
      if (!mounted || _sceneDelivered) return;
      setState(() => _viewerFailed = true);
    });
  }

  /// Resends the scene document to the viewer after a render failure.
  Future<void> _retryViewer() async {
    setState(() {
      _viewerFailed = false;
      _sceneDelivered = false;
      _sceneRendered = false;
    });
    _deliverScene();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recorrido 3D')),
    body: switch (_controller.state) {
      ViewerLoadState.loading => const Center(
        child: CircularProgressIndicator(key: ValueKey('viewer-loading')),
      ),
      ViewerLoadState.notDefined => ListView(
        key: const ValueKey('viewer-not-defined'),
        padding: const EdgeInsets.all(20),
        children: const [
          Text('Recorrido 3D no disponible.'),
          SizedBox(height: 8),
          Text(
            'Este inmueble todavía no tiene una escena publicada por la '
            'inmobiliaria.',
          ),
        ],
      ),
      ViewerLoadState.failed => ListView(
        key: const ValueKey('viewer-failed'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(_controller.message ?? ''),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const ValueKey('viewer-retry'),
            onPressed: () => _controller.load(widget.listingId),
            child: const Text('Reintentar'),
          ),
        ],
      ),
      ViewerLoadState.ready => _viewerBody(),
    },
  );

  Widget _viewerBody() {
    if (!_webViewBuilt) {
      _webViewBuilt = true;
      _webController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'RoomForgeBridge',
          onMessageReceived: _onBridgeMessage,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              _pageFinished = true;
              _deliverScene();
            },
          ),
        )
        ..loadFlutterAsset('assets/viewer/index.html');
    }
    final webController = _webController!;
    // Deliver if the page booted before the document arrived.
    _deliverScene();
    return Stack(
      children: [
        WebViewWidget(controller: webController),
        if (!_sceneRendered)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
            child: _viewerFailed
                ? ListView(
                    key: const ValueKey('viewer-runtime-error'),
                    padding: const EdgeInsets.all(20),
                    children: [
                      const Text('El visor 3D no respondió.'),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        key: const ValueKey('viewer-runtime-retry'),
                        onPressed: _retryViewer,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
