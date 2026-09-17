import 'package:flutter/material.dart';

/// Floating turn-by-turn guidance banner displaying the maneuver icon, distance,
/// and primary instruction text.
class TurnInstructionBanner extends StatelessWidget {
  final String instruction;
  final String? nextInstruction;
  final double distanceMeters;
  final VoidCallback? onRecenter;

  const TurnInstructionBanner({
    super.key,
    required this.instruction,
    this.nextInstruction,
    required this.distanceMeters,
    this.onRecenter,
  });

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  IconData _getManeuverIcon(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('left')) {
      return Icons.turn_left_rounded;
    } else if (lower.contains('right')) {
      return Icons.turn_right_rounded;
    } else if (lower.contains('u-turn') || lower.contains('uturn')) {
      return Icons.u_turn_left_rounded;
    } else if (lower.contains('roundabout')) {
      return Icons.roundabout_left_rounded;
    } else if (lower.contains('arrive') || lower.contains('destination')) {
      return Icons.flag_rounded;
    }
    return Icons.straight_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 6,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getManeuverIcon(instruction),
                    size: 32,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatDistance(distanceMeters),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        instruction,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onRecenter != null)
                  IconButton.filledTonal(
                    onPressed: onRecenter,
                    icon: const Icon(Icons.navigation_rounded),
                    tooltip: 'Recenter Camera',
                  ),
              ],
            ),
            if (nextInstruction != null && nextInstruction!.isNotEmpty) ...[
              const Divider(height: 16),
              Row(
                children: [
                  Text(
                    'Then: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.outline,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      nextInstruction!,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
