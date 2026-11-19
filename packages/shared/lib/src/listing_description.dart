/// Structured view of a listing description. The stored string is unchanged.
/// Renderers must put [text] into text nodes, never into HTML.
enum ListingTextKind { paragraph, bullets, numbered }

class ListingTextBlock {
  const ListingTextBlock._(this.kind, this.text, this.items);

  final ListingTextKind kind;

  /// Paragraph body. Single newlines are line breaks. Not used for lists.
  final String text;

  /// List items with the marker removed.
  final List<String> items;

  factory ListingTextBlock.paragraph(String text) =>
      ListingTextBlock._(ListingTextKind.paragraph, text, const []);

  factory ListingTextBlock.bullets(List<String> items) =>
      ListingTextBlock._(ListingTextKind.bullets, '', List.unmodifiable(items));

  factory ListingTextBlock.numbered(List<String> items) => ListingTextBlock._(
    ListingTextKind.numbered,
    '',
    List.unmodifiable(items),
  );
}

final _bullet = RegExp(r'^\s*(?:[-*]\s+|•\s*)(\S.*?)\s*$');
final _numbered = RegExp(r'^\s*\d+\.\s*(\S.*?)\s*$');

/// Splits a stored description into paragraphs and lists.
/// Blank lines separate blocks. Lines that start with `-`, `*`, `•`, or `1.`
/// become list items. Markup such as `<script>` stays ordinary text.
List<ListingTextBlock> parseListingDescription(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final blocks = <ListingTextBlock>[];
  final paragraph = <String>[];
  final bullets = <String>[];
  final numbered = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(ListingTextBlock.paragraph(paragraph.join('\n')));
    paragraph.clear();
  }

  void flushBullets() {
    if (bullets.isEmpty) return;
    blocks.add(ListingTextBlock.bullets(List.of(bullets)));
    bullets.clear();
  }

  void flushNumbered() {
    if (numbered.isEmpty) return;
    blocks.add(ListingTextBlock.numbered(List.of(numbered)));
    numbered.clear();
  }

  for (final line in lines) {
    if (line.trim().isEmpty) {
      flushParagraph();
      flushBullets();
      flushNumbered();
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      flushNumbered();
      bullets.add(bullet.group(1)!);
      continue;
    }
    final number = _numbered.firstMatch(line);
    if (number != null) {
      flushParagraph();
      flushBullets();
      numbered.add(number.group(1)!);
      continue;
    }
    flushBullets();
    flushNumbered();
    paragraph.add(line.trimRight());
  }
  flushParagraph();
  flushBullets();
  flushNumbered();
  return blocks;
}
