import 'package:cliente_mobile/data/services/hardhat_reservation_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bob = '0x${List.filled(40, '1').join()}';
  final usd = '0x${List.filled(40, '2').join()}';
  final usdt = '0x${List.filled(40, '3').join()}';
  final legacy = '0x${List.filled(40, '4').join()}';

  group('permit identifier validation', () {
    test(
      'hashes reservation and listing API IDs as UTF-8 Keccak bytes32 values',
      () {
        expect(
          permitIdHash('reservation-123'),
          '0x5f40ae0ea4d3351a7796ba7f0f12e2d23d94d463424219c36d61d37ed58e69e6',
        );
        expect(
          permitIdHash('listing-456'),
          '0x5c870d31aa5a69bbdeb905521a60e3124b78af7d7ad25ca43dd38dc09f400bdd',
        );
      },
    );

    test('accepts permit IDs hashed from reservation record IDs', () {
      expect(
        permitIdsMatch(
          permitReservationId:
              '0x5f40ae0ea4d3351a7796ba7f0f12e2d23d94d463424219c36d61d37ed58e69e6',
          permitListingId:
              '0x5c870d31aa5a69bbdeb905521a60e3124b78af7d7ad25ca43dd38dc09f400bdd',
          reservationId: 'reservation-123',
          listingId: 'listing-456',
        ),
        isTrue,
      );
    });

    test('rejects raw permit IDs instead of hashed reservation record IDs', () {
      expect(
        permitIdsMatch(
          permitReservationId: 'reservation-123',
          permitListingId: 'listing-456',
          reservationId: 'reservation-123',
          listingId: 'listing-456',
        ),
        isFalse,
      );
    });
  });

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
