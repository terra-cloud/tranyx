import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/flutter_nav_providers.dart';

/// Modal bottom sheet allowing a driver/broadcaster to manage live telemetry sharing.
class TelemetryShareSheet extends ConsumerWidget {
  final String? defaultChannelId;

  const TelemetryShareSheet({
    super.key,
    this.defaultChannelId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBroadcasting = ref.watch(isBroadcastingActiveProvider);
    final activeChannel = ref.watch(activeBroadcastChannelProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final displayChannel = activeChannel ?? defaultChannelId ?? 'TRIP-${DateTime.now().millisecondsSinceEpoch % 100000}';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isBroadcasting ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                color: isBroadcasting ? Colors.green : colorScheme.outline,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Live Telemetry Broadcasting',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Share your real-time turn-by-turn navigation, location, and ETA with friends or fleet monitors.',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHANNEL ID',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayChannel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: displayChannel));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Channel ID copied to clipboard')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Copy Channel ID',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: isBroadcasting
                ? OutlinedButton.icon(
                    onPressed: () {
                      ref
                          .read(telemetryBroadcastingControllerProvider.notifier)
                          .stopBroadcasting();
                    },
                    icon: const Icon(Icons.stop_rounded, color: Colors.red),
                    label: const Text('Stop Broadcasting', style: TextStyle(color: Colors.red)),
                  )
                : FilledButton.icon(
                    onPressed: () {
                      ref
                          .read(telemetryBroadcastingControllerProvider.notifier)
                          .startBroadcasting(
                            channelId: displayChannel,
                            broadcasterId: 'DEVICE-MOBILE',
                          );
                    },
                    icon: const Icon(Icons.podcasts_rounded),
                    label: const Text('Start Live Broadcasting'),
                  ),
          ),
        ],
      ),
    );
  }
}
