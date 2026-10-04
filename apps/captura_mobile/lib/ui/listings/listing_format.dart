import '../../data/models/staff_listing.dart';

/// Formats a server decimal string with its currency code, without passing
/// through floating point, so amounts up to the API's 16 integer digits stay
/// exact.
String formatMoney(String amount, ListingCurrency currency) {
  final parts = amount.trim().split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final fraction = (parts.length > 1 ? parts[1] : '')
      .padRight(2, '0')
      .substring(0, 2);
  return '${currency.wireName} $grouped,$fraction';
}

/// Base price with its currency and periodicity: rent is monthly, sale is a
/// one-time price.
String priceLabel(StaffListing listing) {
  final price = formatMoney(listing.basePrice, listing.currency);
  return listing.operation == ListingOperation.rent ? '$price por mes' : price;
}

/// Professional Spanish name of a currency, for selectors and read-only views.
String currencyLabel(ListingCurrency currency) => switch (currency) {
  ListingCurrency.bob => 'Boliviano (BOB)',
  ListingCurrency.usd => 'Dólar estadounidense (USD)',
  ListingCurrency.usdt => 'Tether (USDT)',
};

String operationLabel(ListingOperation operation) =>
    operation == ListingOperation.rent ? 'Alquiler' : 'Venta';

String roomsLabel(StaffListing listing) {
  final bedrooms =
      '${listing.bedrooms} ${listing.bedrooms == 1 ? 'dormitorio' : 'dormitorios'}';
  final bathrooms =
      '${listing.bathrooms} ${listing.bathrooms == 1 ? 'baño' : 'baños'}';
  return '$bedrooms · $bathrooms';
}

String statusLabel(ListingStatus status) => switch (status) {
  ListingStatus.draft => 'Borrador',
  ListingStatus.pending => 'En revisión',
  ListingStatus.approved => 'Aprobado',
  ListingStatus.rejected => 'Rechazado',
};
