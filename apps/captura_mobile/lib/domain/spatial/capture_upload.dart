/// Pending capture-package uploads (F07.5): what is persisted on the phone
/// between app restarts and what the server reports. No Flutter, no I/O.
library;

/// Server-side state of a capture package
/// (`docs/api/f07-capture-package.md`, «API (staff)»).
enum RemoteCaptureStatus {
  awaitingUpload('awaiting_upload'),
  queued('queued'),
  processing('processing'),
  completed('completed'),
  failed('failed'),
  accepted('accepted');

  const RemoteCaptureStatus(this.wire);

  final String wire;

  /// Null for a value outside the contract, so a new server state is never
  /// shown as if it were a known one.
  static RemoteCaptureStatus? fromWire(Object? value) {
    for (final status in values) {
      if (status.wire == value) return status;
    }
    return null;
  }

  /// States after which the server has nothing more to do for the phone.
  bool get isTerminal =>
      this == completed || this == failed || this == accepted;
}

/// How far a package got on its way to the server. Every step is idempotent
/// on the server, so a restart can safely resume from the last saved stage.
enum UploadStage {
  /// Only on the phone.
  local,

  /// Registered; [PendingCaptureUpload.uploadUrl] is known.
  registered,

  /// The ZIP reached the object storage.
  uploaded,

  /// `complete` succeeded: the server owns the package now.
  completed,
}

/// One capture package on its way to the server, persisted per staff account.
class PendingCaptureUpload {
  const PendingCaptureUpload({
    required this.captureId,
    required this.listingId,
    required this.zipPath,
    required this.sizeBytes,
    required this.keyframeCount,
    required this.createdAt,
    this.stage = UploadStage.local,
    this.uploadUrl,
    this.remoteStatus,
    this.failureReason,
    this.lastError,
    this.permanent = false,
  });

  final String captureId;
  final String listingId;

  /// The local ZIP; null once `complete` succeeded and it was deleted.
  final String? zipPath;
  final int sizeBytes;
  final int keyframeCount;
  final DateTime createdAt;
  final UploadStage stage;
  final String? uploadUrl;
  final RemoteCaptureStatus? remoteStatus;

  /// Why the server could not reconstruct the package.
  final String? failureReason;

  /// The last local or network problem, phrased for the agent.
  final String? lastError;

  /// A rejection that retrying cannot fix (for example a package too large).
  final bool permanent;

  /// Nothing left to send; only the server's answer can still change.
  bool get isSent => stage == UploadStage.completed;

  bool get isFinished =>
      permanent || (isSent && (remoteStatus?.isTerminal ?? false));

  PendingCaptureUpload copyWith({
    String? zipPath,
    bool clearZipPath = false,
    UploadStage? stage,
    String? uploadUrl,
    bool clearUploadUrl = false,
    RemoteCaptureStatus? remoteStatus,
    String? failureReason,
    String? lastError,
    bool clearLastError = false,
    bool? permanent,
  }) => PendingCaptureUpload(
    captureId: captureId,
    listingId: listingId,
    zipPath: clearZipPath ? null : (zipPath ?? this.zipPath),
    sizeBytes: sizeBytes,
    keyframeCount: keyframeCount,
    createdAt: createdAt,
    stage: stage ?? this.stage,
    uploadUrl: clearUploadUrl ? null : (uploadUrl ?? this.uploadUrl),
    remoteStatus: remoteStatus ?? this.remoteStatus,
    failureReason: failureReason ?? this.failureReason,
    lastError: clearLastError ? null : (lastError ?? this.lastError),
    permanent: permanent ?? this.permanent,
  );

  Map<String, Object?> toJson() => {
    'captureId': captureId,
    'listingId': listingId,
    'zipPath': zipPath,
    'sizeBytes': sizeBytes,
    'keyframeCount': keyframeCount,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'stage': stage.name,
    'uploadUrl': uploadUrl,
    'remoteStatus': remoteStatus?.wire,
    'failureReason': failureReason,
    'lastError': lastError,
    'permanent': permanent,
  };

  /// Throws [FormatException] for a record that is not a valid upload.
  factory PendingCaptureUpload.fromJson(Map<String, Object?> json) {
    String string(String key) {
      final value = json[key];
      if (value is String && value.isNotEmpty) return value;
      throw FormatException('Pending upload field "$key" must be a string');
    }

    int integer(String key) {
      final value = json[key];
      if (value is int && value >= 0) return value;
      throw FormatException('Pending upload field "$key" must be an integer');
    }

    String? optional(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is String) return value;
      throw FormatException('Pending upload field "$key" must be a string');
    }

    final stageName = string('stage');
    final stage = UploadStage.values.where((s) => s.name == stageName);
    if (stage.isEmpty) {
      throw FormatException('Unknown upload stage "$stageName"');
    }
    final created = DateTime.tryParse(string('createdAt'));
    if (created == null) {
      throw const FormatException('Pending upload "createdAt" is not a date');
    }
    final remote = optional('remoteStatus');
    return PendingCaptureUpload(
      captureId: string('captureId'),
      listingId: string('listingId'),
      zipPath: optional('zipPath'),
      sizeBytes: integer('sizeBytes'),
      keyframeCount: integer('keyframeCount'),
      createdAt: created,
      stage: stage.first,
      uploadUrl: optional('uploadUrl'),
      remoteStatus: remote == null
          ? null
          : RemoteCaptureStatus.fromWire(remote),
      failureReason: optional('failureReason'),
      lastError: optional('lastError'),
      permanent: json['permanent'] == true,
    );
  }
}

/// Access to the local ZIPs, kept behind an interface so the upload logic
/// never touches the file system directly.
abstract interface class CapturePackageFiles {
  Future<bool> exists(String path);

  /// The ZIP as a byte stream (never loaded whole: packages reach 150 MB).
  Stream<List<int>> open(String path);

  Future<void> delete(String path);
}
