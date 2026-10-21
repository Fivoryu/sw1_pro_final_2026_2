import '../../domain/spatial/spatial.dart';

/// Metres with two decimals and a decimal comma, as the agent reads them.
String metres(double value) =>
    '${value.toStringAsFixed(2).replaceAll('.', ',')} m';

String squareMetres(double value) =>
    '${value.toStringAsFixed(2).replaceAll('.', ',')} m²';

/// Where a room height came from; an assumed height is never a measurement.
String heightSourceLabel(HeightSource source) => switch (source) {
  HeightSource.ceilingPlane => 'medida al techo',
  HeightSource.wallPoint => 'medida en la pared',
  HeightSource.manual => 'ingresada a mano',
  HeightSource.assumed => 'supuesta, sin medir',
};

String boxSourceLabel(BoxSource source) => switch (source) {
  BoxSource.depth => 'profundidad',
  BoxSource.manual => 'a mano',
};

String openingTypeLabel(OpeningType type) => switch (type) {
  OpeningType.door => 'Puerta',
  OpeningType.window => 'Ventana',
};

/// Parses a positive metre value typed with comma or dot.
double? parseMetres(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || !value.isFinite || value <= 0) return null;
  return value;
}
