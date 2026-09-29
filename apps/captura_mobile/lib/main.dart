import 'package:flutter/material.dart';

/// Prototype-only copy shared by the capture screens. Nothing in this app
/// authenticates, captures, persists or uploads real data.
const _prototypeNotice =
    'Prototipo de interfaz: no hay autenticación, API, cámara ni datos '
    'guardados.';

const _accessNotice =
    'En este prototipo el acceso no pide credenciales, no abre sesión y no '
    'valida identidad.';

const _draftsNotice =
    'Prototipo local: los borradores se muestran solo en pantalla; no se '
    'guardan ni se sincronizan.';

const _nextStepNotice =
    'El asistente para crear un inmueble todavía no está construido en este '
    'prototipo.';

/// Minimum 48 dp touch target for the prototype primary actions.
const _actionMinSize = Size.fromHeight(48);

/// Readable content width on tablets and resizable windows.
const double _contentMaxWidth = 720;

void main() => runApp(const CaptureApp());

class CaptureApp extends StatelessWidget {
  const CaptureApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RoomForge Captura',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D4ED8)),
      useMaterial3: true,
    ),
    home: const AgentAccessScreen(),
  );
}

/// Access step. UI only: no credential inputs, session or identity check.
class AgentAccessScreen extends StatelessWidget {
  const AgentAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('RoomForge Captura')),
      body: _PrototypePage(
        children: [
          Text('Acceso del agente', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 20),
          const _NoticeCard(message: _prototypeNotice),
          const SizedBox(height: 20),
          Text('Acceso al prototipo', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            _accessNotice,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('access-continue-button'),
            style: FilledButton.styleFrom(minimumSize: _actionMinSize),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const DraftsScreen()),
            ),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continuar al prototipo'),
          ),
        ],
      ),
    );
  }
}

/// Empty drafts shell. No property fixture, price or persistence.
class DraftsScreen extends StatelessWidget {
  const DraftsScreen({super.key});

  Future<void> _showNextStep(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('new-property-placeholder-dialog'),
      title: const Text('Paso siguiente no disponible'),
      content: const Text(_nextStepNotice),
      actions: [
        TextButton(
          key: const ValueKey('new-property-placeholder-close'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Borradores')),
      body: _PrototypePage(
        children: [
          Text('Borradores de inmuebles', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('new-property-button'),
            style: FilledButton.styleFrom(minimumSize: _actionMinSize),
            onPressed: () => _showNextStep(context),
            icon: const Icon(Icons.add),
            label: const Text('Nuevo inmueble'),
          ),
          const SizedBox(height: 20),
          const _NoticeCard(message: _draftsNotice),
          const SizedBox(height: 20),
          Card(
            key: const ValueKey('drafts-empty-state'),
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.home_work_outlined,
                      size: 36,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Todavía no hay borradores',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cuando crees un inmueble aparecerá en esta lista. Este '
                    'prototipo no guarda datos.',
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Responsive page wrapper: scrollable content capped at a readable width.
class _PrototypePage extends StatelessWidget {
  const _PrototypePage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: ListView(padding: const EdgeInsets.all(20), children: children),
      ),
    ),
  );
}

/// Honest prototype disclaimer reused by every implemented step.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );
}
