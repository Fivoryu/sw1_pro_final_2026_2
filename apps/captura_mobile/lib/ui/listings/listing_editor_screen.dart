import 'package:flutter/material.dart';

import '../../data/models/staff_listing.dart';
import '../../domain/listing_drafts_controller.dart';
import 'listing_format.dart';

/// Minimum 48 dp touch target for primary actions.
const _actionMinSize = Size.fromHeight(48);

/// Same limits as the staff API: positive, up to 16 integer digits and 2 decimals.
final _pricePattern = RegExp(r'^\d{1,16}(\.\d{1,2})?$');
final _countPattern = RegExp(r'^\d{1,9}$');
const _maxGeoLength = 120;

/// Creates or edits the listing card (F04.1) and submits it for review (F04.3).
///
/// Pops with `true` after a successful submission.
class ListingEditorScreen extends StatefulWidget {
  const ListingEditorScreen({
    super.key,
    required this.controller,
    this.listing,
  });

  final ListingDraftsController controller;
  final StaffListing? listing;

  @override
  State<ListingEditorScreen> createState() => _ListingEditorScreenState();
}

class _ListingEditorScreenState extends State<ListingEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _price;
  late final TextEditingController _city;
  late final TextEditingController _zone;
  late final TextEditingController _bedrooms;
  late final TextEditingController _bathrooms;
  late final TextEditingController _description;
  late final TextEditingController _address;
  late ListingOperation _operation;
  late ListingCurrency _currency;
  StaffListing? _listing;
  Map<String, Object?>? _savedFields;
  String? _rejectionReason;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final listing = widget.listing;
    _listing = listing;
    _operation = listing?.operation ?? ListingOperation.sale;
    // The server fixes the currency per listing (F05): the agent chooses it
    // only when creating, and the editor echoes it read-only afterwards.
    _currency = listing?.currency ?? ListingCurrency.bob;
    _price = TextEditingController(text: listing?.basePrice ?? '');
    _city = TextEditingController(text: listing?.city ?? '');
    _zone = TextEditingController(text: listing?.zone ?? '');
    _bedrooms = TextEditingController(text: listing?.bedrooms.toString() ?? '');
    _bathrooms = TextEditingController(
      text: listing?.bathrooms.toString() ?? '',
    );
    _description = TextEditingController(text: listing?.description ?? '');
    _address = TextEditingController(text: listing?.exactAddress ?? '');
    _savedFields = listing == null ? null : _currentInput()?.toJson();
    for (final field in _fields) {
      field.addListener(_onChanged);
    }
    if (listing?.status == ListingStatus.rejected) _loadRejectionReason();
  }

  List<TextEditingController> get _fields => [
    _price,
    _city,
    _zone,
    _bedrooms,
    _bathrooms,
    _description,
    _address,
  ];

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _loadRejectionReason() async {
    final reason = await widget.controller.latestRejectionReason(
      widget.listing!.listingId,
    );
    if (mounted) setState(() => _rejectionReason = reason);
  }

  static String _normalizedPrice(String raw) => raw.trim().replaceAll(',', '.');

  static String? _optional(String raw) {
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }

  /// The form as API input, or null while a field is invalid.
  ListingDraftInput? _currentInput() {
    final price = _normalizedPrice(_price.text);
    final city = _city.text.trim();
    final zone = _zone.text.trim();
    if (!_pricePattern.hasMatch(price) ||
        !RegExp('[1-9]').hasMatch(price) ||
        city.isEmpty ||
        zone.isEmpty ||
        !_countPattern.hasMatch(_bedrooms.text.trim()) ||
        !_countPattern.hasMatch(_bathrooms.text.trim())) {
      return null;
    }
    return ListingDraftInput(
      operation: _operation,
      basePrice: price,
      currency: _currency,
      city: city,
      zone: zone,
      bedrooms: int.parse(_bedrooms.text.trim()),
      bathrooms: int.parse(_bathrooms.text.trim()),
      description: _optional(_description.text),
      exactAddress: _optional(_address.text),
    );
  }

  bool get _isDirty {
    final saved = _savedFields;
    final current = _currentInput()?.toJson();
    if (saved == null || current == null) return true;
    return saved.entries.any((entry) => current[entry.key] != entry.value);
  }

  bool get _canSubmit =>
      !_busy && _listing?.status == ListingStatus.draft && !_isDirty;

  String? get _submitHint {
    final listing = _listing;
    if (listing == null) {
      return 'Guardá el borrador para poder enviarlo a revisión.';
    }
    if (_isDirty) {
      return 'Guardá los cambios antes de enviar el inmueble a revisión.';
    }
    return switch (listing.status) {
      ListingStatus.draft => null,
      ListingStatus.rejected =>
        'Corregí el inmueble y guardalo para volver a enviarlo.',
      ListingStatus.pending => 'Este inmueble ya está en revisión.',
      ListingStatus.approved => 'Este inmueble ya fue aprobado.',
    };
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final input = _currentInput();
    if (input == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final saved = await widget.controller.save(
      listingId: _listing?.listingId,
      input: input,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saved == null) {
        _message = widget.controller.message;
      } else {
        _listing = saved;
        _savedFields = input.toJson();
        _rejectionReason = null;
      }
    });
    if (saved != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Borrador guardado.')));
    }
  }

  Future<void> _submit() async {
    final listing = _listing;
    if (listing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar a revisión'),
        content: const Text(
          'El inmueble pasará a la cola de revisión de tu inmobiliaria. No '
          'aparecerá en el catálogo hasta que un administrador lo apruebe y '
          'lo publique.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('listing-submit-cancel'),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('listing-submit-confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enviar a revisión'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final submitted = await widget.controller.submit(listing.listingId);
    if (!mounted) return;
    if (submitted) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _message = widget.controller.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = _listing;
    final reopensReview =
        listing != null &&
        (listing.status == ListingStatus.pending ||
            listing.status == ListingStatus.approved);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.listing == null ? 'Nuevo inmueble' : 'Editar inmueble',
        ),
      ),
      body: Center(
        child: SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Form(
              key: _formKey,
              // Every field is built eagerly so Form.validate() reaches all of
              // them; a lazy ListView would skip fields outside the viewport.
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (listing != null) ...[
                      Text(
                        'Estado: ${statusLabel(listing.status)}',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_rejectionReason != null) ...[
                      Card(
                        key: const ValueKey('listing-rejection-reason'),
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Motivo del rechazo: $_rejectionReason'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (reopensReview) ...[
                      Card(
                        key: const ValueKey('listing-status-warning'),
                        color: theme.colorScheme.tertiaryContainer,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Si guardás cambios, el inmueble vuelve a borrador, '
                            'sale del catálogo si estaba publicado y deberá '
                            'aprobarse de nuevo.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_message != null) ...[
                      Card(
                        key: const ValueKey('listing-editor-message'),
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_message!),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Operación', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    SegmentedButton<ListingOperation>(
                      segments: [
                        for (final operation in ListingOperation.values)
                          ButtonSegment(
                            value: operation,
                            label: Text(
                              operationLabel(operation),
                              key: ValueKey(
                                'listing-operation-${operation.wireName}',
                              ),
                            ),
                          ),
                      ],
                      selected: {_operation},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          setState(() => _operation = selection.single),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<ListingCurrency>(
                      key: const ValueKey('listing-currency-field'),
                      initialValue: _currency,
                      decoration: InputDecoration(
                        labelText: 'Moneda',
                        helperText:
                            'Elegí la moneda del precio; después de crear el '
                            'inmueble no se puede cambiar.',
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final currency in ListingCurrency.values)
                          DropdownMenuItem(
                            value: currency,
                            child: Text(currencyLabel(currency)),
                          ),
                      ],
                      // The API rewrites the currency on edit, so the editor
                      // echoes the stored one instead of offering a choice.
                      onChanged: listing == null
                          ? (currency) {
                              if (currency != null) {
                                setState(() => _currency = currency);
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('listing-price-field'),
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Precio base (${_currency.wireName})',
                        helperText: _operation == ListingOperation.rent
                            ? 'Precio mensual, sin muebles opcionales.'
                            : 'Precio de venta, sin muebles opcionales.',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final price = _normalizedPrice(value ?? '');
                        if (price.isEmpty) return 'Ingresá el precio base.';
                        if (!_pricePattern.hasMatch(price)) {
                          return 'Usá hasta 16 dígitos enteros y 2 decimales.';
                        }
                        if (!RegExp('[1-9]').hasMatch(price)) {
                          return 'Ingresá un precio mayor que cero.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      key: 'listing-city-field',
                      controller: _city,
                      label: 'Ciudad',
                      emptyMessage: 'Ingresá la ciudad.',
                    ),
                    const SizedBox(height: 12),
                    _textField(
                      key: 'listing-zone-field',
                      controller: _zone,
                      label: 'Zona o barrio',
                      emptyMessage: 'Ingresá la zona.',
                    ),
                    const SizedBox(height: 12),
                    _countField(
                      'listing-bedrooms-field',
                      _bedrooms,
                      'Dormitorios',
                    ),
                    const SizedBox(height: 12),
                    _countField('listing-bathrooms-field', _bathrooms, 'Baños'),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('listing-description-field'),
                      controller: _description,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('listing-address-field'),
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: 'Dirección exacta (opcional, privada)',
                        helperText: 'No se muestra en el catálogo público.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      key: const ValueKey('listing-save-button'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: _actionMinSize,
                      ),
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar borrador'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const ValueKey('listing-submit-button'),
                      style: FilledButton.styleFrom(
                        minimumSize: _actionMinSize,
                      ),
                      onPressed: _canSubmit ? _submit : null,
                      child: const Text('Enviar a revisión'),
                    ),
                    if (_submitHint != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _submitHint!,
                        key: const ValueKey('listing-submit-hint'),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required String key,
    required TextEditingController controller,
    required String label,
    required String emptyMessage,
  }) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) return emptyMessage;
      if (text.length > _maxGeoLength) return 'Usá hasta 120 caracteres.';
      return null;
    },
  );

  Widget _countField(
    String key,
    TextEditingController controller,
    String label,
  ) => TextFormField(
    key: ValueKey(key),
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) => _countPattern.hasMatch(value?.trim() ?? '')
        ? null
        : 'Ingresá un número entero.',
  );
}
