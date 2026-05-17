import 'package:http/http.dart' as http;

void main() async {
  // Use user's Firebase Project ID (tranyx-8eb6c) and test firestore.
  final url =
      'https://firestore.googleapis.com/v1/projects/tranyx-8eb6c/databases/(default)/documents/config/app_config';
  final res = await http.get(Uri.parse(url));
  print(res.statusCode);
  print(res.body);
}
