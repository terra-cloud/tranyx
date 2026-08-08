void dismissWebSplashScreen() {}
void initRandomMetaballs(String containerId) {}

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

  static String? get pendingQrJobId => null;
  static set pendingQrJobId(String? val) {}
  static String? get pendingQrCode => null;
  static set pendingQrCode(String? val) {}

  static String? get pendingXenditInvoiceId => null;
  static set pendingXenditInvoiceId(String? val) {}
  static double get pendingXenditInvoiceAmount => 0.0;
  static set pendingXenditInvoiceAmount(double val) {}
  static Map<String, dynamic>? get pendingPropertyBookingData => null;
  static set pendingPropertyBookingData(Map<String, dynamic>? val) {}
  static Map<String, dynamic>? get pendingVehicleBookingData => null;
  static set pendingVehicleBookingData(Map<String, dynamic>? val) {}
  static String? get pendingJobId => null;
  static set pendingJobId(String? val) {}
  static Map<String, dynamic>? get pendingApplicantData => null;
  static set pendingApplicantData(Map<String, dynamic>? val) {}
  static String? get offlineLocationBuffer => null;
  static set offlineLocationBuffer(String? val) {}
}

String getHostname() => 'localhost';

class WebFile {
  final String name;
  final List<int> bytes;
  WebFile(this.name, this.bytes);
}

Future<List<WebFile>> readFilesFromEvent(dynamic event) async => [];

Future<String?> connectSolanaWallet(String type) async => null;
Future<String?> getSolanaPublicKeyIfConnected(String type) async => null;
Future<void> disconnectSolanaWallet(String type) async {}
bool isSolanaWalletInstalled(String type) => false;
List<String> getDetectedSolanaWallets() => [];

Future<String?> connectPhantomWallet() async => null;
bool isPhantomInstalled() => false;
Future<String?> getPhantomPublicKeyIfConnected() async => null;

Future<double?> getSolanaBalance(String publicKey) async => null;

Future<List<Map<String, dynamic>>?> getSolanaTokenCollectibles(String publicKey) async => null;

Future<String?> connectEthereumWallet() async => null;
Future<String?> connectSuiWallet() async => null;
Future<String?> getEthereumAddressIfConnected() async => null;
Future<String?> getSuiAddressIfConnected() async => null;
Future<double?> getEthereumBalance(String address) async => null;
Future<double?> getSuiBalance(String address) async => null;

Future<String?> sendSolanaPayment(String fromAddress, String toAddress, double amountInSol) async => null;

Future<String?> sendUsdtPayment(String fromAddress, String toAddress, double amountInUsdt, {String? usdtMint}) async => null;
Future<String?> signSolanaMessage(String fromAddress, String message) async => null;

Future<String?> signInWithGoogleJs(Map<String, String> config) async => null;
Future<String?> linkGoogleAccountJs(Map<String, String> config) async => null;
Future<String?> unlinkGoogleAccountJs(Map<String, String> config) async => null;
Future<String?> checkRedirectResultJs(Map<String, String> config) async => null;

Future<void> signInWithEmailAndPasswordJs(Map<String, String> config, String email, String password) async {}

Future<void> signOutJs() async {}

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

// Rental stubs
void listenToRentalsJs(void Function(String) callback) {}
void stopListeningToRentalsJs() {}
void listenToRentalDetailsJs(String rentalId, void Function(String) callback) {}
void stopListeningToRentalDetailsJs() {}

// Signature pad stubs
void initSignaturePadJs(String canvasId) {}
void clearSignaturePadJs(String canvasId) {}
bool isSignaturePadEmptyJs(String canvasId) => true;
String getSignatureDataUrlJs(String canvasId) => '';

// Rental Q&A stubs
void listenToRentalQAJs(String rentalId, void Function(String) callback) {}
void unlistenRentalQAJs(String rentalId) {}
void postRentalQuestionJs(String rentalId, String uid, String name, String photoUrl, String text) {}
void answerRentalQuestionJs(String rentalId, String questionId, String answerText) {}

// Property Q&A stubs
void listenToPropertyQAJs(String propertyId, void Function(String) callback) {}
void unlistenPropertyQAJs(String propertyId) {}
void postPropertyQuestionJs(String propertyId, String uid, String name, String photoUrl, String text) {}
void answerPropertyQuestionJs(String propertyId, String questionId, String answerText) {}

// Properties List stubs
void listenToPropertiesJs(void Function(String) callback) {}
void stopListeningToPropertiesJs() {}
void listenToPropertyDetailsJs(String propertyId, void Function(String) callback) {}
void stopListeningToPropertyDetailsJs() {}

String getUrlOrigin() => 'http://localhost:8080';
Map<String, String> getUrlQueryParams() => const {};
void clearUrlParams() {}

String getInputValue(dynamic target) => '';
void setInputValue(dynamic target, String value) {}
bool getInputChecked(dynamic target) => false;
void setInputChecked(dynamic target, bool checked) {}
