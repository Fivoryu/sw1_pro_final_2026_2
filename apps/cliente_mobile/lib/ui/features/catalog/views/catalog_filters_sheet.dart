import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../../data/map_config.dart';
import '../../../../data/models/catalog_models.dart';
import '../../../../data/services/device_location.dart';
import 'zone_picker_map.dart';

final _pricePattern = RegExp(r'^\d{1,16}(\.\d{1,2})?$');
final _countPattern = RegExp(r'^\d{1,9}$');

/// Bottom sheet that edits the catalog filters; it pops the new filters, or
/// nothing when dismissed.
class CatalogFiltersSheet extends StatefulWidget {
  const CatalogFiltersSheet({
    super.key,
    required this.initialFilters,
    this.deviceLocation = const GeolocatorDeviceLocation(),
    this.mapConfig = MapTileConfig.openStreetMap,
  });

  final CatalogFilters initialFilters;

  /// Reads the customer's position for "near me"; never stored.
  final DeviceLocation deviceLocation;

  /// Tile provider of the map where a zone centre can be picked.
  final MapTileConfig mapConfig;

  @override
  State<CatalogFiltersSheet> createState() => _CatalogFiltersSheetState();
}

class _CatalogFiltersSheetState extends State<CatalogFiltersSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _city = TextEditingController(text: widget.initialFilters.city);
  late final _zone = TextEditingController(text: widget.initialFilters.zone);
  late final _minPrice = TextEditingController(
    text: widget.initialFilters.minBasePrice,
  );
  late final _maxPrice = TextEditingController(
    text: widget.initialFilters.maxBasePrice,
  );
  late final _bedrooms = TextEditingController(
    text: widget.initialFilters.minBedrooms?.toString(),
  );
  late final _bathrooms = TextEditingController(
    text: widget.initialFilters.minBathrooms?.toString(),
  );
  late ListingOperation? _operation = widget.initialFilters.operation;
  late LatLng? _zoneCentre = widget.initialFilters.hasZone
      ? LatLng(
          widget.initialFilters.latitude!,
          widget.initialFilters.longitude!,
        )
      : null;
  late double _radiusKm = widget.initialFilters.radiusKm;
  bool _locating = false;
  bool _showMap = false;
  String? _locationMessage;

  @override
  void dispose() {
    for (final controller in [
      _city,
      _zone,
      _minPrice,
      _maxPrice,
      _bedrooms,
      _bathrooms,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static String? _text(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  static String? _price(TextEditingController controller) =>
      _text(controller)?.replaceAll(',', '.');

  static int? _count(TextEditingController controller) {
    final value = _text(controller);
    return value == null ? null : int.parse(value);
  }

  /// Price in cents as an exact integer, so the comparison never rounds.
  static BigInt _cents(String price) {
    final parts = price.split('.');
    final fraction = (parts.length > 1 ? parts[1] : '').padRight(2, '0');
    return BigInt.parse('${parts.first}$fraction');
  }

  String? _validateText(String? value) =>
      (value?.trim().length ?? 0) > 120 ? 'Usá hasta 120 caracteres.' : null;

  String? _validatePrice(String? value) {
    final price = value?.trim().replaceAll(',', '.') ?? '';
    if (price.isEmpty) return null;
    if (!_pricePattern.hasMatch(price)) {
      return 'Usá hasta 16 dígitos enteros y 2 decimales.';
    }
    return null;
  }

  String? _validateMaxPrice(String? value) {
    final invalid = _validatePrice(value);
    if (invalid != null) return invalid;
    final min = _price(_minPrice);
    final max = _price(_maxPrice);
    if (min == null || max == null || !_pricePattern.hasMatch(min)) {
      return null;
    }
    return _cents(min) > _cents(max)
        ? 'El mínimo no puede superar al máximo.'
        : null;
  }

  String? _validateCount(String? value) {
    final count = value?.trim() ?? '';
    if (count.isEmpty) return null;
    return _countPattern.hasMatch(count) ? null : 'Ingresá un número entero.';
  }

  static String _messageFor(DeviceLocationFailure failure) => switch (failure) {
    DeviceLocationFailure.servicesDisabled =>
      'La ubicación del teléfono está apagada. Activala o elegí un punto en el mapa.',
    DeviceLocationFailure.denied =>
      'No diste permiso de ubicación. Podés elegir un punto en el mapa.',
    DeviceLocationFailure.deniedForever =>
      'El permiso de ubicación está bloqueado. Habilitalo en Ajustes o elegí un punto en el mapa.',
    DeviceLocationFailure.unavailable =>
      'No pudimos leer tu ubicación. Probá de nuevo o elegí un punto en el mapa.',
  };

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
    });
    final result = await widget.deviceLocation.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (result.isFound) {
        _zoneCentre = LatLng(result.latitude!, result.longitude!);
      } else {
        _locationMessage = _messageFor(result.failure!);
        _showMap = true;
      }
    });
  }

  void _clearZone() => setState(() {
    _zoneCentre = null;
    _radiusKm = CatalogFilters.defaultRadiusKm;
    _locationMessage = null;
  });

  Widget _zoneSection(BuildContext context) {
    final centre = _zoneCentre;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cerca de un punto',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Tu ubicación solo se usa para esta búsqueda y no se guarda.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            key: const ValueKey('zone-use-location'),
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(
              _locating ? 'Buscando tu ubicación…' : 'Usar mi ubicación',
            ),
          ),
        ),
        if (_locationMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _locationMessage!,
            key: const ValueKey('zone-location-message'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        SizedBox(
          height: 48,
          child: TextButton.icon(
            key: const ValueKey('zone-toggle-map'),
            onPressed: () => setState(() => _showMap = !_showMap),
            icon: const Icon(Icons.map_outlined),
            label: Text(_showMap ? 'Ocultar mapa' : 'Elegir en el mapa'),
          ),
        ),
        if (_showMap)
          ZonePickerMap(
            point: centre,
            radiusKm: _radiusKm,
            config: widget.mapConfig,
            onChanged: (point) => setState(() {
              _zoneCentre = point;
              _locationMessage = null;
            }),
          ),
        if (centre != null) ...[
          const SizedBox(height: 8),
          Text(
            'Radio: ${_radiusKm.round()} km',
            key: const ValueKey('zone-radius-label'),
          ),
          Slider(
            key: const ValueKey('zone-radius'),
            value: _radiusKm,
            min: CatalogFilters.minRadiusKm,
            max: CatalogFilters.maxRadiusKm,
            divisions: (CatalogFilters.maxRadiusKm - CatalogFilters.minRadiusKm)
                .round(),
            label: '${_radiusKm.round()} km',
            onChanged: (value) => setState(() => _radiusKm = value),
          ),
          SizedBox(
            height: 48,
            child: TextButton(
              key: const ValueKey('zone-clear'),
              onPressed: _clearZone,
              child: const Text('Quitar zona'),
            ),
          ),
        ],
      ],
    );
  }

  void _apply() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      CatalogFilters(
        city: _text(_city),
        zone: _text(_zone),
        operation: _operation,
        minBasePrice: _price(_minPrice),
        maxBasePrice: _price(_maxPrice),
        minBedrooms: _count(_bedrooms),
        minBathrooms: _count(_bathrooms),
        latitude: _zoneCentre?.latitude,
        longitude: _zoneCentre?.longitude,
        radiusKm: _radiusKm,
      ),
    );
  }

  void _clear() {
    for (final controller in [
      _city,
      _zone,
      _minPrice,
      _maxPrice,
      _bedrooms,
      _bathrooms,
    ]) {
      controller.clear();
    }
    setState(() {
      _operation = null;
      _zoneCentre = null;
      _radiusKm = CatalogFilters.defaultRadiusKm;
      _locationMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Filtros del catálogo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'La ciudad y la zona se buscan por nombre completo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _zoneSection(context),
          const SizedBox(height: 16),
          _field('Ciudad', _city, 'filter-city', _validateText),
          const SizedBox(height: 12),
          _field('Zona', _zone, 'filter-zone', _validateText),
          const SizedBox(height: 12),
          DropdownButtonFormField<ListingOperation?>(
            key: const ValueKey('filter-operation'),
            initialValue: _operation,
            decoration: const InputDecoration(
              labelText: 'Operación',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Cualquiera')),
              DropdownMenuItem(
                value: ListingOperation.sale,
                child: Text('Venta'),
              ),
              DropdownMenuItem(
                value: ListingOperation.rent,
                child: Text('Alquiler'),
              ),
            ],
            onChanged: (value) => setState(() => _operation = value),
          ),
          const SizedBox(height: 12),
          _field(
            'Precio mínimo',
            _minPrice,
            'filter-min-price',
            _validatePrice,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          _field(
            'Precio máximo',
            _maxPrice,
            'filter-max-price',
            _validateMaxPrice,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          _field(
            'Dormitorios mínimos',
            _bedrooms,
            'filter-bedrooms',
            _validateCount,
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _field(
            'Baños mínimos',
            _bathrooms,
            'filter-bathrooms',
            _validateCount,
            keyboard: TextInputType.number,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const ValueKey('filter-apply'),
              onPressed: _apply,
              child: const Text('Aplicar filtros'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: TextButton(
              key: const ValueKey('filter-clear'),
              onPressed: _clear,
              child: const Text('Limpiar campos'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller,
    String key,
    FormFieldValidator<String> validator, {
    TextInputType keyboard = TextInputType.text,
  }) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    keyboardType: keyboard,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}
