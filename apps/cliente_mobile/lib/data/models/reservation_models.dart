import 'catalog_models.dart';

class CustomerWallet {
  const CustomerWallet({required this.id, required this.address});

  factory CustomerWallet.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['id'] is! String ||
        json['address'] is! String) {
      throw const FormatException('Wallet fields are invalid');
    }
    return CustomerWallet(
      id: json['id']! as String,
      address: json['address']! as String,
    );
  }

  final String id;
  final String address;
}

class QuoteLine {
  const QuoteLine({
    required this.kind,
    required this.extraId,
    required this.amount,
    required this.currency,
    required this.chargePeriod,
  });

  factory QuoteLine.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['kind'] is! String ||
        (json['extra_id'] != null && json['extra_id'] is! String) ||
        json['amount'] is! String ||
        json['currency'] is! String ||
        json['charge_period'] is! String) {
      throw const FormatException('Quote line fields are invalid');
    }
    return QuoteLine(
      kind: json['kind']! as String,
      extraId: json['extra_id'] as String?,
      amount: json['amount']! as String,
      currency: json['currency']! as String,
      chargePeriod: json['charge_period']! as String,
    );
  }

  final String kind;
  final String? extraId;
  final String amount;
  final String currency;
  final String chargePeriod;
}

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
  });

  factory QuoteSnapshot.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['quote_id'] is! String ||
        json['listing_id'] is! String ||
        json['offer_version'] is! int ||
        json['operation'] is! String ||
        json['lines'] is! List<Object?> ||
        json['created_at'] is! String ||
        json['expires_at'] is! String) {
      throw const FormatException('Quote fields are invalid');
    }
    return QuoteSnapshot(
      quoteId: json['quote_id']! as String,
      listingId: json['listing_id']! as String,
      offerVersion: json['offer_version']! as int,
      operation: json['operation']! as String,
      lines: (json['lines']! as List<Object?>)
          .map(QuoteLine.fromJson)
          .toList(growable: false),
      oneTimeTotal: CatalogMoney.fromJson(json['one_time_total']),
      monthlyTotal: CatalogMoney.fromJson(json['monthly_total']),
      createdAt: DateTime.parse(json['created_at']! as String),
      expiresAt: DateTime.parse(json['expires_at']! as String),
    );
  }

  final String quoteId;
  final String listingId;
  final int offerVersion;
  final String operation;
  final List<QuoteLine> lines;
  final CatalogMoney oneTimeTotal;
  final CatalogMoney monthlyTotal;
  final DateTime createdAt;
  final DateTime expiresAt;
}

class ReservationRecord {
  const ReservationRecord({
    required this.reservationId,
    required this.listingId,
    required this.status,
    required this.paymentMethod,
    required this.apiCreatedAt,
    required this.decisionDeadlineAt,
    required this.quoteSnapshot,
    required this.depositAmount,
    required this.depositConfirmedAt,
  });

  factory ReservationRecord.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['reservation_id'] is! String ||
        json['listing_id'] is! String ||
        json['status'] is! String ||
        (json['payment_method'] != null && json['payment_method'] is! String) ||
        json['api_created_at'] is! String ||
        json['decision_deadline_at'] is! String ||
        (json['deposit_amount'] != null && json['deposit_amount'] is! String) ||
        (json['deposit_confirmed_at'] != null &&
            json['deposit_confirmed_at'] is! String)) {
      throw const FormatException('Reservation fields are invalid');
    }
    return ReservationRecord(
      reservationId: json['reservation_id']! as String,
      listingId: json['listing_id']! as String,
      status: json['status']! as String,
      paymentMethod: (json['payment_method'] as String?) ?? 'wallet',
      apiCreatedAt: DateTime.parse(json['api_created_at']! as String),
      decisionDeadlineAt: DateTime.parse(
        json['decision_deadline_at']! as String,
      ),
      quoteSnapshot: ReservationQuoteSnapshot.fromJson(json['quote_snapshot']),
      depositAmount: json['deposit_amount'] as String?,
      depositConfirmedAt: json['deposit_confirmed_at'] == null
          ? null
          : DateTime.parse(json['deposit_confirmed_at']! as String),
    );
  }

  final String reservationId;
  final String listingId;
  final String status;
  final String paymentMethod;
  final DateTime apiCreatedAt;
  final DateTime decisionDeadlineAt;
  final ReservationQuoteSnapshot quoteSnapshot;
  final String? depositAmount;
  final DateTime? depositConfirmedAt;
}

class CardPaymentSession {
  const CardPaymentSession({
    required this.reservationId,
    required this.paymentIntentId,
    required this.clientSecret,
    required this.publishableKey,
    required this.amountMinor,
    required this.currency,
    required this.status,
  });

  factory CardPaymentSession.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['reservation_id'] is! String ||
        json['payment_intent_id'] is! String ||
        json['client_secret'] is! String ||
        json['publishable_key'] is! String ||
        json['amount_minor'] is! int ||
        json['currency'] is! String ||
        json['status'] is! String) {
      throw const FormatException('Card payment session fields are invalid');
    }
    return CardPaymentSession(
      reservationId: json['reservation_id']! as String,
      paymentIntentId: json['payment_intent_id']! as String,
      clientSecret: json['client_secret']! as String,
      publishableKey: json['publishable_key']! as String,
      amountMinor: json['amount_minor']! as int,
      currency: json['currency']! as String,
      status: json['status']! as String,
    );
  }

  final String reservationId;
  final String paymentIntentId;
  final String clientSecret;
  final String publishableKey;
  final int amountMinor;
  final String currency;
  final String status;
}

class ReservationPermit {
  const ReservationPermit({
    required this.reservationId,
    required this.listingId,
    required this.customer,
    required this.agency,
    required this.actor,
    required this.action,
    required this.amount,
    required this.deadline,
    required this.nonce,
    required this.signature,
  });

  factory ReservationPermit.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['reservationId'] is! String ||
        json['listingId'] is! String ||
        json['customer'] is! String ||
        json['agency'] is! String ||
        json['actor'] is! String ||
        json['action'] is! int ||
        json['amount'] is! int ||
        json['deadline'] is! int ||
        json['nonce'] is! int ||
        json['signature'] is! String) {
      throw const FormatException('Reservation permit fields are invalid');
    }
    return ReservationPermit(
      reservationId: json['reservationId']! as String,
      listingId: json['listingId']! as String,
      customer: json['customer']! as String,
      agency: json['agency']! as String,
      actor: json['actor']! as String,
      action: json['action']! as int,
      amount: json['amount']! as int,
      deadline: json['deadline']! as int,
      nonce: json['nonce']! as int,
      signature: json['signature']! as String,
    );
  }

  final String reservationId;
  final String listingId;
  final String customer;
  final String agency;
  final String actor;
  final int action;
  final int amount;
  final int deadline;
  final int nonce;
  final String signature;
}

class ReservationQuoteSnapshot {
  const ReservationQuoteSnapshot({
    required this.quoteId,
    required this.offerVersion,
    required this.operation,
    required this.lines,
    required this.oneTimeTotal,
    required this.monthlyTotal,
  });

  factory ReservationQuoteSnapshot.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['quote_id'] is! String ||
        json['offer_version'] is! int ||
        json['operation'] is! String ||
        json['lines'] is! List<Object?>) {
      throw const FormatException('Reservation snapshot fields are invalid');
    }
    return ReservationQuoteSnapshot(
      quoteId: json['quote_id']! as String,
      offerVersion: json['offer_version']! as int,
      operation: json['operation']! as String,
      lines: (json['lines']! as List<Object?>)
          .map(QuoteLine.fromJson)
          .toList(growable: false),
      oneTimeTotal: CatalogMoney.fromJson(json['one_time_total']),
      monthlyTotal: CatalogMoney.fromJson(json['monthly_total']),
    );
  }

  final String quoteId;
  final int offerVersion;
  final String operation;
  final List<QuoteLine> lines;
  final CatalogMoney oneTimeTotal;
  final CatalogMoney monthlyTotal;
}

class CustomerWalletChallenge {
  const CustomerWalletChallenge({
    required this.challengeId,
    required this.message,
    required this.expiresAt,
  });

  factory CustomerWalletChallenge.fromJson(Object? json) {
    if (json is! Map<String, Object?> ||
        json['challenge_id'] is! String ||
        json['message'] is! String ||
        json['expires_at'] is! String) {
      throw const FormatException('Wallet challenge fields are invalid');
    }
    return CustomerWalletChallenge(
      challengeId: json['challenge_id']! as String,
      message: json['message']! as String,
      expiresAt: DateTime.parse(json['expires_at']! as String),
    );
  }

  final String challengeId;
  final String message;
  final DateTime expiresAt;
}
