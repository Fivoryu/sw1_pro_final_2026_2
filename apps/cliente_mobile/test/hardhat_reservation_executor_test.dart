import 'package:cliente_mobile/data/services/hardhat_reservation_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bob = '0x${List.filled(40, '1').join()}';
  final usd = '0x${List.filled(40, '2').join()}';
  final usdt = '0x${List.filled(40, '3').join()}';
  final legacy = '0x${List.filled(40, '4').join()}';

  group('local escrow configuration', () {
    test('selects a distinct escrow for each supported currency', () {
      expect(
        localEscrowAddressForCurrency(
          'BOB',
          bobAddress: bob,
          usdAddress: usd,
          usdtAddress: usdt,
          legacyRftEscrowAddress: legacy,
        ),
        bob,
      );
      expect(
        localEscrowAddressForCurrency(
          'USD',
          bobAddress: bob,
          usdAddress: usd,
          usdtAddress: usdt,
          legacyRftEscrowAddress: legacy,
        ),
        usd,
      );
      expect(
        localEscrowAddressForCurrency(
          'USDT',
          bobAddress: bob,
          usdAddress: usd,
          usdtAddress: usdt,
          legacyRftEscrowAddress: legacy,
        ),
        usdt,
      );
    });

    test('uses the legacy RFT escrow only for BOB/USD configuration gaps', () {
      expect(
        localEscrowAddressForCurrency(
          'BOB',
          bobAddress: '',
          usdAddress: usd,
          usdtAddress: usdt,
          legacyRftEscrowAddress: legacy,
        ),
        legacy,
      );
      expect(
        () => localEscrowAddressForCurrency(
          'USDT',
          bobAddress: bob,
          usdAddress: usd,
          usdtAddress: '',
          legacyRftEscrowAddress: legacy,
        ),
        throwsStateError,
      );
      expect(
        () => localEscrowAddressForCurrency(
          'COP',
          bobAddress: bob,
          usdAddress: usd,
          usdtAddress: usdt,
          legacyRftEscrowAddress: legacy,
        ),
        throwsStateError,
      );
    });
  });
}
