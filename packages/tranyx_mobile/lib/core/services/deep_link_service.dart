import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService();
});

class DeepLinkService {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  Future<void> initialize(GoRouter router) async {
    debugPrint("DeepLinkService: Initializing...");
    
    // 1. Handle cold start link
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint("DeepLinkService: Cold start link received: $initialLink");
        _handleLink(initialLink, router);
      }
    } catch (e) {
      debugPrint("DeepLinkService: Error getting initial link: $e");
    }

    // 2. Handle hot resume links (incoming stream)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        debugPrint("DeepLinkService: Stream link received: $uri");
        _handleLink(uri, router);
      },
      onError: (err) {
        debugPrint("DeepLinkService: Stream link error: $err");
      },
    );
  }

  void _handleLink(Uri uri, GoRouter router) {
    debugPrint("DeepLinkService: Processing URI: $uri");
    if (uri.scheme == 'tranyx') {
      String path = uri.path;
      if (uri.host == 'onConnect' || path == '/onConnect') {
        path = '/onConnect';
      } else if (uri.host.isNotEmpty && !path.startsWith('/')) {
        path = '/${uri.host}$path';
      }
      
      if (path.isEmpty) {
        path = '/';
      }
      
      final queryParams = uri.queryParameters;
      final target = Uri(path: path, queryParameters: queryParams).toString();
      debugPrint("DeepLinkService: Routing to GoRouter path: $target");
      router.go(target);
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }
}
