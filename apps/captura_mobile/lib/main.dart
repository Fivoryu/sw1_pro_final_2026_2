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

  void _openNewPropertyPrototype(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const BasicOperationScreen()),
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
            onPressed: () => _openNewPropertyPrototype(context),
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

/// Step one of the local, unsaved new-property prototype.
class BasicOperationScreen extends StatelessWidget {
  const BasicOperationScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Nuevo inmueble'),
      leading: const BackButton(key: ValueKey('basic-operation-back')),
    ),
    body: KeyedSubtree(
      key: const ValueKey('basic-operation-screen'),
      child: _PrototypePage(
        children: [
          Text(
            'Datos básicos y operación',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text('Paso 1 de 2 · Prototipo local'),
          const SizedBox(height: 20),
          const _NoticeCard(
            message:
                'Esta pantalla demuestra el recorrido, pero no define campos '
                'F04 ni valores de ejemplo.',
          ),
          const SizedBox(height: 20),
          Text(
            'La captura de datos básicos y de operación todavía no está '
            'implementada.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No hay guardado, sincronización ni inmueble creado en este '
            'prototipo local.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('basic-operation-continue'),
            style: FilledButton.styleFrom(minimumSize: _actionMinSize),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const RoomsPhotosScreen(),
              ),
            ),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continuar a ambientes y fotos'),
          ),
        ],
      ),
    ),
  );
}

/// Step two: all permission, connectivity and failure states are simulated.
class RoomsPhotosScreen extends StatefulWidget {
  const RoomsPhotosScreen({super.key});

  @override
  State<RoomsPhotosScreen> createState() => _RoomsPhotosScreenState();
}

enum _PhotoPermission { required, denied, granted }

class _RoomsPhotosScreenState extends State<RoomsPhotosScreen> {
  _PhotoPermission _permission = _PhotoPermission.required;
  bool _photoCaptured = false;
  bool _offline = false;
  bool _error = false;
  bool _retried = false;

  String get _permissionLabel => switch (_permission) {
    _PhotoPermission.required => 'Permiso de fotos: requerido (simulado)',
    _PhotoPermission.denied => 'Permiso de fotos: rechazado (simulado)',
    _PhotoPermission.granted => 'Permiso de fotos: concedido (simulado)',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Nuevo inmueble'),
      leading: const BackButton(key: ValueKey('rooms-photos-back')),
    ),
    body: KeyedSubtree(
      key: const ValueKey('rooms-photos-screen'),
      child: _PrototypePage(
        children: [
          Text(
            'Ambientes y fotos',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text('Paso 2 de 2 · Prototipo local'),
          const SizedBox(height: 20),
          const _NoticeCard(
            message:
                'Este paso solo muestra estados de interfaz. No se guardan '
                'fotos, ambientes ni inmueble.',
          ),
          const SizedBox(height: 24),
          Text(
            'Permiso de fotos',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(_permissionLabel, key: const ValueKey('photo-permission-state')),
          const SizedBox(height: 12),
          _stateButton(
            key: const ValueKey('simulate-photo-denied'),
            label: 'Simular permiso rechazado',
            onPressed: () =>
                setState(() => _permission = _PhotoPermission.denied),
          ),
          const SizedBox(height: 8),
          _stateButton(
            key: const ValueKey('simulate-photo-granted'),
            label: 'Simular permiso concedido',
            onPressed: () =>
                setState(() => _permission = _PhotoPermission.granted),
          ),
          const SizedBox(height: 24),
          Text('Conectividad', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_offline)
            const Text(
              'Estado sin conexión (simulado)',
              key: ValueKey('offline-state'),
            )
          else
            const Text('Estado conectado (simulado, sin red real)'),
          const SizedBox(height: 12),
          _stateButton(
            key: const ValueKey('simulate-offline'),
            label: _offline
                ? 'Simular estado conectado'
                : 'Simular estado sin conexión',
            onPressed: () => setState(() => _offline = !_offline),
          ),
          const SizedBox(height: 24),
          Text('Recuperación', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_error)
            _ErrorState(
              onRetry: () => setState(() {
                _error = false;
                _retried = true;
              }),
            )
          else ...[
            if (_retried) const Text('Reintento completado (simulado)'),
            _stateButton(
              key: const ValueKey('simulate-error'),
              label: 'Simular error',
              onPressed: () => setState(() => _error = true),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Captura de fotos',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          _stateButton(
            key: const ValueKey('simulate-camera-capture'),
            label: _photoCaptured
                ? 'Simular otra captura de foto'
                : 'Simular captura de foto',
            onPressed: () => setState(() => _photoCaptured = true),
          ),
          if (_photoCaptured) ...[
            const SizedBox(height: 12),
            const Text('Captura de foto simulada (sin cámara real)'),
            const SizedBox(height: 8),
            Card(
              key: const ValueKey('simulated-photo-placeholder'),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.photo_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ilustración local; no es una foto capturada.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _stateButton({
    required Key key,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    height: 48,
    child: OutlinedButton(key: key, onPressed: onPressed, child: Text(label)),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('simulated-error-state'),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Error simulado: este paso no está disponible.'),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              key: const ValueKey('simulated-retry'),
              onPressed: onRetry,
              child: const Text('Reintentar (simulado)'),
            ),
          ),
        ],
      ),
    ),
  );
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
