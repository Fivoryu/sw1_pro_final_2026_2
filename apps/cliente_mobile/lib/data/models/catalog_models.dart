/// Commercial operation of a published listing; the wire names are the API's.
enum ListingOperation {
  sale('sale'),
  rent('rent');

  const ListingOperation(this.wireName);

  final String wireName;

  static ListingOperation fromWire(Object? value) => values.firstWhere(
    (operation) => operation.wireName == value,
    orElse: () => throw const FormatException('Unknown listing operation'),
  );
}

/// An amount as the server sends it: a base-ten decimal string and its
/// currency, never converted to a binary floating point number.
class CatalogMoney {
  const CatalogMoney({required this.amount, required this.currency});

  factory CatalogMoney.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Money must be an object');
    }
    final amount = json['amount'];
    final currency = json['currency'];
    if (amount is! String || currency is! String) {
      throw const FormatException('Money fields are invalid');
    }
    return CatalogMoney(amount: amount, currency: currency);
  }

  final String amount;
  final String currency;
}

/// One published listing as the public catalog lists it.
class CatalogListing {
  const CatalogListing({
    required this.listingId,
    required this.offerVersion,
    required this.operation,
    required this.basePrice,
    required this.city,
    required this.zone,
    this.coverPhotoUrl,
  });

  factory CatalogListing.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Listing must be an object');
    }
    final listingId = json['listing_id'];
    final offerVersion = json['offer_version'];
    final city = json['city'];
    final zone = json['zone'];
    final cover = json['cover_photo_url'];
    if (listingId is! String ||
        offerVersion is! int ||
        city is! String ||
        zone is! String ||
        (cover != null && cover is! String)) {
      throw const FormatException('Listing fields are invalid');
    }
    return CatalogListing(
      listingId: listingId,
      offerVersion: offerVersion,
      operation: ListingOperation.fromWire(json['operation']),
      basePrice: CatalogMoney.fromJson(json['base_price']),
      city: city,
      zone: zone,
      coverPhotoUrl: cover as String?,
    );
  }

  final String listingId;
  final int offerVersion;
  final ListingOperation operation;
  final CatalogMoney basePrice;
  final String city;
  final String zone;

  /// Short-lived signed link to the first photo, or null without photos.
  final String? coverPhotoUrl;
}

/// A published listing photo behind a short-lived signed link.
class CatalogPhoto {
  const CatalogPhoto({required this.photoId, required this.url});

  factory CatalogPhoto.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Photo must be an object');
    }
    final photoId = json['photo_id'];
    final url = json['url'];
    if (photoId is! String || url is! String) {
      throw const FormatException('Photo fields are invalid');
    }
    return CatalogPhoto(photoId: photoId, url: url);
  }

  final String photoId;
  final String url;
}

/// An optional item the agency prices apart from the base price.
class CatalogExtra {
  const CatalogExtra({
    required this.extraId,
    required this.name,
    required this.price,
  });

  factory CatalogExtra.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Extra must be an object');
    }
    final extraId = json['extra_id'];
    final name = json['name'];
    if (extraId is! String || name is! String) {
      throw const FormatException('Extra fields are invalid');
    }
    return CatalogExtra(
      extraId: extraId,
      name: name,
      price: CatalogMoney.fromJson(json['price']),
    );
  }

  final String extraId;
  final String name;
  final CatalogMoney price;
}

/// Public detail of a listing: the listed fields plus rooms and extras.
class CatalogListingDetail {
  const CatalogListingDetail({
    required this.listing,
    required this.bedrooms,
    required this.bathrooms,
    required this.extras,
    this.photos = const [],
  });

  factory CatalogListingDetail.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Detail must be an object');
    }
    final bedrooms = json['bedrooms'];
    final bathrooms = json['bathrooms'];
    final extras = json['extras'];
    final photos = json['photos'] ?? const <Object?>[];
    if (bedrooms is! int ||
        bathrooms is! int ||
        extras is! List<Object?> ||
        photos is! List<Object?>) {
      throw const FormatException('Detail fields are invalid');
    }
    return CatalogListingDetail(
      listing: CatalogListing.fromJson(json),
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      extras: extras.map(CatalogExtra.fromJson).toList(growable: false),
      photos: photos.map(CatalogPhoto.fromJson).toList(growable: false),
    );
  }

  final CatalogListing listing;
  final int bedrooms;
  final int bathrooms;
  final List<CatalogExtra> extras;

  /// Gallery in upload order; the first one is the cover.
  final List<CatalogPhoto> photos;
}

/// One page of search results; [nextCursor] is null on the last page.
class CatalogPage {
  const CatalogPage({required this.items, required this.nextCursor});

  factory CatalogPage.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('Page must be an object');
    }
    final items = json['items'];
    final nextCursor = json['next_cursor'];
    if (items is! List<Object?> ||
        (nextCursor != null && nextCursor is! String)) {
      throw const FormatException('Page fields are invalid');
    }
    return CatalogPage(
      items: items.map(CatalogListing.fromJson).toList(growable: false),
      nextCursor: nextCursor as String?,
    );
  }

  final List<CatalogListing> items;
  final String? nextCursor;
}

/// Search filters of the public catalog; a null field is not sent.
class CatalogFilters {
  const CatalogFilters({
    this.city,
    this.zone,
    this.operation,
    this.minBasePrice,
    this.maxBasePrice,
    this.minBedrooms,
    this.minBathrooms,
  });

  final String? city;
  final String? zone;
  final ListingOperation? operation;

  /// Decimal strings with up to two decimals, as the API accepts them.
  final String? minBasePrice;
  final String? maxBasePrice;
  final int? minBedrooms;
  final int? minBathrooms;

  bool get isEmpty => toQuery().isEmpty;

  /// Query parameters of `GET /api/v1/listings` for the active filters.
  Map<String, String> toQuery() => {
    'city': ?city,
    'zone': ?zone,
    'operation': ?operation?.wireName,
    'min_base_price': ?minBasePrice,
    'max_base_price': ?maxBasePrice,
    'min_rooms': ?minBedrooms?.toString(),
    'min_bathrooms': ?minBathrooms?.toString(),
  };
}
