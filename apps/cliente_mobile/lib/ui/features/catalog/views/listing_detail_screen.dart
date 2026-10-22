import 'package:flutter/material.dart';

import '../../../../data/models/catalog_models.dart';
import '../../../../data/models/reservation_models.dart';
import '../../../../domain/catalog_controller.dart';
import '../../../../domain/customer_reservations_controller.dart';
import '../../../../domain/customer_session_controller.dart';
import 'catalog_format.dart';
import 'listing_photo.dart';

/// Public detail of one published listing.
///
/// Without a 3D model or availability data from the API, it says so instead
/// of showing a foreign scene or a guessed status.
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.controller,
    required this.listingId,
    this.reservationsController,
    this.sessionController,
  });

  final CatalogController controller;
  final String listingId;
  final CustomerReservationsController? reservationsController;
  final CustomerSessionController? sessionController;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  CatalogListingDetail? _detail;
  int _photoIndex = 0;
  String? _message;
  bool _loading = true;
  bool _submittingQuote = false;
  final Set<String> _selectedExtras = {};
  String _quoteCurrency = 'BOB';
  QuoteSnapshot? _quote;
  String? _bookingMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    final result = await widget.controller.loadDetail(widget.listingId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = result.detail;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detalle del inmueble')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _body(context),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: ValueKey('detail-loading')),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _message ?? '',
            key: const ValueKey('detail-error'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              key: const ValueKey('detail-retry'),
              onPressed: _load,
              child: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    final listing = detail.listing;
    return ListView(
      key: const ValueKey('property-detail-content'),
      padding: const EdgeInsets.all(20),
      children: [
        _gallery(context, detail),
        const SizedBox(height: 16),
        Text(locationLabel(listing), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(operationLabel(listing.operation)),
        const SizedBox(height: 4),
        Text(roomsLabel(detail.bedrooms, detail.bathrooms)),
        const SizedBox(height: 24),
        Text('Precio base', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          chargeLabel(listing.basePrice, listing.operation),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(basePriceNote(listing.operation)),
        if (listing.basePrice.currency !=
            widget.controller.displayCurrency.code) ...[
          const SizedBox(height: 4),
          Text(cotizableNote(widget.controller.displayCurrency.code)),
        ],
        const SizedBox(height: 24),
        Text('Opcionales', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (detail.extras.isEmpty)
          const Text('Este inmueble no tiene opcionales.')
        else
          for (final extra in detail.extras)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selectedExtras.contains(extra.extraId),
              title: Text(extra.name),
              subtitle: Text(chargeLabel(extra.price, listing.operation)),
              onChanged: (selected) => setState(() {
                if (selected == true) {
                  _selectedExtras.add(extra.extraId);
                } else {
                  _selectedExtras.remove(extra.extraId);
                }
                _quote = null;
              }),
            ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: const ValueKey('quote-currency-selector'),
          initialValue: _quoteCurrency,
          decoration: const InputDecoration(
            labelText: 'Moneda de la cotización',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'BOB', child: Text('BOB')),
            DropdownMenuItem(value: 'USD', child: Text('USD')),
            DropdownMenuItem(value: 'USDT', child: Text('USDT')),
          ],
          onChanged: (value) => setState(() {
            _quoteCurrency = value ?? 'BOB';
            _quote = null;
          }),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const ValueKey('create-quote'),
            onPressed: _submittingQuote ? null : () => _createQuote(detail),
            icon: _submittingQuote
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.request_quote_outlined),
            label: Text(_submittingQuote ? 'Cotizando…' : 'Cotizar y reservar'),
          ),
        ),
        if (_quote case final quote?) ...[
          const SizedBox(height: 16),
          Card(
            key: const ValueKey('quote-snapshot'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cotización del servidor',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final line in quote.lines)
                    Text(
                      '${line.kind == 'base' ? 'Precio base' : 'Opcional'}: '
                      '${line.amount} ${line.currency} · '
                      '${line.chargePeriod == 'monthly' ? 'mensual' : 'pago único'}',
                    ),
                  const Divider(),
                  if (quote.oneTimeTotal.amount != '0.00')
                    Text(
                      'Pago único: ${quote.oneTimeTotal.amount} ${quote.oneTimeTotal.currency}',
                    ),
                  if (quote.monthlyTotal.amount != '0.00')
                    Text(
                      'Total mensual: ${quote.monthlyTotal.amount} ${quote.monthlyTotal.currency}',
                    ),
                  const SizedBox(height: 8),
                  Text('Vence: ${quote.expiresAt.toLocal()}'),
                  if (quote.expiresAt.isBefore(DateTime.now()))
                    const Text(
                      'La cotización venció. Generá una nueva antes de reservar.',
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      key: const ValueKey('request-reservation'),
                      onPressed: quote.expiresAt.isBefore(DateTime.now())
                          ? null
                          : () => _createReservation(quote),
                      child: const Text('Solicitar reserva'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_bookingMessage != null) ...[
          const SizedBox(height: 8),
          Text(_bookingMessage!, key: const ValueKey('booking-message')),
        ],
        const SizedBox(height: 24),
        Text('Recorrido 3D', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Recorrido 3D no disponible.'),
        const SizedBox(height: 24),
        Text('Disponibilidad', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Disponibilidad no consultada ni confirmada.'),
      ],
    );
  }

  /// Photos in upload order, swiped one at a time; the first is the cover.
  Widget _gallery(BuildContext context, CatalogListingDetail detail) {
    final photos = detail.photos;
    final place = locationLabel(detail.listing);
    if (photos.isEmpty) {
      return const SizedBox(
        height: 240,
        child: PhotoPlaceholder(
          message: 'Este inmueble todavía no tiene fotos.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PageView.builder(
              key: const ValueKey('detail-photos'),
              itemCount: photos.length,
              onPageChanged: (index) => setState(() => _photoIndex = index),
              itemBuilder: (context, index) => ListingPhoto(
                key: ValueKey('detail-photo-${photos[index].photoId}'),
                url: photos[index].url,
                semanticLabel:
                    'Foto ${index + 1} de ${photos.length} de $place',
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Foto ${_photoIndex + 1} de ${photos.length}',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _createQuote(CatalogListingDetail detail) async {
    final reservations = widget.reservationsController;
    if (reservations == null) {
      setState(
        () =>
            _bookingMessage = 'El servicio de cotización no está configurado.',
      );
      return;
    }
    setState(() {
      _submittingQuote = true;
      _bookingMessage = null;
      _quote = null;
    });
    final listing = detail.listing;
    final quote = await reservations.createQuote(
      listingId: listing.listingId,
      offerVersion: listing.offerVersion,
      selectedExtraIds: _selectedExtras.toList()..sort(),
      targetCurrency: _quoteCurrency,
    );
    if (!mounted) return;
    setState(() {
      _submittingQuote = false;
      _quote = quote;
      _bookingMessage = quote == null ? reservations.message : null;
    });
  }

  Future<void> _createReservation(QuoteSnapshot quote) async {
    final session = widget.sessionController;
    final reservations = widget.reservationsController;
    if (session?.status != CustomerSessionStatus.signedIn) {
      setState(
        () => _bookingMessage =
            'Iniciá sesión en Cuenta para solicitar una reserva.',
      );
      return;
    }
    if (reservations == null) return;
    final paymentMethod = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elegí cómo reservar'),
        content: const Text(
          'La wallet y la tarjeta son alternativas separadas. La tarjeta se procesa en Stripe en modo de prueba.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('choose-wallet-payment'),
            onPressed: () => Navigator.pop(context, 'wallet'),
            child: const Text('Wallet'),
          ),
          FilledButton(
            key: const ValueKey('choose-card-payment'),
            onPressed: () => Navigator.pop(context, 'card'),
            child: const Text('Tarjeta'),
          ),
        ],
      ),
    );
    if (!mounted || paymentMethod == null) return;
    if (paymentMethod == 'card') {
      final reservation = await reservations.createCardReservation(
        quote: quote,
      );
      if (!mounted) return;
      setState(() {
        _bookingMessage = reservation == null
            ? reservations.message
            : reservations.message ??
                  'Solicitud ${reservation.reservationId} creada. Stripe está verificando el pago.';
      });
      return;
    }
    final wallets = await reservations.loadWallets();
    if (!mounted) return;
    if (wallets == null) {
      setState(() => _bookingMessage = reservations.message);
      return;
    }
    if (wallets.isEmpty) {
      setState(
        () => _bookingMessage =
            'Vinculá una wallet externa verificada desde Cuenta para reservar.',
      );
      return;
    }
    final reservation = await reservations.createReservation(
      quote: quote,
      wallet: wallets.single,
    );
    if (!mounted) return;
    setState(() {
      _bookingMessage = reservation == null
          ? reservations.message
          : 'Solicitud ${reservation.reservationId} creada. Estado: pendiente; vence ${reservation.decisionDeadlineAt.toLocal()}. '
                'El depósito aún no se confirma hasta validar su transacción en cadena.';
    });
  }
}
