/// Web stub fallback for isolate execution.
Future<R> runCompute<R>(R Function() computation) async {
  return computation();
}
