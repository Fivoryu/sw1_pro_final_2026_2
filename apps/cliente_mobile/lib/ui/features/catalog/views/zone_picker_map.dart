import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../data/map_config.dart';

/// Centre shown while no zone is chosen: Santa Cruz de la Sierra.
const _defaultCenter = LatLng(-17.7833, -63.1821);

/// Map where the customer taps the centre of a zone search; the circle shows
/// the radius. Reports every tap through [onChanged].
class ZonePickerMap extends StatefulWidget {
  const ZonePickerMap({
    super.key,
    required this.point,
    required this.radiusKm,
    required this.onChanged,
    this.config = MapTileConfig.openStreetMap,
  });

  final LatLng? point;
  final double radiusKm;
  final ValueChanged<LatLng> onChanged;
  final MapTileConfig config;

  @override
  State<ZonePickerMap> createState() => _ZonePickerMapState();
}

class _ZonePickerMapState extends State<ZonePickerMap> {
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
        if (_tilesFailed) ...[
          Card(
            key: const ValueKey('zone-map-error'),
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
                    key: const ValueKey('zone-map-retry'),
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
          height: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              key: ValueKey('zone-map-$_attempt'),
              options: MapOptions(
                initialCenter: point ?? _defaultCenter,
                initialZoom: point == null ? 11 : 12,
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
                if (point != null) ...[
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: point,
                        radius: widget.radiusKm * 1000,
                        useRadiusInMeter: true,
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.15,
                        ),
                        borderColor: theme.colorScheme.primary,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        key: const ValueKey('zone-marker'),
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
                ],
                SimpleAttributionWidget(
                  source: Text(
                    config.attribution,
                    key: const ValueKey('zone-attribution'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
