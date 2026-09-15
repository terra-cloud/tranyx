import 'package:test/test.dart';
import 'package:shared/shared.dart';

void main() {
  group('TranyxAIService Auto-Drafting & Support Tests', timeout: const Timeout(Duration(minutes: 2)), () {
    late TranyxAIService aiService;

    setUp(() {
      aiService = TranyxAIService();
    });

    test('generateJobDescription auto-drafts structured description', () async {
      final desc = await aiService.generateJobDescription('Electrician needed for outlet wiring');
      print('Auto-drafted Job Description:\n$desc\n');
      expect(desc, isNotEmpty);
      expect(desc.length, greaterThan(20));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Scenario 1: Category-Specific Prompt Tuning for Vehicle Rental & Courier / Delivery', () async {
      // Courier / Delivery category
      final deliveryDesc = await aiService.generateJobDescription(
        'Need pickup in Bacoor',
        categoryLabel: 'Courier / Delivery',
      );
      print('Auto-drafted Delivery Description:\n$deliveryDesc\n');
      expect(deliveryDesc, isNotEmpty);
      expect(
        deliveryDesc.toLowerCase(),
        anyOf(
          contains('courier'),
          contains('delivery'),
          contains('pickup'),
          contains('drop-off'),
          contains('transit'),
        ),
      );

      // Vehicle Rental category
      final rentalDesc = await aiService.generateJobDescription(
        'Need pickup in Bacoor',
        categoryLabel: 'Vehicle Rental',
      );
      print('Auto-drafted Rental Description:\n$rentalDesc\n');
      expect(rentalDesc, isNotEmpty);
      expect(
        rentalDesc.toLowerCase(),
        anyOf(
          contains('vehicle'),
          contains('rental'),
          contains('driver'),
          contains('pickup'),
          contains('timing'),
        ),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('generateCoverNote auto-drafts persuasive application note', () async {
      final cover = await aiService.generateCoverNote('Motorcycle Delivery Rider in Tacloban');
      print('Auto-drafted Cover Note:\n$cover\n');
      expect(cover, isNotEmpty);
      expect(cover.length, greaterThan(20));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('generateJobTitle auto-drafts short catchy title', () async {
      final title = await aiService.generateJobTitle(
        JobCategory.carpenter,
        'Need someone to install drywall and paint living room',
      );
      print('Auto-drafted Job Title:\n$title\n');
      expect(title, isNotEmpty);
      expect(title.split(' ').length, lessThanOrEqualTo(8));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('validateJobTitle validates correctly', () async {
      final isValid = await aiService.validateJobTitle('Plumbing Pipe Repair', JobCategory.plumber);
      expect(isValid, isTrue);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('Scenario: Category Mismatch Validation throws CategoryMismatchException', () async {
      // Leaking sink under Vehicle Rental
      expect(
        () => aiService.generateJobDescription(
          'Fix leaking kitchen sink and faucet pipe',
          categoryLabel: 'Vehicle Rental',
        ),
        throwsA(isA<CategoryMismatchException>().having(
          (e) => e.message,
          'message',
          contains('Category Mismatch'),
        )),
      );

      // Motorcycle driver under Plumbing
      expect(
        () => aiService.generateJobDescription(
          'Need motorcycle driver for courier deliveries',
          categoryLabel: 'Plumbing',
        ),
        throwsA(isA<CategoryMismatchException>().having(
          (e) => e.message,
          'message',
          contains('Category Mismatch'),
        )),
      );

      // User case: Carpenter under Electrician in Waray-Waray
      expect(
        () => aiService.generateJobDescription(
          'Nanginginahanglan ak san karpentero',
          categoryLabel: 'Electrician',
        ),
        throwsA(isA<CategoryMismatchException>().having(
          (e) => e.message,
          'message',
          contains('Category Mismatch'),
        )),
      );
    });

    test('Scenario: Multilingual Auto-Drafting in Tagalog and Waray-Waray', () async {
      // Tagalog aligned prompt
      final tagalogDesc = await aiService.generateJobDescription(
        'Kailangan ng tubero para sa tumutulong lababo',
        categoryLabel: 'Plumbing',
      );
      print('Auto-drafted Tagalog Description:\n$tagalogDesc\n');
      expect(tagalogDesc, isNotEmpty);
      expect(tagalogDesc, isNot(contains('"Kailangan ng tubero para sa tumutulong lababo"')));
      expect(
        tagalogDesc.toLowerCase(),
        anyOf(
          contains('naghahanap'),
          contains('kailangan'),
          contains('tubero'),
          contains('manggagawa'),
          contains('gamit'),
        ),
      );

      // Waray-Waray aligned prompt
      final warayDesc = await aiService.generateJobDescription(
        'Nagkikinahanglan hin panday para hit balay',
        categoryLabel: 'Carpentry',
      );
      print('Auto-drafted Waray-Waray Description:\n$warayDesc\n');
      expect(warayDesc, isNotEmpty);
      expect(warayDesc, isNot(contains('"Nagkikinahanglan hin panday para hit balay"')));
      expect(
        warayDesc.toLowerCase(),
        anyOf(
          contains('nagkikinahanglan'),
          contains('kinahanglan'),
          contains('traba'),
          contains('gamit'),
          contains('panday'),
        ),
      );
    });

    test('getChatResponse answers Tranyx questions accurately in multilingual mode', () async {
      final history = [
        {'role': 'user', 'content': 'Paano gumagana ang Escrow sa Tranyx kapag tapos na ang trabaho?'}
      ];
      final response = await aiService.getChatResponse(history);
      print('AI Support Response (Tagalog):\n$response\n');
      expect(response, isNotEmpty);
      expect(response.toLowerCase(), contains('qr'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
