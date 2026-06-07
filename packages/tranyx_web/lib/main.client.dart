/// The entrypoint for the **client** environment.
///
/// The [main] method will only be executed on the client when loading the page.
/// To run code on the server during pre-rendering, check the `main.server.dart` file.
library;

// Client-specific Jaspr import.
import 'package:jaspr/client.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.client.options.dart';

// Imports the [TranyxApp] component.
import 'client/tranyx_app.dart';

Future<void> loadEnv() async {
  try {
    final response = await http.get(Uri.parse('/.env'));
    if (response.statusCode == 200) {
      Env.load(response.body);
    }
  } catch (e) {
    // ignore
  }
}

void main() async {
  // Load environment variables before initializing Jaspr
  await loadEnv();

  // Initializes the client environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultClientOptions,
  );

  // Starts the app on the client directly (SPA mode)
  runApp(
    const TranyxApp(),
  );
}
