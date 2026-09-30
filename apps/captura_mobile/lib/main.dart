import 'package:flutter/material.dart';

import 'data/services/staff_auth_api.dart';
import 'data/services/staff_credential_store.dart';
import 'domain/staff_session_controller.dart';

/// Backend used by the running app. Override it per environment with
/// `--dart-define=ROOMFORGE_API_BASE_URL=https://host`.
const _apiBaseUrl = String.fromEnvironment(
  'ROOMFORGE_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

/// Prototype-only copy shared by the capture screens. Nothing in this app
/// captures, persists or uploads real data.
const _prototypeNotice =
    'Prototipo de interfaz: no hay cámara ni datos guardados.';

const _credentialsNotice =
    'El acceso valida tus credenciales y el código de tu segundo factor.';

const _draftsNotice =
    'Prototipo local: los borradores se muestran solo en pantalla; no se '
    'guardan ni se sincronizan.';

/// Minimum 48 dp touch target for the prototype primary actions.
const _actionMinSize = Size.fromHeight(48);

/// Readable content width on tablets and resizable windows.
const double _contentMaxWidth = 720;

void main() => runApp(
  CaptureApp(
    controller: StaffSessionController(
      api: StaffAuthApi(baseUrl: _apiBaseUrl),
      credentialStore: SecureStaffCredentialStore(),
    ),
  ),
);

class CaptureApp extends StatelessWidget {
  const CaptureApp({super.key, required this.controller});

  final StaffSessionController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RoomForge Captura',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D4ED8)),
      useMaterial3: true,
    ),
    home: AgentAccessScreen(controller: controller),
  );
}

/// Access step: credentials, then the TOTP proof, then the private drafts.
class AgentAccessScreen extends StatefulWidget {
  const AgentAccessScreen({super.key, required this.controller});

  final StaffSessionController controller;

  @override
  State<AgentAccessScreen> createState() => _AgentAccessScreenState();
}

class _AgentAccessScreenState extends State<AgentAccessScreen> {
  final _credentialsKey = GlobalKey<FormState>();
  final _codeKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.restore();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _submitting = true);
    await action();
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RoomForge Captura')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _PrototypePage(
        children: switch (widget.controller.status) {
          StaffSessionStatus.restoring => _restoring(context),
          StaffSessionStatus.unavailable => _unavailable(context),
          StaffSessionStatus.awaitingCode => _codeStep(context),
          StaffSessionStatus.signedOut => _credentialsStep(context),
          StaffSessionStatus.signedIn => _signedIn(context),
        },
      ),
    ),
  );

  List<Widget> _heading(BuildContext context, String title) => [
    Text('Acceso del agente', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 20),
    const _NoticeCard(message: _prototypeNotice),
    const SizedBox(height: 20),
    Text(title, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
  ];

  List<Widget> _restoring(BuildContext context) => [
    ..._heading(context, 'Comprobando tu sesión'),
    const Center(
      key: ValueKey('access-restoring'),
      child: CircularProgressIndicator(),
    ),
  ];

  List<Widget> _unavailable(BuildContext context) => [
    ..._heading(context, 'Sin conexión'),
    _message(context, widget.controller.message),
    const SizedBox(height: 16),
    FilledButton(
      key: const ValueKey('access-retry'),
      style: FilledButton.styleFrom(minimumSize: _actionMinSize),
      onPressed: widget.controller.restore,
      child: const Text('Reintentar'),
    ),
  ];

  List<Widget> _credentialsStep(BuildContext context) => [
    ..._heading(context, 'Ingresá con tu cuenta de agente'),
    Text(
      _credentialsNotice,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
    ),
    const SizedBox(height: 16),
    if (widget.controller.message != null) _message(context, widget.controller.message),
    Form(
      key: _credentialsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('access-email-field'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo electrónico',
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Ingresá tu correo electrónico'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('access-password-field'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Contraseña',
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.isEmpty)
                ? 'Ingresá tu contraseña'
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('access-credentials-submit'),
            style: FilledButton.styleFrom(minimumSize: _actionMinSize),
            onPressed: _submitting
                ? null
                : () {
                    if (!(_credentialsKey.currentState?.validate() ?? false)) {
                      return;
                    }
                    final email = _email.text.trim();
                    final password = _password.text;
                    _run(
                      () => widget.controller.startLogin(
                        email: email,
                        password: password,
                      ),
                    );
                  },
            child: const Text('Continuar'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _codeStep(BuildContext context) => [
    ..._heading(context, 'Ingresá el código de tu segundo factor'),
    if (widget.controller.message != null) _message(context, widget.controller.message),
    Form(
      key: _codeKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('access-code-field'),
            controller: _code,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Código de 6 dígitos',
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Ingresá el código'
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('access-code-submit'),
            style: FilledButton.styleFrom(minimumSize: _actionMinSize),
            onPressed: _submitting
                ? null
                : () {
                    if (!(_codeKey.currentState?.validate() ?? false)) return;
                    final code = _code.text.trim();
                    _run(() => widget.controller.submitCode(code));
                  },
            child: const Text('Verificar código'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _signedIn(BuildContext context) {
    final account = widget.controller.account;
    return [
      ..._heading(context, 'Sesión iniciada'),
      Text(
        account?.email ?? '',
        key: const ValueKey('access-account-email'),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      if (widget.controller.message != null) ...[
        const SizedBox(height: 16),
        _message(context, widget.controller.message),
      ],
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
      const SizedBox(height: 8),
      OutlinedButton(
        key: const ValueKey('access-logout'),
        style: OutlinedButton.styleFrom(minimumSize: _actionMinSize),
        onPressed: _submitting ? null : () => _run(widget.controller.signOut),
        child: const Text('Cerrar sesión'),
      ),
    ];
  }

  Widget _message(BuildContext context, String? message) => Card(
    key: const ValueKey('access-message'),
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(message ?? ''),
    ),
  );
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
          const Text('Paso 1 de 5 · Prototipo local'),
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
          const Text('Paso 2 de 5 · Prototipo local'),
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
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('rooms-photos-continue'),
            style: FilledButton.styleFrom(minimumSize: _actionMinSize),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const GeometryObjectsScreen(),
              ),
            ),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continuar a corregir geometría'),
          ),
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

/// Step three: illustrative demonstration shapes with honest provenance.
class GeometryObjectsScreen extends StatefulWidget {
  const GeometryObjectsScreen({super.key});

  @override
  State<GeometryObjectsScreen> createState() => _GeometryObjectsScreenState();
}

class _DemoShape {
  const _DemoShape(this.id, this.kind, this.label);

  final String id;
  final String kind;
  final String label;
}

const _demoShapes = <_DemoShape>[
  _DemoShape('room', 'Contorno', 'Ambiente de demostración'),
  _DemoShape('object', 'Bloque', 'Objeto de demostración'),
];

class _GeometryObjectsScreenState extends State<GeometryObjectsScreen> {
  final Set<String> _corrected = <String>{};

  void _toggle(String id) => setState(() {
    if (!_corrected.remove(id)) _corrected.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo inmueble'),
        leading: const BackButton(key: ValueKey('geometry-objects-back')),
      ),
      body: KeyedSubtree(
        key: const ValueKey('geometry-objects-screen'),
        child: _PrototypePage(
          children: [
            Text(
              'Corregir geometría y objetos',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text('Paso 3 de 5 · Prototipo local'),
            const SizedBox(height: 20),
            const _NoticeCard(
              message:
                  'Formas ilustrativas: no provienen de fotos, cámara, medición '
                  'ni reconstrucción real. Corregir aquí solo cambia el estado '
                  'local del prototipo.',
            ),
            const SizedBox(height: 20),
            for (final shape in _demoShapes) ...[
              Card(
                key: ValueKey('shape-${shape.id}-card'),
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${shape.kind} · ${shape.label}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Forma ilustrativa del prototipo; sin medición real ni '
                        'procedencia fotográfica.',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${shape.label}: '
                        '${_corrected.contains(shape.id) ? 'corregida' : 'pendiente'}',
                        key: ValueKey('shape-${shape.id}-state'),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          key: ValueKey('shape-${shape.id}-correction'),
                          onPressed: () => _toggle(shape.id),
                          child: Text(
                            _corrected.contains(shape.id)
                                ? 'Marcar como pendiente'
                                : 'Marcar como corregida',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'Formas corregidas: ${_corrected.length} de ${_demoShapes.length}',
              key: const ValueKey('geometry-correction-summary'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('geometry-continue'),
              style: FilledButton.styleFrom(minimumSize: _actionMinSize),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const OfferPreparationScreen(),
                ),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Continuar a preparar oferta'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step four: the approved offer structure without any commercial value.
class OfferPreparationScreen extends StatelessWidget {
  const OfferPreparationScreen({super.key});

  static const _structure = <(String, String)>[
    ('Precio base', 'pendiente de definir en una fase posterior'),
    ('Ajustes seleccionados', 'pendiente de definir en una fase posterior'),
    (
      'Total calculado',
      'regla de dos decimales aprobada para fases posteriores',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo inmueble'),
        leading: const BackButton(key: ValueKey('offer-back')),
      ),
      body: KeyedSubtree(
        key: const ValueKey('offer-screen'),
        child: _PrototypePage(
          children: [
            Text('Preparar oferta', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('Paso 4 de 5 · Prototipo local'),
            const SizedBox(height: 20),
            const _NoticeCard(
              message:
                  'Estructura conceptual: no se muestran precios, moneda, '
                  'impuestos, cargos, descuentos ni vigencia.',
            ),
            const SizedBox(height: 20),
            Card(
              color: theme.colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, value) in _structure) ...[
                      Text(label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(value),
                      const SizedBox(height: 12),
                    ],
                    const Text(
                      'Sin moneda definida en F02: la moneda y las condiciones '
                      'comerciales siguen pendientes.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('offer-continue'),
              style: FilledButton.styleFrom(minimumSize: _actionMinSize),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const ReviewSummaryScreen(),
                ),
              ),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Revisar resumen'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step five: explicit confirmation, then a simulated submission result.
class ReviewSummaryScreen extends StatefulWidget {
  const ReviewSummaryScreen({super.key});

  @override
  State<ReviewSummaryScreen> createState() => _ReviewSummaryScreenState();
}

class _ReviewSummaryScreenState extends State<ReviewSummaryScreen> {
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo inmueble'),
        leading: const BackButton(key: ValueKey('review-summary-back')),
      ),
      body: KeyedSubtree(
        key: const ValueKey('review-summary-screen'),
        child: _PrototypePage(
          children: [
            Text('Revisar resumen', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('Paso 5 de 5 · Prototipo local'),
            const SizedBox(height: 20),
            const _NoticeCard(
              message:
                  'Confirmación del prototipo: nada se envía, se guarda ni se '
                  'sincroniza.',
            ),
            const SizedBox(height: 20),
            const _SummaryRow(
              label: 'Objeto:',
              value: 'borrador de demostración sin datos reales',
            ),
            const _SummaryRow(
              label: 'Consecuencia:',
              value:
                  'el borrador aparecería en la cola de revisión de la '
                  'agencia (simulado)',
            ),
            const _SummaryRow(
              label: 'Acción elegida:',
              value: 'enviar a revisión (simulado)',
            ),
            const SizedBox(height: 24),
            if (_submitted)
              Card(
                key: const ValueKey('submission-result'),
                color: theme.colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Envío simulado registrado',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text('Estado: pendiente de revisión (simulado)'),
                      const SizedBox(height: 8),
                      const Text(
                        'Nada se guarda ni se sincroniza: no hay persistencia, '
                        'carga ni notificación real; no se envió nada real.',
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          key: const ValueKey('result-restart'),
                          onPressed: () => Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst),
                          child: const Text('Volver al inicio del prototipo'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              FilledButton.icon(
                key: const ValueKey('confirm-submit'),
                style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                onPressed: () => setState(() => _submitted = true),
                icon: const Icon(Icons.send),
                label: const Text('Confirmar envío (simulado)'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value),
      ],
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
