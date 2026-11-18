import 'package:flutter/material.dart';

import '../../domain/video_capture_controller.dart';

const _actionMinSize = Size.fromHeight(48);

/// Entry to the video walkthrough (F07): explains the flow, opens the native
/// recorder and reports what happened with the package.
class VideoCaptureScreen extends StatelessWidget {
  const VideoCaptureScreen({super.key, required this.controller});

  final VideoCaptureController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recorrido en video')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Grabá un recorrido por el inmueble. No hace falta una cinta '
                'métrica: al empezar, encuadrá un objeto de tamaño conocido '
                '(una hoja A4, una tarjeta, una puerta). La app detecta el '
                'objeto y vos confirmás o ajustás sus esquinas; si no lo '
                'encuentra, podés marcarlo a mano. Podés grabar con el '
                'teléfono en vertical u horizontal. Durante el recorrido '
                'tocá «Siguiente ambiente» cada vez que pases a otro '
                'ambiente. La grabación se corta a los 5 minutos y no lleva '
                'audio.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              _Notice(
                key: const ValueKey('video-reference-hint'),
                icon: Icons.straighten,
                text:
                    'La referencia es opcional: sin ella el plano será '
                    'proporcional, sin medidas reales.',
              ),
              const SizedBox(height: 12),
              _Notice(
                key: const ValueKey('video-guidance-hint'),
                icon: Icons.tips_and_updates_outlined,
                text:
                    'Mientras grabás verás avisos sobre la imagen: movimiento '
                    'brusco o giro rápido, poca luz y, al volver cerca del '
                    'inicio, una sugerencia de cerrar el recorrido. Son '
                    'orientativos y no se guardan.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('start-video-button'),
                style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                onPressed: controller.busy ? null : controller.start,
                icon: const Icon(Icons.videocam),
                label: Text(
                  controller.busy ? 'Grabando…' : 'Iniciar grabación',
                ),
              ),
              if (controller.message case final message?) ...[
                const SizedBox(height: 16),
                _Notice(
                  key: const ValueKey('video-message'),
                  icon: controller.status == VideoCaptureStatus.failed
                      ? Icons.error_outline
                      : Icons.cloud_upload_outlined,
                  text: message,
                ),
              ],
              if (controller.warning case final warning?) ...[
                const SizedBox(height: 12),
                _Notice(
                  key: const ValueKey('video-warning'),
                  icon: Icons.warning_amber_rounded,
                  text: warning,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.tertiary),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
