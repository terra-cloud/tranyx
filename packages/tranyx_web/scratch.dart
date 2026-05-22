import 'dart:js_interop';

void main() {
  final arr = JSArray();
  arr.add(1.toJS);
  print(arr);
}
