extension StringCasingExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }

  String capitalizeWords() {
    return split(' ')
        .map(
          (word) => word.trim().isEmpty
              ? word
              : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  String truncate(int max) {
    if (length <= max) return this;
    return '${substring(0, max)}...';
  }
}

extension CaseExtension on String {
  String normalizeSnakeCase() {
    return split('_')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  String normalizeCamelCase() {
    return replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    ).replaceFirstMapped(
      RegExp(r'^[a-z]'),
      (match) => match.group(0)!.toUpperCase(),
    );
  }
}
