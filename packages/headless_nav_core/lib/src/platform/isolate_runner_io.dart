import 'dart:isolate';

/// Native VM implementation executing computation inside an Isolate.
Future<R> runCompute<R>(R Function() computation) async {
  return Isolate.run(computation);
}
