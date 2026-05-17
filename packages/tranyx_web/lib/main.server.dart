/// The entrypoint for the **server** environment.
///
/// The [main] method will only be executed on the server during pre-rendering.
/// To run code on the client, check the `main.client.dart` file.
library;

import 'package:jaspr/dom.dart';
// Server-specific Jaspr import.
import 'package:jaspr/server.dart';

// Imports the [TranyxApp] component.
import 'client/tranyx_app.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.server.options.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultServerOptions,
  );

  // Starts the app.
  //
  // [Document] renders the root document structure (<html>, <head> and <body>)
  // with the provided parameters and components.
  runApp(
    Document(
      title: 'Welcome to Tranyx',
      head: [
        script(src: 'https://cdn.tailwindcss.com'),
        script(src: 'https://unpkg.com/lucide@latest'),
        script(src: 'https://www.gstatic.com/firebasejs/10.12.1/firebase-app-compat.js'),
        script(src: 'https://www.gstatic.com/firebasejs/10.12.1/firebase-auth-compat.js'),
        link(rel: 'stylesheet', href: 'styles.css'),
        script(
          content: '''
              document.addEventListener('DOMContentLoaded', () => {
                lucide.createIcons();
                const observer = new MutationObserver(() => {
                  observer.disconnect();
                  lucide.createIcons();
                  observer.observe(document.body, { childList: true, subtree: true });
                });
                observer.observe(document.body, { childList: true, subtree: true });
              });

              window.signInWithGoogle = async function(config) {
                if (!firebase.apps.length) {
                  firebase.initializeApp(config);
                }
                const provider = new firebase.auth.GoogleAuthProvider();
                try {
                  const result = await firebase.auth().signInWithPopup(provider);
                  const idToken = await result.user.getIdToken();
                  return JSON.stringify({
                    uid: result.user.uid,
                    idToken: idToken,
                    refreshToken: result.user.refreshToken,
                    email: result.user.email,
                    displayName: result.user.displayName,
                    photoUrl: result.user.photoURL
                  });
                } catch (error) {
                  console.error(error);
                  throw error;
                }
              };
            ''',
        ),
      ],
      styles: [
        css.import('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&display=swap'),
        css('html, body').styles(
          width: 100.percent,
          minHeight: 100.vh,
          padding: .zero,
          margin: .zero,
          fontFamily: const .list([FontFamily('Inter'), FontFamilies.sansSerif]),
          backgroundColor: const Color('#09090b'), // zinc-950
          color: const Color('#fafafa'), // zinc-50
        ),
      ],
      body: const TranyxApp(),
    ),
  );
}
