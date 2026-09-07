import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('Promo & Platform-Fee-Only Discount Tests', () {
    test('Scenario 1: Vehicle Rental with 50% Platform Fee Promo', () {
      // Vehicle Rental: ₱2,000, Platform Fee (10%): ₱200
      final promo = Promo(
        code: 'LAUNCH50',
        name: 'TRANYX Launch Promo',
        discountType: 'percentage',
        discountValue: 50.0,
        applicableFee: 'platform_fee',
        applicableTo: 'rentals',
        createdAt: DateTime.now(),
      );

      final result = promo.calculateDiscount(
        basePrice: 2000.0,
        platformFee: 200.0,
      );

      // Calculations:
      // Base Price (Provider Settlement): ₱2,000 (100% intact, NOT discounted)
      // Original Platform Fee: ₱200
      // Discount Amount (50% of ₱200): ₱100
      // Final Platform Fee: ₱100
      // Customer Total: ₱2,100
      // TRANYX Revenue: ₱100
      // TRANYX Promo Cost: ₱100
      expect(result.basePrice, 2000.0);
      expect(result.providerSettlement, 2000.0);
      expect(result.originalPlatformFee, 200.0);
      expect(result.discountAmount, 100.0);
      expect(result.finalPlatformFee, 100.0);
      expect(result.finalCustomerAmount, 2100.0);
      expect(result.tranyxRevenue, 100.0);
      expect(result.tranyxPromoCost, 100.0);
    });

    test('Scenario 2: Property Rental with 50% Platform Fee Promo', () {
      // Property Rental: ₱5,000, Platform Fee (10%): ₱500
      final promo = Promo(
        code: 'PROPHALF',
        name: 'Property Half Fee',
        discountType: 'percentage',
        discountValue: 50.0,
        applicableFee: 'platform_fee',
        applicableTo: 'rentals',
        createdAt: DateTime.now(),
      );

      final result = promo.calculateDiscount(
        basePrice: 5000.0,
        platformFee: 500.0,
      );

      expect(result.basePrice, 5000.0);
      expect(result.providerSettlement, 5000.0);
      expect(result.originalPlatformFee, 500.0);
      expect(result.discountAmount, 250.0);
      expect(result.finalPlatformFee, 250.0);
      expect(result.finalCustomerAmount, 5250.0);
    });

    test('Scenario 3: Service Listing with 100% (Zero Fee) Discount', () {
      // Service Provider Price: ₱1,500, Transaction Fee: ₱150
      final promo = Promo(
        code: 'ZEROFEES1000',
        name: 'Auto Zero Fees - First 1,000 Users',
        discountType: 'percentage',
        discountValue: 100.0,
        applicableFee: 'transaction_fee',
        applicableTo: 'services',
        maxUsers: 1000,
        isAutoApply: true,
        createdAt: DateTime.now(),
      );

      final result = promo.calculateDiscount(
        basePrice: 1500.0,
        platformFee: 150.0,
      );

      // Result:
      // Service Price: ₱1,500 (Untouched)
      // Transaction Fee: ₱150 -> ₱0
      // Customer Pays: ₱1,500
      // Provider Receives: ₱1,500
      expect(result.basePrice, 1500.0);
      expect(result.providerSettlement, 1500.0);
      expect(result.originalPlatformFee, 150.0);
      expect(result.discountAmount, 150.0);
      expect(result.finalPlatformFee, 0.0);
      expect(result.finalCustomerAmount, 1500.0);
      expect(result.tranyxRevenue, 0.0);
      expect(result.tranyxPromoCost, 150.0);
    });

    test('Scenario 4: Fixed Amount ₱50 OFF Platform Fee', () {
      // Listing Price: ₱2,000, Platform Fee: ₱200, Promo: ₱50 OFF Platform Fee
      final promo = Promo(
        code: 'FEE50OFF',
        discountType: 'flat',
        discountValue: 50.0,
        applicableFee: 'platform_fee',
        applicableTo: 'both',
        createdAt: DateTime.now(),
      );

      final result = promo.calculateDiscount(
        basePrice: 2000.0,
        platformFee: 200.0,
      );

      expect(result.basePrice, 2000.0);
      expect(result.providerSettlement, 2000.0);
      expect(result.originalPlatformFee, 200.0);
      expect(result.discountAmount, 50.0);
      expect(result.finalPlatformFee, 150.0);
      expect(result.finalCustomerAmount, 2150.0);
    });

    test('Scenario 5: Fixed Discount Exceeding Fee is Capped to Eligible Fee (Never touches Provider)', () {
      // Listing Price: ₱1,000, Platform Fee: ₱30 (3%), Promo: ₱100 OFF Platform Fee
      final promo = Promo(
        code: 'BIGFEE100',
        discountType: 'flat',
        discountValue: 100.0,
        applicableFee: 'platform_fee',
        applicableTo: 'both',
        createdAt: DateTime.now(),
      );

      final result = promo.calculateDiscount(
        basePrice: 1000.0,
        platformFee: 30.0,
      );

      // Discount is strictly clamped to platform fee (₱30) and NEVER eats into the ₱1,000 listing price!
      expect(result.discountAmount, 30.0);
      expect(result.finalPlatformFee, 0.0);
      expect(result.finalCustomerAmount, 1000.0);
      expect(result.providerSettlement, 1000.0);
    });

    test('Scenario 6: Max Discount Capping Enforcement', () {
      // Platform Fee: ₱500, Promo: 50% discount but max discount capped at ₱100
      final promo = Promo(
        code: 'CAP100',
        discountType: 'percentage',
        discountValue: 50.0, // 50% of 500 is 250
        maxDiscountAmount: 100.0, // Cap at 100
        applicableFee: 'platform_fee',
        applicableTo: 'both',
        createdAt: DateTime.now(),
      );

      final result = promo.calculateDiscount(
        basePrice: 3000.0,
        platformFee: 500.0,
      );

      expect(result.discountAmount, 100.0);
      expect(result.finalPlatformFee, 400.0);
      expect(result.finalCustomerAmount, 3400.0);
      expect(result.providerSettlement, 3000.0);
    });

    test('Scenario 7: Minimum Transaction Requirement', () {
      final promo = Promo(
        code: 'MIN500',
        discountType: 'percentage',
        discountValue: 50.0,
        minTransactionAmount: 500.0,
        applicableFee: 'platform_fee',
        applicableTo: 'both',
        createdAt: DateTime.now(),
      );

      // Transaction below min: Total = 200 + 20 = 220 < 500
      final resultBelow = promo.calculateDiscount(
        basePrice: 200.0,
        platformFee: 20.0,
      );
      expect(resultBelow.discountAmount, 0.0);
      expect(resultBelow.finalCustomerAmount, 220.0);

      // Transaction above min: Total = 1000 + 100 = 1100 >= 500
      final resultAbove = promo.calculateDiscount(
        basePrice: 1000.0,
        platformFee: 100.0,
      );
      expect(resultAbove.discountAmount, 50.0);
      expect(resultAbove.finalCustomerAmount, 1050.0);
    });

    test('Scenario 8: Serialization & Deserialization with new Admin fields', () {
      final now = DateTime.now();
      final promo = Promo(
        code: 'ZEROFEES1000',
        name: 'Auto Zero Platform Fees - First 1,000 Users',
        description: 'Auto waiver of all TRANYX platform fees for the first 1,000 users.',
        discountType: 'percentage',
        discountValue: 100.0,
        applicableFee: 'all_fees',
        applicableTo: 'both',
        eligibleModules: ['jobs', 'services', 'rentals', 'vehicle_rentals', 'property_rentals', 'all'],
        minTransactionAmount: 100.0,
        maxDiscountAmount: 5000.0,
        maxUsers: 1000,
        maxUsesPerUser: 1,
        usedCount: 15,
        isSingleUsePerUser: true,
        isAutoApply: true,
        isActive: true,
        createdAt: now,
        startDate: now,
        endDate: now.add(const Duration(days: 90)),
        createdBy: 'admin_zeus',
      );

      final map = promo.toMap();
      final restored = Promo.fromMap(map, 'ZEROFEES1000');

      expect(restored.code, 'ZEROFEES1000');
      expect(restored.name, 'Auto Zero Platform Fees - First 1,000 Users');
      expect(restored.applicableFee, 'all_fees');
      expect(restored.discountType, 'percentage');
      expect(restored.discountValue, 100.0);
      expect(restored.maxUsers, 1000);
      expect(restored.usedCount, 15);
      expect(restored.isAutoApply, true);
      expect(restored.createdBy, 'admin_zeus');
    });
  });
}
