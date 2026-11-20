import 'catalog_models.dart';

/// One of the customer's favorites. [listing] is null when the listing is no
/// longer public: the favorite stays, but nothing about the listing is shown.
class FavoriteEntry {
  const FavoriteEntry({
    required this.listingId,
    required this.favoritedAt,
    required this.available,
    this.listing,
  });

  factory FavoriteEntry.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Favorite must be an object');
    }
    final listingId = json['listing_id'];
    final favoritedAt = json['favorited_at'];
    final available = json['available'];
    final listing = json['listing'];
    if (listingId is! String || favoritedAt is! String || available is! bool) {
      throw const FormatException('Favorite fields are invalid');
    }
    if (available != (listing != null)) {
      throw const FormatException('Favorite availability is inconsistent');
    }
    return FavoriteEntry(
      listingId: listingId,
      favoritedAt: DateTime.parse(favoritedAt),
      available: available,
      listing: listing == null ? null : CatalogListing.fromJson(listing),
    );
  }

  final String listingId;
  final DateTime favoritedAt;
  final bool available;
  final CatalogListing? listing;
}

/// A named set of catalog filters the customer can apply again.
///
/// The zone search point is never part of it: the customer's location is not
/// stored (F14.5, S4).
class SavedSearch {
  const SavedSearch({
    required this.id,
    required this.name,
    required this.filters,
    required this.createdAt,
  });

  factory SavedSearch.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Saved search must be an object');
    }
    final id = json['id'];
    final name = json['name'];
    final createdAt = json['created_at'];
    if (id is! String || name is! String || createdAt is! String) {
      throw const FormatException('Saved search fields are invalid');
    }
    return SavedSearch(
      id: id,
      name: name,
      filters: savedFiltersFromJson(json['filters']),
      createdAt: DateTime.parse(createdAt),
    );
  }

  final String id;
  final String name;
  final CatalogFilters filters;
  final DateTime createdAt;
}

/// Body of `filters` for a saved search: the catalog filters without the zone.
Map<String, Object?> savedFiltersToJson(CatalogFilters filters) => {
  'city': ?filters.city,
  'zone': ?filters.zone,
  'operation': ?filters.operation?.wireName,
  'min_base_price': ?filters.minBasePrice,
  'max_base_price': ?filters.maxBasePrice,
  'min_rooms': ?filters.minBedrooms,
  'min_bathrooms': ?filters.minBathrooms,
};

CatalogFilters savedFiltersFromJson(Object? json) {
  if (json is! Map<String, Object?>) {
    throw const FormatException('Filters must be an object');
  }
  String? text(String key) {
    final value = json[key];
    if (value != null && value is! String) {
      throw FormatException('Filter $key is invalid');
    }
    return value as String?;
  }

  int? number(String key) {
    final value = json[key];
    if (value != null && value is! int) {
      throw FormatException('Filter $key is invalid');
    }
    return value as int?;
  }

  final operation = json['operation'];
  return CatalogFilters(
    city: text('city'),
    zone: text('zone'),
    operation: operation == null ? null : ListingOperation.fromWire(operation),
    minBasePrice: text('min_base_price'),
    maxBasePrice: text('max_base_price'),
    minBedrooms: number('min_rooms'),
    minBathrooms: number('min_bathrooms'),
  );
}
