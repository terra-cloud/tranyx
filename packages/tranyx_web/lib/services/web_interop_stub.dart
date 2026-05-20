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

void initFirebaseJs(Map<String, dynamic> config) {}

void listenToNotificationsJs(String uid, void Function(String) callback) {}

void markNotificationReadJs(String notifId) {}

void openUrl(String url) {}

bool confirmDialog(String message) => false;

void listenToJobsJs(String uid, void Function(String) callback) {}
void stopListeningToJobsJs() {}

void listenToChatJs(String chatId, void Function(String) callback) {}
void unlistenChatJs(String chatId) {}
String sendChatMessageJs(String chatId, String senderId, String senderName, String text, {String? photoUrl}) => 'ok';
Future<String?> uploadChatPhotoJs(String chatId, String base64Data, String mimeType) async => null;

// Job Details stubs
void listenToJobDetailsJs(String jobId, void Function(String) callback) {}
void stopListeningToJobDetailsJs() {}

