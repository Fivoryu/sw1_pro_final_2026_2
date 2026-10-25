import 'package:flutter/material.dart';

import '../../../../data/models/catalog_models.dart';
import '../../../../data/models/quote_models.dart';
import '../../../../data/services/quote_api.dart';
import '../../../../domain/catalog_controller.dart' show DisplayCurrency;
import '../../../../domain/quote_controller.dart';
import '../../catalog/views/catalog_format.dart';
import '../../../theme/andean_theme.dart';

/// Minimal quote screen (F06.5): selects extras of the listing, requests a
/// snapshot from `POST /api/v1/quotes` and shows exactly what the server
/// returned. The server is the only converter; the app never converts prices.
class ListingQuoteScreen extends StatefulWidget {
  const ListingQuoteScreen({
    super.key,
    required this.quoteApi,
    required this.detail,
    this.preselectedExtraId,
    this.initialCurrency = DisplayCurrency.bob,
  });

  final QuoteApi quoteApi;
  final CatalogListingDetail detail;
  final String? preselectedExtraId;
  final DisplayCurrency initialCurrency;

  @override
  State<ListingQuoteScreen> createState() => _ListingQuoteScreenState();
}

class _ListingQuoteScreenState extends State<ListingQuoteScreen> {
  late final QuoteController _controller = QuoteController(api: widget.quoteApi);
  late final Set<String> _selectedExtraIds = {
    if (widget.preselectedExtraId != null) widget.preselectedExtraId!,
  };
  late DisplayCurrency _currency = widget.initialCurrency;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createQuote() async {
    await _controller.createQuote(
      listingId: widget.detail.listing.listingId,
      offerVersion: widget.detail.listing.offerVersion,
      extraIds: _selectedExtraIds.toList(growable: false),
      displayCurrency: _currency.code,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Cotización')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text('Precio base', style: AndeanTypography.headlineMd),
            const SizedBox(height: 4),
            Text(
              chargeLabel(widget.detail.listing.basePrice, widget.detail.listing.operation),
            ),
            const SizedBox(height: 16),
            if (widget.detail.extras.isEmpty)
              const Text('Este inmueble no tiene opcionales publicados.')
            else ...[
              Text('Opcionales', style: AndeanTypography.headlineMd),
              for (final extra in widget.detail.extras)
                CheckboxListTile(
                  key: ValueKey('quote-extra-${extra.extraId}'),
                  title: Text(extra.name),
                  subtitle: Text(
                    formatMoney(extra.price.amount, extra.price.currency),
                  ),
                  value: _selectedExtraIds.contains(extra.extraId),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _selectedExtraIds.add(extra.extraId);
                    } else {
                      _selectedExtraIds.remove(extra.extraId);
                    }
                  }),
                ),
            ],
            const SizedBox(height: 16),
            Text('Moneda de la cotización', style: AndeanTypography.headlineMd),
            const SizedBox(height: 4),
            SegmentedButton<DisplayCurrency>(
              segments: [
                for (final currency in DisplayCurrency.values)
                  ButtonSegment(value: currency, label: Text(currency.code)),
              ],
              selected: {_currency},
              onSelectionChanged: (selection) =>
                  setState(() => _currency = selection.first),
            ),
            const SizedBox(height: 24),
            if (_controller.state == QuoteState.failed &&
                _controller.message != null) ...[
              Text(
                _controller.message!,
                key: const ValueKey('quote-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            if (_controller.snapshot case final snapshot?)
              _QuoteSnapshotCard(snapshot: snapshot)
            else
              FilledButton(
                key: const ValueKey('quote-create'),
                onPressed:
                    _controller.state == QuoteState.creating ? null : _createQuote,
                child: _controller.state == QuoteState.creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cotizar'),
              ),
          ],
        ),
      ),
    );
  }
}

/// The server's snapshot, shown verbatim: lines, totals and expiry.
class _QuoteSnapshotCard extends StatelessWidget {
  const _QuoteSnapshotCard({required this.snapshot});

  final QuoteSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = snapshot.displayTotals;
    final oneTime = display?.oneTimeTotal ?? snapshot.oneTimeTotal;
    final monthly = display?.monthlyTotal ?? snapshot.monthlyTotal;
    return Card(
      key: const ValueKey('quote-snapshot'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cotización ${snapshot.quoteId}', style: AndeanTypography.headlineMd),
            const SizedBox(height: 8),
            Text('Vigencia de precios: oferta v${snapshot.offerVersion}'),
            const SizedBox(height: 8),
            for (final line in snapshot.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${line.kind == 'base' ? 'Precio base' : line.extraId ?? line.kind}: '
                  '${formatMoney(line.amount, line.currency)}'
                  '${line.chargePeriod == 'monthly' ? ' por mes' : ''}',
                ),
              ),
            const Divider(),
            Text(
              'Total: ${formatMoney(oneTime.amount, oneTime.currency)}',
              style: AndeanTypography.headlineMd.copyWith(
                color: AndeanColors.primaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (snapshot.monthlyTotal.amount != '0.00')
              Text(
                'Mensual: ${formatMoney(monthly.amount, monthly.currency)} por mes',
              ),
            const SizedBox(height: 8),
            Text(
              'Válida hasta ${snapshot.expiresAt.toLocal()}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
