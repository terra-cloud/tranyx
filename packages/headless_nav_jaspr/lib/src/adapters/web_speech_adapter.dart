import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:headless_nav_core/headless_nav_core.dart';

/// Binds [NavigationEngine]'s voice events to the browser's Web Speech API (`window.speechSynthesis`).
class WebSpeechAdapter {
  final String language;
  final double rate;
  final double volume;

  StreamSubscription<NavEvent>? _subscription;

  String? _lastSpokenText;
  DateTime? _lastSpokenTime;
  final Set<web.SpeechSynthesisUtterance> _activeUtterances = {};

  WebSpeechAdapter({
    this.language = 'en-US',
    this.rate = 1.05,
    this.volume = 1.0,
  }) {
    _primeVoices();
  }

  void _primeVoices() {
    try {
      final synth = web.window.speechSynthesis;
      synth.getVoices();
      synth.onvoiceschanged = ((web.Event _) {
        try {
          synth.getVoices();
        } catch (_) {}
      }).toJS;
    } catch (_) {}
  }

  /// Attaches this adapter to a navigation event stream and speaks turn prompts.
  void attach(Stream<NavEvent> eventStream) {
    _subscription?.cancel();
    _subscription = eventStream.listen((event) {
      if (event is VoiceInstructionEvent) {
        speak(event.instruction);
      }
    });
  }

  /// Synthesizes spoken voice in the browser with anti-stutter deduplication and async queue protection.
  void speak(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    // Anti-stutter deduplication: if exact same instruction is called within 3.5s, skip
    if (_lastSpokenText == trimmed && _lastSpokenTime != null) {
      if (now.difference(_lastSpokenTime!) < const Duration(milliseconds: 3500)) {
        return;
      }
    }

    _lastSpokenText = trimmed;
    _lastSpokenTime = now;

    try {
      final synth = web.window.speechSynthesis;

      // Chrome/Safari speech synthesis engine bug workaround:
      // Calling cancel() immediately followed by speak() on the exact same tick locks up
      // or causes seconds-long audio delay in Chromium audio subsystem.
      // If speaking or pending, cancel and dispatch on a micro-delay to let the engine cleanly reset.
      if (synth.speaking || synth.pending) {
        synth.cancel();
        Future.delayed(const Duration(milliseconds: 40), () {
          _dispatchSpeak(synth, trimmed);
        });
      } else {
        if (synth.paused) {
          synth.resume();
        }
        _dispatchSpeak(synth, trimmed);
      }
    } catch (e) {
      web.console.warn('Speech synthesis error: $e'.toJS);
    }
  }

  void _dispatchSpeak(web.SpeechSynthesis synth, String text) {
    try {
      if (synth.paused) {
        synth.resume();
      }

      final utterance = web.SpeechSynthesisUtterance(text);
      utterance.lang = language;
      utterance.rate = rate;
      utterance.volume = volume;

      // Retain utterance reference in Dart set to prevent browser GC mid-speech
      _activeUtterances.add(utterance);

      utterance.onend = ((web.Event _) {
        _activeUtterances.remove(utterance);
      }).toJS;

      utterance.onerror = ((web.Event _) {
        _activeUtterances.remove(utterance);
      }).toJS;

      synth.speak(utterance);
      web.console.log('TTS Voice: $text'.toJS);
    } catch (e) {
      web.console.warn('TTS dispatch error: $e'.toJS);
    }
  }

  void cancel() {
    _lastSpokenText = null;
    _lastSpokenTime = null;
    _activeUtterances.clear();
    try {
      web.window.speechSynthesis.cancel();
    } catch (_) {}
  }

  void stop() => cancel();

  void dispose() {
    _subscription?.cancel();
    cancel();
  }
}
