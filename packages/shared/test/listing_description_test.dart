import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  test('keeps paragraph breaks and single line breaks', () {
    final blocks = parseListingDescription(
      'Near the park.\nQuiet street.\n\nHouse rules:\nNo smoking.',
    );
    expect(blocks, hasLength(2));
    expect(blocks[0].kind, ListingTextKind.paragraph);
    expect(blocks[0].text, 'Near the park.\nQuiet street.');
    expect(blocks[1].text, 'House rules:\nNo smoking.');
  });

  test('groups dash, bullet, star, and numbered lines into lists', () {
    final blocks = parseListingDescription(
      'Features\n'
      '- WiFi\n'
      '* Parking\n'
      '• Aircon\n'
      '\n'
      'Rules\n'
      '1. No parties\n'
      '2.Quiet hours after 10',
    );
    expect(blocks.map((b) => b.kind).toList(), [
      ListingTextKind.paragraph,
      ListingTextKind.bullets,
      ListingTextKind.paragraph,
      ListingTextKind.numbered,
    ]);
    expect(blocks[1].items, ['WiFi', 'Parking', 'Aircon']);
    expect(blocks[3].items, ['No parties', 'Quiet hours after 10']);
  });

  test('leaves stored text unchanged and keeps markup as text', () {
    const stored = 'Line one\n\n<script>alert(1)</script>\n- <b>bold</b>';
    final blocks = parseListingDescription(stored);
    expect(stored, contains('\n'));
    expect(blocks[0].text, 'Line one');
    expect(blocks[1].text, '<script>alert(1)</script>');
    expect(blocks[2].items, ['<b>bold</b>']);
    expect(blocks.map((b) => b.text).join(), isNot(contains('innerHTML')));
  });

  test('normalizes Windows newlines and keeps a bare marker as text', () {
    final blocks = parseListingDescription('First\r\n\r\n-\r\nSecond');
    expect(blocks.map((b) => b.text).toList(), ['First', '-\nSecond']);
    expect(blocks.every((b) => b.kind == ListingTextKind.paragraph), isTrue);
  });
}
