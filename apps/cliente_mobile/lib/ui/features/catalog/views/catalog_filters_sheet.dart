import 'package:flutter/material.dart';

import '../../../../data/models/catalog_models.dart';

final _pricePattern = RegExp(r'^\d{1,16}(\.\d{1,2})?$');
final _countPattern = RegExp(r'^\d{1,9}$');

/// Bottom sheet that edits the catalog filters; it pops the new filters, or
/// nothing when dismissed.
class CatalogFiltersSheet extends StatefulWidget {
  const CatalogFiltersSheet({super.key, required this.initialFilters});

  final CatalogFilters initialFilters;

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
    setState(() => _operation = null);
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
            'Precio mínimo (COP)',
            _minPrice,
            'filter-min-price',
            _validatePrice,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          _field(
            'Precio máximo (COP)',
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
