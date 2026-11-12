import 'dart:convert';
import 'dart:typed_data';

import 'package:captura_mobile/data/map_config.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

final _blankPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

/// Serves a blank tile, or an undecodable one while [failing] is true, so the
/// picker's loaded and error states can be tested without a network.
class FakeTileProvider extends TileProvider {
  FakeTileProvider({this.failing = false});

  bool failing;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(failing ? Uint8List(0) : _blankPng);

  MapTileConfig get config => MapTileConfig(
    urlTemplate: 'https://tiles.test/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.example.captura_mobile',
    attribution: '© OpenStreetMap contributors',
    tileProvider: this,
  );
}
