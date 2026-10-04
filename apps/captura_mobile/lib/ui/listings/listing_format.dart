import '../../data/models/staff_listing.dart';

/// Formats a server decimal string as COP without passing through floating
/// point, so amounts up to the API's 16 integer digits stay exact.
String formatCop(String amount) {
  final parts = amount.trim().split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final fraction = (parts.length > 1 ? parts[1] : '')
      .padRight(2, '0')
      .substring(0, 2);
  return 'COP $grouped,$fraction';
}

/// Base price with its periodicity: rent is monthly, sale is a one-time price.
String priceLabel(StaffListing listing) {
  final price = formatCop(listing.basePrice);
  return listing.operation == ListingOperation.rent ? '$price por mes' : price;
}

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
