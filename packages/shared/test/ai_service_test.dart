import 'package:test/test.dart';
import 'package:shared/shared.dart';

@Timeout(Duration(minutes: 2))
void main() {
  group('TranyxAIService Auto-Drafting & Support Tests', () {
    late TranyxAIService aiService;

    setUp(() {
      aiService = TranyxAIService();
    });

    test('generateJobDescription auto-drafts structured description', () async {
      final desc = await aiService.generateJobDescription('Electrician needed for outlet wiring');
      print('Auto-drafted Job Description:\n$desc\n');
      expect(desc, isNotEmpty);
      expect(desc.length, greaterThan(20));
    });

    test('generateCoverNote auto-drafts persuasive application note', () async {
      final cover = await aiService.generateCoverNote('Motorcycle Delivery Rider in Tacloban');
      print('Auto-drafted Cover Note:\n$cover\n');
      expect(cover, isNotEmpty);
      expect(cover.length, greaterThan(20));
    });

    test('generateJobTitle auto-drafts short catchy title', () async {
      final title = await aiService.generateJobTitle(
        JobCategory.carpenter,
        'Need someone to install drywall and paint living room',
      );
      print('Auto-drafted Job Title:\n$title\n');
      expect(title, isNotEmpty);
      expect(title.split(' ').length, lessThanOrEqualTo(8));
    });

    test('validateJobTitle validates correctly', () async {
      final isValid = await aiService.validateJobTitle('Plumbing Pipe Repair', JobCategory.plumber);
      expect(isValid, isTrue);
    });

    test('getChatResponse answers Tranyx questions accurately in multilingual mode', () async {
      final history = [
        {'role': 'user', 'content': 'Paano gumagana ang Escrow sa Tranyx kapag tapos na ang trabaho?'}
      ];
      final response = await aiService.getChatResponse(history);
      print('AI Support Response (Tagalog):\n$response\n');
      expect(response, isNotEmpty);
      expect(response.toLowerCase(), contains('qr'));
    });
  });
}
