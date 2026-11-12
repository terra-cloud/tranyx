import 'package:flutter/material.dart';

/// Solana brand mark (three gradient bars), shown wherever the Solana wallet
/// option or payment method appears. Asset: `assets/icons/solana_logo.png`
/// (transparent background, so it works on light and dark surfaces).
class SolanaLogo extends StatelessWidget {
  const SolanaLogo({super.key, this.size = 20});

  final double size;

  static const String assetPath = 'assets/icons/solana_logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Solana',
    );
  }
}
