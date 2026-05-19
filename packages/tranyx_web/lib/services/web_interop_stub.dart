class SessionStorage {
  static void save(dynamic auth) {}
  static void saveProfile({String? name, String? email, String? accountType}) {}
  static String? get uid => null;
  static String? get idToken => null;
  static String? get refreshToken => null;
  static String? get displayName => null;
  static String? get email => null;
  static String? get accountType => null;
  static bool get hasSession => false;
  static void clear() {}
  static void updateIdToken(String token) {}
}

String getHostname() => 'localhost';

class WebFile {
  final String name;
  final List<int> bytes;
  WebFile(this.name, this.bytes);
}

Future<List<WebFile>> readFilesFromEvent(dynamic event) async => [];

Future<String?> connectPhantomWallet() async => null;

bool isPhantomInstalled() => false;

Future<String?> getPhantomPublicKeyIfConnected() async => null;

Future<double?> getSolanaBalance(String publicKey) async => null;

Future<String?> signInWithGoogleJs(Map<String, String> config) async => null;

void openUrl(String url) {}

bool confirmDialog(String message) => false;
