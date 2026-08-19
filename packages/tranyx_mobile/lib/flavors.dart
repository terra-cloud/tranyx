enum Flavor { dev, uat, production }

class F {
  static late final Flavor appFlavor;

  static String get name => appFlavor.name;

  static String get title {
    switch (appFlavor) {
      case Flavor.dev:
        return 'Tranyx Dev';
      case Flavor.uat:
        return 'Tranyx UAT';
      case Flavor.production:
        return 'Tranyx';
    }
  }

  static String get googleClientId {
    switch (appFlavor) {
      case Flavor.dev:
        return '709467070093-6rvs5nug0iurv3r46ervcrptoejph87t.apps.googleusercontent.com';
      case Flavor.uat:
        return '108125328804-56ge8g06o798l4h56gaq14s4ijs1a397.apps.googleusercontent.com';
      case Flavor.production:
        return '174332525079-ch59nh7tj9r95janu4pktknub35lafaf.apps.googleusercontent.com';
    }
  }

  /// Web client ID (server client ID) — used for server-side token verification.
  /// Leave empty if you don't have a server-side OAuth client.
  static String? get googleServerClientId {
    switch (appFlavor) {
      case Flavor.dev:
        return null;
      case Flavor.uat:
        return null;
      case Flavor.production:
        return null;
    }
  }

  /// Whether fiat top-ups/withdrawals (e.g. Xendit GCash Sandbox) are enabled.
  /// Gated to false in production until full fiat regulatory compliance is active.
  static bool get isFiatEnabled => appFlavor != Flavor.production;
}
