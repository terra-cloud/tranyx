import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';

/// Detail-view description. Text nodes only, so stored markup cannot run.
List<Component> listingDescriptionView(
  String raw, {
  required bool isDark,
  String empty = 'No description provided.',
  String? proseClass,
}) {
  final tone =
      proseClass ?? 'text-sm leading-relaxed break-words max-w-full ${isDark ? "text-zinc-300" : "text-zinc-600"}';
  final blocks = parseListingDescription(raw);
  if (blocks.isEmpty) {
    return [
      p(classes: tone, [Component.text(empty)]),
    ];
  }
  final body = tone;
  return [
    for (final block in blocks)
      switch (block.kind) {
        ListingTextKind.paragraph => p(
          classes: '$body whitespace-pre-wrap mb-3 last:mb-0',
          [Component.text(block.text)],
        ),
        ListingTextKind.bullets => ul(
          classes: 'list-disc pl-5 mb-3 last:mb-0 space-y-1.5 $body',
          [
            for (final item in block.items) li(classes: 'break-words pl-1', [Component.text(item)]),
          ],
        ),
        ListingTextKind.numbered => ol(
          classes: 'list-decimal pl-5 mb-3 last:mb-0 space-y-1.5 $body',
          [
            for (final item in block.items) li(classes: 'break-words pl-1', [Component.text(item)]),
          ],
        ),
      },
  ];
}
