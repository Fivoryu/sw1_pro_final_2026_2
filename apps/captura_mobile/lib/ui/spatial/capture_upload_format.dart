import '../../domain/spatial/capture_upload.dart';
import '../../domain/spatial/capture_upload_controller.dart';

/// Binary megabytes with a decimal comma, as the agent reads them.
String megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';

/// What the screen says about one capture package, and which actions apply.
class CaptureUploadText {
  const CaptureUploadText({
    required this.title,
    required this.detail,
    this.progress,
    this.canRetry = false,
    this.canRefresh = false,
    this.canDismiss = false,
  });

  final String title;
  final String detail;

  /// 0..1 while uploading; null otherwise.
  final double? progress;

  /// The package is still on the phone and can be sent again.
  final bool canRetry;

  /// The server state can still change.
  final bool canRefresh;

  /// Nothing more will happen; the agent may clear it from the list.
  final bool canDismiss;
}

/// Honest Spanish copy for one package. The reconstruction result is never
/// shown on the phone: the agency reviews the draft in the panel.
CaptureUploadText captureUploadText(CaptureUploadItem item) {
  final upload = item.upload;
  switch (item.phase) {
    case UploadPhase.registering:
      return const CaptureUploadText(
        title: 'Preparando la subida…',
        detail: 'Registrando el recorrido en RoomForge.',
      );
    case UploadPhase.uploading:
      final fraction = item.progress ?? 0;
      return CaptureUploadText(
        title: fraction >= 1
            ? 'Esperando respuesta del almacenamiento…'
            : 'Subiendo el recorrido…',
        detail: fraction >= 1
            ? 'El envío todavía no está confirmado. Mantené la conexión '
                  'hasta recibir la respuesta del almacenamiento.'
            : '${(fraction * 100).floor()} % de ${megabytes(upload.sizeBytes)}',
        progress: fraction,
      );
    case UploadPhase.finishing:
      return const CaptureUploadText(
        title: 'Confirmando la subida…',
        detail: 'Falta avisarle al servidor que el recorrido llegó completo.',
      );
    case UploadPhase.checking:
      return const CaptureUploadText(
        title: 'Consultando el estado…',
        detail: 'Preguntándole al servidor cómo va la reconstrucción.',
      );
    case UploadPhase.idle:
      break;
  }

  final problem = upload.lastError;
  if (upload.permanent) {
    return CaptureUploadText(
      title: 'No se pudo subir el recorrido',
      detail: problem ?? 'El servidor rechazó el recorrido.',
      canDismiss: true,
    );
  }
  if (!upload.isSent) {
    return CaptureUploadText(
      title: problem == null
          ? 'Recorrido guardado en el teléfono'
          : 'Subida pendiente: no se completó el envío',
      detail:
          problem ??
          'Se sube cuando haya conexión (${megabytes(upload.sizeBytes)}).',
      canRetry: true,
    );
  }

  String withProblem(String text) => problem == null ? text : '$text\n$problem';
  return switch (upload.remoteStatus) {
    RemoteCaptureStatus.awaitingUpload => CaptureUploadText(
      title: 'Esperando la subida',
      detail: withProblem(
        'El servidor todavía no confirmó la recepción del recorrido.',
      ),
      canRefresh: true,
    ),
    RemoteCaptureStatus.queued => CaptureUploadText(
      title: 'En la cola de reconstrucción',
      detail: withProblem(
        'El servidor recibió el recorrido y todavía no empezó a '
        'reconstruir el ambiente.',
      ),
      canRefresh: true,
    ),
    RemoteCaptureStatus.processing => CaptureUploadText(
      title: 'Reconstruyendo el ambiente',
      detail: withProblem(
        'Puede tardar unos minutos. Podés cerrar la app: el servidor sigue '
        'trabajando.',
      ),
      canRefresh: true,
    ),
    RemoteCaptureStatus.completed => CaptureUploadText(
      title: 'Borrador generado · requiere revisión',
      detail: withProblem(
        'El procesamiento terminó; las medidas aún deben validarse. La agencia '
        'revisa escala y geometría en el panel o continúa con captura manual. Desde el teléfono no '
        'se muestra el resultado en 3D.',
      ),
      canDismiss: true,
    ),
    RemoteCaptureStatus.failed => CaptureUploadText(
      title: 'La reconstrucción falló',
      detail: withProblem(
        upload.failureReason == null
            ? 'El servidor no indicó el motivo. Volvé a capturar el ambiente.'
            : reconstructionFailureText(upload.failureReason!),
      ),
      canDismiss: true,
    ),
    RemoteCaptureStatus.accepted => CaptureUploadText(
      title: 'Borrador aceptado',
      detail: withProblem('La agencia ya lo guardó en el editor.'),
      canDismiss: true,
    ),
    null => CaptureUploadText(
      title: 'Recorrido enviado',
      detail: withProblem('Falta consultar el estado de la reconstrucción.'),
      canRefresh: true,
    ),
  };
}

String reconstructionFailureText(String reason) {
  final classified = reason.replaceFirst('Invalid package: ', '');
  final context = [
    if (classified.contains('Sin referencia métrica.'))
      'Falta una referencia: confirmá las dimensiones reales medidas del objeto.',
    if (classified.contains('Referencia sin escala aplicada.'))
      'Las dimensiones aportadas no pudieron aplicarse al modelo. Mostrá el objeto '
          'completo con su pared o piso de apoyo alrededor.',
    if (classified.contains('Piezas desconectadas.'))
      'Faltan vistas compartidas entre zonas del recorrido; no se conoce su posición relativa.',
    if (classified.contains('Reloj no verificado.'))
      'El reloj de cámara no está verificado; las medidas no pueden certificarse.',
  ].join('\n');
  if (classified.startsWith('F07_OVERLAP:')) {
    return 'Se registraron pocas vistas para cerrar el ambiente. Conservá vistas '
        'superpuestas al pasar por bases y esquinas; incluí detalles con textura. '
        'También podés usar captura manual.\n$classified\n$context';
  }
  if (classified.startsWith('F07_POSES:')) {
    return 'No se pudieron relacionar suficientes imágenes. Revisá luz, nitidez y '
        'textura; movete despacio con vistas superpuestas, o usá captura manual.';
  }
  if (classified.startsWith('F07_CONTOUR:')) {
    return 'Las paredes observadas no permiten cerrar el ambiente. Revisá bases y '
        'esquinas, manteniendo la pared anterior a la vista, o usá captura manual.\n$context';
  }
  if (classified.startsWith('F07_FFMPEG:') ||
      classified.startsWith('F07_SFM')) {
    return '$classified\nEl video subido se conserva según la política de retención. '
        'No necesitás grabar otra vez para pedir revisión técnica.';
  }
  return 'Motivo: $reason. Podés revisar la captura o usar captura manual.';
}
