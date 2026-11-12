import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/map_config.dart';

/// Centre used while the listing has no point yet: Santa Cruz de la Sierra.
const _defaultCenter = LatLng(-17.7833, -63.1821);

/// Lets the agent tap a map to place or move the listing's point (F14).
///
/// Reports every change through [onChanged]; null means the point was cleared.
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    required this.point,
    required this.onChanged,
    this.config = MapTileConfig.openStreetMap,
  });

  final LatLng? point;
  final ValueChanged<LatLng?> onChanged;
  final MapTileConfig config;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  bool _tilesFailed = false;
  int _attempt = 0;

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (!mounted || _tilesFailed) return;
    // Reported while tiles build, so the rebuild waits for the frame to end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tilesFailed = true);
    });
  }

  void _retry() => setState(() {
    _tilesFailed = false;
    _attempt++;
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final point = widget.point;
    final config = widget.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ubicación en el mapa', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_tilesFailed) ...[
          Card(
            key: const ValueKey('location-map-error'),
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'No se pudo cargar el mapa. Revisá tu conexión.',
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('location-map-retry'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 48),
                    ),
                    onPressed: _retry,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 260,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              key: ValueKey('location-map-$_attempt'),
              options: MapOptions(
                initialCenter: point ?? _defaultCenter,
                initialZoom: point == null ? 12 : 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, latLng) => widget.onChanged(latLng),
              ),
              children: [
                TileLayer(
                  urlTemplate: config.urlTemplate,
                  userAgentPackageName: config.userAgentPackageName,
                  tileProvider: config.tileProvider,
                  errorTileCallback: _onTileError,
                ),
                if (point != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        key: const ValueKey('location-marker'),
                        point: point,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.location_on,
                          size: 40,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                SimpleAttributionWidget(
                  source: Text(
                    config.attribution,
                    key: const ValueKey('location-attribution'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          point == null
              ? 'Tocá el mapa para marcar la ubicación del inmueble.'
              : 'Lat ${point.latitude.toStringAsFixed(6)}, '
                    'Lon ${point.longitude.toStringAsFixed(6)}',
          key: const ValueKey('location-coordinates'),
          style: theme.textTheme.bodyMedium,
        ),
        if (point != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('location-clear'),
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: () => widget.onChanged(null),
              icon: const Icon(Icons.location_off_outlined),
              label: const Text('Quitar ubicación'),
            ),
          ),
      ],
    );
  }
}
