/// Commercial operation of a listing, as the staff API names it on the wire.
enum ListingOperation {
  sale('sale'),
  rent('rent');

  const ListingOperation(this.wireName);

  final String wireName;

  static ListingOperation fromWire(Object? value) =>
      ListingOperation.values.firstWhere(
        (operation) => operation.wireName == value,
        orElse: () {
          throw FormatException('Unknown listing operation: $value');
        },
      );
}

/// Review status of a listing (F04.3).
enum ListingStatus {
  draft('draft'),
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const ListingStatus(this.wireName);

  final String wireName;

  static ListingStatus fromWire(Object? value) =>
      ListingStatus.values.firstWhere(
        (status) => status.wireName == value,
        orElse: () {
          throw FormatException('Unknown listing status: $value');
        },
      );
}

/// A listing as seen by staff of its own agency, private fields included.
///
/// [basePrice] keeps the server's decimal string in COP; the app never turns it
/// into a floating-point number.
class StaffListing {
  const StaffListing({
    required this.listingId,
    required this.agencyId,
    required this.operation,
    required this.basePrice,
    required this.city,
    required this.zone,
    required this.bedrooms,
    required this.bathrooms,
    required this.description,
    required this.exactAddress,
    required this.status,
    required this.isPublished,
    required this.offerVersion,
    required this.createdAt,
  });

  /// Throws [FormatException] when [json] does not match the staff contract.
  factory StaffListing.fromJson(Map<String, Object?> json) => StaffListing(
    listingId: _string(json, 'listing_id'),
    agencyId: _string(json, 'agency_id'),
    operation: ListingOperation.fromWire(json['operation']),
    basePrice: _string(json, 'base_price'),
    city: _string(json, 'city'),
    zone: _string(json, 'zone'),
    bedrooms: _int(json, 'bedrooms'),
    bathrooms: _int(json, 'bathrooms'),
    description: _optionalString(json, 'description'),
    exactAddress: _optionalString(json, 'exact_address'),
    status: ListingStatus.fromWire(json['approval_status']),
    isPublished: _bool(json, 'is_published'),
    offerVersion: _int(json, 'offer_version'),
    createdAt: DateTime.parse(_string(json, 'created_at')),
  );

  final String listingId;
  final String agencyId;
  final ListingOperation operation;
  final String basePrice;
  final String city;
  final String zone;
  final int bedrooms;
  final int bathrooms;
  final String? description;
  final String? exactAddress;
  final ListingStatus status;
  final bool isPublished;
  final int offerVersion;
  final DateTime createdAt;
}

/// One entry of a listing's append-only review history.
class ListingTransitionEntry {
  const ListingTransitionEntry({
    required this.action,
    required this.toStatus,
    required this.observation,
    required this.actorRole,
    required this.createdAt,
  });

  factory ListingTransitionEntry.fromJson(Map<String, Object?> json) =>
      ListingTransitionEntry(
        action: _string(json, 'action'),
        toStatus: _string(json, 'to_status'),
        observation: _optionalString(json, 'observation'),
        actorRole: _string(json, 'actor_role'),
        createdAt: DateTime.parse(_string(json, 'created_at')),
      );

  final String action;
  final String toStatus;
  final String? observation;
  final String actorRole;
  final DateTime createdAt;
}

/// The only fields an agent may author; authority and state stay server-side.
class ListingDraftInput {
  const ListingDraftInput({
    required this.operation,
    required this.basePrice,
    required this.city,
    required this.zone,
    required this.bedrooms,
    required this.bathrooms,
    required this.description,
    required this.exactAddress,
  });

  final ListingOperation operation;
  final String basePrice;
  final String city;
  final String zone;
  final int bedrooms;
  final int bathrooms;
  final String? description;
  final String? exactAddress;

  Map<String, Object?> toJson() => {
    'operation': operation.wireName,
    'base_price': basePrice,
    'city': city,
    'zone': zone,
    'bedrooms': bedrooms,
    'bathrooms': bathrooms,
    'description': description,
    'exact_address': exactAddress,
  };
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Missing string field: $key');
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid string field: $key');
  return value;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('Missing integer field: $key');
  return value;
}

bool _bool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Missing boolean field: $key');
  return value;
}
