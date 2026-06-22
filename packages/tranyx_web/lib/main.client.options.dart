// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/client.dart';

import 'package:tranyx_web/client/tranyx_app.dart' deferred as _tranyx_app;
import 'package:tranyx_web/pages/about.dart' deferred as _about;
import 'package:tranyx_web/pages/home.dart' deferred as _home;
import 'package:tranyx_web/pages/post_job.dart' deferred as _post_job;
import 'package:tranyx_web/pages/privacy_policy.dart'
    deferred as _privacy_policy;
import 'package:tranyx_web/pages/terms_of_use.dart' deferred as _terms_of_use;

/// Default [ClientOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.client.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultClientOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ClientOptions get defaultClientOptions => ClientOptions(
  clients: {
    'tranyx_app': ClientLoader(
      (p) => _tranyx_app.TranyxApp(),
      loader: _tranyx_app.loadLibrary,
    ),
    'about': ClientLoader((p) => _about.About(), loader: _about.loadLibrary),
    'home': ClientLoader((p) => _home.Home(), loader: _home.loadLibrary),
    'post_job': ClientLoader(
      (p) => _post_job.PostJobPage(),
      loader: _post_job.loadLibrary,
    ),
    'privacy_policy': ClientLoader(
      (p) => _privacy_policy.PrivacyPolicy(),
      loader: _privacy_policy.loadLibrary,
    ),
    'terms_of_use': ClientLoader(
      (p) => _terms_of_use.TermsOfUse(),
      loader: _terms_of_use.loadLibrary,
    ),
  },
);
