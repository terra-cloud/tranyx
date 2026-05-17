import 'package:flutter/material.dart';

/// Extension on [Color] to provide utility methods for color manipulation.
extension ColorExtension on Color {
  /// Lightens the color by the given [amount] (between 0 and 1).
  /// 
  /// The [amount] defaults to 0.1 (10%).
  /// A value of 0 results in the original color, and 1 results in white.
  Color lighten([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return hslLight.toColor();
  }

  /// Darkens the color by the given [amount] (between 0 and 1).
  /// 
  /// The [amount] defaults to 0.1 (10%).
  /// A value of 0 results in the original color, and 1 results in black.
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
  
  /// Returns a color that is either lighter or darker than the current color
  /// depending on its perceived brightness.
  /// 
  /// This is useful for generating adaptive highlights or shadows.
  Color contrast([double amount = .1]) {
    return computeLuminance() > 0.5 ? darken(amount) : lighten(amount);
  }
}
