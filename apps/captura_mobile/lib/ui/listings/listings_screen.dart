import 'package:flutter/material.dart';

import '../../data/models/staff_listing.dart';
import '../../domain/listing_drafts_controller.dart';
import 'listing_editor_screen.dart';
import 'listing_format.dart';
import '../theme/andean_theme.dart';
import '../theme/andean_widgets.dart';

/// Minimum 48 dp touch target for primary actions.
const _actionMinSize = Size.fromHeight(48);

const _tabs = <(ListingStatus, String, String)>[
  (ListingStatus.draft, 'Borradores', 'Todavía no tenés borradores.'),
  (ListingStatus.rejected, 'Rechazados', 'No hay inmuebles rechazados.'),
  (ListingStatus.pending, 'En revisión', 'No hay inmuebles en revisión.'),
];

/// The agent's listings of the agency, by review status (F04.1 / F04.3).
class ListingsScreen extends StatefulWidget {
  const ListingsScreen({super.key, required this.controller});

  final ListingDraftsController controller;

  @override
  State<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends State<ListingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  Future<void> _openEditor([StaffListing? listing]) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ListingEditorScreen(
          controller: widget.controller,
          listing: listing,
        ),
      ),
    );
    if (!mounted) return;
    if (submitted == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inmueble enviado a revisión.')),
      );
    }
    await widget.controller.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis inmuebles')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final tab = _tabs.firstWhere((entry) => entry.$1 == controller.tab);
        return Center(
          child: SafeArea(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AndeanColors.secondaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.real_estate_agent_outlined,
                              size: 16,
                              color: AndeanColors.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Cartera Activa',
                            style: AndeanTypography.labelLg,
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AndeanColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text(
                              '${controller.listings.length} Inmuebles',
                              style: AndeanTypography.monoData.copyWith(
                                color: AndeanColors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const ValueKey('new-listing-button'),
                    style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo inmueble'),
                  ),
                  const SizedBox(height: 16),
                  const AndeanNoticeBanner(
                    title: 'CONTROL NOTARIAL & AGENCIA',
                    badge: 'Regla R-202',
                    icon: Icons.policy_outlined,
                    variant: AndeanBannerVariant.institutional,
                    message:
                        'Los cambios en fotos o datos de publicaciones aprobadas devuelven el inmueble a estado Borrador de forma automática para nueva certificación.',
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<ListingStatus>(
                    segments: [
                      for (final (status, label, _) in _tabs)
                        ButtonSegment(
                          value: status,
                          label: Text(
                            label,
                            key: ValueKey('listings-tab-${status.wireName}'),
                          ),
                        ),
                    ],
                    selected: {controller.tab},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        controller.load(selection.single),
                  ),
                  const SizedBox(height: 16),
                  ..._content(context, controller, tab.$3),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  List<Widget> _content(
    BuildContext context,
    ListingDraftsController controller,
    String emptyMessage,
  ) {
    final theme = Theme.of(context);
    switch (controller.loadState) {
      case ListingsLoadState.loading:
        return const [
          Center(
            key: ValueKey('listings-loading'),
            child: CircularProgressIndicator(),
          ),
        ];
      case ListingsLoadState.failed:
        return [
          Card(
            key: const ValueKey('listings-error'),
            color: AndeanColors.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.message ?? '',
                    style: AndeanTypography.bodyMd.copyWith(
                      color: AndeanColors.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('listings-retry'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: _actionMinSize,
                    ),
                    onPressed: () => controller.load(),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ];
      case ListingsLoadState.ready:
        if (controller.listings.isEmpty) {
          return [
            Card(
              key: const ValueKey('listings-empty'),
              color: AndeanColors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AndeanColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(emptyMessage, style: theme.textTheme.bodyLarge),
              ),
            ),
          ];
        }
        return [
          for (final listing in controller.listings)
            Card(
              key: ValueKey('listing-item-card-${listing.listingId}'),
              margin: const EdgeInsets.only(bottom: 12),
              color: AndeanColors.surfaceContainerLowest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AndeanColors.border, width: 1),
              ),
              child: ListTile(
                key: ValueKey('listing-item-${listing.listingId}'),
                minVerticalPadding: 12,
                title: Text(
                  '${operationLabel(listing.operation)} · ${listing.city}, '
                  '${listing.zone}',
                  style: AndeanTypography.headlineSm.copyWith(fontSize: 16),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${priceLabel(listing)}\n${roomsLabel(listing)}',
                    style: AndeanTypography.bodySm,
                  ),
                ),
                isThreeLine: true,
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AndeanColors.secondary,
                ),
                onTap: () => _openEditor(listing),
              ),
            ),
        ];
    }
  }
}
