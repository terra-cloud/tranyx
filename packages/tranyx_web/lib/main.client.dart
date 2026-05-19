/// The entrypoint for the **client** environment.
///
/// The [main] method will only be executed on the client when loading the page.
/// To run code on the server during pre-rendering, check the `main.server.dart` file.
library;

// Client-specific Jaspr import.
import 'package:jaspr/client.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.client.options.dart';

// Imports the [TranyxApp] component.
import 'client/tranyx_app.dart';

void main() {
  // Initializes the client environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultClientOptions,
  );

  // Starts the app on the client directly (SPA mode)
  runApp(
    const TranyxApp(),
  );
}
