import 'package:flutter/material.dart';

import '../../data/models/staff_listing.dart';
import '../../domain/listing_drafts_controller.dart';
import 'listing_editor_screen.dart';
import 'listing_format.dart';

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
                  FilledButton.icon(
                    key: const ValueKey('new-listing-button'),
                    style: FilledButton.styleFrom(minimumSize: _actionMinSize),
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo inmueble'),
                  ),
                  const SizedBox(height: 20),
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
                  const SizedBox(height: 20),
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
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(controller.message ?? ''),
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
              color: theme.colorScheme.surfaceContainerLow,
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
              child: ListTile(
                key: ValueKey('listing-item-${listing.listingId}'),
                minVerticalPadding: 12,
                title: Text(
                  '${operationLabel(listing.operation)} · ${listing.city}, '
                  '${listing.zone}',
                ),
                subtitle: Text(
                  '${priceLabel(listing)}\n${roomsLabel(listing)}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openEditor(listing),
              ),
            ),
        ];
    }
  }
}
