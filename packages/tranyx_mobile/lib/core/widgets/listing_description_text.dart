import 'package:flutter/material.dart';
import 'package:shared/shared.dart';

/// Listing description with paragraph breaks and lists. Text widgets only.
class ListingDescriptionText extends StatelessWidget {
  const ListingDescriptionText({
    super.key,
    required this.text,
    required this.style,
    this.empty = 'No description provided.',
  });

  final String text;
  final TextStyle style;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final blocks = parseListingDescription(text);
    if (blocks.isEmpty) {
      return Text(empty, style: style);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          switch (blocks[i].kind) {
            ListingTextKind.paragraph => Text(blocks[i].text, style: style),
            ListingTextKind.bullets => _items(blocks[i].items, numbered: false),
            ListingTextKind.numbered => _items(blocks[i].items, numbered: true),
          },
        ],
      ],
    );
  }

  Widget _items(List<String> items, {required bool numbered}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(numbered ? '${i + 1}.' : '•', style: style),
                ),
                Expanded(child: Text(items[i], style: style)),
              ],
            ),
          ),
      ],
    );
  }
}
