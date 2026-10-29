/// W70 "Get the app": only official store listings are accepted from build-time env.
const kAppStoreHost = 'apps.apple.com';
const kPlayStoreHost = 'play.google.com';
const kAllowedStoreHosts = {kAppStoreHost, kPlayStoreHost};

/// Returns the normalized URL when [raw] is https on an allowlisted store host with no userInfo and no
/// explicit port; otherwise null. Pass [hosts] to pin a variable to one store.
String? safeStoreUrl(String raw, {Set<String> hosts = kAllowedStoreHosts}) {
  final u = Uri.tryParse(raw.trim());
  if (u == null) return null;
  if (u.scheme != 'https') return null;
  if (!hosts.contains(u.host)) return null; // exact match, Uri lowercases the host
  if (u.userInfo.isNotEmpty) return null;
  if (u.hasPort) return null;
  // Uri drops a default port (":443"), so also check the raw authority for any explicit port or userInfo.
  final rest = raw.trim().substring(raw.trim().indexOf('//') + 2);
  final authority = rest.split(RegExp(r'[/?#]')).first;
  if (authority.contains(':') || authority.contains('@')) return null;
  return u.toString();
}
