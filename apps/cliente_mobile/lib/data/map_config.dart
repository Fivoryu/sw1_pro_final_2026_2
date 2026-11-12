import 'package:flutter_map/flutter_map.dart';

/// Where the map tiles come from (F14). The provider is configurable; the
/// default is the public OpenStreetMap server, allowed for this academic
/// project under the OSM tile usage policy (no API key, no bulk prefetch).
class MapTileConfig {
  const MapTileConfig({
    required this.urlTemplate,
    required this.userAgentPackageName,
    required this.attribution,
    this.tileProvider,
  });

  /// Public OpenStreetMap tiles.
  ///
  /// The tile URL and the identifier sent to the tile server can be replaced at
  /// build time without touching code, for example a self-hosted or commercial
  /// provider: `--dart-define=MAP_TILE_URL=...` and
  /// `--dart-define=MAP_USER_AGENT=...`.
  static const openStreetMap = MapTileConfig(
    urlTemplate: String.fromEnvironment(
      'MAP_TILE_URL',
      defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    ),
    userAgentPackageName: String.fromEnvironment(
      'MAP_USER_AGENT',
      defaultValue: 'roomforge-cliente-sw1-g12',
    ),
    attribution: '© OpenStreetMap contributors',
  );

  final String urlTemplate;

  /// Identifies the app to the tile server, as the OSM policy requires.
  final String userAgentPackageName;

  /// Credit that must stay visible over the map.
  final String attribution;

  /// Overrides the network provider; tests inject an offline one.
  final TileProvider? tileProvider;
}
