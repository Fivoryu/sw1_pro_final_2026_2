/// A confirmed listing photo with a short-lived signed link to view it.
class ListingPhoto {
  const ListingPhoto({
    required this.photoId,
    required this.contentType,
    required this.sizeBytes,
    required this.url,
    required this.createdAt,
  });

  factory ListingPhoto.fromJson(Map<String, Object?> json) {
    final photoId = json['photo_id'];
    final contentType = json['content_type'];
    final sizeBytes = json['size_bytes'];
    final url = json['url'];
    final createdAt = json['created_at'];
    if (photoId is! String ||
        contentType is! String ||
        sizeBytes is! int ||
        url is! String ||
        createdAt is! String) {
      throw const FormatException('Photo fields are invalid');
    }
    return ListingPhoto(
      photoId: photoId,
      contentType: contentType,
      sizeBytes: sizeBytes,
      url: url,
      createdAt: DateTime.parse(createdAt),
    );
  }

  final String photoId;
  final String contentType;
  final int sizeBytes;
  final String url;
  final DateTime createdAt;
}

/// Permission to upload one photo straight to object storage.
class PhotoUploadGrant {
  const PhotoUploadGrant({
    required this.photoId,
    required this.uploadUrl,
    required this.headers,
    required this.expiresAt,
  });

  factory PhotoUploadGrant.fromJson(Map<String, Object?> json) {
    final photoId = json['photo_id'];
    final uploadUrl = json['upload_url'];
    final method = json['upload_method'];
    final headers = json['upload_headers'];
    final expiresAt = json['expires_at'];
    if (photoId is! String ||
        uploadUrl is! String ||
        method != 'PUT' ||
        headers is! Map<String, Object?> ||
        expiresAt is! String) {
      throw const FormatException('Upload grant fields are invalid');
    }
    return PhotoUploadGrant(
      photoId: photoId,
      uploadUrl: uploadUrl,
      headers: {
        for (final entry in headers.entries) entry.key: entry.value as String,
      },
      expiresAt: DateTime.parse(expiresAt),
    );
  }

  final String photoId;
  final String uploadUrl;

  /// Headers the signed link requires, such as `Content-Type`.
  final Map<String, String> headers;
  final DateTime expiresAt;
}
