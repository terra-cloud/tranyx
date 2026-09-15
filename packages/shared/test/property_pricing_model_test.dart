import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('PropertyPricingModel Calculations (TRX-RENT-3100)', () {
    test('TC-REV-01: 1 Day Rental with Daily Rate and Fixed Deposit', () {
      const model = PropertyPricingModel(
        dailyRate: 1500.0,
        weeklyRate: 8000.0,
        monthlyRate: 30000.0,
        depositType: DepositType.fixed,
        depositValue: 500.0,
      );

      final f = model.calculate(totalDays: 1);

      expect(f.appliedTier, equals(DurationTier.daily));
      expect(f.totalDays, equals(1));
      expect(f.baseRent, equals(1500.0));
      expect(f.customerPlatformFeeRate, equals(0.03));
      expect(f.customerPlatformFee, equals(45.0)); // 1500 * 0.03
      expect(f.securityDeposit, equals(500.0));
      expect(f.totalCustomerPayable, equals(2045.0)); // 1500 + 45 + 500
      expect(f.hostCommissionRate, equals(0.07));
      expect(f.hostCommission, equals(105.0)); // 1500 * 0.07
      expect(f.hostNetIncome, equals(1395.0)); // 1500 - 105
    });

    test('TC-REV-02: 3 Days Rental with Daily Rate and Fixed Deposit', () {
      const model = PropertyPricingModel(
        dailyRate: 1500.0,
        weeklyRate: 8000.0,
        monthlyRate: 30000.0,
        depositType: DepositType.fixed,
        depositValue: 1000.0,
      );

      final f = model.calculate(totalDays: 3);

      expect(f.appliedTier, equals(DurationTier.daily));
      expect(f.totalDays, equals(3));
      expect(f.baseRent, equals(4500.0)); // 1500 * 3
      expect(f.customerPlatformFee, equals(135.0)); // 4500 * 0.03
      expect(f.securityDeposit, equals(1000.0));
      expect(f.totalCustomerPayable, equals(5635.0)); // 4500 + 135 + 1000
      expect(f.hostCommission, equals(315.0)); // 4500 * 0.07
      expect(f.hostNetIncome, equals(4185.0)); // 4500 - 315
    });

    test('TC-REV-03: 1 Week (7 Days) Rental with Percentage Deposit', () {
      const model = PropertyPricingModel(
        dailyRate: 1500.0,
        weeklyRate: 8000.0,
        monthlyRate: 30000.0,
        depositType: DepositType.percentage,
        depositValue: 20.0, // 20%
      );

      final f = model.calculate(totalDays: 7);

      expect(f.appliedTier, equals(DurationTier.weekly));
      expect(f.totalDays, equals(7));
      expect(f.baseRent, equals(8000.0)); // 1 week
      expect(f.customerPlatformFee, equals(240.0)); // 8000 * 0.03
      expect(f.securityDeposit, equals(1600.0)); // 20% of 8000
      expect(f.totalCustomerPayable, equals(9840.0)); // 8000 + 240 + 1600
      expect(f.hostCommission, equals(560.0)); // 8000 * 0.07
      expect(f.hostNetIncome, equals(7440.0)); // 8000 - 560
    });

    test('TC-REV-04: 1 Month (30 Days) Rental with Fixed Deposit', () {
      const model = PropertyPricingModel(
        dailyRate: 1500.0,
        weeklyRate: 8000.0,
        monthlyRate: 30000.0,
        depositType: DepositType.fixed,
        depositValue: 5000.0,
      );

      final f = model.calculate(totalDays: 30);

      expect(f.appliedTier, equals(DurationTier.monthly));
      expect(f.totalDays, equals(30));
      expect(f.baseRent, equals(30000.0)); // 1 month
      expect(f.customerPlatformFee, equals(900.0)); // 30000 * 0.03
      expect(f.securityDeposit, equals(5000.0));
      expect(f.totalCustomerPayable, equals(35900.0)); // 30000 + 900 + 5000
      expect(f.hostCommission, equals(2100.0)); // 30000 * 0.07
      expect(f.hostNetIncome, equals(27900.0)); // 30000 - 2100
    });

    test('TC-REV-05: Dynamic Admin Fee Rates (Custom 4% Customer Fee, 8% Host Commission)', () {
      const model = PropertyPricingModel(
        dailyRate: 1000.0,
        depositType: DepositType.none,
        depositValue: 0.0,
      );

      final f = model.calculate(
        totalDays: 3,
        customerPlatformFeeRate: 0.04,
        hostCommissionRate: 0.08,
      );

      expect(f.baseRent, equals(3000.0));
      expect(f.customerPlatformFeeRate, equals(0.04));
      expect(f.customerPlatformFee, equals(120.0)); // 3000 * 0.04
      expect(f.securityDeposit, equals(0.0));
      expect(f.totalCustomerPayable, equals(3120.0)); // 3000 + 120
      expect(f.hostCommissionRate, equals(0.08));
      expect(f.hostCommission, equals(240.0)); // 3000 * 0.08
      expect(f.hostNetIncome, equals(2760.0)); // 3000 - 240
    });

    test('Remainder days in weekly tier prorate using daily rate', () {
      const model = PropertyPricingModel(
        dailyRate: 1000.0,
        weeklyRate: 6000.0,
        monthlyRate: 24000.0,
      );

      // 10 days = 1 week (6000) + 3 remainder days (3 * 1000 = 3000) = 9000
      final f = model.calculate(totalDays: 10);
      expect(f.appliedTier, equals(DurationTier.weekly));
      expect(f.baseRent, equals(9000.0));
    });

    test('Serialization toMap and fromMap preserves all fields', () {
      const model = PropertyPricingModel(
        dailyRate: 1500.0,
        weeklyRate: 8000.0,
        monthlyRate: 30000.0,
        depositType: DepositType.percentage,
        depositValue: 15.0,
      );

      final financials = model.calculate(totalDays: 5);
      final map = financials.toMap();
      final restored = BookingFinancials.fromMap(map);

      expect(restored.appliedTier, equals(financials.appliedTier));
      expect(restored.totalDays, equals(financials.totalDays));
      expect(restored.baseRent, equals(financials.baseRent));
      expect(restored.securityDeposit, equals(financials.securityDeposit));
      expect(restored.depositType, equals(financials.depositType));
      expect(restored.customerPlatformFee, equals(financials.customerPlatformFee));
      expect(restored.totalCustomerPayable, equals(financials.totalCustomerPayable));
      expect(restored.hostCommission, equals(financials.hostCommission));
      expect(restored.hostNetIncome, equals(financials.hostNetIncome));
    });

    test('Deserialization from untyped Map<dynamic, dynamic> with nested policy succeeds', () {
      final rawMap = <dynamic, dynamic>{
        'dailyRate': 2000,
        'weeklyRate': 12000,
        'monthlyRate': 45000,
        'securityDepositPolicy': <dynamic, dynamic>{
          'type': 'fixed',
          'value': 2500,
        },
      };

      final model = PropertyPricingModel.fromPropertyMap(rawMap);
      expect(model.dailyRate, equals(2000.0));
      expect(model.depositType, equals(DepositType.fixed));
      expect(model.depositValue, equals(2500.0));

      final rawPropMap = <dynamic, dynamic>{
        'id': 'prop_123',
        'hostId': 'host_456',
        'title': 'Test Property',
        'description': 'A beautiful test apartment',
        'type': 'apartment',
        'category': 'residential',
        'priceDaily': 2000,
        'priceWeekly': 12000,
        'priceMonthly': 45000,
        'securityDepositPolicy': <dynamic, dynamic>{
          'type': 'percentage',
          'value': 10,
        },
        'status': 'Available',
      };

      final prop = PropertyRental.fromMap(rawPropMap, 'prop_123');
      expect(prop.id, equals('prop_123'));
      expect(prop.priceDaily, equals(2000.0));
      expect(prop.depositType, equals(DepositType.percentage));
      expect(prop.depositValue, equals(10.0));

      final rawFinancialsMap = <dynamic, dynamic>{
        'appliedTier': 'DAILY',
        'totalDays': 2,
        'unitRate': 2000.0,
        'baseRentAmount': 4000.0,
        'securityDepositAmount': 500.0,
        'depositType': 'fixed',
        'depositValue': 500.0,
        'customerPlatformFeeRate': 0.03,
        'customerPlatformFeeAmount': 120.0,
        'totalCustomerPaid': 4620.0,
        'hostCommissionRate': 0.07,
        'hostCommissionAmount': 280.0,
        'hostNetPayout': 3720.0,
      };
      final financials = BookingFinancials.fromMap(rawFinancialsMap);
      expect(financials.appliedTier, equals(DurationTier.daily));
      expect(financials.totalCustomerPayable, equals(4620.0));

      final rawUserMap = <dynamic, dynamic>{
        'name': 'Test User',
        'email': 'test@example.com',
        'tyxBalance': 5000.0,
        'accountType': 'employer',
        'verificationLevel': 2,
        'idVerified': true,
      };
      final user = UserProfile.fromMap('user_123', rawUserMap);
      expect(user.uid, equals('user_123'));
      expect(user.name, equals('Test User'));
      expect(user.tyxBalance, equals(5000.0));

      final rawPromoMap = <dynamic, dynamic>{
        'name': 'WELCOME50',
        'discountType': 'percentage',
        'discountValue': 50.0,
        'applicableFee': 'platform_fee',
        'applicableTo': 'both',
        'isActive': true,
      };
      final promo = Promo.fromMap(rawPromoMap, 'WELCOME50');
      expect(promo.code, equals('WELCOME50'));
      expect(promo.discountValue, equals(50.0));
    });
  });
}
