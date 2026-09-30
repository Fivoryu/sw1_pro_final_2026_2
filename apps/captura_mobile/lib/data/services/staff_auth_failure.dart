import 'dart:convert';

/// Stable error codes shared by the RoomForge API.
const String kValidationError = 'validation_error';
const String kUnauthorized = 'unauthorized';
const String kForbidden = 'forbidden';
const String kNotFound = 'not_found';
const String kConflict = 'conflict';
const String kDependencyUnavailable = 'dependency_unavailable';
const String kInternalError = 'internal_error';

/// The transport never reached the API, so the caller can offer a retry.
const String kNetworkError = 'network_error';

/// User-facing text chosen locally. Server details are used only when the
/// response carries the documented envelope.
const Map<String, String> kSafeFailureDetails = {
  kValidationError: 'La solicitud no es válida.',
  kUnauthorized: 'Las credenciales o la sesión no son válidas.',
  kForbidden: 'Tu cuenta no tiene permisos para esta acción.',
  kNotFound: 'El recurso solicitado no existe.',
  kConflict: 'La operación entra en conflicto con datos existentes.',
  kDependencyUnavailable: 'Un servicio requerido no está disponible.',
  kInternalError: 'Ocurrió un error inesperado. Intentá de nuevo.',
  kNetworkError: 'No pudimos contactar el servicio. Revisá tu conexión.',
};

/// Name of the HttpOnly refresh cookie the staff API sets.
const String kRefreshCookieName = 'roomforge_refresh';

/// A rejected staff authentication call.
///
/// [detail] is always safe to show: it comes from the server's envelope or from
/// a local message chosen here, never from an unparsed response body.
class StaffAuthFailure implements Exception {
  const StaffAuthFailure({
    required this.code,
    required this.detail,
    this.statusCode,
    this.isNetworkFailure = false,
  });

  final String code;
  final String detail;
  final int? statusCode;
  final bool isNetworkFailure;

  @override
  String toString() => 'StaffAuthFailure($code)';
}

/// Maps an HTTP status to the shared error vocabulary.
String codeForStatus(int statusCode) {
  if (statusCode == 400 || statusCode == 422) return kValidationError;
  if (statusCode == 401) return kUnauthorized;
  if (statusCode == 403) return kForbidden;
  if (statusCode == 404) return kNotFound;
  if (statusCode == 409) return kConflict;
  if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
    return kDependencyUnavailable;
  }
  return kInternalError;
}

/// Builds the failure for a non-success response.
///
/// The documented envelope `{"detail": ..., "code": ...}` is trusted when the
/// body carries it; otherwise the status decides the code and the detail is
/// replaced by a local message so unparsed bytes never reach the UI.
StaffAuthFailure failureFromResponse({
  required int statusCode,
  required String body,
}) {
  Map<String, Object?>? envelope;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, Object?>) {
      envelope = decoded;
    }
  } on FormatException {
    envelope = null;
  }
  if (envelope != null) {
    final code = envelope['code'];
    final detail = envelope['detail'];
    if (code is String && detail is String && code.isNotEmpty) {
      return StaffAuthFailure(
        code: code,
        detail: detail,
        statusCode: statusCode,
      );
    }
  }
  final fallback = codeForStatus(statusCode);
  return StaffAuthFailure(
    code: fallback,
    detail: kSafeFailureDetails[fallback] ?? kSafeFailureDetails[kInternalError]!,
    statusCode: statusCode,
  );
}

/// Failure for a transport error: nothing was parsed, so retrying is safe.
StaffAuthFailure networkFailure() => const StaffAuthFailure(
  code: kNetworkError,
  detail: 'No pudimos contactar el servicio. Revisá tu conexión.',
  isNetworkFailure: true,
);

/// Failure for a success status whose body did not match the contract.
StaffAuthFailure malformedResponseFailure() => const StaffAuthFailure(
  code: kInternalError,
  detail: 'Ocurrió un error inesperado. Intentá de nuevo.',
);

/// Reads the opaque refresh value out of a `set-cookie` header, if present.
///
/// The staff API is browser-shaped, so a mobile client has no cookie jar and
/// must carry this value itself.
String? readRefreshCookie(Map<String, String> headers) {
  final raw = headers['set-cookie'];
  if (raw == null) return null;

  for (final part in raw.split(RegExp('[;,]'))) {
    final trimmed = part.trim();
    final prefix = '$kRefreshCookieName=';
    if (trimmed.startsWith(prefix)) {
      final value = trimmed.substring(prefix.length);
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}
