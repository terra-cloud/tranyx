extension CurrencyFormat on num {
  String toAmount({String currency = "₱", int length = 2}) {
    return "$currency${toStringAsFixed(length).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}";
  }
}

extension DurationFormat on num {
  Duration get milliseconds => Duration(milliseconds: round());
  Duration get seconds => Duration(seconds: round());
  Duration get minutes => Duration(minutes: round());
  Duration get hours => Duration(hours: round());
  Duration get days => Duration(days: round());

  /// Approximate durations (not precise due to month/year variability)
  Duration get weeks => Duration(days: round() * 7);
  Duration get months => Duration(days: round() * 30); // avg month
  Duration get years => Duration(days: round() * 365); // non-leap year
}
