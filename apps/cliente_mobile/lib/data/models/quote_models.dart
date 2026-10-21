/// A quote snapshot returned by `POST /api/v1/quotes` (F05).
///
/// The server is the only converter: the totals come exactly as the API sent
/// them, and the app never converts prices locally.
class QuoteSnapshot {
  const QuoteSnapshot({
    required this.quoteId,
    required this.listingId,
    required this.offerVersion,
    required this.operation,
    required this.lines,
    required this.oneTimeTotal,
    required this.monthlyTotal,
    required this.createdAt,
    required this.expiresAt,
    this.displayTotals,
  });

  factory QuoteSnapshot.fromJson(Map<String, Object?> json) => QuoteSnapshot(
    quoteId: json['quote_id']! as String,
    listingId: json['listing_id']! as String,
    offerVersion: json['offer_version']! as int,
    operation: json['operation']! as String,
    lines: [
      for (final line in json['lines']! as List<Object?>)
        QuoteLine.fromJson(line! as Map<String, Object?>),
    ],
    oneTimeTotal: QuoteMoney.fromJson(json['one_time_total']! as Map<String, Object?>),
    monthlyTotal: QuoteMoney.fromJson(json['monthly_total']! as Map<String, Object?>),
    createdAt: DateTime.parse(json['created_at']! as String),
    expiresAt: DateTime.parse(json['expires_at']! as String),
    displayTotals: json['display_totals'] is Map<String, Object?>
        ? QuoteDisplayTotals.fromJson(
            json['display_totals']! as Map<String, Object?>,
          )
        : null,
  );

  final String quoteId;
  final String listingId;
  final int offerVersion;
  final String operation;
  final List<QuoteLine> lines;
  final QuoteMoney oneTimeTotal;
  final QuoteMoney monthlyTotal;
  final DateTime createdAt;
  final DateTime expiresAt;
  final QuoteDisplayTotals? displayTotals;
}

class QuoteLine {
  factory QuoteLine.fromJson(Map<String, Object?> json) => QuoteLine._(
    kind: json['kind']! as String,
    extraId: json['extra_id'] as String?,
    amount: json['amount']! as String,
    currency: json['currency']! as String,
    chargePeriod: json['charge_period']! as String,
  );

  const QuoteLine._({
    required this.kind,
    required this.extraId,
    required this.amount,
    required this.currency,
    required this.chargePeriod,
  });

  final String kind;
  final String? extraId;
  final String amount;
  final String currency;
  final String chargePeriod;
}

class QuoteMoney {
  const QuoteMoney({required this.amount, required this.currency});

  factory QuoteMoney.fromJson(Map<String, Object?> json) => QuoteMoney(
    amount: json['amount']! as String,
    currency: json['currency']! as String,
  );

  final String amount;
  final String currency;
}

class QuoteDisplayTotals {
  const QuoteDisplayTotals({required this.oneTimeTotal, required this.monthlyTotal});

  factory QuoteDisplayTotals.fromJson(Map<String, Object?> json) =>
      QuoteDisplayTotals(
        oneTimeTotal: QuoteMoney.fromJson(json['one_time_total']! as Map<String, Object?>),
        monthlyTotal: QuoteMoney.fromJson(json['monthly_total']! as Map<String, Object?>),
      );

  final QuoteMoney oneTimeTotal;
  final QuoteMoney monthlyTotal;
}
