import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../data/services/scene_api.dart';
import '../../../../domain/viewer_controller.dart';
import '../logic/viewer_assets.dart';
import '../logic/viewer_bridge.dart';

/// How long the page has to prove itself before the walkthrough stops waiting
/// silently: first to signal `ready`, then to report `scene_loaded`.
const _viewerPageTimeout = Duration(seconds: 10);

/// Builds the page that hosts the viewer, reporting its bridge traffic.
typedef ViewerPageBuilder =
    Widget Function(BuildContext context, void Function(String payload) report);

/// First-person walkthrough of one published listing (F06.4/F06.5).
///
/// The page and its scripts are local bundle assets served over a virtual
/// origin (see `viewer_assets.dart`), and the scene document is fetched here
/// with [SceneApi] and injected into the page: no credentials and no remote
/// page ever share the WebView.
class ListingViewerScreen extends StatefulWidget {
  const ListingViewerScreen({
    super.key,
    required this.sceneApi,
    required this.listingId,
    this.onObjectSelected,
    this.pageTimeout = _viewerPageTimeout,
    this.viewerBuilder,
    this.scriptRunner,
  });

  final SceneApi sceneApi;
  final String listingId;

  /// Hotspot callback: the customer tapped an object (null clears it).
  final ValueChanged<String?>? onObjectSelected;

  /// Deadline for each page signal (`ready`, then `scene_loaded`).
  final Duration pageTimeout;

  /// Test seam: replaces the WebView with a widget that drives [report].
  final ViewerPageBuilder? viewerBuilder;

  /// Test seam: receives the JavaScript that delivers the scene to the page.
  final ValueChanged<String>? scriptRunner;

  @override
  State<ListingViewerScreen> createState() => _ListingViewerScreenState();
}

class _ListingViewerScreenState extends State<ListingViewerScreen> {
  late final ViewerController _controller;
  InAppWebViewController? _webController;
  bool _pageBuilt = false;
  bool _pageBooted = false;
  bool _sceneDelivered = false;
  bool _sceneRendered = false;
  bool _viewerFailed = false;
  Timer? _pageWatchdog;
  Timer? _renderWatchdog;

  @override
  void initState() {
    super.initState();
    _controller = ViewerController(api: widget.sceneApi);
    _controller.addListener(_onControllerChanged);
    _controller.load(widget.listingId);
  }

  @override
  void dispose() {
    _pageWatchdog?.cancel();
    _renderWatchdog?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (_controller.state == ViewerLoadState.ready) _deliverScene();
  }

  /// Sends the scene document once the page booted and the document arrived.
  void _deliverScene() {
    final document = _controller.document;
    if (document == null || !_pageBooted || !_pageBuilt || _sceneDelivered) {
      return;
    }
    // Exactly one delivery per attempt: re-sending `loadScene` on every rebuild
    // would reset the camera to its spawn point on each frame.
    _sceneDelivered = true;
    // The page owes us a rendered scene now, whether or not the controller is
    // already attached: silence is still a failure the customer must see.
    _armRenderWatchdog();
    final source = 'window.viewerHost.loadScene(${jsonEncode(document)})';
    final runner = widget.scriptRunner;
    if (runner != null) {
      runner(source);
      return;
    }
    _webController?.evaluateJavascript(source: source);
  }

  /// After delivery the page must report  within the deadline.
  void _armRenderWatchdog() {
    _renderWatchdog?.cancel();
    _renderWatchdog = Timer(widget.pageTimeout, () {
      if (!mounted || _sceneRendered) return;
      setState(() => _viewerFailed = true);
    });
  }

  void _onBridgePayload(String payload) {
    final parsed = ViewerBridgeMessage.tryParse(payload);
    if (parsed == null) return; // Unknown traffic is dropped, never trusted.
    switch (parsed) {
      case ViewerReady():
        _pageWatchdog?.cancel();
        _pageBooted = true;
        _deliverScene();
      case SceneLoaded():
        _renderWatchdog?.cancel();
        if (!mounted) return;
        setState(() {
          _sceneRendered = true;
          _viewerFailed = false;
        });
      case ViewerLoadError():
        _pageWatchdog?.cancel();
        _renderWatchdog?.cancel();
        if (!mounted) return;
        setState(() => _viewerFailed = true);
      case ViewerSelection(:final objectId):
        widget.onObjectSelected?.call(objectId);
    }
  }

  /// The page must answer within [widget.pageTimeout]; silence is a failure we
  /// show, never a blank canvas that looks like a building without walls.
  void _armPageWatchdog() {
    _pageWatchdog?.cancel();
    _pageWatchdog = Timer(widget.pageTimeout, () {
      if (!mounted || _pageBooted) return;
      setState(() => _viewerFailed = true);
    });
  }

  Future<void> _retryViewer() async {
    setState(() {
      _viewerFailed = false;
      _sceneDelivered = false;
      _sceneRendered = false;
    });
    if (_pageBooted) {
      _deliverScene();
      return;
    }
    _armPageWatchdog();
    await _webController?.reload();
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
    if (!_pageBuilt) {
      _pageBuilt = true;
      _armPageWatchdog();
    }
    final page = widget.viewerBuilder?.call(context, _onBridgePayload) ??
        _ViewerPage(
          onReady: (controller) => _webController = controller,
          report: _onBridgePayload,
        );
    // Deliver if the page booted before the document arrived.
    _deliverScene();
    return Stack(
      children: [
        page,
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

/// The real page: bundle assets over the virtual origin, bridge shim ahead of
/// the viewer scripts, and no navigation away from the serving origin.
class _ViewerPage extends StatelessWidget {
  const _ViewerPage({required this.onReady, required this.report});

  final ValueChanged<InAppWebViewController> onReady;
  final void Function(String payload) report;

  @override
  Widget build(BuildContext context) => InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri('$viewerOrigin/index.html')),
    initialSettings: InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldInterceptRequest: true,
      // The viewer is a local, self-contained page: no popups, no file access.
      supportMultipleWindows: false,
      allowFileAccess: false,
      allowContentAccess: false,
      transparentBackground: false,
    ),
    initialUserScripts: UnmodifiableListView([
      UserScript(
        source: viewerBridgeShim,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]),
    shouldInterceptRequest: (controller, request) async {
      final key = viewerAssetKeyFor(request.url);
      if (key == null) return null;
      final contentType = contentTypeForViewerAsset(key);
      if (contentType == null) return null;
      final data = await rootBundle.load(key);
      return WebResourceResponse(
        contentType: contentType,
        data: data.buffer.asUint8List(),
      );
    },
    shouldOverrideUrlLoading: (controller, action) async {
      final url = action.request.url;
      if (url == null || viewerAssetKeyFor(url) != null) {
        return NavigationActionPolicy.ALLOW;
      }
      return NavigationActionPolicy.CANCEL;
    },
    onWebViewCreated: (controller) {
      if (kDebugMode) {
        // Debug builds expose the page to `chrome://inspect` / CDP so the run
        // can be measured; release builds never do.
        InAppWebViewController.setWebContentsDebuggingEnabled(true);
      }
      onReady(controller);
      controller.addJavaScriptHandler(
        handlerName: 'RoomForgeBridge',
        callback: (args) {
          if (args.isEmpty) return null;
          report(args.first.toString());
          return null;
        },
      );
    },
  );
}
