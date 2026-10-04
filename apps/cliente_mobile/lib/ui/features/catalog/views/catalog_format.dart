import '../../../../data/models/catalog_models.dart';

/// Formats a server decimal string with its currency code, without passing
/// through floating point, so amounts keep every digit the API sends. The
/// code is echoed from the server: the app never converts prices.
String formatMoney(String amount, String currency) {
  final parts = amount.trim().split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final fraction = (parts.length > 1 ? parts[1] : '')
      .padRight(2, '0')
      .substring(0, 2);
  return '$currency $grouped,$fraction';
}

/// An amount with the periodicity of [operation]: rent charges are monthly,
/// sale charges are paid once, so a sale never shows a monthly label. The
/// currency shown is the server's, never converted.
String chargeLabel(CatalogMoney money, ListingOperation operation) {
  final price = formatMoney(money.amount, money.currency);
  return operation == ListingOperation.rent ? '$price por mes' : price;
}

/// Note shown on the detail when the listing's currency differs from the
/// chosen display currency: prices stay in the server currency, and a quote
/// can be requested in the chosen one.
String cotizableNote(String displayCurrency) =>
    'Cotizable en $displayCurrency';

String operationLabel(ListingOperation operation) => switch (operation) {
  ListingOperation.sale => 'Venta',
  ListingOperation.rent => 'Alquiler',
};

/// Explains what the base price covers, by operation.
String basePriceNote(ListingOperation operation) => switch (operation) {
  ListingOperation.sale =>
    'Precio base de pago único. No incluye los opcionales.',
  ListingOperation.rent => 'Precio base mensual. No incluye los opcionales.',
};

String roomsLabel(int bedrooms, int bathrooms) {
  final rooms = '$bedrooms ${bedrooms == 1 ? 'dormitorio' : 'dormitorios'}';
  final baths = '$bathrooms ${bathrooms == 1 ? 'baño' : 'baños'}';
  return '$rooms · $baths';
}

String locationLabel(CatalogListing listing) =>
    '${listing.city}, ${listing.zone}';
