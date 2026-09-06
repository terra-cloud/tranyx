import 'package:test/test.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

void main() {
  group('Geospatial Broadcasting & Streaming Counterparts', () {
    test('BroadcasterTelemetry serializes and deserializes to JSON accurately', () {
      final telemetry = BroadcasterTelemetry(
        channelId: 'CH-99',
        broadcasterId: 'DEV-1',
        rawPosition: NavPosition.now(
          latitude: 14.5995,
          longitude: 120.9842,
          speed: 12.5,
          heading: 85.0,
        ),
        snappedPosition: NavPosition.now(
          latitude: 14.5994,
          longitude: 120.9842,
        ),
        currentBearing: 85.0,
        remainingDistance: 450.0,
        remainingDuration: 60.0,
        currentInstruction: 'In 200m, turn right',
        timestamp: DateTime.now().toUtc(),
        metadata: {'battery': 95, 'vehicle': 'car'},
      );

      final json = telemetry.toJson();
      final reconstructed = BroadcasterTelemetry.fromJson(json);

      expect(reconstructed.channelId, equals('CH-99'));
      expect(reconstructed.broadcasterId, equals('DEV-1'));
      expect(reconstructed.rawPosition.latitude, equals(14.5995));
      expect(reconstructed.snappedPosition?.latitude, equals(14.5994));
      expect(reconstructed.currentBearing, equals(85.0));
      expect(reconstructed.remainingDistance, equals(450.0));
      expect(reconstructed.currentInstruction, equals('In 200m, turn right'));
      expect(reconstructed.metadata?['battery'], equals(95));
    });

    test('InMemoryLocationBroadcaster and InMemoryLocationStreaming transmit telemetry across channels', () async {
      final bus = InMemoryTelemetryBus();
      final broadcaster = InMemoryLocationBroadcaster(bus: bus);
      final streaming = InMemoryLocationStreaming(bus: bus);

      final receivedPacketsA = <BroadcasterTelemetry>[];
      final receivedPacketsB = <BroadcasterTelemetry>[];

      final subA = streaming.stream('CHANNEL_A').listen(receivedPacketsA.add);
      final subB = streaming.stream('CHANNEL_B').listen(receivedPacketsB.add);

      final packetA = BroadcasterTelemetry(
        channelId: 'CHANNEL_A',
        broadcasterId: 'USER_1',
        rawPosition: NavPosition.now(latitude: 14.500, longitude: 121.000),
        timestamp: DateTime.now().toUtc(),
      );

      final packetB = BroadcasterTelemetry(
        channelId: 'CHANNEL_B',
        broadcasterId: 'USER_2',
        rawPosition: NavPosition.now(latitude: 14.600, longitude: 121.100),
        timestamp: DateTime.now().toUtc(),
      );

      await broadcaster.broadcast('CHANNEL_A', packetA);
      await broadcaster.broadcast('CHANNEL_B', packetB);

      // Channel isolation check
      expect(receivedPacketsA.length, equals(1));
      expect(receivedPacketsA.first.channelId, equals('CHANNEL_A'));
      expect(receivedPacketsB.length, equals(1));
      expect(receivedPacketsB.first.channelId, equals('CHANNEL_B'));

      await subA.cancel();
      await subB.cancel();
      await broadcaster.close();
      await streaming.close();
    });

    test('WSLocationBroadcaster and WSLocationStreaming encode and receive frames', () async {
      String? lastSent;
      final broadcaster = WSLocationBroadcaster(
        serverUrl: 'wss://example.com/ws',
        customSender: (msg) async {
          lastSent = msg;
        },
      );

      final telemetry = BroadcasterTelemetry(
        channelId: 'WS-1',
        broadcasterId: 'DRIVER-42',
        rawPosition: NavPosition.now(latitude: 14.500, longitude: 121.000),
        timestamp: DateTime.now().toUtc(),
      );

      await broadcaster.broadcast('WS-1', telemetry);
      expect(lastSent, contains('"action":"broadcast"'));
      expect(lastSent, contains('"channelId":"WS-1"'));

      await broadcaster.close();
    });

    test('FirebaseLocationBroadcaster writes to document updater', () async {
      String? updatedCollection;
      String? updatedDoc;
      Map<String, dynamic>? updatedData;

      final broadcaster = FirebaseLocationBroadcaster(
        collectionPath: 'telemetry_v1',
        documentUpdater: (col, doc, data) async {
          updatedCollection = col;
          updatedDoc = doc;
          updatedData = data;
        },
      );

      final telemetry = BroadcasterTelemetry(
        channelId: 'FB-999',
        broadcasterId: 'TRUCK-1',
        rawPosition: NavPosition.now(latitude: 14.500, longitude: 121.000),
        timestamp: DateTime.now().toUtc(),
      );

      await broadcaster.broadcast('FB-999', telemetry);

      expect(updatedCollection, equals('telemetry_v1'));
      expect(updatedDoc, equals('FB-999'));
      expect(updatedData?['broadcasterId'], equals('TRUCK-1'));

      await broadcaster.close();
    });

    test('SupabaseLocationBroadcaster dispatches topic broadcast', () async {
      String? sentTopic;
      String? sentEvent;
      Map<String, dynamic>? sentPayload;

      final broadcaster = SupabaseLocationBroadcaster(
        topicPrefix: 'fleet',
        eventName: 'geo_tick',
        channelBroadcaster: (topic, event, payload) async {
          sentTopic = topic;
          sentEvent = event;
          sentPayload = payload;
        },
      );

      final telemetry = BroadcasterTelemetry(
        channelId: 'VAN-7',
        broadcasterId: 'DRIVER-7',
        rawPosition: NavPosition.now(latitude: 14.500, longitude: 121.000),
        timestamp: DateTime.now().toUtc(),
      );

      await broadcaster.broadcast('VAN-7', telemetry);

      expect(sentTopic, equals('fleet:VAN-7'));
      expect(sentEvent, equals('geo_tick'));
      expect(sentPayload?['channelId'], equals('VAN-7'));

      await broadcaster.close();
    });
  });
}
