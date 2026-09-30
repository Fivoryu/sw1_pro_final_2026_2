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
  kUnauthorized: 'La sesión no es válida o expiró.',
  kForbidden: 'No tenés permiso para realizar esta acción.',
  kNotFound: 'El recurso solicitado no existe.',
  kConflict: 'La operación entra en conflicto con datos existentes.',
  kDependencyUnavailable: 'Un servicio requerido no está disponible.',
  kInternalError: 'Ocurrió un error inesperado. Intentá de nuevo.',
  kNetworkError: 'No pudimos contactar el servicio. Revisá tu conexión.',
};

/// A rejected customer authentication call.
///
/// [detail] is always safe to show: it comes from the server's error envelope
/// or from a local message chosen here, never from an unparsed response body.
class CustomerAuthFailure implements Exception {
  const CustomerAuthFailure({
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
  String toString() => 'CustomerAuthFailure($code)';
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
/// body actually carries it; otherwise the status decides the code and the
/// detail is replaced by a local message so unparsed bytes never reach the UI.
CustomerAuthFailure failureFromResponse({
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
      return CustomerAuthFailure(
        code: code,
        detail: detail,
        statusCode: statusCode,
      );
    }
  }
  final fallback = codeForStatus(statusCode);
  return CustomerAuthFailure(
    code: fallback,
    detail: kSafeFailureDetails[fallback] ?? kSafeFailureDetails[kInternalError]!,
    statusCode: statusCode,
  );
}

/// Failure for a transport error: nothing was parsed, so retrying is safe.
CustomerAuthFailure networkFailure() => CustomerAuthFailure(
  code: kNetworkError,
  detail: kSafeFailureDetails[kNetworkError]!,
  isNetworkFailure: true,
);

/// Failure for a success status whose body did not match the contract.
CustomerAuthFailure malformedResponseFailure() => CustomerAuthFailure(
  code: kInternalError,
  detail: kSafeFailureDetails[kInternalError]!,
);
