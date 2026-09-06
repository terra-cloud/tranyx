import 'dart:async';
import '../models/nav_event.dart';
import '../models/nav_position.dart';
import '../models/navigation_state.dart';
import '../models/nav_waypoint.dart';
import '../models/osrm_payload.dart';
import '../math/geo_computation_dispatcher.dart';
import 'navigation_engine_options.dart';

/// Headless pure Dart turn-by-turn navigation engine.
///
/// Consumes raw GPS ticks ([NavPosition]), calculates real-time spatial geometry
/// off the UI thread via [GeoComputationDispatcher], tracks multi-stop step transitions,
/// triggers voice prompts, detects off-route conditions, and emits an immutable
/// stream of [NavigationState] and [NavEvent].
class NavigationEngine {
  OsrmPayload _route;
  final List<NavWaypoint>? waypoints;
  final NavigationEngineOptions options;
  final GeoComputationDispatcher _dispatcher;

  final StreamController<NavigationState> _stateController =
      StreamController<NavigationState>.broadcast(sync: true);
  final StreamController<NavEvent> _eventController =
      StreamController<NavEvent>.broadcast(sync: true);

  StreamSubscription<NavPosition>? _positionSubscription;

  NavigationState? _currentState;
  int _currentLegIndex = 0;
  int _currentStepIndex = 0;
  int _consecutiveOffRouteTicks = 0;
  bool _hasArrived = false;

  final Map<int, Set<double>> _firedVoiceMilestones = {};

  /// Optional callback triggered when arriving at a stop or destination,
  /// passing the 1-based stop count index (e.g. 1 for first stop, 2 for second stop).
  final void Function(int stopCount)? onArrived;

  NavigationEngine({
    required OsrmPayload route,
    this.waypoints,
    this.options = const NavigationEngineOptions(),
    this.onArrived,
  })  : _route = route,
        _dispatcher = GeoComputationDispatcher(
          enableBackgroundIsolates: options.enableBackgroundIsolates,
        );

  OsrmPayload get route => _route;
  Stream<NavigationState> get stateStream => _stateController.stream;
  Stream<NavEvent> get eventStream => _eventController.stream;
  NavigationState? get currentState => _currentState;
  int get currentLegIndex => _currentLegIndex;
  int get currentStepIndex => _currentStepIndex;
  bool get hasArrived => _hasArrived;

  void start(Stream<NavPosition> positionStream) {
    _positionSubscription?.cancel();
    _positionSubscription = positionStream.listen(
      processTick,
      onError: (e, st) {},
    );
  }

  Future<void> processTick(NavPosition rawPosition) async {
    final primary = _route.primaryRoute;
    if (primary == null || primary.geometryCoordinates.isEmpty) return;

    final legs = primary.legs;
    if (legs.isEmpty) return;

    final currentLeg = legs[_currentLegIndex.clamp(0, legs.length - 1)];
    final steps = currentLeg.steps;

    // Identify target coordinates of the current stop (end of active leg)
    List<double>? stopTargetCoords;
    if (waypoints != null && _currentLegIndex + 1 < waypoints!.length) {
      final wp = waypoints![_currentLegIndex + 1].position;
      stopTargetCoords = [wp.longitude, wp.latitude];
    } else if (currentLeg.steps.isNotEmpty &&
        currentLeg.steps.last.geometryCoordinates.isNotEmpty) {
      stopTargetCoords = currentLeg.steps.last.geometryCoordinates.last;
    } else if (primary.geometryCoordinates.isNotEmpty) {
      stopTargetCoords = primary.geometryCoordinates.last;
    }

    // Compute geometry off the UI isolate
    final result = await _dispatcher.computeTick(
      rawPosition: rawPosition,
      routeCoordinates: primary.geometryCoordinates,
      steps: steps,
      currentStepIndex: _currentStepIndex,
      routeTotalDistance: primary.distance,
      routeTotalDuration: primary.duration,
      offRouteThresholdMeters: options.offRouteThresholdMeters,
      arrivalThresholdMeters: options.arrivalThresholdMeters,
      currentStopCoords: stopTargetCoords,
      stopTotalDistance: currentLeg.distance,
      stopTotalDuration: currentLeg.duration,
    );

    final totalStops = waypoints != null && waypoints!.length > 1
        ? waypoints!.length - 1
        : (legs.isNotEmpty ? legs.length : 1);

    final currentTitle = waypoints != null &&
            _currentLegIndex + 1 < waypoints!.length
        ? waypoints![_currentLegIndex + 1].title
        : 'Stop ${_currentLegIndex + 1}';

    // 1. Arrival & Stop Transition Check (must not be off route)
    if (!result.isOffRoute &&
        result.distanceToCurrentStop <= options.arrivalThresholdMeters &&
        !_hasArrived) {
      if (_currentLegIndex < legs.length - 1) {
        // Intermediate stop arrival
        final reachedIndex = _currentLegIndex;
        _currentLegIndex++;
        _currentStepIndex = 0;
        _firedVoiceMilestones.clear();

        _eventController.add(ArrivedAtStopEvent(
          stopIndex: reachedIndex,
          totalStops: totalStops,
          stopTitle: currentTitle,
          position: result.snappedPosition,
          isFinalStop: false,
        ));

        _eventController.add(VoiceInstructionEvent(
          instruction: 'Arrived at $currentTitle. Continuing to next stop.',
          distanceToManeuver: 0.0,
          maneuverType: 'arrive',
        ));

        try {
          onArrived?.call(reachedIndex + 1);
        } catch (_) {}
      } else {
        // Final destination arrival
        _hasArrived = true;
        final finalStopIndex = _currentLegIndex;
        _eventController.add(ArrivedAtStopEvent(
          stopIndex: finalStopIndex,
          totalStops: totalStops,
          stopTitle: currentTitle,
          position: result.snappedPosition,
          isFinalStop: true,
        ));
        _eventController.add(ArrivedEvent(finalPosition: result.snappedPosition));
        _eventController.add(VoiceInstructionEvent(
          instruction: 'You have arrived at your final destination.',
          distanceToManeuver: 0.0,
          maneuverType: 'arrive',
        ));

        try {
          onArrived?.call(finalStopIndex + 1);
        } catch (_) {}
      }
    }

    // 2. Off-Route Check
    if (result.isOffRoute) {
      _consecutiveOffRouteTicks++;
      if (_consecutiveOffRouteTicks >= options.offRouteConsecutiveTicks) {
        _eventController.add(OffRouteEvent(
          currentPosition: rawPosition,
          deviationDistance: result.distanceFromRoute,
        ));
        _eventController.add(RerouteRequestedEvent(currentPosition: rawPosition));
      }
    } else {
      _consecutiveOffRouteTicks = 0;
    }

    // 3. Step Transition Check
    if (result.evaluatedStepIndex != _currentStepIndex) {
      _currentStepIndex = result.evaluatedStepIndex;
      if (_currentStepIndex < steps.length) {
        _eventController.add(StepProgressEvent(
          stepIndex: _currentStepIndex,
          step: steps[_currentStepIndex],
        ));
      }
    }

    // 4. Voice Prompt Triggers
    if (!_hasArrived && steps.isNotEmpty && _currentStepIndex < steps.length) {
      final currentStep = steps[_currentStepIndex];
      final stepMilestones = _firedVoiceMilestones.putIfAbsent(
        _currentStepIndex,
        () {
          // Pre-mark milestones significantly larger than current distance to next turn
          // to prevent rapid back-to-back firing on short steps or step transitions.
          final prePassed = <double>{};
          for (final m in options.voiceTriggerDistancesMeters) {
            if (m > result.distanceToNextTurn + 20.0) {
              prePassed.add(m);
            }
          }
          return prePassed;
        },
      );

      for (final milestone in options.voiceTriggerDistancesMeters) {
        if (result.distanceToNextTurn <= milestone &&
            !stepMilestones.contains(milestone)) {
          stepMilestones.add(milestone);
          final baseInstruction = currentStep.maneuver.effectiveInstruction;
          final roadName = currentStep.name.isNotEmpty ? ' onto ${currentStep.name}' : '';

          String voiceText;
          if (milestone >= 100.0) {
            // If we started this step already closer than milestone, announce actual distance
            final announcedDist = result.distanceToNextTurn < milestone * 0.85
                ? ((result.distanceToNextTurn / 10).round() * 10)
                : milestone.round();
            voiceText = 'In $announcedDist meters, $baseInstruction$roadName';
          } else {
            voiceText = '$baseInstruction$roadName';
          }

          _eventController.add(VoiceInstructionEvent(
            instruction: voiceText,
            distanceToManeuver: result.distanceToNextTurn,
            maneuverType: currentStep.maneuver.type,
          ));
          break;
        }
      }
    }

    // 5. Instruction text formatting
    String currentInstruction = 'Continue on route';
    String? nextInstruction;
    if (steps.isNotEmpty && _currentStepIndex < steps.length) {
      final step = steps[_currentStepIndex];
      currentInstruction = step.maneuver.effectiveInstruction;
      if (step.name.isNotEmpty) {
        currentInstruction = '$currentInstruction onto ${step.name}';
      }
      if (_currentStepIndex + 1 < steps.length) {
        final nextStep = steps[_currentStepIndex + 1];
        nextInstruction = nextStep.maneuver.effectiveInstruction;
      }
    }

    if (_hasArrived) {
      currentInstruction = 'You have arrived at your destination';
      nextInstruction = null;
    }

    // 6. Assemble and emit immutable NavigationState
    final state = NavigationState(
      snappedLocation: result.snappedPosition,
      rawLocation: rawPosition,
      currentBearing: result.bearing,
      distanceToNextTurn: result.distanceToNextTurn,
      currentInstruction: currentInstruction,
      nextInstruction: nextInstruction,
      currentStepIndex: _currentStepIndex,
      totalSteps: steps.length,
      currentStopIndex: _currentLegIndex,
      totalStopsCount: totalStops,
      currentStopTitle: currentTitle,
      distanceToCurrentStop: result.distanceToCurrentStop,
      durationToCurrentStop: result.durationToCurrentStop,
      currentStopEta: result.currentStopEta,
      currentSpeedKmh: result.currentSpeedKmh,
      remainingDistance: result.remainingDistance,
      remainingDuration: result.remainingDuration,
      distanceFromRoute: result.distanceFromRoute,
      isOffRoute: result.isOffRoute,
      slicedRouteCoordinates: result.slicedRouteCoordinates,
    );

    _currentState = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  void updateRoute(OsrmPayload newRoute) {
    _route = newRoute;
    _currentLegIndex = 0;
    _currentStepIndex = 0;
    _consecutiveOffRouteTicks = 0;
    _hasArrived = false;
    _firedVoiceMilestones.clear();
    _eventController.add(RerouteCompletedEvent(newRoute: newRoute));
  }

  Future<void> dispose() async {
    await _positionSubscription?.cancel();
    await _stateController.close();
    await _eventController.close();
  }
}
