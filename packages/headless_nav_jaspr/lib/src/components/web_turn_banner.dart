import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Turn-by-turn guidance banner component for Jaspr Web.
class WebTurnBanner extends StatelessComponent {
  final String instruction;
  final String? nextInstruction;
  final double distanceMeters;
  final VoidCallback? onRecenter;
  final bool isDark;
  final String accentColor;
  final bool isEmbedded;

  const WebTurnBanner({
    super.key,
    required this.instruction,
    this.nextInstruction,
    required this.distanceMeters,
    this.onRecenter,
    this.isDark = false,
    this.accentColor = '#1976D2',
    this.isEmbedded = false,
  });

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'nav-banner-card',
      styles: Styles(
        position: isEmbedded
            ? Position.absolute(top: 14.px, left: 50.percent)
            : Position.fixed(top: 14.px, left: 50.percent),
        zIndex: ZIndex(100),
        transform: Transform.translate(x: (-50).percent),
        maxWidth: 460.px,
        padding: Padding.all(16.px),
        radius: BorderRadius.circular(16.px),
        border: Border.all(
          color: isDark
              ? Color('rgba(255, 255, 255, 0.12)')
              : Color('rgba(0, 0, 0, 0.08)'),
          width: 1.px,
          style: BorderStyle.solid,
        ),
        shadow: BoxShadow(
          offsetX: 0.px,
          offsetY: 4.px,
          blur: 16.px,
          color: isDark ? Color('rgba(0, 0, 0, 0.55)') : Color('rgba(0, 0, 0, 0.15)'),
        ),
        raw: {
          'width': 'calc(100% - 40px)',
          'max-width': '460px',
          'box-sizing': 'border-box',
          'backdrop-filter': 'blur(16px)',
          '-webkit-backdrop-filter': 'blur(16px)',
          'background': isDark
              ? 'rgba(15, 23, 42, 0.92)'
              : 'rgba(255, 255, 255, 0.96)',
        },
      ),
      [
        div(
          styles: const Styles(
            display: Display.flex,
            flexDirection: FlexDirection.column,
          ),
          [
            span(
              styles: Styles(
                fontSize: 24.px,
                fontWeight: FontWeight.bold,
                color: Color(accentColor),
              ),
              [Component.text(_formatDistance(distanceMeters))],
            ),
            span(
              styles: Styles(
                fontSize: 16.px,
                fontWeight: FontWeight.w600,
                color: isDark ? Color('#F8FAFC') : Color('#1E293B'),
              ),
              [Component.text(instruction)],
            ),
          ],
        ),
        if (nextInstruction != null && nextInstruction!.isNotEmpty)
          div(
            styles: Styles(
              margin: Margin.only(top: 10.px),
              padding: Padding.only(top: 8.px),
              border: Border.only(
                top: BorderSide.solid(
                  color: isDark ? Color('rgba(255, 255, 255, 0.10)') : Color('rgba(0, 0, 0, 0.06)'),
                  width: 1.px,
                ),
              ),
            ),
            [
              span(
                styles: Styles(
                  fontSize: 13.px,
                  color: isDark ? Color('#94A3B8') : Color('#64748B'),
                ),
                [Component.text('Then: $nextInstruction')],
              ),
            ],
          ),
      ],
    );
  }
}
