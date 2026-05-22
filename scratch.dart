import 'dart:js_interop';

void main() {
  final list = [1.23.toJS, 4.56.toJS];
  final jsArr = list.toJS;
  print(jsArr);
}
