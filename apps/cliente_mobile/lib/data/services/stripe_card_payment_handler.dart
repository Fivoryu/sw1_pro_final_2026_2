import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../models/reservation_models.dart';

abstract interface class CardPaymentHandler {
  Future<bool> present(CardPaymentSession session);
}

class StripeCardPaymentHandler implements CardPaymentHandler {
  @override
  Future<bool> present(CardPaymentSession session) async {
    Stripe.publishableKey = session.publishableKey;
    await Stripe.instance.applySettings();
    await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: session.clientSecret,
        merchantDisplayName: 'RoomForge',
        style: ThemeMode.system,
      ),
    );
    try {
      await Stripe.instance.presentPaymentSheet();
      return true;
    } on StripeException catch (error) {
      if (error.error.code == FailureCode.Canceled) return false;
      rethrow;
    }
  }
}
