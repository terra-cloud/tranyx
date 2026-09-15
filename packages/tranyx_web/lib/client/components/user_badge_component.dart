import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import 'package:web/web.dart' as web;
import '../../components/ui_helpers.dart';

/// Reusable Jaspr Component for rendering user verification badge.
/// Renders nothing (empty text) if unverified ([VerificationLevel.none]),
/// a distinct Level 1 badge for [VerificationLevel.level1Basic],
/// and a gold tier badge for [VerificationLevel.level2Pro].
class UserBadgeComponent extends StatelessComponent {
  final VerificationLevel level;
  final bool showLabel;
  final String? customClass;

  const UserBadgeComponent({
    required this.level,
    this.showLabel = false,
    this.customClass,
    super.key,
  });

  factory UserBadgeComponent.fromDynamic({
    dynamic verificationLevel,
    bool? isVerified,
    bool? idVerified,
    String? status,
    bool showLabel = false,
    String? customClass,
  }) {
    VerificationLevel parsed = VerificationLevel.none;
    if (verificationLevel != null) {
      parsed = VerificationLevel.fromValue(verificationLevel);
    } else if (idVerified == true || isVerified == true || (status != null && status.toUpperCase() == 'VERIFIED')) {
      parsed = VerificationLevel.level1Basic;
    }
    return UserBadgeComponent(
      level: parsed,
      showLabel: showLabel,
      customClass: customClass,
    );
  }

  @override
  Component build(BuildContext context) {
    if (level == VerificationLevel.none) {
      return Component.text('');
    }

    final isLevel2 = level == VerificationLevel.level2Pro;
    final badgeColorCls = isLevel2
        ? 'bg-amber-500/15 text-amber-400 border-amber-500/30'
        : 'bg-cyan-500/15 text-cyan-400 border-cyan-500/30';
    final iconName = isLevel2 ? 'shield-check' : 'check-circle';
    final labelText = isLevel2 ? 'PRO' : 'VERIFIED';

    return span(
      classes:
          'inline-flex items-center gap-1 px-1.5 py-0.5 rounded-full text-[11px] font-bold border cursor-pointer hover:opacity-80 transition-opacity $badgeColorCls ${customClass ?? ""}',
      events: {
        'click': (e) {
          try {
            e.stopPropagation();
          } catch (_) {}
          _showWebVerificationModal(level);
        },
      },
      [
        lIcon(iconName, cls: 'w-3.5 h-3.5 flex-shrink-0'),
        if (showLabel) Component.text(labelText),
      ],
    );
  }

  static void _showWebVerificationModal(VerificationLevel level) {
    // Show details using simple alert or browser modal
    final isLevel2 = level == VerificationLevel.level2Pro;
    final title = isLevel2 ? 'PRO VERIFIED (Tier 2)' : 'GOVERNMENT ID VERIFIED (Tier 1)';
    final details = isLevel2
        ? 'This user has verified their government-issued identity, passed facial biometric liveness checks, and holds a verified merchant/business record.'
        : 'This user has submitted and verified a government-issued photo ID with the Tranyx compliance engine.';

    web.window.alert('$title\n\n$details');
  }
}
