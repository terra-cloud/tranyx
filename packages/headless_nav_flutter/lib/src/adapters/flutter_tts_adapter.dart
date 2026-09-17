import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:headless_nav_core/headless_nav_core.dart';

/// Binds [NavigationEngine]'s [VoiceInstructionEvent] stream to device speech synthesis.
class FlutterTtsAdapter {
  final FlutterTts _flutterTts;
  StreamSubscription<NavEvent>? _subscription;

  FlutterTtsAdapter({FlutterTts? tts}) : _flutterTts = tts ?? FlutterTts() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  /// Begins listening to the navigation engine's event stream and speaks turn prompts.
  void attach(Stream<NavEvent> eventStream) {
    _subscription?.cancel();
    _subscription = eventStream.listen((event) {
      if (event is VoiceInstructionEvent) {
        speak(event.instruction);
      }
    });
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    }
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _flutterTts.stop();
  }
}
