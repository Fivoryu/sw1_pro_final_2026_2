import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// URL del visor 3D web (panel/staff-shell, ruta /visor3d).
///
/// Por defecto apunta a `http://localhost:5173/visor3d`, que en un celular
/// físico conectado por USB funciona gracias a `adb reverse tcp:5173 tcp:5173`.
/// Se puede cambiar con `--dart-define=ROOMFORGE_VISOR_URL=http://host:puerto/visor3d`.
const visor3dUrl = String.fromEnvironment(
  'ROOMFORGE_VISOR_URL',
  defaultValue: 'http://localhost:5173/visor3d',
);

/// Pantalla piloto de la Fase 6 que carga el visor 3D web dentro de un WebView.
class Visor3dScreen extends StatefulWidget {
  const Visor3dScreen({super.key, this.url = visor3dUrl});

  final String url;

  @override
  State<Visor3dScreen> createState() => _Visor3dScreenState();
}

class _Visor3dScreenState extends State<Visor3dScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;
  final _stopwatch = Stopwatch();
  Duration? _loadTime;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF222222))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _stopwatch
              ..reset()
              ..start();
            setState(() {
              _error = null;
              _loadTime = null;
            });
          },
          onProgress: (progress) => setState(() => _progress = progress),
          onPageFinished: (_) {
            _stopwatch.stop();
            setState(() => _loadTime = _stopwatch.elapsed);
          },
          onWebResourceError: (error) {
            // Solo nos interesa el error de la página principal.
            if (error.isForMainFrame ?? true) {
              setState(() => _error = '${error.errorCode}: ${error.description}');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  void _reload() {
    setState(() {
      _error = null;
      _progress = 0;
    });
    _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'No se pudo cargar el visor 3D',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.url}\n$_error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_progress < 100)
          LinearProgressIndicator(value: _progress / 100),
        if (_loadTime != null)
          Positioned(
            left: 8,
            bottom: 8,
            child: Chip(
              label: Text(
                'Carga: ${_loadTime!.inMilliseconds} ms',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
        Positioned(
          right: 8,
          bottom: 8,
          child: FloatingActionButton.small(
            heroTag: 'visor3d-reload',
            tooltip: 'Recargar visor',
            onPressed: _reload,
            child: const Icon(Icons.refresh),
          ),
        ),
      ],
    );
  }
}
