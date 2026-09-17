import 'package:meta/meta.dart';
import 'nav_position.dart';
import 'osrm_payload.dart';

/// Sealed class hierarchy representing system events emitted during navigation.
@immutable
sealed class NavEvent {
  const NavEvent();
}

/// Emitted when the vehicle drifts further than the configured off-route threshold.
final class OffRouteEvent extends NavEvent {
  final NavPosition currentPosition;
  final double deviationDistance;

  const OffRouteEvent({
    required this.currentPosition,
    required this.deviationDistance,
  });

  @override
  String toString() =>
      'OffRouteEvent(pos: $currentPosition, deviation: ${deviationDistance.toStringAsFixed(1)}m)';
}

/// Emitted when the vehicle reaches the final destination (within arrival radius).
final class ArrivedEvent extends NavEvent {
  final NavPosition finalPosition;

  const ArrivedEvent({required this.finalPosition});

  @override
  String toString() => 'ArrivedEvent(pos: $finalPosition)';
}

/// Emitted when the vehicle arrives at an intermediate stop along a multi-stop route.
final class ArrivedAtStopEvent extends NavEvent {
  final int stopIndex;
  final int totalStops;
  final String stopTitle;
  final NavPosition position;
  final bool isFinalStop;

  const ArrivedAtStopEvent({
    required this.stopIndex,
    required this.totalStops,
    required this.stopTitle,
    required this.position,
    required this.isFinalStop,
  });

  @override
  String toString() =>
      'ArrivedAtStopEvent(stop: ${stopIndex + 1}/$totalStops "$stopTitle")';
}

/// Emitted when approaching a turn/maneuver milestone distance to trigger TTS.
final class VoiceInstructionEvent extends NavEvent {
  final String instruction;
  final double distanceToManeuver;
  final String maneuverType;

  const VoiceInstructionEvent({
    required this.instruction,
    required this.distanceToManeuver,
    required this.maneuverType,
  });

  @override
  String toString() =>
      'VoiceInstructionEvent(instruction: "$instruction", dist: ${distanceToManeuver.toStringAsFixed(0)}m)';
}

/// Emitted when advancing to the next turn-by-turn navigation step.
final class StepProgressEvent extends NavEvent {
  final int stepIndex;
  final OsrmStep step;

  const StepProgressEvent({
    required this.stepIndex,
    required this.step,
  });

  @override
  String toString() =>
      'StepProgressEvent(stepIndex: $stepIndex, name: "${step.name}")';
}

/// Emitted when an off-route condition requests a new route calculation.
final class RerouteRequestedEvent extends NavEvent {
  final NavPosition currentPosition;

  const RerouteRequestedEvent({required this.currentPosition});

  @override
  String toString() => 'RerouteRequestedEvent(pos: $currentPosition)';
}

/// Emitted when a recalculated route has been successfully loaded into the engine.
final class RerouteCompletedEvent extends NavEvent {
  final OsrmPayload newRoute;

  const RerouteCompletedEvent({required this.newRoute});

  @override
  String toString() => 'RerouteCompletedEvent()';
}
