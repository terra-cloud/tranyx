// ignore: avoid_web_libraries_in_flutter
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:tranyx_web/services/web_interop.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';

import 'package:tranyx_web/services/firebase_service.dart';
import 'package:tranyx_web/components/ui_helpers.dart';
import 'package:tranyx_web/services/map_interop.dart';

import '../state/app_state.dart';
import '../pages/privacy_policy.dart';
import '../pages/terms_of_use.dart';
import '../client/views/auth_view.dart';
import '../client/views/home_view.dart';
import '../client/views/jobs_view.dart';
import '../client/views/transit_view.dart';
import '../client/views/profile_view.dart';
import '../client/widgets/sidebar.dart';
import '../client/widgets/bottom_nav.dart';
import '../client/widgets/chat_widget.dart';
import '../client/widgets/top_header.dart';
import '../client/widgets/category_modal.dart';
import '../client/widgets/payment_modal.dart';
import '../client/widgets/rating_modal.dart';
import '../client/widgets/delete_confirm_modal.dart';
import '../client/components/list_vehicle_modal.dart';
import '../client/components/book_vehicle_modal.dart';
import '../client/components/extend_rental_modal.dart';
import '../client/components/rental_tracker_map.dart';
import '../client/components/manage_vehicle_modal.dart';
import '../client/components/vehicle_qa_modal.dart';
import '../client/components/list_property_modal.dart';
import '../client/components/book_property_modal.dart';
import '../client/components/manage_property_modal.dart';
import '../client/components/property_qa_modal.dart';
import '../client/components/sign_contract_modal.dart';
import '../client/components/kyc_id_modal.dart';
import '../client/components/kyc_bg_modal.dart';
import '../client/widgets/session_expired_modal.dart';

@client
class TranyxApp extends StatefulComponent {
  const TranyxApp({super.key});
  @override
  State<TranyxApp> createState() => TranyxAppState();
}

class TranyxAppState extends State<TranyxApp> {
  // ── Theme / Auth ────────────────────────────────────────────
  bool isDark = true;
  bool showWebSplash = true;
  bool showMobileAppPrompt = false;
  bool isAuthenticated = false;
  bool isAuthLoading = false;
  String? authError;
  String? fullScreenPhotoUrl;

  void showFullScreenPhoto(String url) {
    setState(() => fullScreenPhotoUrl = url);
  }

  AccountType accountType = AccountType.employer;
  AuthView authView = AuthView.login;
  AccountType? pendingAccountType;
  String? pendingWalletPublicKey; // set when coming from Phantom sign-in for new users
  AuthResult? pendingGoogleAuthResult;

  // ── User profile ────────────────────────────────────────────
  String userName = '';
  String userEmail = '';
  String? userPhotoUrl;
  UserProfile? userProfile;
  List<Map<String, dynamic>> pendingHoldbacks = [];
  List<Map<String, dynamic>> rewardsHistory = [];
  bool rewardsLoaded = false;

  // ── Profile edit fields ──────────────────────────────────────
  String editName = '';
  String editEmail = '';
  String editPhone = '';
  String editHeadline = '';
  String editHourlyRate = '';
  List<String> editSkills = [];
  String newSkillInput = '';
  String editBusinessName = '';
  String editIndustry = '';
  String editTaxId = '';
  bool isSavingProfile = false;
  String? profileSaveError;

  // ── Navigation ──────────────────────────────────────────────
  AppTab activeTab = AppTab.home;
  AccountType hybridToggle = AccountType.employer;
  TransitMode transitMode = TransitMode.rent;
  ProfileView profileView = ProfileView.main;
  bool verificationEmailSent = false;
  bool showSmsModal = false;
  String smsVerificationPhoneNumber = '';
  String smsVerificationSessionInfo = '';
  String smsVerificationCode = '';
  String? smsVerificationError;
  bool isSendingSms = false;
  bool isVerifyingSms = false;
  String? simulatedSmsCode;
  JobsView jobsView = JobsView.list;

  // ── Category modal ──────────────────────────────────────────
  bool showCategoryModal = false;
  bool categoryModalForSelect = false;

  // ── Transit modales ──────────────────────────────────────────
  bool showListVehicleModal = false;
  bool showBookVehicleModal = false;
  bool showExtendRentalModal = false;
  bool showRentalTrackerMap = false;
  bool showManageVehicleModal = false;
  bool showVehicleQaModal = false;
  Map<String, dynamic>? selectedRentalData;

  // ── Property state ──────────────────────────────────────────
  RentalCategory activeRentalCategory = RentalCategory.vehicles;
  bool showListPropertyModal = false;
  bool showBookPropertyModal = false;
  bool showManagePropertyModal = false;
  bool showPropertyQaModal = false;
  bool showSignContractModal = false;
  Map<String, dynamic>? selectedPropertyData;
  UserProfile? renterProfilePreview;
  List<PropertyRental> realtimeProperties = [];
  List<Map<String, dynamic>> propertyRenterPendingRequests = [];
  String? signingContractId;
  String? signingContractTitle;
  String? signingContractTerms;
  bool signingContractIsProperty = false;

  // ── Wallet reconnect modal ──────────────────────────────────
  bool showWalletReconnectPrompt = false;
  String? pendingReconnectWalletKey;
  bool showSessionExpiredModal = false;

  // ── Jobs state ──────────────────────────────────────────────
  List<Map<String, dynamic>> myJobs = [];
  List<Map<String, dynamic>> sessionPostedJobs = [];
  List<Map<String, dynamic>> realtimeEmployerJobs = [];
  List<Map<String, dynamic>> realtimeNyxianJobs = [];
  List<Map<String, dynamic>> availableJobs = [];
  List<Map<String, dynamic>> realtimeRentals = [];
  List<Map<String, dynamic>> renterPendingRequests = [];
  List<Map<String, dynamic>> appliedJobs = [];
  List<Map<String, dynamic>> hostPendingRequests = [];
  List<Map<String, dynamic>> propertyHostPendingRequests = [];
  bool isLoadingJobs = false;
  String? jobsError;
  String activeJobFilter = 'Recommended';
  String activeJobPane = 'active'; // 'active'/'history' for employer, 'browse'/'my_gigs' for nyxian
  Map<String, dynamic>? ongoingJob; // first 'In Progress' job
  String homeSearchQuery = '';

  // ── Geofencing state ─────────────────────────────────────────
  double userLatitude = 14.5995; // default Manila
  double userLongitude = 120.9842; // default Manila
  double geofenceRadius = 30.0; // default 30km
  bool includeRemoteJobs = true; // remote jobs option, default true

  Map<String, dynamic>? selectedJobData; // raw Firestore map
  SelectedJob? selectedJob;
  int selectedJobImageCarouselIndex = 0;

  bool isCounterOffer = false;
  int createStep = 1;
  String newJobTitle = '';
  String newJobDesc = '';
  SelectedCategory? selectedCategory;
  JobCategory? selectedJobCategory;
  JobCategoryGroup? selectedJobCategoryGroup;
  bool isGeneratingDesc = false;
  JobDateType jobDateType = JobDateType.flexible;
  String jobDate = '';
  TimePref timePref = TimePref.morning;
  EmpType empType = EmpType.contractual;
  LocType locType = LocType.onsite;
  PaymentType paymentType = PaymentType.packageFixed;
  String priceRate = '';
  String jobAddress = '';
  String jobLandmark = '';
  // Pickup & destination (for on-site tracked jobs)
  bool hasTracker = false;
  double? pickupLat;
  double? pickupLng;
  String pickupAddress = '';
  double? destinationLat;
  double? destinationLng;
  String destinationAddress = '';
  List<String> jobImageUrls = [];
  bool isUploadingImages = false;
  bool isPostingJob = false;
  String? postJobError;
  String? jobPromoCode;
  double jobDiscountAmount = 0.0;
  String profilePromoCodeInput = '';
  String? profilePromoFeedback;
  bool isValidatingProfilePromo = false;


  // ── Nyxian sub-status (for tracked in-progress jobs) ─────────
  bool isUpdatingSubStatus = false;

  // ── Apply state ─────────────────────────────────────────────
  String coverNote = '';
  String applyPriceRate = ''; // isolated from job-create priceRate
  bool isGeneratingCover = false;
  bool isSubmittingApplication = false;
  String? applyError;

  // ── Questions state ─────────────────────────────────────────
  List<Map<String, dynamic>> jobQuestions = [];
  bool isLoadingQuestions = false;
  String newQuestionText = '';
  bool isPostingQuestion = false;
  Map<String, String> answerDrafts = {};
  String? activeAnswerQuestionId;

  // ── Review & Manage state ───────────────────────────────────
  List<Map<String, dynamic>> jobApplicants = [];
  bool isLoadingApplicants = false;
  bool isUpdatingJobStatus = false;

  // ── Report Job state ────────────────────────────────────────
  bool showReportModal = false;
  String selectedReportReason = '';
  bool isSubmittingReport = false;

  // ── Authenticity Check state ──────────────────────────────────
  bool showAuthenticityModal = false;
  bool isCheckingAuthenticity = false;
  String? authenticityResult;

  String? get idToken => SessionStorage.idToken;

  // ── Tyx payment & deposit state ───────────────────────────────
  bool showDepositModal = false;
  double depositAmount = 0.0;
  bool isDepositing = false;
  String selectedPaymentMethod = const String.fromEnvironment('ENV', defaultValue: 'dev') == 'prod'
      ? 'solana'
      : 'xendit';
  String selectedSolanaCurrency = 'SOL'; // 'SOL' or 'USDT'
  double solToPhpRate = 8500.0;
  double usdToPhpRate = 57.0; // fallback USD-PHP rate for USDT
  bool isFetchingRate = false;
  Map<String, dynamic>? pendingPropertyBookingData;
  Map<String, dynamic>? pendingVehicleBookingData;

  // Job Completion State
  bool showCompletionScanner = false;
  bool showEmployerFeePopup = false;
  String completionScanInput = '';
  bool isCompletingJob = false;
  bool isGeneratingCode = false;
  String? generatedCompletionCode;
  String? pendingQrJobId;
  String? pendingQrCode;

  // Rating State
  bool showRatingPopup = false;
  bool showDeleteConfirm = false;
  String? ratingTargetId;
  String? ratingTargetName;
  int ratingScore = 0;
  String ratingComment = '';
  bool isSubmittingRating = false;

  // Delivery receipt upload state
  String? receiptPhotoUrl;
  bool isUploadingReceipt = false;

  // ── Employer Profile state ────────────────────────────────────
  bool showEmployerProfileModal = false;
  bool isLoadingEmployerProfile = false;
  Map<String, dynamic>? employerProfileData;

  // ── Wallet ──────────────────────────────────────────────────
  bool showWalletSelectionModal = false;
  String? selectedWalletType;
  WalletState walletState = WalletState.disconnected;
  String walletAddress = '';
  double walletBalance = 0.0;
  List<Map<String, dynamic>> walletCollectibles = [];
  String ethAddress = '';
  String suiAddress = '';
  double ethBalance = 0.0;
  double suiBalance = 0.0;
  bool isRefreshingBalance = false;
  List<Map<String, dynamic>> userTransactions = [];

  // ── Notifications ───────────────────────────────────────────
  List<Map<String, dynamic>> notifications = [];
  bool showNotificationsDropdown = false;
  Map<String, dynamic>? latestToastNotification;

  // ── Chat ─────────────────────────────────────────────────────
  bool showChat = false;
  String currentChatId = '';
  List<Map<String, dynamic>> chatMessages = [];
  String chatInputText = '';
  bool chatPiiBlocked = false;
  bool chatDisintermediationBlocked = false;
  bool isUploadingChatPhoto = false;
  bool isUploadingCertificate = false;
  Map<String, dynamic>? acceptedApplicantProfile;
  Map<String, dynamic>? selectedJobCreatorProfile;
  List<Map<String, double>> offlineLocationBuffer = [];
  bool hasInspectionHoldback = false;

  // ── Services ────────────────────────────────────────────────
  final _auth = FirebaseAuthService();
  GeminiService? _gemini;

  FirestoreService get _firestore => FirestoreService(SessionStorage.idToken, _handleTokenRefresh);
  FirestoreService get firestore => _firestore;

  Future<String?> _handleTokenRefresh() async {
    final rt = SessionStorage.refreshToken;
    if (rt == null) return null;
    try {
      final newToken = await _auth.refreshIdToken(rt);
      SessionStorage.updateIdToken(newToken);
      return newToken;
    } catch (_) {
      return null;
    }
  }

  Future<String?> Function() get handleTokenRefresh => _handleTokenRefresh;

  bool get canPostJob {
    final uid = SessionStorage.uid;
    if (uid == null) return false;
    final isPremium = userProfile?.isPremium ?? false;
    if (isPremium) return true;

    // Filter active jobs posted by this user
    final activeCount = myJobs.where((j) {
      final isCreator = j['creatorId'] == uid;
      if (!isCreator) return false;
      final s = (j['status'] as String?)?.toLowerCase();
      final isTerminal = s == 'completed' || s == 'complete' || s == 'cancelled' || s == 'closed';
      return !isTerminal;
    }).length;

    return activeCount == 0;
  }

  Map<String, dynamic>? get firstActiveJob {
    final uid = SessionStorage.uid;
    if (uid == null) return null;
    try {
      return myJobs.firstWhere((j) {
        final isCreator = j['creatorId'] == uid;
        if (!isCreator) return false;
        final s = (j['status'] as String?)?.toLowerCase();
        final isTerminal = s == 'completed' || s == 'complete' || s == 'cancelled' || s == 'closed';
        return !isTerminal;
      });
    } catch (_) {
      return null;
    }
  }

  void triggerSessionExpired() {
    if (showSessionExpiredModal) return;
    setState(() {
      showSessionExpiredModal = true;
    });
  }

  void showAppToast(String title, String message) {
    final lowerTitle = title.toLowerCase();
    final lowerMsg = message.toLowerCase();
    if (lowerTitle.contains('401') ||
        lowerTitle.contains('not logged in') ||
        lowerMsg.contains('401') ||
        lowerMsg.contains('not logged in') ||
        lowerMsg.contains('id-token-expired')) {
      triggerSessionExpired();
      return;
    }

    setState(() {
      latestToastNotification = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'title': title,
        'message': message,
      };
    });
    Timer(const Duration(seconds: 5), () {
      setState(() => latestToastNotification = null);
    });
  }

  void exitJobDetails() {
    setState(() {
      jobsView = JobsView.list;
      selectedJob = null;
      selectedJobData = null;
      selectedJobCreatorProfile = null;
      acceptedApplicantProfile = null;
      showDeleteConfirm = false;
      _stopSelectedJobRealtime();
    });
  }

  void _startSelectedJobRealtime(String jobId) {
    stopListeningToJobDetailsJs();
    listenToJobDetailsJs(jobId, (String jsonString) {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonString);
        final String type = data['type'] as String;
        if (type == 'job') {
          final Map<String, dynamic> fresh = data['data'] as Map<String, dynamic>;
          setState(() {
            if (selectedJobData != null && selectedJobData!['id'] == fresh['id']) {
              selectedJobData = {...selectedJobData!, ...fresh};

              final catName = (fresh['category'] as String? ?? selectedJobData?['category'] as String? ?? '')
                  .toLowerCase();
              final cat = JobCategory.values.firstWhere(
                (e) => e.name.toLowerCase() == catName || e.label.toLowerCase() == catName,
                orElse: () => JobCategory.others,
              );
              hasTracker =
                  fresh['hasTracker'] == true ||
                  fresh['hasTracker'] == 'true' ||
                  selectedJobData?['hasTracker'] == true ||
                  selectedJobData?['hasTracker'] == 'true' ||
                  cat.hasTracker;

              var title = fresh['title'] as String? ?? selectedJob?.title ?? '';
              if (title.isEmpty || title == 'Untitled') {
                final category = fresh['category'] as String? ?? selectedJobData?['category'] as String? ?? '';
                final categoryLabel =
                    fresh['categoryLabel'] as String? ?? selectedJobData?['categoryLabel'] as String? ?? '';
                final nameToNormalize = categoryLabel.isNotEmpty ? categoryLabel : category;
                title = nameToNormalize.isNotEmpty ? normalizeCategoryName(nameToNormalize) : 'Untitled Gig';
              }

              final rate = fresh['pricingValue'] != null
                  ? '₱ ${(fresh['pricingValue'] as num).toStringAsFixed(0)}'
                  : selectedJob?.rate ?? '';
              final urgency = fresh['dateRequirement'] as String? ?? selectedJob?.urgency ?? '';
              final status = fresh['status'] as String? ?? selectedJob?.status ?? '';
              final applicants = fresh['applicantCount'] as int? ?? selectedJob?.applicants ?? 0;
              selectedJob = SelectedJob(
                title: title,
                rate: rate,
                distance: selectedJob?.distance ?? '—',
                urgency: urgency,
                status: status,
                applicants: applicants,
              );
            }

            // Sync session copy too
            final idx = sessionPostedJobs.indexWhere((j) => j['id'] == jobId);
            if (idx != -1) sessionPostedJobs[idx] = selectedJobData!;
          });
        } else if (type == 'applications') {
          final List<dynamic> rawApps = data['data'] as List? ?? [];
          final apps = rawApps.map((e) => e as Map<String, dynamic>).toList();
          setState(() {
            jobApplicants = apps;
          });
        }
      } catch (e) {
        print('Error parsing realtime job details: $e');
      }
    });
  }

  void _stopSelectedJobRealtime() {
    stopListeningToJobDetailsJs();
  }

  AccountType get currentViewMode => accountType == AccountType.hybrid ? hybridToggle : accountType;

  @override
  // ignore: invalid_use_of_protected_member
  void setState(void Function() fn) => super.setState(fn);

  @override
  void initState() {
    super.initState();
    _handleMobileRedirect();
    onSessionExpiredGlobal = () {
      triggerSessionExpired();
    };
    _initGemini();

    try {
      web.window.addEventListener(
        'solanaWalletAccountChanged',
        (web.Event event) {
          final customEvent = event as web.CustomEvent;
          final detail = customEvent.detail as JSObject;
          final publicKey = (detail.getProperty<JSString>('publicKey'.toJS)).toDart;
          final walletType = (detail.getProperty<JSString>('walletType'.toJS)).toDart;
          _handleSolanaAccountChanged(publicKey, walletType);
        }.toJS,
      );

      web.window.addEventListener(
        'solanaWalletDisconnected',
        (web.Event event) {
          _handleSolanaWalletDisconnected();
        }.toJS,
      );
    } catch (_) {}

    // Load any pending QR details from SessionStorage
    pendingQrJobId = SessionStorage.pendingQrJobId;
    pendingQrCode = SessionStorage.pendingQrCode;

    // Load any pending Xendit invoice details from SessionStorage
    pendingXenditInvoiceId = SessionStorage.pendingXenditInvoiceId;
    if (pendingXenditInvoiceId != null) {
      depositAmount = SessionStorage.pendingXenditInvoiceAmount;
      pendingPropertyBookingData = SessionStorage.pendingPropertyBookingData;
      pendingVehicleBookingData = SessionStorage.pendingVehicleBookingData;
      pendingJobId = SessionStorage.pendingJobId;
      pendingApplicantData = SessionStorage.pendingApplicantData;
    }

    fetchSolToPhpRate();
    _loadOfflineLocationBuffer();
    _initUserLocation();
    final startTime = DateTime.now();
    void scheduleDismissal() {
      final elapsed = DateTime.now().difference(startTime);
      // Fast, responsive splash screen duration: 1.6s max wait once session is ready
      const minDuration = Duration(milliseconds: 1600);
      final remaining = minDuration - elapsed;

      void triggerExitSequence() {
        dismissWebSplashScreen();
        // Wait 800ms for 3D warp transition before unmounting splash overlay
        Timer(const Duration(milliseconds: 800), () {
          if (mounted) setState(() => showWebSplash = false);
        });
      }

      if (remaining.isNegative) {
        triggerExitSequence();
      } else {
        Timer(remaining, triggerExitSequence);
      }
    }

    if (SessionStorage.hasSession) {
      _restoreSession().whenComplete(scheduleDismissal);
    } else {
      _checkGoogleRedirectResult().whenComplete(scheduleDismissal);
    }
  }

  void _handleMobileRedirect() {
    final path = web.window.location.pathname;
    if (path == '/' || path == '') {
      final userAgent = web.window.navigator.userAgent.toLowerCase();
      final isIOS = userAgent.contains('iphone') || userAgent.contains('ipad') || userAgent.contains('ipod');
      final isAndroid = userAgent.contains('android');

      if (isIOS || isAndroid) {
        // Show choice prompt modal instead of auto-redirecting
        setState(() => showMobileAppPrompt = true);
      }
    }
  }

  void _initGemini() {
    _gemini = GeminiService(
      currentFirebaseConfig,
      idToken: SessionStorage.idToken,
      onTokenRefresh: _handleTokenRefresh,
    );
  }

  bool isLocationEnabled = true;

  void _initUserLocation() async {
    if (!isLocationEnabled) return;
    try {
      final pos = await getCurrentPosition();
      if (pos != null) {
        setState(() {
          userLatitude = pos.lat;
          userLongitude = pos.lng;
        });
      }
    } catch (_) {}
  }

  Future<void> requestAndUpdateUserLocation() async {
    try {
      final pos = await getCurrentPosition();
      if (pos != null) {
        setState(() {
          userLatitude = pos.lat;
          userLongitude = pos.lng;
          isLocationEnabled = true;
        });
      }
    } catch (_) {}
  }

  /// Restore a previous session from localStorage
  Future<void> _restoreSession() async {
    final storedType = SessionStorage.accountType;
    AccountType type = AccountType.employer;
    if (storedType != null) {
      type = AccountType.values.firstWhere(
        (e) => e.name == storedType,
        orElse: () => AccountType.employer,
      );
    }

    setState(() {
      isAuthenticated = true;
      accountType = type;
      hybridToggle = type == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
      userName = SessionStorage.displayName ?? '';
      userEmail = SessionStorage.email ?? '';
    });

    // Load full profile from Firestore
    await loadUserProfile();
    if (userProfile == null) {
      setState(() {
        activeTab = AppTab.profile;
        profileView = ProfileView.personal;
      });
    }
    // Load jobs for current tab
    await loadJobs();
    await loadTransactions();
    await loadRenterPendingRequests();
    await loadHostPendingRequests();
    _startListeningNotifications();
    _startListeningJobs();
    _startListeningRentals();
    _startListeningProperties();
    await handleQrVerificationParams();

    // Auto-execute pending QR verification if one exists and we are logged in
    if (pendingQrJobId != null && pendingQrCode != null) {
      await executePendingQrVerification();
    }
  }

  Future<void> _checkGoogleRedirectResult() async {
    try {
      final configMap = {
        'apiKey': currentFirebaseConfig.apiKey,
        'authDomain': currentFirebaseConfig.authDomain,
        'projectId': currentFirebaseConfig.projectId,
        'storageBucket': currentFirebaseConfig.storageBucket,
        'messagingSenderId': currentFirebaseConfig.messagingSenderId,
        'appId': currentFirebaseConfig.appId,
      };

      final googleJsonStr = await checkRedirectResultJs(configMap);
      if (googleJsonStr != null) {
        setState(() {
          isAuthLoading = true;
          authError = null;
        });

        final Map<String, dynamic> googleData = jsonDecode(googleJsonStr);
        final authResult = AuthResult(
          uid: googleData['uid'],
          idToken: googleData['idToken'],
          refreshToken: googleData['refreshToken'],
          email: googleData['email'],
          displayName: googleData['displayName'],
          photoUrl: googleData['photoUrl'],
        );

        SessionStorage.save(authResult);

        var profile = await FirestoreService(authResult.idToken, _handleTokenRefresh).getUser(authResult.uid);

        if (profile == null) {
          setState(() {
            pendingGoogleAuthResult = authResult;
            authView = AuthView.registerPath;
            isAuthLoading = false;
          });
        } else {
          if (profile.googleEmail == null || profile.googleEmail!.isEmpty) {
            await FirestoreService(
              authResult.idToken,
              _handleTokenRefresh,
            ).setDocument('users/${authResult.uid}', {'googleEmail': authResult.email});
            profile = profile.copyWith(googleEmail: authResult.email);
          }
          final type = profile.accountType;
          SessionStorage.saveProfile(
            name: profile.name,
            email: profile.email,
            accountType: type.name,
          );
          await _restoreSession();
          setState(() {
            isAuthLoading = false;
          });
        }
      } else {
        handleQrVerificationParams();
      }
    } catch (e) {
      print("checkGoogleRedirectResult error: $e");
      handleQrVerificationParams();
    }
  }

  int getUnreadChatCount(String chatId) {
    return notifications.where((n) => n['type'] == 'chat' && n['chatId'] == chatId).length;
  }

  bool get hasUnreadJobChats {
    return notifications.any(
      (n) =>
          n['type'] == 'chat' &&
          !n['chatId'].toString().startsWith('rental_') &&
          !n['chatId'].toString().startsWith('property_'),
    );
  }

  bool get hasUnreadRentalChats {
    return notifications.any(
      (n) =>
          n['type'] == 'chat' &&
          (n['chatId'].toString().startsWith('rental_') || n['chatId'].toString().startsWith('property_')),
    );
  }

  int get unreadJobChatsCount {
    return notifications
        .where(
          (n) =>
              n['type'] == 'chat' &&
              !n['chatId'].toString().startsWith('rental_') &&
              !n['chatId'].toString().startsWith('property_'),
        )
        .length;
  }

  int get unreadRentalChatsCount {
    return notifications
        .where(
          (n) =>
              n['type'] == 'chat' &&
              (n['chatId'].toString().startsWith('rental_') || n['chatId'].toString().startsWith('property_')),
        )
        .length;
  }

  void _startListeningNotifications() {
    final uid = SessionStorage.uid;
    if (uid == null) return;
    initFirebaseJs({
      'apiKey': currentFirebaseConfig.apiKey,
      'authDomain': currentFirebaseConfig.authDomain,
      'projectId': currentFirebaseConfig.projectId,
      'storageBucket': currentFirebaseConfig.storageBucket,
      'messagingSenderId': currentFirebaseConfig.messagingSenderId,
      'appId': currentFirebaseConfig.appId,
    });
    listenToNotificationsJs(uid, (String jsonString) {
      try {
        final List<dynamic> rawList = jsonDecode(jsonString);
        final parsed = rawList.map((e) => e as Map<String, dynamic>).toList();
        parsed.sort((notifA, notifB) => (notifB['createdAt'] as num? ?? 0).compareTo(notifA['createdAt'] as num? ?? 0));

        setState(() {
          // Filter out read notifications locally
          final unreadNotifs = parsed.where((n) => n['isRead'] != true).toList();

          // Automatically mark notifications read if they belong to the current open chat
          final List<Map<String, dynamic>> finalUnreadNotifs = [];
          for (final notif in unreadNotifs) {
            if (notif['type'] == 'chat' && notif['chatId'] == currentChatId) {
              final id = notif['id'] as String?;
              if (id != null) {
                markNotificationReadJs(id);
              }
            } else {
              finalUnreadNotifs.add(notif);
            }
          }

          // Identify if there are new notifications that we didn't have before
          final newNotifs = finalUnreadNotifs
              .where((n) => !notifications.any((existing) => existing['id'] == n['id']))
              .toList();
          if (newNotifs.isNotEmpty) {
            final latest = newNotifs.first;
            latestToastNotification = latest;

            // Trigger rating popup in real-time if a job completion notification is received
            if (latest['type'] == 'job_completed' && latest['isRead'] != true) {
              showRatingPopup = true;
              ratingTargetId = latest['senderUid'] as String?;
              ratingTargetName = latest['senderName'] as String? ?? 'User';
              ratingScore = 0;
              ratingComment = '';

              final token = SessionStorage.idToken;
              if (token != null) {
                final svc = FirestoreService(token, _handleTokenRefresh);
                unawaited(
                  svc.createOrUpdate('notifications/${latest['id']}', {
                    ...latest,
                    'isRead': true,
                  }),
                );
              }
            }

            // Clear toast after 5 seconds
            Timer(const Duration(seconds: 5), () {
              if (latestToastNotification?['id'] == latest['id']) {
                setState(() => latestToastNotification = null);
              }
            });
          }
          notifications = finalUnreadNotifs;
          _updateDocumentTitle();
        });
      } catch (e) {
        print('Error parsing notifications: $e');
      }
    });
  }

  void _updateDocumentTitle() {
    try {
      final unreadCount = notifications.where((n) => n['type'] == 'chat').length;
      if (unreadCount > 0) {
        web.document.title = '($unreadCount) Tranyx Web';
      } else {
        web.document.title = 'Tranyx — Decentralized Freelance Gig Marketplace';
      }
    } catch (_) {}
  }

  void _startListeningJobs() {
    final uid = SessionStorage.uid;
    if (uid == null) return;
    initFirebaseJs({
      'apiKey': currentFirebaseConfig.apiKey,
      'authDomain': currentFirebaseConfig.authDomain,
      'projectId': currentFirebaseConfig.projectId,
      'storageBucket': currentFirebaseConfig.storageBucket,
      'messagingSenderId': currentFirebaseConfig.messagingSenderId,
      'appId': currentFirebaseConfig.appId,
    });

    listenToJobsJs(uid, (String jsonString) {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonString);
        final String type = data['type'] as String;
        final List<dynamic> rawJobs = data['jobs'] as List? ?? [];
        final parsed = rawJobs.map((e) => e as Map<String, dynamic>).toList();

        setState(() {
          if (type == 'employer') {
            realtimeEmployerJobs = parsed;
          } else {
            realtimeNyxianJobs = parsed;
          }

          // Sync sessionPostedJobs with fresh real-time data so Firestore
          // status changes (e.g. arrived_dropoff) always win over stale session copies.
          final allRealtime = [...realtimeEmployerJobs, ...realtimeNyxianJobs];
          for (final fresh in allRealtime) {
            final id = fresh['id'] as String?;
            if (id == null) continue;
            final idx = sessionPostedJobs.indexWhere((j) => j['id'] == id);
            if (idx != -1) {
              sessionPostedJobs[idx] = fresh;
            }
          }

          // Combine and de-duplicate (session jobs now have fresh data)
          final seenIds = <String>{};
          final merged = <Map<String, dynamic>>[];

          for (final job in sessionPostedJobs) {
            final id = job['id'] as String?;
            if (id != null) {
              seenIds.add(id);
              merged.add(job);
            }
          }

          for (final job in realtimeEmployerJobs) {
            final id = job['id'] as String?;
            if (id != null && !seenIds.contains(id)) {
              seenIds.add(id);
              merged.add(job);
            }
          }

          for (final job in realtimeNyxianJobs) {
            final id = job['id'] as String?;
            if (id != null && !seenIds.contains(id)) {
              seenIds.add(id);
              merged.add(job);
            }
          }

          myJobs = merged;

          // Find ongoing job from merged list
          ongoingJob = merged.cast<Map<String, dynamic>?>().firstWhere(
            (j) {
              final s = (j?['status'] as String?)?.toLowerCase();
              return s != null && s != 'open' && s != 'completed' && s != 'cancelled' && s != 'held' && s != 'pending';
            },
            orElse: () => null,
          );

          // Update selectedJobData in real-time if it's currently open
          if (selectedJobData != null) {
            final match = merged.firstWhere(
              (j) => j['id'] == selectedJobData!['id'],
              orElse: () => <String, dynamic>{},
            );
            if (match.isNotEmpty) {
              selectedJobData = match;
            }
          }
        });
      } catch (e) {
        print('Error parsing realtime jobs: $e');
      }
    });
  }

  void _startListeningRentals() {
    listenToRentalsJs((String jsonString) {
      try {
        final List<dynamic> raw = jsonDecode(jsonString);
        final parsed = raw.map((e) => e as Map<String, dynamic>).toList();
        setState(() {
          realtimeRentals = parsed;
        });
      } catch (e) {
        print('Error parsing realtime rentals: $e');
      }
    });
  }

  void _startListeningProperties() {
    listenToPropertiesJs((String jsonString) {
      try {
        final List<dynamic> raw = jsonDecode(jsonString);
        final parsed = raw.map((e) {
          final map = e as Map<String, dynamic>;
          final id = map['id'] ?? '';
          return PropertyRental.fromMap(map, id);
        }).toList();
        setState(() {
          realtimeProperties = parsed;
        });
      } catch (e) {
        print('Error parsing realtime properties: $e');
      }
    });
    _loadRenterPendingPropertyRequests();
  }

  Future<void> _loadRenterPendingPropertyRequests() async {
    final uid = SessionStorage.uid;
    if (uid == null) return;
    try {
      final list = await _firestore.getPropertyPendingRequestsForRenter(uid);
      setState(() {
        propertyRenterPendingRequests = list;
      });
    } catch (e) {
      print('Error loading property renter pending requests: $e');
    }
  }

  Future<void> loadRenterPendingRequests() async {
    final uid = SessionStorage.uid;
    if (uid == null) return;
    try {
      final results = await Future.wait([
        _firestore.getRenterPendingRequests(uid),
        _firestore.getPropertyPendingRequestsForRenter(uid),
      ]);
      setState(() {
        renterPendingRequests = results[0];
        propertyRenterPendingRequests = results[1];
      });
    } catch (e) {
      print('Error loading renter pending requests: $e');
    }
  }

  Future<void> loadHostPendingRequests() async {
    final uid = SessionStorage.uid;
    if (uid == null) return;
    try {
      final results = await Future.wait([
        _firestore.getPendingRequestsForHost(uid),
        _firestore.getPropertyPendingRequestsForHost(uid),
      ]);
      setState(() {
        hostPendingRequests = results[0];
        propertyHostPendingRequests = results[1];
      });
    } catch (e) {
      print('Error loading host pending requests: $e');
    }
  }

  Future<void> loadUserProfile() async {
    final uid = SessionStorage.uid;
    if (uid == null) return;
    try {
      // Silently run onboarding verification at startup
      final token = SessionStorage.idToken;
      if (token != null) {
        final svc = FirestoreService(token, handleTokenRefresh);
        await svc.checkAndAwardOnboardingQuests(uid);
        await checkAndExpireSubscription(uid, svc);
      }

      final profile = await _firestore.getUser(uid);
      if (profile != null) {
        setState(() {
          userProfile = profile;
          userName = profile.name;
          userEmail = profile.email;
          userPhotoUrl = profile.photoUrl;
          accountType = profile.accountType;
          hybridToggle = accountType == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
        });
      }
      initializeProfileEditing();
      await loadKycSubmission();
      await loadHoldbacks();
    } catch (_) {}
  }

  Future<void> checkAndExpireSubscription(String uid, FirestoreService svc) async {
    try {
      final doc = await svc.getDocument('users/$uid');
      if (doc != null) {
        final isPremium = doc['isPremium'] as bool? ?? false;
        final premiumUntilMs = doc['premiumUntil'] as int?;
        if (isPremium && premiumUntilMs != null) {
          final expiry = DateTime.fromMillisecondsSinceEpoch(premiumUntilMs);
          if (expiry.isBefore(DateTime.now())) {
            // Revert premium status & accountType in Firestore
            await svc.createOrUpdate('users/$uid', {
              ...doc,
              'isPremium': false,
              'accountType': 'nyxian',
              'premiumUntil': null,
            });

            // Create notification for expiry
            final now = DateTime.now();
            final docId = 'notif_${now.millisecondsSinceEpoch}_${uid.substring(0, uid.length > 5 ? 5 : uid.length)}';
            await svc.createOrUpdate('notifications/$docId', {
              'uid': uid,
              'title': 'Subscription Expired',
              'message': 'Your Premium Hybrid subscription has expired. Renew now to continue enjoying PRO features!',
              'isRead': false,
              'createdAt': now.millisecondsSinceEpoch,
            });
          }
        }
      }
    } catch (_) {
      // ignore
    }
  }

  // ── Auth actions ────────────────────────────────────────────

  Future<void> handleSignIn(String email, String password) async {
    setState(() {
      isAuthLoading = true;
      authError = null;
    });
    try {
      final result = await _auth.signIn(email, password);
      SessionStorage.save(result);

      try {
        final configMap = {
          'apiKey': currentFirebaseConfig.apiKey,
          'authDomain': currentFirebaseConfig.authDomain,
          'projectId': currentFirebaseConfig.projectId,
          'storageBucket': currentFirebaseConfig.storageBucket,
          'messagingSenderId': currentFirebaseConfig.messagingSenderId,
          'appId': currentFirebaseConfig.appId,
        };
        await signInWithEmailAndPasswordJs(configMap, email, password);
      } catch (_) {}

      // Load user profile from Firestore to get account type
      final profile = await FirestoreService(result.idToken, _handleTokenRefresh).getUser(result.uid);

      final type = profile?.accountType ?? AccountType.employer;
      SessionStorage.saveProfile(
        name: profile?.name ?? result.displayName ?? email.split('@').first,
        email: email,
        accountType: type.name,
      );

      setState(() {
        isAuthenticated = true;
        accountType = type;
        hybridToggle = type == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
        userName = profile?.name ?? result.displayName ?? email.split('@').first;
        userEmail = email;
        userProfile = profile;
        isAuthLoading = false;
        authView = AuthView.login;
      });

      // If this sign-in was triggered after Phantom wallet recognition, link it
      if (pendingWalletPublicKey != null) {
        final walletKey = pendingWalletPublicKey!;
        pendingWalletPublicKey = null;
        try {
          await FirestoreService(result.idToken, _handleTokenRefresh).linkWalletToUser(
            result.uid,
            walletKey,
            refreshToken: result.refreshToken,
          );
        } catch (_) {}
      }

      _initGemini();
      await loadJobs();
      await loadTransactions();
      await loadRenterPendingRequests();
      await loadHostPendingRequests();
      _startListeningNotifications();
      _startListeningJobs();
      _startListeningRentals();
      _startListeningProperties();
      // Auto-connect Phantom wallet if already trusted by the browser
      unawaited(autoConnectPhantomIfLinked(profile?.walletPublicKey));

      if (pendingQrJobId != null && pendingQrCode != null) {
        await executePendingQrVerification();
      }
    } on FirebaseException catch (e) {
      String msg = e.message;
      if (msg.contains('INVALID_LOGIN_CREDENTIALS') ||
          msg.contains('INVALID_PASSWORD') ||
          msg.contains('EMAIL_NOT_FOUND')) {
        msg = 'Invalid email or password.';
      } else if (msg.contains('TOO_MANY_ATTEMPTS')) {
        msg = 'Too many attempts. Please try again later.';
      }
      setState(() {
        authError = msg;
        isAuthLoading = false;
      });
    } catch (e) {
      setState(() {
        authError = e.toString();
        isAuthLoading = false;
      });
    }
  }

  Future<void> handleRegister({
    required String name,
    required String email,
    required String password,
    required AccountType type,
    EmployerType? employerType,
    String? businessName,
  }) async {
    setState(() {
      isAuthLoading = true;
      authError = null;
    });
    try {
      final result = await _auth.register(email, password);
      await _auth.updateDisplayName(result.idToken, name);
      SessionStorage.save(result);

      try {
        final configMap = {
          'apiKey': currentFirebaseConfig.apiKey,
          'authDomain': currentFirebaseConfig.authDomain,
          'projectId': currentFirebaseConfig.projectId,
          'storageBucket': currentFirebaseConfig.storageBucket,
          'messagingSenderId': currentFirebaseConfig.messagingSenderId,
          'appId': currentFirebaseConfig.appId,
        };
        await signInWithEmailAndPasswordJs(configMap, email, password);
      } catch (_) {}

      final profile = UserProfile(
        uid: result.uid,
        name: name,
        email: email,
        accountType: type,
        employerType: type == AccountType.employer ? (employerType ?? EmployerType.personal) : null,
        businessName: businessName,
        createdAt: DateTime.now(),
      );

      await FirestoreService(result.idToken, _handleTokenRefresh).saveUser(profile);
      SessionStorage.saveProfile(name: name, email: email, accountType: type.name);

      setState(() {
        isAuthenticated = true;
        accountType = type;
        hybridToggle = type == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
        userName = name;
        userEmail = email;
        userProfile = profile;
        isAuthLoading = false;
        authView = AuthView.login;
        activeTab = AppTab.home;
      });

      // Link Phantom wallet if present from sign-in flow
      if (pendingWalletPublicKey != null) {
        final walletKey = pendingWalletPublicKey!;
        pendingWalletPublicKey = null;
        try {
          await FirestoreService(result.idToken, _handleTokenRefresh).linkWalletToUser(
            result.uid,
            walletKey,
            refreshToken: result.refreshToken,
          );
        } catch (_) {}
      }

      _initGemini();
      await loadJobs();
      await loadTransactions();
      _startListeningNotifications();
      _startListeningJobs();
      _startListeningRentals();
      _startListeningProperties();

      if (pendingQrJobId != null && pendingQrCode != null) {
        await executePendingQrVerification();
      }
    } on FirebaseException catch (e) {
      String msg = e.message;
      if (msg.contains('EMAIL_EXISTS')) {
        msg = 'This email is already registered.';
      } else if (msg.contains('WEAK_PASSWORD')) {
        msg = 'Password must be at least 6 characters.';
      }
      setState(() {
        authError = msg;
        isAuthLoading = false;
      });
    } catch (e) {
      setState(() {
        authError = e.toString();
        isAuthLoading = false;
      });
    }
  }

  Future<void> handleForgotPassword(String email) async {
    try {
      await _auth.resetPassword(email);
    } catch (_) {}
  }

  Future<void> handleGoogleSignIn() async {
    setState(() {
      isAuthLoading = true;
      authError = null;
    });

    try {
      final configMap = {
        'apiKey': currentFirebaseConfig.apiKey,
        'authDomain': currentFirebaseConfig.authDomain,
        'projectId': currentFirebaseConfig.projectId,
        'storageBucket': currentFirebaseConfig.storageBucket,
        'messagingSenderId': currentFirebaseConfig.messagingSenderId,
        'appId': currentFirebaseConfig.appId,
      };

      final googleJsonStr = await signInWithGoogleJs(configMap);
      if (googleJsonStr == null) {
        setState(() {
          authError = 'Google Sign-In was cancelled or failed.';
          isAuthLoading = false;
        });
        return;
      }

      final Map<String, dynamic> googleData = jsonDecode(googleJsonStr);
      if (googleData['redirecting'] == true) {
        setState(() {
          isAuthLoading = true;
        });
        return;
      }
      final authResult = AuthResult(
        uid: googleData['uid'] ?? '',
        idToken: googleData['idToken'] ?? '',
        refreshToken: googleData['refreshToken'] ?? '',
        email: googleData['email'] ?? '',
        displayName: googleData['displayName'] ?? '',
        photoUrl: googleData['photoUrl'],
      );

      SessionStorage.save(authResult);

      var profile = await FirestoreService(authResult.idToken, _handleTokenRefresh).getUser(authResult.uid);

      if (profile == null) {
        // Redirect to register path to ask for role
        setState(() {
          pendingGoogleAuthResult = authResult;
          authView = AuthView.registerPath;
          isAuthLoading = false;
        });
        return;
      }

      if (profile.googleEmail == null || profile.googleEmail!.isEmpty) {
        await FirestoreService(
          authResult.idToken,
          _handleTokenRefresh,
        ).setDocument('users/${authResult.uid}', {'googleEmail': authResult.email});
        profile = profile.copyWith(googleEmail: authResult.email);
      }

      final type = profile.accountType;
      SessionStorage.saveProfile(
        name: profile.name,
        email: profile.email,
        accountType: type.name,
      );

      setState(() {
        isAuthenticated = true;
        accountType = type;
        hybridToggle = type == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
        userName = profile?.name ?? 'Tranyx User';
        userEmail = profile?.email ?? 'unknown@tranyx.app';
        userProfile = profile;
        isAuthLoading = false;
        authView = AuthView.login;
      });

      if (pendingWalletPublicKey != null) {
        final walletKey = pendingWalletPublicKey!;
        pendingWalletPublicKey = null;
        try {
          await FirestoreService(authResult.idToken, _handleTokenRefresh).linkWalletToUser(
            authResult.uid,
            walletKey,
            refreshToken: authResult.refreshToken,
          );
        } catch (_) {}
      }

      _initGemini();
      await loadJobs();
      await loadTransactions();
      _startListeningNotifications();
      _startListeningJobs();
      _startListeningRentals();
      _startListeningProperties();
      unawaited(autoConnectPhantomIfLinked(profile.walletPublicKey));

      if (pendingQrJobId != null && pendingQrCode != null) {
        await executePendingQrVerification();
      }
    } on FirebaseException catch (e) {
      setState(() {
        authError = e.message;
        isAuthLoading = false;
      });
    } catch (e) {
      setState(() {
        authError = e.toString();
        isAuthLoading = false;
      });
    }
  }

  Future<void> handleGoogleRegisterComplete(AccountType type) async {
    setState(() => isAuthLoading = true);
    final authResult = pendingGoogleAuthResult;
    if (authResult == null) return;

    try {
      final profile = UserProfile(
        uid: authResult.uid,
        name: authResult.displayName ?? authResult.email?.split('@').first ?? 'User',
        email: authResult.email ?? '',
        accountType: type,
        employerType: type == AccountType.employer ? EmployerType.personal : null,
        createdAt: DateTime.now(),
        photoUrl: authResult.photoUrl,
        googleEmail: authResult.email,
      );

      await FirestoreService(authResult.idToken, _handleTokenRefresh).saveUser(profile);
      SessionStorage.saveProfile(
        name: profile.name,
        email: profile.email,
        accountType: type.name,
      );

      setState(() {
        isAuthenticated = true;
        accountType = type;
        hybridToggle = type == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
        userName = profile.name;
        userEmail = profile.email;
        userProfile = profile;
        isAuthLoading = false;
        authView = AuthView.login;
        activeTab = AppTab.home;
      });

      if (pendingWalletPublicKey != null) {
        final walletKey = pendingWalletPublicKey!;
        pendingWalletPublicKey = null;
        try {
          await FirestoreService(authResult.idToken, _handleTokenRefresh).linkWalletToUser(
            authResult.uid,
            walletKey,
            refreshToken: authResult.refreshToken,
          );
        } catch (_) {}
      }

      _initGemini();
      await loadJobs();
      await loadTransactions();
      _startListeningNotifications();
      _startListeningJobs();
      _startListeningRentals();
      _startListeningProperties();
      unawaited(autoConnectPhantomIfLinked(profile.walletPublicKey));

      if (pendingQrJobId != null && pendingQrCode != null) {
        await executePendingQrVerification();
      }
    } catch (e) {
      setState(() {
        authError = e.toString();
        isAuthLoading = false;
      });
    }
  }

  Future<void> handlePhantomSignIn() async {
    setState(() {
      showWalletSelectionModal = true;
    });
  }

  void handleLogout() {
    SessionStorage.clear();
    stopListeningToJobsJs();
    stopListeningToRentalsJs();
    stopListeningToPropertiesJs();
    unawaited(signOutJs());
    setState(() {
      isAuthenticated = false;
      authView = AuthView.login;
      profileView = ProfileView.main;
      userProfile = null;
      userName = '';
      userEmail = '';
      userPhotoUrl = null;
      myJobs = [];
      sessionPostedJobs = [];
      availableJobs = [];
      authError = null;
      notifications = [];
    });
    _updateDocumentTitle();
  }

  // ── Job actions ─────────────────────────────────────────────

  Future<void> loadTransactions() async {
    if (!isAuthenticated) return;
    try {
      final uid = SessionStorage.uid;
      if (uid == null) return;
      final trans = await _firestore.getMyTransactions(uid);
      setState(() {
        userTransactions = trans;
      });
    } catch (_) {}
  }

  Future<void> loadJobs() async {
    if (!isAuthenticated) return;
    setState(() {
      isLoadingJobs = true;
      jobsError = null;
    });
    try {
      final uid = SessionStorage.uid;
      if (uid == null) {
        setState(() => isLoadingJobs = false);
        return;
      }

      // Execute all 4 job queries concurrently in parallel
      final results = await Future.wait([
        _firestore.getMyJobs(uid),
        _firestore.getAcceptedJobs(uid),
        _firestore.getAvailableJobs(currentViewMode),
        _firestore.getAppliedJobs(uid),
      ]);

      final my = results[0];
      final accepted = results[1];
      final avail = results[2];
      final applied = results[3];

      // Combine created jobs and accepted jobs into one list
      final allMyJobs = [...my, ...accepted];

      // De-duplicate by id
      final seenIds = <String>{};
      final merged = <Map<String, dynamic>>[];

      for (final job in sessionPostedJobs) {
        final id = job['id'] as String?;
        if (id != null) {
          seenIds.add(id);
          merged.add(job);
        }
      }

      for (final job in allMyJobs) {
        final id = job['id'] as String?;
        if (id != null && !seenIds.contains(id)) {
          seenIds.add(id);
          merged.add(job);
        }
      }

      // Find the first job with status 'In Progress', active delivery, or 'Done' for the ongoing widget
      final ongoing = merged.cast<Map<String, dynamic>?>().firstWhere(
        (j) {
          final s = (j?['status'] as String?)?.toLowerCase();
          return s != null && s != 'open' && s != 'completed' && s != 'cancelled' && s != 'held' && s != 'pending';
        },
        orElse: () => null,
      );
      setState(() {
        myJobs = merged;
        availableJobs = avail;
        appliedJobs = applied;
        ongoingJob = ongoing;
        isLoadingJobs = false;
      });
    } catch (e) {
      setState(() {
        jobsError = e.toString();
        isLoadingJobs = false;
      });
    }
  }

  void handleHomeSearch(String query) {
    if (query.trim().isEmpty) return;
    setState(() {
      homeSearchQuery = query.trim();
      activeJobFilter = 'All';
      activeTab = AppTab.jobs;
      jobsView = JobsView.list;
    });
  }

  bool checkProfanity(String text) {
    if (text.isEmpty) return false;
    final cleanText = text.toLowerCase();
    final bannedWords = const [
      'putang ina',
      'tangina',
      'gago',
      'tarantado',
      'kupal',
      'puki',
      'kiki',
      'puta',
      'pota',
      'bobo',
      'pakyu',
      'ulol',
      'salsal',
      'fuck',
      'shit',
      'asshole',
      'bitch',
      'bastard',
      'cunt',
      'pussy',
      'dick',
      'cock',
    ];
    for (final word in bannedWords) {
      if (cleanText.contains(word)) {
        return true;
      }
    }
    return false;
  }

  Future<void> handlePostJob() async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;

    if (checkProfanity(newJobTitle) || checkProfanity(newJobDesc)) {
      setState(() {
        postJobError = 'Your job title or description contains inappropriate language. Please review and try again.';
      });
      return;
    }

    if (!canPostJob) {
      setState(() {
        postJobError =
            'Normal accounts can only have 1 active job at a time. Please complete your current ongoing job before posting a new one.';
      });
      return;
    }

    final price = double.tryParse(priceRate) ?? 0.0;

    setState(() {
      isPostingJob = true;
      postJobError = null;
    });

    try {
      final svc = FirestoreService(token, _handleTokenRefresh);

      // 1. Check user balance first
      final userDoc = await svc.getDocument('users/$uid');
      if (userDoc == null) throw 'User profile not found';

      final currentBal = (userDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
      final discountedPrice = (price - jobDiscountAmount).clamp(0.0, 999999.0);
      if (currentBal < discountedPrice) {
        setState(() {
          depositAmount = discountedPrice - currentBal;
          showDepositModal = true;
          isPostingJob = false;
        });
        return;
      }

      // 2. Sufficient balance: Deduct and Move to Escrow
      await svc.createOrUpdate('users/$uid', {
        ...userDoc,
        'tyxBalance': currentBal - discountedPrice,
      });

      // Update local state balance
      walletBalance = currentBal - discountedPrice;
      if (userProfile != null) {
        userProfile = userProfile!.copyWith(
          tyxBalance: walletBalance,
        );
      }

      final now = DateTime.now();
      final jobData = {
        'creatorId': uid,
        'creatorName': userName,
        'creatorPhotoUrl': userPhotoUrl,
        'creatorType': currentViewMode.name,
        'title': newJobTitle,
        'description': newJobDesc,
        'category': selectedJobCategory?.name ?? JobCategory.others.name,
        'categoryGroup': selectedJobCategoryGroup?.name ?? JobCategoryGroup.miscellaneousEvents.name,
        'employmentType': _empTypeLabel(empType),
        'dateRequirement': _dateTypeLabel(jobDateType),
        'jobDate': jobDate.isNotEmpty ? jobDate : null,
        'timePreference': _timePrefLabel(timePref),
        'pricingType': _paymentTypeLabel(paymentType),
        'pricingValue': price,
        'locationType': locType == LocType.onsite ? 'On-site' : 'Remote',
        'address': pickupAddress.isEmpty ? null : pickupAddress, // Fallback/General site address
        'pickupAddress': pickupAddress.isEmpty ? null : pickupAddress,
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'destinationAddress': destinationAddress.isEmpty ? null : destinationAddress,
        'destinationLat': destinationLat,
        'destinationLng': destinationLng,
        'landmark': jobLandmark.isEmpty ? null : jobLandmark,
        'imageUrls': jobImageUrls.isEmpty ? null : jobImageUrls,
        'createdAt': now.millisecondsSinceEpoch,
        'status': 'Open',
        'applicantCount': 0,
        'recentApplicantPhotos': <String>[],
        'applicantUids': <String>[],
        'hasTracker': hasTracker && locType == LocType.onsite,
        'hasInspectionHoldback': hasInspectionHoldback,
        if (jobPromoCode != null) 'promoCode': jobPromoCode,
        if (jobPromoCode != null) 'discountAmount': jobDiscountAmount,
      };

      // Create the job
      final jobId = await svc.createJob(jobData);

      // Automatically add new job category/skills to employer's preferred skills list
      final newSkill = selectedJobCategory?.name ?? JobCategory.others.name;
      final currentSkills = List<String>.from(userProfile?.skills ?? []);
      if (!currentSkills.contains(newSkill)) {
        currentSkills.add(newSkill);
        if (userProfile != null) {
          final updatedProfile = userProfile!.copyWith(skills: currentSkills);
          await svc.createOrUpdate('users/$uid', updatedProfile.toMap());
          userProfile = updatedProfile;
        }
      }

      // Create escrow record with holdback metadata if chosen
      await svc.createOrUpdate('escrow/$jobId', {
        'amount': discountedPrice,
        'employerId': uid,
        'status': 'held',
        'createdAt': now.millisecondsSinceEpoch,
        'hasInspectionHoldback': hasInspectionHoldback,
        if (hasInspectionHoldback) 'holdbackAmount': price * 0.10,
      });

      // Increment promo usage
      if (jobPromoCode != null) {
        await svc.incrementPromoUsage(jobPromoCode!, uid);
      }

      // Add to sessionPostedJobs to display instantly on posting page
      sessionPostedJobs.insert(0, {
        'id': jobId,
        ...jobData,
      });

      setState(() {
        isPostingJob = false;
        showDepositModal = false;
        jobsView = JobsView.success;
        // Reset form
        newJobTitle = '';
        newJobDesc = '';
        selectedCategory = null;
        selectedJobCategory = null;
        selectedJobCategoryGroup = null;
        createStep = 1;
        priceRate = '';
        jobAddress = '';
        hasInspectionHoldback = false;
        jobLandmark = '';
        hasTracker = false;
        pickupLat = null;
        pickupLng = null;
        pickupAddress = '';
        destinationLat = null;
        destinationLng = null;
        destinationAddress = '';
        jobImageUrls = [];
      });

      await loadJobs();
    } catch (e) {
      setState(() {
        postJobError = e.toString();
        isPostingJob = false;
        showDepositModal = false;
      });
    }
  }

  Future<void> fetchSolToPhpRate() async {
    if (isFetchingRate) return;
    setState(() {
      isFetchingRate = true;
      postJobError = null;
    });
    try {
      final response = await http.get(Uri.parse('https://api.coinbase.com/v2/prices/SOL-PHP/spot'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rateStr = data['data']?['amount'] as String?;
        if (rateStr != null) {
          final rate = double.tryParse(rateStr);
          if (rate != null && rate > 0) {
            setState(() {
              solToPhpRate = rate;
            });
            print("SOL-PHP exchange rate fetched: ₱$solToPhpRate");
          }
        }
      }
    } catch (e) {
      print("Failed to fetch SOL-PHP rate, using fallback ₱$solToPhpRate: $e");
    } finally {
      setState(() {
        isFetchingRate = false;
      });
    }
  }

  Future<void> processSolanaPayment(double amountInSol) async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) {
      setState(() => postJobError = 'Please log in to make a payment.');
      return;
    }

    setState(() {
      isDepositing = true;
      postJobError = null;
    });

    try {
      // 1. Ensure Solana wallet is connected and obtain the active user's public key
      final activeWalletType = selectedWalletType ?? 'phantom';
      if (!isSolanaWalletInstalled(activeWalletType)) {
        throw '${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)} Wallet is not installed. Please install the browser extension.';
      }

      var fromPubKey = userProfile?.walletPublicKey;
      if (fromPubKey == null || fromPubKey.trim().isEmpty) {
        fromPubKey = await connectSolanaWallet(activeWalletType);
        if (fromPubKey == null) {
          throw 'Failed to connect ${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)} Wallet. Please approve the connection.';
        }
        await FirestoreService(token, _handleTokenRefresh).linkWalletToUser(
          uid,
          fromPubKey,
          refreshToken: SessionStorage.refreshToken,
        );
      }

      // 2. Platform target Solana address
      const adminSolanaAddress = '4zMMC4mCK23ccaJ2rbzn36gkJr2cT6w9P5BmgFniS59D';

      // 3. Initiate the transfer transaction
      final signature = await sendSolanaPayment(fromPubKey, adminSolanaAddress, amountInSol);
      if (signature == null || signature.trim().isEmpty) {
        throw 'Solana transaction rejected or failed to broadcast.';
      }

      // 4. Update balance in Firestore and record the deposit transaction
      final svc = FirestoreService(token, _handleTokenRefresh);
      final userDoc = await svc.getDocument('users/$uid');
      if (userDoc != null) {
        final currentBal = (userDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
        final newBal = currentBal + depositAmount;

        await svc.createOrUpdate('users/$uid', {
          ...userDoc,
          'tyxBalance': newBal,
        });

        walletBalance = newBal;
        if (userProfile != null) {
          userProfile = UserProfile.fromMap(uid, {
            ...userDoc,
            'tyxBalance': newBal,
          });
        }

        // Record deposit transaction with Solana signature
        await svc.createOrUpdate('transactions/deposit_sol_$signature', {
          'uid': uid,
          'title': 'Wallet Top-Up (SOL)',
          'desc':
              'Crypto deposit of ${amountInSol.toStringAsFixed(4)} SOL via ${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)}',
          'amount': depositAmount,
          'status': 'Successful',
          'method': 'Solana',
          'solanaTxSignature': signature,
          'solanaAmount': amountInSol,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'type': 'deposit',
        });

        await loadTransactions();

        // Award deposit onboarding quest if eligible
        unawaited(svc.awardPointsIfEligible(uid, 'deposit_any_amount'));
      }

      setState(() {
        isDepositing = false;
        showDepositModal = false;
      });

      // Re-fetch real Phantom SOL balance in the background after payment
      unawaited(handleRefreshBalance());

      // 5. Finalize any pending actions
      if (newJobTitle.isNotEmpty) {
        await handlePostJob();
      } else if (pendingJobId != null && pendingApplicantData != null) {
        final jId = pendingJobId!;
        final aData = pendingApplicantData!;
        pendingJobId = null;
        pendingApplicantData = null;
        await acceptApplicant(jId, aData);
      } else if (pendingPropertyBookingData != null) {
        final data = pendingPropertyBookingData!;
        pendingPropertyBookingData = null;
        await firestore.createPropertyBookingRequest(
          propertyId: data['propertyId'] as String,
          renteeId: uid,
          renteeName: userProfile!.name,
          renteePhotoUrl: userProfile!.photoUrl,
          durationType: data['durationType'] as String,
          multiplier: data['multiplier'] as int,
          totalCost: (data['totalCost'] as num).toDouble(),
          contractType: data['contractType'] as String,
          contractTerms: data['contractTerms'] as String,
          startDate: data['startDate'] as int,
          endDate: data['endDate'] as int,
          licenseNumber: data['licenseNumber'] as String? ?? '',
          promoCode: data['promoCode'] as String?,
          discountAmount: data['discountAmount'] == null ? null : (data['discountAmount'] as num).toDouble(),
        );
      } else if (pendingVehicleBookingData != null) {
        final data = pendingVehicleBookingData!;
        pendingVehicleBookingData = null;
        await firestore.createBookingRequest(
          rentalId: data['rentalId'] as String,
          renteeId: uid,
          renteeName: userProfile!.name,
          renteePhotoUrl: userProfile!.photoUrl,
          durationType: data['durationType'] as String,
          multiplier: data['multiplier'] as int,
          licenseNumber: data['licenseNumber'] as String,
          totalCost: (data['totalCost'] as num).toDouble(),
          hireWithDriver: data['hireWithDriver'] as bool,
          rentalType: data['rentalType'] as String,
          deliveryAddress: data['deliveryAddress'] as String?,
          deliveryLat: data['deliveryLat'] == null ? null : (data['deliveryLat'] as num).toDouble(),
          deliveryLng: data['deliveryLng'] == null ? null : (data['deliveryLng'] as num).toDouble(),
          startDate: data['startDate'] as int,
          endDate: data['endDate'] as int,
          promoCode: data['promoCode'] as String?,
          discountAmount: data['discountAmount'] == null ? null : (data['discountAmount'] as num).toDouble(),
        );
        loadRenterPendingRequests();
      }
    } catch (e) {
      setState(() {
        isDepositing = false;
        postJobError = e.toString();
      });
    }
  }

  Future<void> processSubscriptionPayment(double amountInSol, String subType) async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) {
      setState(() => postJobError = 'Please log in to make a payment.');
      return;
    }

    setState(() {
      isDepositing = true;
      postJobError = null;
    });

    try {
      // 1. Ensure Solana wallet is connected and obtain the active user's public key
      final activeWalletType = selectedWalletType ?? 'phantom';
      if (!isSolanaWalletInstalled(activeWalletType)) {
        throw '${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)} Wallet is not installed. Please install the browser extension.';
      }

      var fromPubKey = userProfile?.walletPublicKey;
      if (fromPubKey == null || fromPubKey.trim().isEmpty) {
        fromPubKey = await connectSolanaWallet(activeWalletType);
        if (fromPubKey == null) {
          throw 'Failed to connect ${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)} Wallet. Please approve the connection.';
        }
        await FirestoreService(token, _handleTokenRefresh).linkWalletToUser(
          uid,
          fromPubKey,
          refreshToken: SessionStorage.refreshToken,
        );
      }

      // 2. Platform target Solana address
      const adminSolanaAddress = '4zMMC4mCK23ccaJ2rbzn36gkJr2cT6w9P5BmgFniS59D';

      // 3. Initiate the transfer transaction
      final signature = await sendSolanaPayment(fromPubKey, adminSolanaAddress, amountInSol);
      if (signature == null || signature.trim().isEmpty) {
        throw 'Solana transaction rejected or failed to broadcast.';
      }

      // 4. Update premium status in user profile & set account type to hybrid
      final svc = FirestoreService(token, _handleTokenRefresh);
      final userDoc = await svc.getDocument('users/$uid');
      if (userDoc != null) {
        final double phpPrice = subType == 'yearly' ? 2999.0 : 299.0;
        final now = DateTime.now();
        final premiumUntil = subType == 'yearly'
            ? now.add(const Duration(days: 365))
            : now.add(const Duration(days: 30));

        final updatedProfile = {
          ...userDoc,
          'isPremium': true,
          'premiumUntil': premiumUntil.millisecondsSinceEpoch,
          'accountType': 'hybrid',
        };

        await svc.createOrUpdate('users/$uid', updatedProfile);

        if (userProfile != null) {
          userProfile = UserProfile.fromMap(uid, updatedProfile);
        }

        // Record subscription transaction with Solana signature
        await svc.createOrUpdate('transactions/sub_sol_$signature', {
          'uid': uid,
          'title': 'Hybrid PRO Subscription (${subType == 'yearly' ? 'Yearly' : 'Monthly'})',
          'desc':
              'Subscribed via ${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)} (${amountInSol.toStringAsFixed(4)} SOL)',
          'amount': phpPrice,
          'status': 'Successful',
          'method': 'Solana',
          'solanaTxSignature': signature,
          'solanaAmount': amountInSol,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'type': 'subscription',
        });

        await loadTransactions();
      }
    } catch (e) {
      setState(() => postJobError = e.toString());
      rethrow;
    } finally {
      setState(() {
        isDepositing = false;
      });
      unawaited(handleRefreshBalance());
    }
  }

  Future<void> processUsdtPayment(double amountInUsdt) async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) {
      setState(() => postJobError = 'Please log in to make a payment.');
      return;
    }

    setState(() {
      isDepositing = true;
      postJobError = null;
    });

    try {
      final activeWalletType = selectedWalletType ?? 'phantom';
      if (!isSolanaWalletInstalled(activeWalletType)) {
        throw '${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)} Wallet is not installed. Please install the browser extension.';
      }

      var fromPubKey = userProfile?.walletPublicKey;
      if (fromPubKey == null || fromPubKey.trim().isEmpty) {
        fromPubKey = await connectSolanaWallet(activeWalletType);
        if (fromPubKey == null) {
          throw 'Failed to connect ${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)} Wallet. Please approve the connection.';
        }
        await FirestoreService(token, _handleTokenRefresh).linkWalletToUser(
          uid,
          fromPubKey,
          refreshToken: SessionStorage.refreshToken,
        );
      }

      const adminSolanaAddress = '4zMMC4mCK23ccaJ2rbzn36gkJr2cT6w9P5BmgFniS59D';

      // Auto-detect if user holds a USDT token, and use that mint if present
      String? customMint;
      final usdtToken = walletCollectibles.firstWhere(
        (t) => t['symbol'].toString().toUpperCase() == 'USDT',
        orElse: () => <String, dynamic>{},
      );
      if (usdtToken.isNotEmpty) {
        customMint = usdtToken['mint'] as String?;
      }

      final signature = await sendUsdtPayment(
        fromPubKey,
        adminSolanaAddress,
        amountInUsdt,
        usdtMint: customMint,
      );
      if (signature == null || signature.trim().isEmpty) {
        throw 'USDT transaction rejected or failed to broadcast.';
      }

      final svc = FirestoreService(token, _handleTokenRefresh);
      final userDoc = await svc.getDocument('users/$uid');
      if (userDoc != null) {
        final currentBal = (userDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
        final phpEquivalent = amountInUsdt * usdToPhpRate;
        final newBal = currentBal + phpEquivalent;

        await svc.createOrUpdate('users/$uid', {
          ...userDoc,
          'tyxBalance': newBal,
        });

        walletBalance = newBal;
        if (userProfile != null) {
          userProfile = UserProfile.fromMap(uid, {
            ...userDoc,
            'tyxBalance': newBal,
          });
        }

        await svc.createOrUpdate('transactions/deposit_usdt_$signature', {
          'uid': uid,
          'title': 'Wallet Top-Up (USDT)',
          'desc':
              'Crypto deposit of ${amountInUsdt.toStringAsFixed(2)} USDT via ${activeWalletType.substring(0, 1).toUpperCase()}${activeWalletType.substring(1)}',
          'amount': phpEquivalent,
          'status': 'Successful',
          'method': 'Solana/USDT',
          'solanaTxSignature': signature,
          'usdtAmount': amountInUsdt,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'type': 'deposit',
        });

        await loadTransactions();
      }

      setState(() {
        isDepositing = false;
        showDepositModal = false;
      });

      if (newJobTitle.isNotEmpty) {
        await handlePostJob();
      } else if (pendingJobId != null && pendingApplicantData != null) {
        final jId = pendingJobId!;
        final aData = pendingApplicantData!;
        pendingJobId = null;
        pendingApplicantData = null;
        await acceptApplicant(jId, aData);
      } else if (pendingPropertyBookingData != null) {
        final data = pendingPropertyBookingData!;
        pendingPropertyBookingData = null;
        await firestore.createPropertyBookingRequest(
          propertyId: data['propertyId'] as String,
          renteeId: uid,
          renteeName: userProfile!.name,
          renteePhotoUrl: userProfile!.photoUrl,
          durationType: data['durationType'] as String,
          multiplier: data['multiplier'] as int,
          totalCost: (data['totalCost'] as num).toDouble(),
          contractType: data['contractType'] as String,
          contractTerms: data['contractTerms'] as String,
          startDate: data['startDate'] as int,
          endDate: data['endDate'] as int,
          licenseNumber: data['licenseNumber'] as String? ?? '',
          promoCode: data['promoCode'] as String?,
          discountAmount: data['discountAmount'] == null ? null : (data['discountAmount'] as num).toDouble(),
        );
      } else if (pendingVehicleBookingData != null) {
        final data = pendingVehicleBookingData!;
        pendingVehicleBookingData = null;
        await firestore.createBookingRequest(
          rentalId: data['rentalId'] as String,
          renteeId: uid,
          renteeName: userProfile!.name,
          renteePhotoUrl: userProfile!.photoUrl,
          durationType: data['durationType'] as String,
          multiplier: data['multiplier'] as int,
          licenseNumber: data['licenseNumber'] as String,
          totalCost: (data['totalCost'] as num).toDouble(),
          hireWithDriver: data['hireWithDriver'] as bool,
          rentalType: data['rentalType'] as String,
          deliveryAddress: data['deliveryAddress'] as String?,
          deliveryLat: data['deliveryLat'] == null ? null : (data['deliveryLat'] as num).toDouble(),
          deliveryLng: data['deliveryLng'] == null ? null : (data['deliveryLng'] as num).toDouble(),
          startDate: data['startDate'] as int,
          endDate: data['endDate'] as int,
          promoCode: data['promoCode'] as String?,
          discountAmount: data['discountAmount'] == null ? null : (data['discountAmount'] as num).toDouble(),
        );
        loadRenterPendingRequests();
      }
    } catch (e) {
      setState(() {
        isDepositing = false;
        postJobError = e.toString();
      });
    }
  }

  String? pendingXenditInvoiceId;
  String? pendingJobId;
  Map<String, dynamic>? pendingApplicantData;
  bool isVerifyingPayment = false;

  Future<void> createXenditInvoice() async {
    final uid = SessionStorage.uid;
    if (uid == null) return;

    if (depositAmount <= 0) {
      setState(() {
        postJobError = 'Please enter a valid amount.';
      });
      return;
    }

    setState(() {
      isDepositing = true;
      postJobError = null;
    });

    try {
      final apiKey = Env.get('XENDIT_SECRET_KEY');
      final basicAuth = base64Encode(utf8.encode('$apiKey:'));
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final response = await http.post(
        Uri.parse('https://api.xendit.co/v2/invoices'),
        headers: {
          'Authorization': 'Basic $basicAuth',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'external_id': 'topup_${uid}_$timestamp',
          'amount': depositAmount.round(), // Xendit requires integer amounts (PHP)
          'payer_email': userName.isNotEmpty
              ? '$userName@example.com'.replaceAll(' ', '').toLowerCase()
              : 'user@example.com',
          'description': 'Tyxbit Top-up for $userName',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final invoiceUrl = data['invoice_url'] as String?;
        final invoiceId = data['id'] as String?;

        if (invoiceUrl != null && invoiceId != null) {
          SessionStorage.pendingXenditInvoiceId = invoiceId;
          SessionStorage.pendingXenditInvoiceAmount = depositAmount;
          SessionStorage.pendingPropertyBookingData = pendingPropertyBookingData;
          SessionStorage.pendingVehicleBookingData = pendingVehicleBookingData;
          SessionStorage.pendingJobId = pendingJobId;
          SessionStorage.pendingApplicantData = pendingApplicantData;

          openUrl(invoiceUrl);
          setState(() {
            isDepositing = false;
            pendingXenditInvoiceId = invoiceId;
          });
        } else {
          setState(() {
            isDepositing = false;
            postJobError = 'Failed to get invoice URL.';
          });
        }
      } else {
        setState(() {
          isDepositing = false;
          postJobError = 'Xendit Invoice Creation Failed: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isDepositing = false;
        postJobError = 'Top-up failed: $e';
      });
    }
  }

  Future<void> verifyXenditPayment() async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    final invoiceId = pendingXenditInvoiceId;
    if (uid == null || token == null || invoiceId == null) return;

    setState(() => isVerifyingPayment = true);

    try {
      final apiKey = Env.get('XENDIT_SECRET_KEY');
      final basicAuth = base64Encode(utf8.encode('$apiKey:'));

      final checkRes = await http.get(
        Uri.parse('https://api.xendit.co/v2/invoices/$invoiceId'),
        headers: {'Authorization': 'Basic $basicAuth'},
      );

      if (checkRes.statusCode == 200) {
        final checkData = jsonDecode(checkRes.body);
        final status = checkData['status'];
        if (status == 'PAID' || status == 'SETTLED') {
          print("PAID XENDIT!");
          // Update Firebase
          final svc = FirestoreService(token, _handleTokenRefresh);
          final userDoc = await svc.getDocument('users/$uid');
          if (userDoc != null) {
            final currentBal = (userDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            final newBal = currentBal + depositAmount;
            await svc.createOrUpdate('users/$uid', {
              ...userDoc,
              'tyxBalance': newBal,
            });
            walletBalance = newBal;
            if (userProfile != null) {
              userProfile = UserProfile.fromMap(uid, {
                ...userDoc,
                'tyxBalance': newBal,
              });
            }

            // Record transaction history
            await svc.createOrUpdate('transactions/deposit_$invoiceId', {
              'uid': uid,
              'title': 'Wallet Top-Up',
              'desc': 'Fiat deposit via Xendit',
              'amount': depositAmount,
              'status': 'Successful',
              'method': 'Xendit',
              'createdAt': DateTime.now().millisecondsSinceEpoch,
              'type': 'deposit',
            });

            // Reload history if needed
            await loadTransactions();

            // Award deposit onboarding quest if eligible
            unawaited(svc.awardPointsIfEligible(uid, 'deposit_any_amount'));
          }

          SessionStorage.pendingXenditInvoiceId = null;
          SessionStorage.pendingXenditInvoiceAmount = 0.0;
          SessionStorage.pendingPropertyBookingData = null;
          SessionStorage.pendingVehicleBookingData = null;
          SessionStorage.pendingJobId = null;
          SessionStorage.pendingApplicantData = null;

          setState(() {
            isVerifyingPayment = false;
            pendingXenditInvoiceId = null;
            showDepositModal = false;
          });

          // Finalize job posting or bookings
          if (newJobTitle.isNotEmpty) {
            await handlePostJob();
          } else if (pendingJobId != null && pendingApplicantData != null) {
            final jId = pendingJobId!;
            final aData = pendingApplicantData!;
            pendingJobId = null;
            pendingApplicantData = null;
            await acceptApplicant(jId, aData);
          } else if (pendingPropertyBookingData != null) {
            final data = pendingPropertyBookingData!;
            pendingPropertyBookingData = null;
            await firestore.createPropertyBookingRequest(
              propertyId: data['propertyId'] as String,
              renteeId: uid,
              renteeName: userProfile!.name,
              renteePhotoUrl: userProfile!.photoUrl,
              durationType: data['durationType'] as String,
              multiplier: data['multiplier'] as int,
              totalCost: (data['totalCost'] as num).toDouble(),
              contractType: data['contractType'] as String,
              contractTerms: data['contractTerms'] as String,
              startDate: data['startDate'] as int,
              endDate: data['endDate'] as int,
              licenseNumber: data['licenseNumber'] as String? ?? '',
              promoCode: data['promoCode'] as String?,
              discountAmount: data['discountAmount'] == null ? null : (data['discountAmount'] as num).toDouble(),
            );
          } else if (pendingVehicleBookingData != null) {
            final data = pendingVehicleBookingData!;
            pendingVehicleBookingData = null;
            await firestore.createBookingRequest(
              rentalId: data['rentalId'] as String,
              renteeId: uid,
              renteeName: userProfile!.name,
              renteePhotoUrl: userProfile!.photoUrl,
              durationType: data['durationType'] as String,
              multiplier: data['multiplier'] as int,
              licenseNumber: data['licenseNumber'] as String,
              totalCost: (data['totalCost'] as num).toDouble(),
              hireWithDriver: data['hireWithDriver'] as bool,
              rentalType: data['rentalType'] as String,
              deliveryAddress: data['deliveryAddress'] as String?,
              deliveryLat: data['deliveryLat'] == null ? null : (data['deliveryLat'] as num).toDouble(),
              deliveryLng: data['deliveryLng'] == null ? null : (data['deliveryLng'] as num).toDouble(),
              startDate: data['startDate'] as int,
              endDate: data['endDate'] as int,
              promoCode: data['promoCode'] as String?,
              discountAmount: data['discountAmount'] == null ? null : (data['discountAmount'] as num).toDouble(),
            );
            loadRenterPendingRequests();
          }
        } else if (status == 'EXPIRED') {
          SessionStorage.pendingXenditInvoiceId = null;
          SessionStorage.pendingXenditInvoiceAmount = 0.0;
          SessionStorage.pendingPropertyBookingData = null;
          SessionStorage.pendingVehicleBookingData = null;
          SessionStorage.pendingJobId = null;
          SessionStorage.pendingApplicantData = null;

          setState(() {
            isVerifyingPayment = false;
            pendingXenditInvoiceId = null;
            postJobError = 'Invoice has expired. Please try again.';
          });
        } else {
          setState(() {
            isVerifyingPayment = false;
            postJobError = 'Payment not completed yet. Status: $status';
          });
        }
      } else {
        setState(() {
          isVerifyingPayment = false;
          postJobError = 'Failed to verify payment status.';
        });
      }
    } catch (e, s) {
      print("ERROR $e $s");
      setState(() {
        isVerifyingPayment = false;
        postJobError = 'Verification error: $e';
      });
    }
  }

  Future<void> handleWithdrawTyx() async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;

    // Prevent withdrawals if user has active/ongoing rentals as a rentee (to protect hosts/owners from unpaid extension/late return fees)
    final hasActiveVehicleRentals = realtimeRentals.any((rMap) {
      final rental = VehicleRental.fromMap(rMap, rMap['id'] ?? '');
      final isRenter = (rental.renteeId == uid);
      final statusLower = rental.status.toLowerCase();
      final isActive = (statusLower != 'completed' && statusLower != 'cancelled');
      return isRenter && isActive;
    });

    final hasActivePropertyRentals = realtimeProperties.any((prop) {
      final isRenter = (prop.renteeId == uid);
      final statusLower = prop.status.toLowerCase();
      final isActive = (statusLower != 'completed' && statusLower != 'cancelled' && statusLower != 'available');
      return isRenter && isActive;
    });

    if (hasActiveVehicleRentals || hasActivePropertyRentals) {
      setState(
        () => profileSaveError =
            'Withdrawals are disabled while you have active/ongoing rentals to ensure potential extensions, late returns, or security fees are covered.',
      );
      return;
    }

    final tyxBal = userProfile?.tyxBalance ?? 0.0;
    if (tyxBal < 100) {
      setState(() => profileSaveError = 'Minimum withdrawal is 100 Tyx (₱100).');
      return;
    }

    final walletKey = userProfile?.walletPublicKey;
    if (walletKey == null || walletKey.isEmpty) {
      setState(() => profileSaveError = 'Please connect your Solana wallet in the Payment tab first.');
      return;
    }

    setState(() {
      isSavingProfile = true;
      profileSaveError = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final message =
          'Authorize withdrawal of ${tyxBal.toStringAsFixed(2)} Tyxbits from Tranyx account $uid to wallet $walletKey at $timestamp';

      final activeWalletType = selectedWalletType ?? 'phantom';

      var activePublicKey = await getSolanaPublicKeyIfConnected(activeWalletType);
      if (activePublicKey == null || activePublicKey != walletKey) {
        activePublicKey = await connectSolanaWallet(activeWalletType);
      }

      if (activePublicKey != walletKey) {
        throw 'Connected wallet address ($activePublicKey) does not match profile address ($walletKey).';
      }

      final signature = await signSolanaMessage(walletKey, message);
      if (signature == null || signature.isEmpty) {
        throw 'Signature request rejected or failed.';
      }

      final svc = FirestoreService(token, _handleTokenRefresh);

      // Create withdrawal request record with signature
      await svc.createOrUpdate('withdrawalRequests/withdraw_$timestamp', {
        'uid': uid,
        'userName': userName,
        'amount': tyxBal,
        'status': 'Pending',
        'createdAt': timestamp,
        'method': 'Solana',
        'walletPublicKey': walletKey,
        'signature': signature,
        'message': message,
      });

      setState(() {
        isSavingProfile = false;
        profileSaveError = 'Withdrawal request authorized and sent! Our back office will process it within 24 hours.';
      });
      showAppToast('Withdrawal Requested', 'Authorized with signature: ${signature.substring(0, 8)}...');
    } catch (e) {
      setState(() {
        isSavingProfile = false;
        profileSaveError = e.toString();
      });
    }
  }

  Future<void> handleImageUpload(dynamic eventTarget) async {
    final token = SessionStorage.idToken;
    if (token == null) return;

    setState(() => isUploadingImages = true);

    try {
      final files = await readFilesFromEvent(eventTarget);
      for (final file in files) {
        if (jobImageUrls.length >= 5) break;
        final url = await ImgBBService(
          currentFirebaseConfig,
          idToken: token,
          onTokenRefresh: _handleTokenRefresh,
        ).uploadImageBytes(file.bytes, file.name);
        if (url != null) {
          setState(() => jobImageUrls.add(url));
        }
      }
    } catch (e, stack) {
      print('handleImageUpload error: $e');
      print(stack);
    } finally {
      setState(() => isUploadingImages = false);
    }
  }

  Future<void> selectJobAndLoadDetails(Map<String, dynamic> jobMap) async {
    var title = jobMap['title'] as String? ?? '';
    if (title.isEmpty || title == 'Untitled') {
      final category = jobMap['category'] as String? ?? '';
      final categoryLabel = jobMap['categoryLabel'] as String? ?? '';
      final nameToNormalize = categoryLabel.isNotEmpty ? categoryLabel : category;
      title = nameToNormalize.isNotEmpty ? normalizeCategoryName(nameToNormalize) : 'Untitled Gig';
    }

    final rate = '₱ ${(jobMap['pricingValue'] as num?)?.toStringAsFixed(0) ?? '0'}';
    final urgency = jobMap['dateRequirement'] as String? ?? 'Flexible';
    final status = jobMap['status'] as String? ?? 'Open';
    final applicants = jobMap['applicantCount'] as int? ?? 0;
    final catName = (jobMap['category'] as String? ?? '').toLowerCase();
    final cat = JobCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == catName || e.label.toLowerCase() == catName,
      orElse: () => JobCategory.others,
    );
    final hasTracker = jobMap['hasTracker'] == true || jobMap['hasTracker'] == 'true' || cat.hasTracker;

    setState(() {
      selectedJobData = jobMap;
      selectedJob = SelectedJob(
        title: title,
        rate: rate,
        distance: '—',
        urgency: urgency,
        status: status,
        applicants: applicants,
      );
      selectedJobImageCarouselIndex = 0;
      activeTab = AppTab.jobs;
      jobsView = JobsView.details;
      jobQuestions = [];
      this.hasTracker = hasTracker;
    });

    // Load questions
    final jobId = jobMap['id'] as String? ?? '';
    if (jobId.isNotEmpty) {
      await loadJobQuestions(jobId);
      final uid = SessionStorage.uid;
      if (uid != null && uid == jobMap['creatorId']) {
        await loadApplicants(jobId);
      }
    }

    final acceptedId = jobMap['acceptedApplicantId'] as String?;
    if (acceptedId != null && acceptedId.isNotEmpty) {
      try {
        final token = SessionStorage.idToken;
        if (token != null) {
          final doc = await FirestoreService(token, _handleTokenRefresh).getDocument('users/$acceptedId');
          setState(() {
            acceptedApplicantProfile = doc;
          });
        }
      } catch (_) {}
    } else {
      setState(() {
        acceptedApplicantProfile = null;
      });
    }

    final creatorId = jobMap['creatorId'] as String?;
    if (creatorId != null && creatorId.isNotEmpty) {
      try {
        final token = SessionStorage.idToken;
        if (token != null) {
          final doc = await FirestoreService(token, _handleTokenRefresh).getDocument('users/$creatorId');
          setState(() {
            selectedJobCreatorProfile = doc;
            if (selectedJobData != null && doc != null) {
              selectedJobData = {
                ...selectedJobData!,
                'creatorName':
                    doc['name'] as String? ??
                    doc['displayName'] as String? ??
                    selectedJobData!['creatorName'] ??
                    'Employer',
                'creatorPhotoUrl': doc['photoUrl'] as String? ?? selectedJobData!['creatorPhotoUrl'] ?? '',
              };
            }
          });
        }
      } catch (_) {}
    } else {
      setState(() {
        selectedJobCreatorProfile = null;
      });
    }

    // Keep selectedJobData fresh via real-time listener
    if (jobId.isNotEmpty) {
      _startSelectedJobRealtime(jobId);
    }
  }

  Future<void> loadJobQuestions(String jobId) async {
    setState(() => isLoadingQuestions = true);
    try {
      final questions = await _firestore.getQuestions(jobId);
      setState(() {
        jobQuestions = questions;
        isLoadingQuestions = false;
      });
    } catch (_) {
      setState(() => isLoadingQuestions = false);
    }
  }

  Future<void> handleAskQuestion() async {
    if (newQuestionText.trim().isEmpty) return;
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    final jobId = selectedJobData?['id'] as String? ?? '';
    if (uid == null || token == null || jobId.isEmpty) return;

    setState(() => isPostingQuestion = true);
    try {
      await FirestoreService(token, _handleTokenRefresh).addQuestion(
        jobId: jobId,
        authorId: uid,
        authorName: userName.isEmpty ? 'Anonymous' : userName,
        authorPhotoUrl: userPhotoUrl,
        questionText: newQuestionText,
      );
      setState(() {
        newQuestionText = '';
        isPostingQuestion = false;
      });
      await loadJobQuestions(jobId);
    } catch (_) {
      setState(() => isPostingQuestion = false);
    }
  }

  Future<void> handleAnswerQuestion(String questionId) async {
    final answer = answerDrafts[questionId] ?? '';
    if (answer.trim().isEmpty) return;
    final token = SessionStorage.idToken;
    final jobId = selectedJobData?['id'] as String? ?? '';
    if (token == null || jobId.isEmpty) return;

    try {
      await FirestoreService(token, _handleTokenRefresh).answerQuestion(
        jobId: jobId,
        questionId: questionId,
        answer: answer,
      );
      setState(() {
        answerDrafts.remove(questionId);
        activeAnswerQuestionId = null;
      });
      await loadJobQuestions(jobId);
    } catch (_) {}
  }

  Future<void> handleDeleteQuestion(String questionId) async {
    final token = SessionStorage.idToken;
    final jobId = selectedJobData?['id'] as String? ?? '';
    if (token == null || jobId.isEmpty) return;
    try {
      await FirestoreService(token, _handleTokenRefresh).deleteQuestion(jobId, questionId);
      await loadJobQuestions(jobId);
    } catch (_) {}
  }

  Future<void> handleLikeQuestion(String questionId, bool isLiked) async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    final jobId = selectedJobData?['id'] as String? ?? '';
    if (token == null || uid == null || jobId.isEmpty) return;
    try {
      await FirestoreService(token, _handleTokenRefresh).toggleQuestionLike(jobId, questionId, uid, isLiked);
      await loadJobQuestions(jobId);
    } catch (_) {}
  }

  void handleReportJob() {
    setState(() {
      showReportModal = true;
      selectedReportReason = '';
    });
  }

  // ── Chat Actions ──────────────────────────────────────────────
  void openChat(String chatId) {
    final uid = SessionStorage.uid;
    if (uid == null || chatId.isEmpty) return;

    // Check if chatting is allowed for vehicle rentals
    if (chatId.startsWith('rental_')) {
      final parts = chatId.split('_');
      if (parts.length >= 2) {
        final rentalId = parts[1];
        final rental = realtimeRentals.firstWhere(
          (r) => r['id'] == rentalId,
          orElse: () => <String, dynamic>{},
        );
        if (rental.isNotEmpty) {
          final allowChatVal = rental['allowChat'] as bool? ?? false;
          final isHost = rental['hostId'] == uid;
          if (!isHost && !allowChatVal) {
            print('Chat blocked: Vehicle host has not enabled chatting.');
            return;
          }
        }
      }
    }

    // Check if chatting is allowed for properties
    if (chatId.startsWith('property_')) {
      final parts = chatId.split('_');
      if (parts.length >= 2) {
        final propertyId = parts[1];
        final prop = realtimeProperties.firstWhere(
          (item) => item.id == propertyId,
          orElse: () => PropertyRental(
            id: '',
            hostId: '',
            hostName: '',
            title: '',
            description: '',
            type: PropertyType.house,
            category: PropertyCategory.residential,
            priceMonthly: 0,
            priceWeekly: 0,
            priceDaily: 0,
            depositMonths: 0,
            address: '',
            latitude: 0,
            longitude: 0,
            photoUrls: [],
            amenities: [],
            status: '',
            contractType: '',
            contractTerms: '',
            createdAt: DateTime.now(),
            allowChat: false,
          ),
        );
        if (prop.id.isNotEmpty) {
          final isHost = prop.hostId == uid;
          if (!isHost && !prop.allowChat) {
            print('Chat blocked: Property host has not enabled chatting.');
            return;
          }
        }
      }
    }

    setState(() {
      showChat = true;
      currentChatId = chatId;
      chatMessages = [];
      chatInputText = '';
      chatPiiBlocked = false;
      chatDisintermediationBlocked = false;
    });

    // Clear unread notifications for this chat
    final notifsToRead = notifications.where((n) => n['type'] == 'chat' && n['chatId'] == chatId).toList();
    for (final notif in notifsToRead) {
      final notifId = notif['id'] as String?;
      if (notifId != null) {
        markNotificationReadJs(notifId);
      }
    }
    listenToChatJs(chatId, (String jsonStr) {
      try {
        final raw = jsonDecode(jsonStr) as List<dynamic>;
        setState(() {
          chatMessages = raw.map((m) {
            final map = Map<String, dynamic>.from(m as Map);
            // Normalize Firestore timestamp
            if (map['createdAt'] is Map) {
              final ts = map['createdAt'] as Map;
              map['createdAt'] = (ts['_seconds'] as int? ?? 0) * 1000 + ((ts['_nanoseconds'] as int? ?? 0) ~/ 1000000);
            }
            return map;
          }).toList();
        });
      } catch (_) {}
    });
  }

  void closeChat() {
    if (currentChatId.isNotEmpty) unlistenChatJs(currentChatId);
    setState(() {
      showChat = false;
      currentChatId = '';
      chatMessages = [];
      chatInputText = '';
      chatPiiBlocked = false;
    });
  }

  void sendChatMessage() {
    final uid = SessionStorage.uid;
    if (uid == null || currentChatId.isEmpty || chatInputText.trim().isEmpty) return;
    final text = chatInputText.trim();
    final name = userProfile?.name ?? userName;
    final result = sendChatMessageJs(currentChatId, uid, name, text);
    if (result == 'pii_blocked') {
      setState(() => chatPiiBlocked = true);
      Timer(const Duration(seconds: 4), () {
        setState(() => chatPiiBlocked = false);
      });
      return;
    }
    if (result == 'disintermediation_blocked') {
      setState(() => chatDisintermediationBlocked = true);
      Timer(const Duration(seconds: 6), () {
        setState(() => chatDisintermediationBlocked = false);
      });
      return;
    }
    setState(() {
      chatInputText = '';
      chatPiiBlocked = false;
      chatDisintermediationBlocked = false;
    });
  }

  Future<void> sendChatPhoto(dynamic event) async {
    final uid = SessionStorage.uid;
    if (uid == null || currentChatId.isEmpty) return;
    setState(() => isUploadingChatPhoto = true);
    try {
      final files = await readFilesFromEvent(event);
      if (files.isEmpty) return;
      final file = files.first;
      final name = userProfile?.name ?? userName;
      final b64 = base64Encode(file.bytes);
      final mime = file.name.endsWith('.png') ? 'image/png' : 'image/jpeg';
      final url = await uploadChatPhotoJs(currentChatId, b64, mime);
      if (url != null) {
        sendChatMessageJs(currentChatId, uid, name, '', photoUrl: url);
      }
    } catch (_) {
    } finally {
      setState(() => isUploadingChatPhoto = false);
    }
  }

  Future<void> submitJobReport() async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    final jobId = selectedJobData?['id'] as String? ?? '';
    final employerId = selectedJobData?['creatorId'] as String? ?? '';
    if (token == null || uid == null || jobId.isEmpty || employerId.isEmpty || selectedReportReason.isEmpty) return;

    setState(() => isSubmittingReport = true);
    try {
      await FirestoreService(token, _handleTokenRefresh).reportJob(jobId, employerId, uid, selectedReportReason);
      setState(() {
        isSubmittingReport = false;
        showReportModal = false;
        jobsView = JobsView.success; // Or a specific report success state
      });
    } catch (_) {
      setState(() => isSubmittingReport = false);
    }
  }

  Future<void> checkJobAuthenticity() async {
    if (_gemini == null || selectedJobData == null) return;

    setState(() {
      showAuthenticityModal = true;
      isCheckingAuthenticity = true;
      authenticityResult = null;
    });

    try {
      final res = await _gemini!.evaluateJobAuthenticity(selectedJobData!);
      setState(() {
        authenticityResult = res;
        isCheckingAuthenticity = false;
      });
    } catch (_) {
      setState(() {
        authenticityResult = 'Failed to check authenticity. Please try again.';
        isCheckingAuthenticity = false;
      });
    }
  }

  Future<void> viewEmployerProfile(String employerId) async {
    final token = SessionStorage.idToken;
    if (token == null) return;

    setState(() {
      showEmployerProfileModal = true;
      isLoadingEmployerProfile = true;
      employerProfileData = null;
    });

    try {
      final doc = await FirestoreService(token, _handleTokenRefresh).getDocument('users/$employerId');
      setState(() {
        employerProfileData = doc;
        isLoadingEmployerProfile = false;
      });
    } catch (_) {
      setState(() => isLoadingEmployerProfile = false);
    }
  }

  // ── Review & Manage Actions ─────────────────────────────────

  Future<void> loadApplicants(String jobId) async {
    final token = SessionStorage.idToken;
    if (token == null) return;
    setState(() => isLoadingApplicants = true);
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final apps = await svc.getApplications(jobId);
      final List<Map<String, dynamic>> enrichedApps = [];
      for (final app in apps) {
        final copy = Map<String, dynamic>.from(app);
        final applicantUid = copy['applicantUid'] as String?;
        if (applicantUid != null) {
          final userDoc = await svc.getDocument('users/$applicantUid');
          if (userDoc != null) {
            copy['isBonded'] = userDoc['isBonded'] as bool? ?? false;
            copy['certificationUrls'] = userDoc['certificationUrls'];
          }
        }
        enrichedApps.add(copy);
      }
      setState(() {
        jobApplicants = enrichedApps;
        isLoadingApplicants = false;
      });
    } catch (e) {
      setState(() => isLoadingApplicants = false);
    }
  }

  Future<void> acceptApplicant(String jobId, Map<String, dynamic> appData) async {
    final token = SessionStorage.idToken;
    final applicantUid = appData['applicantUid'] as String? ?? '';
    if (token == null || applicantUid.isEmpty) return;

    setState(() => isUpdatingJobStatus = true);
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final jobDoc = await svc.getDocument('jobs/$jobId');
      if (jobDoc != null) {
        final updates = <String, dynamic>{
          ...jobDoc,
          'status': 'In Progress',
          'acceptedApplicantId': applicantUid,
        };

        // Use counter offer if provided
        if (appData['isCounterOffer'] == true && appData['proposalRate'] != null) {
          final rate = (appData['proposalRate'] as num).toDouble();
          final originalPrice = (jobDoc['pricingValue'] as num).toDouble();

          if (rate > originalPrice) {
            final diff = rate - originalPrice;
            final uid = SessionStorage.uid;
            final userDoc = await svc.getDocument('users/$uid');
            final currentBal = (userDoc?['tyxBalance'] as num?)?.toDouble() ?? 0.0;

            if (currentBal < diff) {
              setState(() {
                depositAmount = diff - currentBal;
                showDepositModal = true;
                isUpdatingJobStatus = false;

                pendingJobId = jobId;
                pendingApplicantData = appData;
              });
              return;
            } else {
              // Deduct difference from user balance
              await svc.createOrUpdate('users/$uid', {
                ...userDoc!,
                'tyxBalance': currentBal - diff,
              });

              walletBalance = currentBal - diff;
              if (userProfile != null) {
                userProfile = userProfile!.copyWith(tyxBalance: walletBalance);
              }

              // Update escrow amount
              final escrowDoc = await svc.getDocument('escrow/$jobId');
              if (escrowDoc != null) {
                await svc.createOrUpdate('escrow/$jobId', {
                  ...escrowDoc,
                  'amount': rate,
                });
              }
            }
          } else if (rate < originalPrice && rate > 0) {
            // Refund the difference if the counter offer is lower than the original price
            final diff = originalPrice - rate;
            final uid = SessionStorage.uid;
            final userDoc = await svc.getDocument('users/$uid');
            final currentBal = (userDoc?['tyxBalance'] as num?)?.toDouble() ?? 0.0;

            if (userDoc != null) {
              await svc.createOrUpdate('users/$uid', {
                ...userDoc,
                'tyxBalance': currentBal + diff,
              });

              walletBalance = currentBal + diff;
              if (userProfile != null) {
                userProfile = userProfile!.copyWith(tyxBalance: walletBalance);
              }
            }

            // Update escrow amount
            final escrowDoc = await svc.getDocument('escrow/$jobId');
            if (escrowDoc != null) {
              await svc.createOrUpdate('escrow/$jobId', {
                ...escrowDoc,
                'amount': rate,
              });
            }
          }

          if (rate > 0) {
            updates['pricingValue'] = rate;
            updates['pricingType'] = 'Fixed Task'; // or keep previous type
          }
        }

        await svc.createOrUpdate('jobs/$jobId', updates);
        await svc.awardPointsIfEligible(SessionStorage.uid ?? '', 'hire_applicant');
        await svc.awardPointsIfEligible(applicantUid, 'be_hired');

        final jobTitle = jobDoc['title'] as String? ?? 'Job';
        await svc.createNotification(
          uid: applicantUid,
          title: 'Application Accepted',
          message: 'You have been selected for the job "$jobTitle".',
        );
      }
      setState(() => isUpdatingJobStatus = false);
      await loadJobs();
      if (selectedJobData != null) {
        selectJobAndLoadDetails({
          ...selectedJobData!,
          'status': 'In Progress',
          'acceptedApplicantId': applicantUid,
        });
      }
    } catch (e) {
      setState(() => isUpdatingJobStatus = false);
    }
  }

  Future<void> generateCompletionCode() async {
    if (selectedJobData == null) return;
    final jobId = selectedJobData!['id'] as String;
    final token = SessionStorage.idToken;
    if (token == null) return;

    setState(() => isGeneratingCode = true);
    try {
      // Generate a 6-digit numeric code
      final code = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();

      final svc = FirestoreService(token, _handleTokenRefresh);
      await svc.createOrUpdate('jobs/$jobId', {
        ...selectedJobData!,
        'completionCode': code,
      });

      setState(() {
        generatedCompletionCode = code;
        isGeneratingCode = false;
      });
    } catch (_) {
      setState(() => isGeneratingCode = false);
    }
  }

  Future<void> sendCompletionCodeToWorker() async {
    if (selectedJobData == null || generatedCompletionCode == null) return;
    final jobId = selectedJobData!['id'] as String;
    final code = generatedCompletionCode!;
    final uid = SessionStorage.uid;
    if (uid == null) return;
    final name = userProfile?.name ?? userName;
    final text = 'Verification Code: $code. Please use this code to mark the gig as complete.';
    sendChatMessageJs(jobId, uid, name, text);
    showAppToast('Code Sent', 'Verification code sent to the worker via chat.');
  }

  Future<void> handleCompleteJob() async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    final job = selectedJobData;
    if (token == null || job == null || uid == null) return;

    setState(() => isCompletingJob = true);
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final jobDoc = await svc.getDocument('jobs/${job['id']}');

      if (jobDoc != null) {
        final correctCode = jobDoc['completionCode']?.toString() ?? jobDoc['verificationCode']?.toString();
        if (completionScanInput.trim() != correctCode?.trim()) {
          throw 'Invalid completion code. Please try again.';
        }

        final price = (jobDoc['pricingValue'] as num?)?.toDouble() ?? 0.0;
        final nyxianId = jobDoc['acceptedApplicantId'] as String?;

        // 1. Release from Escrow (with graceful developer fallback if document is missing in sandbox)
        final escrowDoc = await svc.getDocument('escrow/${job['id']}');
        if (escrowDoc == null) {
          print(
            'Escrow record not found for job ${job['id']}. Proceeding with graceful fallback using pricing value: $price',
          );
        }

        // Deduct 3% platform commission fee from Nyxian payout
        final platformFee = price * 0.03;
        final nyxianPayout = price - platformFee;

        final hasHoldback = jobDoc['hasInspectionHoldback'] as bool? ?? false;
        final holdbackAmount = hasHoldback ? price * 0.10 : 0.0;
        final immediatePayout = nyxianPayout - holdbackAmount;

        // Add to Nyxian Wallet (Payout only, NO rebate)
        if (nyxianId != null) {
          final txNyxDoc = await svc.getDocument('transactions/payout_nyx_${job['id']}');
          if (txNyxDoc == null) {
            final nyxDoc = await svc.getDocument('users/$nyxianId');
            if (nyxDoc != null) {
              final currentNyxBal = (nyxDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
              final currentJobsDone = nyxDoc['jobsDone'] as int? ?? 0;
              final currentEarned = (nyxDoc['totalEarned'] as num?)?.toDouble() ?? 0.0;
              final gigsCount = (nyxDoc['completedGigsCount'] as int?) ?? 0;
              final newGigsCount = gigsCount + 1;
              final repeatHireRate = newGigsCount > 1 ? 0.35 : 0.0;

              await svc.createOrUpdate('users/$nyxianId', {
                ...nyxDoc,
                'tyxBalance': currentNyxBal + immediatePayout,
                'jobsDone': currentJobsDone + 1,
                'totalEarned': currentEarned + immediatePayout,
                'completedGigsCount': newGigsCount,
                'repeatHireRate': repeatHireRate,
              });

              // Log payout transaction for Nyxian
              await svc.createOrUpdate('transactions/payout_nyx_${job['id']}', {
                'uid': nyxianId,
                'title': 'Gig Payout Released',
                'desc': 'Payout for completing job ${job['id']} (3% commission deducted)',
                'amount': immediatePayout,
                'status': 'Successful',
                'method': 'Tranyx Wallet',
                'createdAt': DateTime.now().millisecondsSinceEpoch,
                'type': 'payout',
              });
            }
          }
        }

        // Create escrow holdback record if enabled
        if (hasHoldback && nyxianId != null) {
          await svc.createOrUpdate('escrow_holdbacks/${job['id']}', {
            'jobId': job['id'],
            'amount': holdbackAmount,
            'nyxianId': nyxianId,
            'employerId': jobDoc['creatorId'],
            'status': 'held',
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'releaseAt': DateTime.now().add(const Duration(hours: 48)).millisecondsSinceEpoch,
          });
        }

        // Deduct fees from Employer Wallet (7% Transaction Fee + 3% Convenience Fee = 10%)
        final employerId = jobDoc['creatorId'] as String?;
        if (employerId != null) {
          final txEmpDoc = await svc.getDocument('transactions/fees_emp_${job['id']}');
          if (txEmpDoc == null) {
            final empDoc = await svc.getDocument('users/$employerId');
            if (empDoc != null) {
              final currentBal = (empDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
              final txFee = price * 0.07;
              final convFee = price * 0.03;
              final totalFees = txFee + convFee;
              await svc.createOrUpdate('users/$employerId', {
                ...empDoc,
                'tyxBalance': currentBal - totalFees,
              });

              // Log fee deduction transaction for Employer
              await svc.createOrUpdate('transactions/fees_emp_${job['id']}', {
                'uid': employerId,
                'title': 'Job Completion Fees (10%)',
                'desc':
                    '7% Transaction Fee (${txFee.toStringAsFixed(2)}) & 3% Convenience Fee (${convFee.toStringAsFixed(2)}) for job ${job['id']}',
                'amount': totalFees,
                'status': 'Successful',
                'method': 'Tranyx Wallet',
                'createdAt': DateTime.now().millisecondsSinceEpoch,
                'type': 'fee_deduction',
              });
            }
          }
        }

        // Record all platform fees and company income (total 13% of base price)
        final txFee = price * 0.07;
        final convFee = price * 0.03;
        final totalCompanyIncome = platformFee + txFee + convFee;
        await svc.createOrUpdate('platform_fees/${job['id']}', {
          'jobId': job['id'],
          'amount': totalCompanyIncome,
          'commissionFee': platformFee, // 3% from Nyxian
          'transactionFee': txFee, // 7% from Employer
          'convenienceFee': convFee, // 3% from Employer
          'employerFees': txFee + convFee, // 10% total from Employer
          'nyxianFee': platformFee, // 3% total from Nyxian
          'totalFees': totalCompanyIncome, // 13% total Company Funds
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        // Delete escrow
        await svc.deleteDocument('escrow/${job['id']}');

        // Mark job as complete
        await svc.createOrUpdate('jobs/${job['id']}', {
          ...jobDoc,
          'status': 'Completed',
        });

        final isCreator = jobDoc['creatorId'] == uid;
        String? targetId;
        String? targetName;
        if (isCreator) {
          targetId = nyxianId;
          if (nyxianId != null) {
            final targetDoc = await svc.getDocument('users/$nyxianId');
            targetName = targetDoc?['name'] as String? ?? 'Nyxian';
          }
        } else {
          targetId = jobDoc['creatorId'] as String?;
          if (targetId != null) {
            final targetDoc = await svc.getDocument('users/$targetId');
            targetName = targetDoc?['name'] as String? ?? 'Employer';
          }
        }

        setState(() {
          isCompletingJob = false;
          showCompletionScanner = false;
          completionScanInput = '';
          if (isCreator) {
            showEmployerFeePopup = true;
          }
          final hasHoldback = jobDoc['hasInspectionHoldback'] as bool? ?? false;
          final holdbackAmount = hasHoldback ? price * 0.10 : 0.0;
          final immediatePayout = nyxianPayout - holdbackAmount;
          if (nyxianId == uid && userProfile != null) {
            userProfile = userProfile!.copyWith(
              tyxBalance: userProfile!.tyxBalance + immediatePayout,
              totalEarned: userProfile!.totalEarned + immediatePayout,
            );
          } else if (jobDoc['creatorId'] == uid && userProfile != null) {
            final txFee = price * 0.07;
            final convFee = price * 0.03;
            final totalFees = txFee + convFee;
            userProfile = userProfile!.copyWith(
              tyxBalance: userProfile!.tyxBalance - totalFees,
            );
          }
          if (targetId != null) {
            showRatingPopup = true;
            ratingTargetId = targetId;
            ratingTargetName = targetName;
            ratingScore = 0;
            ratingComment = '';
          }
        });

        await loadUserProfile();

        // Send a notification to the target user about job completion to trigger rating popup
        if (targetId != null) {
          final prefix = targetId.length > 5 ? targetId.substring(0, 5) : targetId;
          final docId = 'notif_${DateTime.now().millisecondsSinceEpoch}_$prefix';
          await svc.createOrUpdate('notifications/$docId', {
            'uid': targetId,
            'title': 'Gig Completed 🎉',
            'message': '${userProfile?.name ?? "Someone"} has completed "${job['title']}". Click to rate them.',
            'type': 'job_completed',
            'jobId': job['id'],
            'senderUid': SessionStorage.uid,
            'senderName': userProfile?.name ?? 'User',
            'isRead': false,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }
      await loadJobs();
      if (selectedJobData != null) {
        selectJobAndLoadDetails({
          ...selectedJobData!,
          'status': 'Completed',
        });
      }
    } catch (e) {
      setState(() {
        isCompletingJob = false;
        profileSaveError = e.toString();
      });
      showAppToast('Verification Error', e.toString());
    }
  }

  Future<void> handleQrVerificationParams() async {
    final params = getUrlQueryParams();
    final action = params['action'];
    final qJobId = params['jobId'];
    final qCode = params['code'];

    if (action == 'verify_qr' && qJobId != null && qCode != null) {
      clearUrlParams();

      SessionStorage.pendingQrJobId = qJobId;
      SessionStorage.pendingQrCode = qCode;
      pendingQrJobId = qJobId;
      pendingQrCode = qCode;

      final uid = SessionStorage.uid;
      final email = SessionStorage.email ?? userProfile?.email ?? '';
      final name = SessionStorage.displayName ?? userProfile?.name ?? '';
      final isAnonymous = uid == null || email.isEmpty || email.contains('anonymous') || name == 'Anonymous';

      if (!isAuthenticated || isAnonymous) {
        if (isAuthenticated) {
          handleLogout();
        }
        setState(() {
          authView = AuthView.login;
          authError = 'Please log in with your registered Nyxian account to verify the QR code payment.';
        });
        showAppToast('Login Required', 'Please log in to verify the QR code and receive payment.');
      } else {
        await executePendingQrVerification();
      }
    }
  }

  Future<void> executePendingQrVerification() async {
    final jobId = pendingQrJobId;
    final code = pendingQrCode;
    if (jobId == null || code == null) return;

    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    if (token == null || uid == null) return;

    showAppToast('Verifying QR Code', 'Validating payment release...');

    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final jobDoc = await svc.getDocument('jobs/$jobId');

      if (jobDoc == null) {
        throw 'Job not found.';
      }

      final status = (jobDoc['status'] as String? ?? '').toLowerCase();
      if (status == 'completed') {
        throw 'This job is already completed.';
      }

      // Check verification/completion code
      final correctCode = jobDoc['completionCode']?.toString() ?? jobDoc['verificationCode']?.toString();
      if (code.trim() != correctCode?.trim()) {
        throw 'Invalid or expired verification code.';
      }

      // Check if logged user is authorized to verify completion based on hasTracker
      final catName = (jobDoc['category'] as String? ?? '').toLowerCase();
      final cat = JobCategory.values.firstWhere(
        (e) => e.name.toLowerCase() == catName || e.label.toLowerCase() == catName,
        orElse: () => JobCategory.others,
      );
      final hasTracker = jobDoc['hasTracker'] == true || jobDoc['hasTracker'] == 'true' || cat.hasTracker;

      final nyxianId = jobDoc['acceptedApplicantId'] as String? ?? jobDoc['nyxianId'] as String?;
      final employerId = jobDoc['creatorId'] as String?;

      if (hasTracker) {
        if (employerId != uid) {
          throw 'Verification failed: You are not the Employer for this job.';
        }
      } else {
        if (nyxianId != uid) {
          throw 'Verification failed: You are not the assigned Nyxian for this job.';
        }
      }

      // Release payment from escrow and credit the Nyxian
      final price = (jobDoc['pricingValue'] as num?)?.toDouble() ?? 0.0;
      final platformFee = price * 0.03;
      double actualPlatformFee = platformFee;

      String? redeemedPromoCode;
      if (nyxianId != null) {
        final nyxDoc = await svc.getDocument('users/$nyxianId');
        if (nyxDoc != null) {
          redeemedPromoCode = nyxDoc['activePromoCode'] as String?;
          if (redeemedPromoCode != null) {
            final discountVal = (nyxDoc['activePromoDiscountValue'] as num?)?.toDouble() ?? 0.0;
            final discountType = nyxDoc['activePromoDiscountType'] as String? ?? 'flat';
            double discountAmt = 0.0;
            if (discountType == 'percentage') {
              discountAmt = platformFee * (discountVal / 100.0);
            } else {
              discountAmt = discountVal;
            }
            actualPlatformFee = (platformFee - discountAmt).clamp(0.0, platformFee);
          }
        }
      }

      final nyxianPayout = price - actualPlatformFee;
      final hasHoldback = jobDoc['hasInspectionHoldback'] as bool? ?? false;
      final holdbackAmount = hasHoldback ? price * 0.10 : 0.0;
      final immediatePayout = nyxianPayout - holdbackAmount;

      // 1. Release escrow
      await svc.deleteDocument('escrow/$jobId');

      // 1.1 Create escrow holdback record if enabled
      if (hasHoldback) {
        await svc.createOrUpdate('escrow_holdbacks/$jobId', {
          'jobId': jobId,
          'amount': holdbackAmount,
          'nyxianId': nyxianId,
          'employerId': employerId,
          'status': 'held',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'releaseAt': DateTime.now().add(const Duration(hours: 48)).millisecondsSinceEpoch,
        });
      }

      // 2. Add to Nyxian Wallet (Payout only, NO rebate)
      final txNyxDoc = await svc.getDocument('transactions/payout_nyx_$jobId');
      if (txNyxDoc == null) {
        if (nyxianId != null) {
          final nyxDoc = await svc.getDocument('users/$nyxianId');
          if (nyxDoc != null) {
            final currentNyxBal = (nyxDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            final currentJobsDone = nyxDoc['jobsDone'] as int? ?? 0;
            final currentEarned = (nyxDoc['totalEarned'] as num?)?.toDouble() ?? 0.0;
            final gigsCount = (nyxDoc['completedGigsCount'] as int?) ?? 0;
            final newGigsCount = gigsCount + 1;
            final repeatHireRate = newGigsCount > 1 ? 0.35 : 0.0;

            await svc.createOrUpdate('users/$nyxianId', {
              ...nyxDoc,
              'tyxBalance': currentNyxBal + immediatePayout,
              'jobsDone': currentJobsDone + 1,
              'totalEarned': currentEarned + immediatePayout,
              'completedGigsCount': newGigsCount,
              'repeatHireRate': repeatHireRate,
              if (redeemedPromoCode != null) 'activePromoCode': null,
              if (redeemedPromoCode != null) 'activePromoDiscountType': null,
              if (redeemedPromoCode != null) 'activePromoDiscountValue': null,
            });

            // Increment promo usage
            if (redeemedPromoCode != null) {
              await svc.incrementPromoUsage(redeemedPromoCode, nyxianId);
            }

            // Log payout transaction for Nyxian
            await svc.createOrUpdate('transactions/payout_nyx_$jobId', {
              'uid': nyxianId,
              'title': 'Gig Payout Released',
              'desc': 'Payout for completing job $jobId (3% commission deducted${redeemedPromoCode != null ? ' - Promo $redeemedPromoCode applied' : ''})',
              'amount': immediatePayout,
              'status': 'Successful',
              'method': 'Tranyx Wallet',
              'createdAt': DateTime.now().millisecondsSinceEpoch,
              'type': 'payout',
            });
          }
        }
      }

      // 2.1 Deduct fees from Employer Wallet (7% Transaction Fee + 3% Convenience Fee = 10%)
      if (employerId != null) {
        final txEmpDoc = await svc.getDocument('transactions/fees_emp_$jobId');
        if (txEmpDoc == null) {
          final empDoc = await svc.getDocument('users/$employerId');
          if (empDoc != null) {
            final currentBal = (empDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            final discount = (jobDoc['discountAmount'] as num?)?.toDouble() ?? 0.0;
            final discountedPrice = (price - discount).clamp(0.0, 999999.0);
            final txFee = discountedPrice * 0.07;
            final convFee = discountedPrice * 0.03;
            final totalFees = txFee + convFee;
            await svc.createOrUpdate('users/$employerId', {
              ...empDoc,
              'tyxBalance': currentBal - totalFees,
            });

            // Log fee deduction transaction for Employer
            await svc.createOrUpdate('transactions/fees_emp_$jobId', {
              'uid': employerId,
              'title': 'Job Completion Fees (10%)',
              'desc':
                  '7% Transaction Fee (${txFee.toStringAsFixed(2)}) & 3% Convenience Fee (${convFee.toStringAsFixed(2)}) for job $jobId${discount > 0 ? ' (Discounted base of ₱${discountedPrice.toStringAsFixed(2)} applied)' : ''}',
              'amount': totalFees,
              'status': 'Successful',
              'method': 'Tranyx Wallet',
              'createdAt': DateTime.now().millisecondsSinceEpoch,
              'type': 'fee_deduction',
            });
          }
        }
      }

      // 3. Record all platform fees and company income (total 13% of base price)
      final discount = (jobDoc['discountAmount'] as num?)?.toDouble() ?? 0.0;
      final discountedPrice = (price - discount).clamp(0.0, 999999.0);
      final txFee = discountedPrice * 0.07;
      final convFee = discountedPrice * 0.03;
      final totalCompanyIncome = actualPlatformFee + txFee + convFee;
      await svc.createOrUpdate('platform_fees/$jobId', {
        'jobId': jobId,
        'amount': totalCompanyIncome,
        'commissionFee': actualPlatformFee, // 3% from Nyxian
        'transactionFee': txFee, // 7% from Employer
        'convenienceFee': convFee, // 3% from Employer
        'employerFees': txFee + convFee, // 10% total from Employer
        'nyxianFee': actualPlatformFee, // 3% total from Nyxian
        'totalFees': totalCompanyIncome, // 13% total Company Funds
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // 4. Mark job as complete
      await svc.createOrUpdate('jobs/$jobId', {
        ...jobDoc,
        'status': 'Completed',
      });

      if (employerId != null) {
        await svc.awardPointsIfEligible(employerId, 'employer_complete_transaction');
      }
      if (nyxianId != null) {
        await svc.awardPointsIfEligible(nyxianId, 'jobseeker_complete_transaction');
      }

      // Update local state
      setState(() {
        pendingQrJobId = null;
        pendingQrCode = null;
      });
      SessionStorage.pendingQrJobId = null;
      SessionStorage.pendingQrCode = null;

      showAppToast('Payment Released! 🎉', '₱ ${nyxianPayout.toStringAsFixed(2)} has been credited to your wallet.');

      // Send a notification to the other party about job completion to trigger rating popup
      final targetUser = (uid == employerId) ? nyxianId : employerId;
      if (targetUser != null) {
        final prefix = targetUser.length > 5 ? targetUser.substring(0, 5) : targetUser;
        final docId = 'notif_${DateTime.now().millisecondsSinceEpoch}_$prefix';
        await svc.createOrUpdate('notifications/$docId', {
          'uid': targetUser,
          'title': 'Gig Completed 🎉',
          'message': '${userProfile?.name ?? "Someone"} has completed "${jobDoc['title']}". Click to rate them.',
          'type': 'job_completed',
          'jobId': jobId,
          'senderUid': uid,
          'senderName': userProfile?.name ?? 'User',
          'isRead': false,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // Reload profile & lists
      await loadUserProfile();
      await loadJobs();

      // Show details & rating popup for the scanning user
      final updatedJob = await svc.getDocument('jobs/$jobId');
      if (updatedJob != null) {
        setState(() {
          selectedJobData = {'id': jobId, ...updatedJob};
          final isCreator = updatedJob['creatorId'] == uid;
          final ratingTarget = isCreator ? nyxianId : employerId;
          final ratingName = isCreator
              ? (updatedJob['acceptedApplicantName'] as String? ?? 'Nyxian')
              : (updatedJob['creatorName'] as String? ?? 'Employer');

          if (ratingTarget != null) {
            showRatingPopup = true;
            ratingTargetId = ratingTarget;
            ratingTargetName = ratingName;
            ratingScore = 0;
            ratingComment = '';
          }
        });
      }
    } catch (e) {
      setState(() {
        pendingQrJobId = null;
        pendingQrCode = null;
      });
      SessionStorage.pendingQrJobId = null;
      SessionStorage.pendingQrCode = null;
      showAppToast('Verification Error', e.toString());
    }
  }

  Future<void> handleConfirmRating(int score, String comment) async {
    final token = SessionStorage.idToken;
    final targetId = ratingTargetId;
    if (token == null || targetId == null) return;

    setState(() => isSubmittingRating = true);
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final targetDoc = await svc.getDocument('users/$targetId');
      if (targetDoc != null) {
        final currentRating = (targetDoc['rating'] as num?)?.toDouble() ?? 0.0;
        final currentRatingCount = targetDoc['ratingCount'] as int? ?? 0;

        final double newRating;
        if (currentRatingCount == 0) {
          newRating = score.toDouble();
        } else {
          newRating = ((currentRating * currentRatingCount) + score) / (currentRatingCount + 1);
        }

        await svc.createOrUpdate('users/$targetId', {
          ...targetDoc,
          'rating': newRating,
          'ratingCount': currentRatingCount + 1,
        });

        final jobId = selectedJobData?['id'] as String? ?? 'job_review';
        await svc.createOrUpdate('users/$targetId/reviews/$jobId', {
          'reviewerId': SessionStorage.uid,
          'reviewerName': userProfile?.name ?? 'User',
          'score': score,
          'comment': comment,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        // Also update the job document
        final jId = selectedJobData?['id'] as String?;
        if (jId != null) {
          final jobDoc = await svc.getDocument('jobs/$jId');
          if (jobDoc != null) {
            final isEmployerRole = currentViewMode == AccountType.employer;
            final isNyxianRole = currentViewMode == AccountType.nyxian;

            await svc.createOrUpdate('jobs/$jId', {
              ...jobDoc,
              if (isEmployerRole) 'employerRated': true,
              if (isNyxianRole) 'nyxianRated': true,
            });

            // Update local state immediately so UI refreshes without reopening job details
            if (selectedJobData != null && selectedJobData!['id'] == jId) {
              selectedJobData = {
                ...selectedJobData!,
                if (isEmployerRole) 'employerRated': true,
                if (isNyxianRole) 'nyxianRated': true,
              };
            }
          }
        }
      }

      setState(() {
        showRatingPopup = false;
        ratingTargetId = null;
        ratingTargetName = null;
        isSubmittingRating = false;
      });
      await loadJobs();
    } catch (e) {
      setState(() {
        isSubmittingRating = false;
        showRatingPopup = false;
      });
    }
  }

  void handleSkipRating() {
    setState(() {
      showRatingPopup = false;
      ratingTargetId = null;
      ratingTargetName = null;
    });
  }

  Future<void> handleCancelJob() async {
    final token = SessionStorage.idToken;
    final job = selectedJobData;
    if (token == null || job == null) return;

    setState(() => isUpdatingJobStatus = true);
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final jobDoc = await svc.getDocument('jobs/${job['id']}');

      if (jobDoc != null) {
        final employerId = jobDoc['creatorId'] as String?;
        final nyxianId = jobDoc['acceptedApplicantId'] as String?;

        final catName = (jobDoc['category'] as String? ?? '').toLowerCase();
        final cat = JobCategory.values.firstWhere(
          (e) => e.name.toLowerCase() == catName || e.label.toLowerCase() == catName,
          orElse: () => JobCategory.others,
        );
        final hasTracker = jobDoc['hasTracker'] == true || jobDoc['hasTracker'] == 'true' || cat.hasTracker;

        final status = (jobDoc['status'] as String? ?? '').toLowerCase();
        final reachedFirstPoint =
            hasTracker &&
            (status == 'arrived_pickup' ||
                status == 'paid_cashier' ||
                status == 'in_transit' ||
                status == 'arrived_dropoff' ||
                status == 'done' ||
                status == 'completed');

        // 1. Check for escrow
        final escrowDoc = await svc.getEscrow(job['id'] as String);
        if (escrowDoc != null && employerId != null) {
          final totalEscrow = (escrowDoc['amount'] as num?)?.toDouble() ?? 0.0;
          final double compensation = reachedFirstPoint ? (totalEscrow >= 20.0 ? 20.0 : totalEscrow) : 0.0;
          final refundAmount = totalEscrow - compensation;

          // 2. Refund to Employer
          if (refundAmount > 0.0) {
            final empDoc = await svc.getDocument('users/$employerId');
            if (empDoc != null) {
              final currentBal = (empDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
              final newBal = currentBal + refundAmount;

              await svc.createOrUpdate('users/$employerId', {
                ...empDoc,
                'tyxBalance': newBal,
              });

              // Update local balance if current user is the employer
              if (employerId == SessionStorage.uid) {
                walletBalance = newBal;
                if (userProfile != null) {
                  userProfile = userProfile!.copyWith(tyxBalance: newBal);
                }
              }
            }
          }

          // 3. Compensation to Nyxian
          if (compensation > 0.0 && nyxianId != null) {
            final nyxDoc = await svc.getDocument('users/$nyxianId');
            if (nyxDoc != null) {
              final nyxBal = (nyxDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
              final newNyxBal = nyxBal + compensation;

              await svc.createOrUpdate('users/$nyxianId', {
                ...nyxDoc,
                'tyxBalance': newNyxBal,
              });

              // Update local balance if current user is the Nyxian
              if (nyxianId == SessionStorage.uid) {
                walletBalance = newNyxBal;
                if (userProfile != null) {
                  userProfile = userProfile!.copyWith(tyxBalance: newNyxBal);
                }
              }
            }
          }

          // 4. Delete escrow
          await svc.deleteDocument('escrow/${job['id']}');
        }

        // 5. Update Job Status
        await svc.updateJobStatus(job['id'] as String, 'Cancelled');
      }

      setState(() => isUpdatingJobStatus = false);
      await loadJobs();
      if (selectedJobData != null) {
        selectJobAndLoadDetails({
          ...selectedJobData!,
          'status': 'Cancelled',
        });
      }
    } catch (e) {
      setState(() => isUpdatingJobStatus = false);
    }
  }

  void handleRedeemProfilePromo(String code) async {
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      setState(() {
        profilePromoFeedback = 'Please enter a promo code.';
      });
      return;
    }

    setState(() {
      isValidatingProfilePromo = true;
      profilePromoFeedback = null;
    });

    try {
      final token = SessionStorage.idToken;
      final uid = SessionStorage.uid;
      if (token == null || uid == null) throw Exception('User not logged in');

      final svc = FirestoreService(token, _handleTokenRefresh);
      if (userProfile != null && userProfile!.disabledPromos.contains(cleanCode)) {
        setState(() {
          profilePromoFeedback = 'You have disabled this promotion and cannot re-enable it.';
        });
        return;
      }

      final promo = await svc.getPromo(cleanCode);
      if (promo == null) {
        setState(() {
          profilePromoFeedback = 'Promo code not found.';
        });
        return;
      }

      final now = DateTime.now();
      if (!promo.isActive) {
        setState(() {
          profilePromoFeedback = 'This promo code is inactive.';
        });
        return;
      }
      if (promo.expirationDate != null && promo.expirationDate!.isBefore(now)) {
        setState(() {
          profilePromoFeedback = 'This promo code has expired.';
        });
        return;
      }
      if (promo.maxUsers != null && promo.usedCount >= promo.maxUsers!) {
        setState(() {
          profilePromoFeedback = 'This promo code has reached its maximum usage limit.';
        });
        return;
      }
      if (promo.isSingleUsePerUser && promo.usedBy.contains(uid)) {
        setState(() {
          profilePromoFeedback = 'You have already used this promo code.';
        });
        return;
      }
      if (promo.eligibleUserUids != null &&
          promo.eligibleUserUids!.isNotEmpty &&
          !promo.eligibleUserUids!.contains(uid)) {
        setState(() {
          profilePromoFeedback = 'You are not eligible for this promo code.';
        });
        return;
      }

      if (userProfile == null) throw Exception('Profile not loaded');
      if (promo.onlyForSubscribed && !userProfile!.isPremium) {
        setState(() {
          profilePromoFeedback = 'This promo code is only for subscribed premium users.';
        });
        return;
      }
      if (promo.onlyForHybrid && userProfile!.accountType != AccountType.hybrid) {
        setState(() {
          profilePromoFeedback = 'This promo code is only for Hybrid PRO accounts.';
        });
        return;
      }

      if (promo.applicableRoles.isNotEmpty) {
        final userRoles = <String>[];
        if (userProfile!.accountType == AccountType.employer) {
          userRoles.addAll(['renter', 'employer']);
        } else if (userProfile!.accountType == AccountType.nyxian) {
          userRoles.addAll(['host', 'nyxian']);
        } else if (userProfile!.accountType == AccountType.hybrid) {
          userRoles.addAll(['renter', 'host', 'employer', 'nyxian']);
        }
        final roleMatched = promo.applicableRoles.any((r) => userRoles.contains(r));
        if (!roleMatched) {
          setState(() {
            profilePromoFeedback = 'This promo is not applicable to your account role.';
          });
          return;
        }
      }

      await svc.redeemPromoToProfile(promo.code, uid);
      final updatedProfile = await svc.getUser(uid);
      setState(() {
        userProfile = updatedProfile;
        profilePromoFeedback = 'Promo code "${promo.code}" redeemed successfully!';
      });
    } catch (e) {
      setState(() {
        profilePromoFeedback = 'Failed to redeem promo code: $e';
      });
    } finally {
      setState(() {
        isValidatingProfilePromo = false;
      });
    }
  }

  void handleDisableProfilePromo(String code) async {
    final cleanCode = code.trim().toUpperCase();
    final confirm = web.window.confirm('Are you sure you want to disable the promo code "$cleanCode"? Once disabled, you will lose the discount and can never re-enable or redeem it again.');
    if (!confirm) return;

    setState(() {
      isValidatingProfilePromo = true;
      profilePromoFeedback = null;
    });

    try {
      final token = SessionStorage.idToken;
      final uid = SessionStorage.uid;
      if (token == null || uid == null) throw Exception('User not logged in');

      final svc = FirestoreService(token, _handleTokenRefresh);
      await svc.disablePromoForUser(cleanCode, uid);
      final updatedProfile = await svc.getUser(uid);
      setState(() {
        userProfile = updatedProfile;
        profilePromoFeedback = 'Promo code "$cleanCode" disabled permanently.';
      });
    } catch (e) {
      setState(() {
        profilePromoFeedback = 'Failed to disable promo: $e';
      });
    } finally {
      setState(() {
        isValidatingProfilePromo = false;
      });
    }
  }

  Future<void> handleDeletePosting(String jobId) async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    if (token == null || uid == null || jobId.isEmpty) return;

    setState(() => isUpdatingJobStatus = true);
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final jobDoc = await svc.getDocument('jobs/$jobId');

      if (jobDoc == null) {
        throw 'Job posting not found';
      }

      // Check permissions
      if (jobDoc['creatorId'] != uid) {
        throw 'You are not authorized to delete this posting';
      }

      // Check status: only Open jobs can be deleted/cancelled
      final status = (jobDoc['status'] as String? ?? '').toLowerCase();
      if (status != 'open') {
        throw 'Only open job postings can be deleted';
      }

      // 1. Check for escrow
      final escrowDoc = await svc.getEscrow(jobId);
      double refundAmount = 0.0;
      if (escrowDoc != null) {
        refundAmount = (escrowDoc['amount'] as num?)?.toDouble() ?? 0.0;

        // 2. Refund to Employer
        final empDoc = await svc.getDocument('users/$uid');
        if (empDoc != null) {
          final currentBal = (empDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
          final newBal = currentBal + refundAmount;

          await svc.createOrUpdate('users/$uid', {
            ...empDoc,
            'tyxBalance': newBal,
          });

          // Update local balance
          walletBalance = newBal;
          if (userProfile != null) {
            userProfile = userProfile!.copyWith(tyxBalance: newBal);
          }
        }

        // Revert promo usage
        final promoCode = jobDoc['promoCode'] as String?;
        if (promoCode != null) {
          await svc.decrementPromoUsage(promoCode, uid);
        }

        // 3. Delete escrow document
        await svc.deleteDocument('escrow/$jobId');
      }

      // 4. Delete the job document
      await svc.deleteDocument('jobs/$jobId');

      // Update local lists
      myJobs.removeWhere((j) => j['id'] == jobId);
      sessionPostedJobs.removeWhere((j) => j['id'] == jobId);

      setState(() {
        isUpdatingJobStatus = false;
        showDeleteConfirm = false;
        jobsView = JobsView.list;
        selectedJob = null;
        selectedJobData = null;
      });

      _stopSelectedJobRealtime();
      showAppToast(
        'Posting Deleted',
        'Job posting has been deleted and the ₱ ${refundAmount.toStringAsFixed(0)} held escrow has been returned to your balance.',
      );
    } catch (e) {
      setState(() {
        isUpdatingJobStatus = false;
        showDeleteConfirm = false;
      });
      showAppToast('Error Deleting Posting', e.toString());
    }
  }

  /// Nyxian marks a standard job as Done (triggers Employer to generate QR).
  Future<void> handleMarkJobDone() async {
    final token = SessionStorage.idToken;
    final job = selectedJobData;
    if (token == null || job == null) return;
    setState(() => isUpdatingSubStatus = true);
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      await svc.updateJobStatus(job['id'] as String, 'Done');
      setState(() {
        isUpdatingSubStatus = false;
        selectedJobData = {...selectedJobData!, 'status': 'Done'};
      });
      await loadJobs();
    } catch (_) {
      setState(() => isUpdatingSubStatus = false);
    }
  }

  /// Nyxian calls this to advance a delivery job to the next checkpoint.
  /// [newStatus] must be one of:
  ///   'arrived_pickup' | 'paid_cashier' | 'in_transit' | 'arrived_dropoff'
  Future<void> handleUpdateNyxianSubStatus(String newStatus) async {
    final token = SessionStorage.idToken;
    final job = selectedJobData;
    if (token == null || job == null) return;
    setState(() => isUpdatingSubStatus = true);
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final jobDoc = await svc.getDocument('jobs/${job['id']}');
      if (jobDoc != null) {
        final updates = <String, dynamic>{
          ...jobDoc,
          'status': newStatus,
          // Attach receipt URL when transitioning to paid_cashier
          if (newStatus == 'paid_cashier' && receiptPhotoUrl != null) 'receiptUrl': receiptPhotoUrl,
        };
        await svc.createOrUpdate('jobs/${job['id']}', updates);
      }
      setState(() {
        isUpdatingSubStatus = false;
        selectedJobData = {
          ...selectedJobData!,
          'status': newStatus,
          if (newStatus == 'paid_cashier' && receiptPhotoUrl != null) 'receiptUrl': receiptPhotoUrl,
        };
        if (newStatus == 'paid_cashier') receiptPhotoUrl = null;
      });
      await loadJobs();
    } catch (_) {
      setState(() => isUpdatingSubStatus = false);
    }
  }

  /// Upload a delivery receipt photo (used at the paid_cashier step).
  Future<void> handleReceiptUpload(dynamic eventTarget) async {
    final token = SessionStorage.idToken;
    if (token == null) return;
    setState(() => isUploadingReceipt = true);
    try {
      final files = await readFilesFromEvent(eventTarget);
      if (files.isNotEmpty) {
        final file = files.first;
        final url = await ImgBBService(
          currentFirebaseConfig,
          idToken: token,
          onTokenRefresh: _handleTokenRefresh,
        ).uploadImageBytes(file.bytes, file.name);
        if (url != null) {
          setState(() => receiptPhotoUrl = url);
        }
      }
    } catch (_) {
    } finally {
      setState(() => isUploadingReceipt = false);
    }
  }

  /// Upload skill certificate and append to user's certification list
  Future<void> uploadCertification(dynamic eventTarget) async {
    final token = SessionStorage.idToken;
    final uid = SessionStorage.uid;
    if (token == null || uid == null) return;

    setState(() => isUploadingCertificate = true);

    try {
      final files = await readFilesFromEvent(eventTarget);
      if (files.isNotEmpty) {
        final file = files.first;
        final url = await ImgBBService(currentFirebaseConfig, idToken: token).uploadImageBytes(file.bytes, file.name);
        if (url != null) {
          final svc = FirestoreService(token, _handleTokenRefresh);
          final userDoc = await svc.getDocument('users/$uid');
          if (userDoc != null) {
            final List<String> currentCerts = List<String>.from(userDoc['certificationUrls'] ?? []);
            if (currentCerts.length < 3) {
              currentCerts.add(url);
              await svc.createOrUpdate('users/$uid', {
                ...userDoc,
                'certificationUrls': currentCerts,
              });
              await loadUserProfile();
              showAppToast('Upload Successful! 🎓', 'Your credential has been uploaded and verified.');
            } else {
              showAppToast('Limit Reached', 'You can upload up to 3 certification credentials.');
            }
          }
        }
      }
    } catch (e) {
      print('uploadCertification error: $e');
    } finally {
      setState(() => isUploadingCertificate = false);
    }
  }

  void _loadOfflineLocationBuffer() {
    final s = SessionStorage.offlineLocationBuffer;
    if (s != null && s.isNotEmpty) {
      try {
        final decoded = jsonDecode(s) as List;
        offlineLocationBuffer = decoded.map((e) => Map<String, double>.from(e as Map)).toList();
      } catch (_) {}
    }
  }

  void _saveOfflineLocationBuffer() {
    SessionStorage.offlineLocationBuffer = jsonEncode(offlineLocationBuffer);
  }

  /// Nyxian's browser calls this to broadcast their GPS position.
  Future<void> broadcastNyxianLocation(double lat, double lng) async {
    final token = SessionStorage.idToken;
    final job = selectedJobData;
    if (token == null || job == null) return;

    _loadOfflineLocationBuffer();

    try {
      final svc = FirestoreService(token, _handleTokenRefresh);

      if (offlineLocationBuffer.isNotEmpty) {
        print('Connection recovered! Syncing ${offlineLocationBuffer.length} offline coordinates...');
        final List<Map<String, dynamic>> routeHistory = [];
        final jobDoc = await svc.getDocument('jobs/${job['id']}');
        if (jobDoc != null) {
          final existingHistory = jobDoc['routeHistory'] as List?;
          if (existingHistory != null) {
            routeHistory.addAll(existingHistory.map((e) => Map<String, dynamic>.from(e as Map)));
          }

          for (final coord in offlineLocationBuffer) {
            routeHistory.add({
              'lat': coord['lat'],
              'lng': coord['lng'],
              'timestamp': coord['timestamp']?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
            });
          }

          routeHistory.add({
            'lat': lat,
            'lng': lng,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });

          await svc.createOrUpdate('jobs/${job['id']}', {
            ...jobDoc,
            'nyxianLat': lat,
            'nyxianLng': lng,
            'routeHistory': routeHistory,
          });

          offlineLocationBuffer.clear();
          _saveOfflineLocationBuffer();
          print('Offline coordinates synced successfully.');
        }
      } else {
        final jobDoc = await svc.getDocument('jobs/${job['id']}');
        if (jobDoc != null) {
          final List<Map<String, dynamic>> routeHistory = [];
          final existingHistory = jobDoc['routeHistory'] as List?;
          if (existingHistory != null) {
            routeHistory.addAll(existingHistory.map((e) => Map<String, dynamic>.from(e as Map)));
          }
          routeHistory.add({
            'lat': lat,
            'lng': lng,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });

          await svc.createOrUpdate('jobs/${job['id']}', {
            ...jobDoc,
            'nyxianLat': lat,
            'nyxianLng': lng,
            'routeHistory': routeHistory,
          });
        }
      }
    } catch (e) {
      print('Network drop detected. Buffering location locally: ($lat, $lng)');
      offlineLocationBuffer.add({
        'lat': lat,
        'lng': lng,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      });
      _saveOfflineLocationBuffer();
    }
  }

  Future<void> handleApplyJob() async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    final jobId = selectedJobData?['id'] as String? ?? '';
    if (uid == null || token == null || jobId.isEmpty) return;

    setState(() {
      isSubmittingApplication = true;
      applyError = null;
    });
    try {
      await FirestoreService(token, _handleTokenRefresh).applyToJob(
        jobId: jobId,
        applicantUid: uid,
        applicantName: userName.isEmpty ? 'Anonymous' : userName,
        applicantPhotoUrl: userPhotoUrl,
        coverNote: coverNote,
        proposalRate: isCounterOffer ? (double.tryParse(applyPriceRate) ?? 0.0) : 0.0,
        isCounterOffer: isCounterOffer,
      );

      final creatorId = selectedJobData?['creatorId'] as String?;
      if (creatorId != null && creatorId.isNotEmpty) {
        final jobTitle = selectedJobData?['title'] as String? ?? 'Job';
        final appName = userName.isEmpty ? 'Anonymous' : userName;
        await FirestoreService(token, _handleTokenRefresh).createNotification(
          uid: creatorId,
          title: 'New Applicant',
          message: '$appName has applied to your job "$jobTitle".',
        );
      }
      setState(() {
        isSubmittingApplication = false;
        jobsView = JobsView.success;
        coverNote = '';
        applyPriceRate = '';
        isCounterOffer = false;
      });
      await loadJobs();
    } catch (e) {
      setState(() {
        applyError = e.toString();
        isSubmittingApplication = false;
      });
    }
  }

  // ── Profile actions ─────────────────────────────────────────

  bool isUpdatingVerification = false;
  Map<String, dynamic>? activeKycSubmission;
  bool isLoadingKyc = false;
  bool showKycIdModal = false;
  bool showKycBgModal = false;

  void initializeProfileEditing() {
    final profile = userProfile;
    if (profile == null) {
      editName = SessionStorage.displayName ?? userName;
      editEmail = SessionStorage.email ?? userEmail;
      editPhone = '';
      editTaxId = '';
      editHeadline = '';
      editHourlyRate = '';
      editSkills = [];
      editBusinessName = '';
      editIndustry = '';
      profileSaveError = null;
      return;
    }
    editName = profile.name;
    editEmail = profile.email;
    editPhone = getDisplayPhone(profile.phoneNumber);
    editTaxId = profile.taxId ?? '';
    editHeadline = profile.headline ?? '';
    editHourlyRate = profile.hourlyRate?.toString() ?? '';
    editSkills = List<String>.from(profile.skills ?? []);
    editBusinessName = profile.businessName ?? '';
    editIndustry = profile.industry ?? '';
    profileSaveError = null;
  }

  String getDisplayPhone(String? fullPhone) {
    if (fullPhone == null) return '';
    var p = fullPhone.replaceAll('+63', '').replaceAll(RegExp(r'\D'), '');
    if (p.startsWith('0')) p = p.substring(1);
    return p;
  }

  String formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return '${digits.substring(0, 3)} ${digits.substring(3)}';
    return '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
  }

  String formatTIN(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) return '${digits.substring(0, 3)}-${digits.substring(3)}';
    if (digits.length <= 9) return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6, 9)}-${digits.substring(9, digits.length > 12 ? 12 : digits.length)}';
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool get hasPersonalInfoChanges {
    final profile = userProfile;
    if (profile == null) {
      return editName.trim().isNotEmpty && editEmail.trim().isNotEmpty;
    }

    final cleanEditPhone = editPhone.replaceAll(RegExp(r'\D'), '');
    final cleanProfilePhone = (profile.phoneNumber ?? '').replaceAll(RegExp(r'\D'), '');

    final cleanEditTax = editTaxId.replaceAll(RegExp(r'\D'), '');
    final cleanProfileTax = (profile.taxId ?? '').replaceAll(RegExp(r'\D'), '');

    return editName.trim() != profile.name ||
        editEmail.trim() != profile.email ||
        cleanEditPhone != cleanProfilePhone ||
        cleanEditTax != cleanProfileTax;
  }

  bool get isPersonalInfoValid {
    if (editPhone.trim().isNotEmpty) {
      if (!editPhone.trim().startsWith('9') || editPhone.trim().length != 10) {
        return false;
      }
    }
    final digits = editTaxId.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) {
      if (digits.length != 9 && digits.length != 12) {
        return false;
      }
    }
    return editName.trim().isNotEmpty && editEmail.trim().isNotEmpty;
  }

  bool get hasProfessionalInfoChanges {
    final profile = userProfile;
    if (profile == null) {
      return editHeadline.trim().isNotEmpty ||
          editHourlyRate.trim().isNotEmpty ||
          editSkills.isNotEmpty ||
          editBusinessName.trim().isNotEmpty ||
          editIndustry.trim().isNotEmpty ||
          editTaxId.trim().isNotEmpty;
    }
    final skillsChanged = !_listsEqual(editSkills, profile.skills ?? []);
    final cleanEditTax = editTaxId.replaceAll(RegExp(r'\D'), '');
    final cleanProfileTax = (profile.taxId ?? '').replaceAll(RegExp(r'\D'), '');

    return editHeadline.trim() != (profile.headline ?? '') ||
        editHourlyRate.trim() != (profile.hourlyRate?.toString() ?? '') ||
        skillsChanged ||
        editBusinessName.trim() != (profile.businessName ?? '') ||
        editIndustry.trim() != (profile.industry ?? '') ||
        cleanEditTax != cleanProfileTax;
  }

  bool get isProfessionalInfoValid {
    final digits = editTaxId.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) {
      if (digits.length != 9 && digits.length != 12) {
        return false;
      }
    }
    return true;
  }

  int _calculateVerificationLevel({
    required bool email,
    required bool phone,
    required bool id,
    required bool bg,
  }) {
    if (email && phone && id && bg) {
      return 2;
    } else if (email && phone) {
      return 1;
    } else {
      return 0;
    }
  }

  Future<void> handleEmailVerificationClick() async {
    final existing = userProfile;
    if (existing == null) return;

    final token = SessionStorage.idToken;
    if (token == null) return;

    setState(() => isUpdatingVerification = true);
    try {
      if (!verificationEmailSent) {
        // Send email
        await FirebaseAuthService().sendEmailVerification(token);
        setState(() {
          verificationEmailSent = true;
        });
      } else {
        // Refresh & check if they clicked the link
        final data = await FirebaseAuthService().getUserData(token);
        final isVerified = data['emailVerified'] as bool? ?? false;
        if (isVerified) {
          final nextLevel = _calculateVerificationLevel(
            email: true,
            phone: existing.phoneVerified,
            id: existing.idVerified,
            bg: existing.bgChecked,
          );
          final updated = existing.copyWith(
            emailVerified: true,
            verificationLevel: nextLevel,
          );
          await handleSaveProfile(updated);
          setState(() {
            verificationEmailSent = false;
          });
        } else {
          throw 'Email is still unverified. Please check your inbox and click the verification link.';
        }
      }
    } catch (e) {
      setState(() {
        // Toast / notice of error
      });
      rethrow;
    } finally {
      setState(() => isUpdatingVerification = false);
    }
  }

  Future<void> sendSmsCodeAction(String inputNumber) async {
    if (inputNumber.trim().length != 10) {
      setState(() {
        smsVerificationError = 'Please enter a valid 10-digit mobile number';
      });
      return;
    }
    setState(() {
      isSendingSms = true;
      smsVerificationError = null;
      simulatedSmsCode = null;
    });

    final fullNumber = '+63$inputNumber';

    try {
      final session = await FirebaseAuthService().sendSmsVerificationCode(fullNumber);
      setState(() {
        smsVerificationSessionInfo = session;
        isSendingSms = false;
      });
    } catch (e) {
      const isDevEnv = String.fromEnvironment('ENV', defaultValue: 'dev') == 'dev';
      if (isDevEnv) {
        // Gracefully switch to simulated playground mode with a beautiful OTP code!
        final randomOtp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
        setState(() {
          simulatedSmsCode = randomOtp;
          smsVerificationSessionInfo = 'simulated';
          isSendingSms = false;
        });
      } else {
        setState(() {
          smsVerificationError = 'Failed to send SMS code: $e';
          isSendingSms = false;
        });
      }
    }
  }

  Future<void> verifySmsCodeAction(String code) async {
    final existing = userProfile;
    if (existing == null) return;

    if (code.trim().length != 6) {
      setState(() {
        smsVerificationError = 'Please enter a 6-digit verification code';
      });
      return;
    }

    setState(() {
      isVerifyingSms = true;
      smsVerificationError = null;
    });

    try {
      if (smsVerificationSessionInfo == 'simulated') {
        const isDevEnv = String.fromEnvironment('ENV', defaultValue: 'dev') == 'dev';
        if (isDevEnv && (code == simulatedSmsCode || code == '123456')) {
          // Success!
          final nextLevel = _calculateVerificationLevel(
            email: existing.emailVerified,
            phone: true,
            id: existing.idVerified,
            bg: existing.bgChecked,
          );
          final updated = existing.copyWith(
            phoneVerified: true,
            phoneNumber: '+63$smsVerificationPhoneNumber',
            verificationLevel: nextLevel,
          );
          await handleSaveProfile(updated);

          final didNotHavePhoneBefore = existing.phoneNumber == null || existing.phoneNumber!.isEmpty;
          if (didNotHavePhoneBefore &&
              confirmDialog(
                "Would you like to use this same phone number as your Company/Business phone number too?",
              )) {
            final token = SessionStorage.idToken;
            if (token != null) {
              await FirestoreService(token, _handleTokenRefresh).setDocument('users/${existing.uid}', {
                'mobileNumber': '+63$smsVerificationPhoneNumber',
                'companyPhone': '+63$smsVerificationPhoneNumber',
              });
            }
          }

          setState(() {
            showSmsModal = false;
            simulatedSmsCode = null;
            smsVerificationSessionInfo = '';
            smsVerificationCode = '';
          });
        } else {
          throw 'Invalid verification code. Please try again.';
        }
      } else {
        await FirebaseAuthService().verifySmsCode(smsVerificationSessionInfo, code);
        final nextLevel = _calculateVerificationLevel(
          email: existing.emailVerified,
          phone: true,
          id: existing.idVerified,
          bg: existing.bgChecked,
        );
        final updated = existing.copyWith(
          phoneVerified: true,
          phoneNumber: '+63$smsVerificationPhoneNumber',
          verificationLevel: nextLevel,
        );
        await handleSaveProfile(updated);

        final didNotHavePhoneBefore = existing.phoneNumber == null || existing.phoneNumber!.isEmpty;
        if (didNotHavePhoneBefore &&
            confirmDialog("Would you like to use this same phone number as your Company/Business phone number too?")) {
          final token = SessionStorage.idToken;
          if (token != null) {
            await FirestoreService(token, _handleTokenRefresh).setDocument('users/${existing.uid}', {
              'mobileNumber': '+63$smsVerificationPhoneNumber',
              'companyPhone': '+63$smsVerificationPhoneNumber',
            });
          }
        }

        setState(() {
          showSmsModal = false;
          smsVerificationSessionInfo = '';
          smsVerificationCode = '';
        });
      }
    } catch (e) {
      setState(() {
        smsVerificationError = e.toString();
      });
    } finally {
      setState(() {
        isVerifyingSms = false;
      });
    }
  }

  Future<void> updateVerificationField({
    bool? email,
    bool? phone,
    bool? id,
    bool? bg,
  }) async {
    if (email == true) {
      await handleEmailVerificationClick();
      return;
    }
    if (phone == true) {
      final existingPhone = getDisplayPhone(userProfile?.phoneNumber);
      if (existingPhone.isNotEmpty) {
        setState(() {
          smsVerificationPhoneNumber = existingPhone;
          showSmsModal = true;
          smsVerificationSessionInfo = '';
          smsVerificationCode = '';
          smsVerificationError = null;
        });
        sendSmsCodeAction(existingPhone);
      } else {
        setState(() {
          smsVerificationPhoneNumber = '';
          showSmsModal = true;
          smsVerificationSessionInfo = '';
          smsVerificationCode = '';
          smsVerificationError = null;
        });
      }
      return;
    }

    final existing = userProfile;
    if (existing == null) return;

    setState(() => isUpdatingVerification = true);
    try {
      final nextEmail = existing.emailVerified;
      final nextPhone = existing.phoneVerified;
      final nextId = id ?? existing.idVerified;
      final nextBg = bg ?? existing.bgChecked;

      final nextLevel = _calculateVerificationLevel(
        email: nextEmail,
        phone: nextPhone,
        id: nextId,
        bg: nextBg,
      );

      final updated = existing.copyWith(
        emailVerified: nextEmail,
        phoneVerified: nextPhone,
        idVerified: nextId,
        bgChecked: nextBg,
        verificationLevel: nextLevel,
      );

      await handleSaveProfile(updated);
    } catch (_) {
    } finally {
      setState(() => isUpdatingVerification = false);
    }
  }

  Future<void> handleSaveProfile(UserProfile updated) async {
    final token = SessionStorage.idToken;
    if (token == null) return;
    try {
      await FirestoreService(token, _handleTokenRefresh).saveUser(updated);
      SessionStorage.saveProfile(
        name: updated.name,
        email: updated.email,
        accountType: updated.accountType.name,
      );
      setState(() {
        userProfile = updated;
        userName = updated.name;
        userEmail = updated.email;
        accountType = updated.accountType;
      });
    } catch (_) {}
  }

  Future<void> handleSavePersonalInfo() async {
    if (!isPersonalInfoValid || !hasPersonalInfoChanges) return;
    setState(() {
      isSavingProfile = true;
      profileSaveError = null;
    });
    try {
      final uid = SessionStorage.uid;
      if (uid == null) return;

      final formattedEditPhone = editPhone.trim().isNotEmpty ? '+63 ${editPhone.trim()}' : null;

      final existing = userProfile;
      final UserProfile updated;
      if (existing == null) {
        updated = UserProfile(
          uid: uid,
          name: editName.trim().isNotEmpty ? editName.trim() : (SessionStorage.displayName ?? 'User'),
          email: editEmail.trim().isNotEmpty ? editEmail.trim() : (SessionStorage.email ?? ''),
          accountType: accountType,
          phoneNumber: formattedEditPhone,
          taxId: editTaxId.trim().isNotEmpty ? editTaxId.trim() : '',
          createdAt: DateTime.now(),
        );
      } else {
        updated = existing.copyWith(
          name: editName.trim().isNotEmpty ? editName.trim() : null,
          email: editEmail.trim().isNotEmpty ? editEmail.trim() : null,
          phoneNumber: formattedEditPhone,
          taxId: editTaxId.trim().isNotEmpty ? editTaxId.trim() : '',
        );
      }

      await handleSaveProfile(updated);
      setState(() {
        isSavingProfile = false;
        initializeProfileEditing();
      });
    } catch (e) {
      setState(() {
        isSavingProfile = false;
        profileSaveError = e.toString();
      });
    }
  }

  Future<void> handleSaveProfessionalInfo() async {
    if (!isProfessionalInfoValid || !hasProfessionalInfoChanges) return;
    setState(() {
      isSavingProfile = true;
      profileSaveError = null;
    });
    try {
      final uid = SessionStorage.uid;
      if (uid == null) return;
      final skills = editSkills;

      final existing = userProfile;
      final UserProfile updated;
      if (existing == null) {
        updated = UserProfile(
          uid: uid,
          name: SessionStorage.displayName ?? userName,
          email: SessionStorage.email ?? userEmail,
          accountType: accountType,
          taxId: editTaxId.trim().isNotEmpty ? editTaxId.trim() : '',
          headline: editHeadline.trim().isNotEmpty ? editHeadline.trim() : '',
          hourlyRate: editHourlyRate.trim().isNotEmpty ? (double.tryParse(editHourlyRate) ?? 0.0) : 0.0,
          skills: skills,
          businessName: editBusinessName.trim().isNotEmpty ? editBusinessName.trim() : '',
          industry: editIndustry.trim().isNotEmpty ? editIndustry.trim() : '',
          createdAt: DateTime.now(),
        );
      } else {
        updated = existing.copyWith(
          businessName: editBusinessName.trim().isNotEmpty ? editBusinessName.trim() : '',
          industry: editIndustry.trim().isNotEmpty ? editIndustry.trim() : '',
          taxId: editTaxId.trim().isNotEmpty ? editTaxId.trim() : '',
          headline: editHeadline.trim().isNotEmpty ? editHeadline.trim() : '',
          hourlyRate: editHourlyRate.trim().isNotEmpty ? (double.tryParse(editHourlyRate) ?? existing.hourlyRate) : 0.0,
          skills: skills,
        );
      }

      await handleSaveProfile(updated);
      setState(() {
        isSavingProfile = false;
        initializeProfileEditing();
      });
    } catch (e) {
      setState(() {
        isSavingProfile = false;
        profileSaveError = e.toString();
      });
    }
  }

  // ── Gemini ──────────────────────────────────────────────────

  Future<String> generateJobDesc(String title) async {
    if (_gemini == null) return 'AI service not available.';
    return _gemini!.generateJobDescription(title);
  }

  Future<String> generateCoverNote(String title) async {
    if (_gemini == null) return 'AI service not available.';
    return _gemini!.generateCoverNote(title);
  }

  // ── Navigation ──────────────────────────────────────────────

  void switchTab(AppTab tab) {
    if (activeTab == tab) return;

    setState(() {
      activeTab = tab;
      if (tab != AppTab.profile) profileView = ProfileView.main;
      if (tab == AppTab.profile) {
        initializeProfileEditing();
      }
      if (tab != AppTab.jobs) {
        jobsView = JobsView.list;
        createStep = 1;
        selectedJob = null;
        selectedJobData = null;
        _stopSelectedJobRealtime();
      }
    });

    if (tab == AppTab.jobs) {
      loadJobs();
    } else if (tab == AppTab.transit) {
      loadRenterPendingRequests();
      loadHostPendingRequests();
    }
  }

  bool get jobsHasUpdates {
    if (!isAuthenticated) return false;
    final myUid = SessionStorage.uid;
    if (myUid == null) return false;
    if (currentViewMode == AccountType.employer) {
      return myJobs.any((j) {
        final status = (j['status'] as String? ?? 'Open').toLowerCase();
        final count = j['applicantCount'] as int? ?? 0;
        return status == 'open' && count > 0;
      });
    } else {
      return appliedJobs.any((j) {
        final status = (j['status'] as String? ?? 'Open').toLowerCase();
        return status != 'open';
      });
    }
  }

  bool get transitHasUpdates {
    if (!isAuthenticated) return false;
    final renterHasUpdates =
        renterPendingRequests.any((r) => r['status'] != 'Pending') ||
        propertyRenterPendingRequests.any((r) => r['status'] != 'Pending');
    final hostHasUpdates = hostPendingRequests.isNotEmpty || propertyHostPendingRequests.isNotEmpty;
    return renterHasUpdates || hostHasUpdates;
  }

  // ── Wallet ──────────────────────────────────────────────────

  Future<void> handleConnectWallet() async {
    setState(() {
      showWalletSelectionModal = true;
    });
  }

  Future<void> handleRefreshBalance() async {
    if (walletState != WalletState.connected || walletAddress.isEmpty) return;
    setState(() => isRefreshingBalance = true);
    try {
      String? publicKey = userProfile?.walletPublicKey;
      final activeWalletType = selectedWalletType ?? 'phantom';
      if (publicKey == null && isSolanaWalletInstalled(activeWalletType)) {
        publicKey = await getSolanaPublicKeyIfConnected(activeWalletType);
      }

      final ethAddrVal = await getEthereumAddressIfConnected();
      final suiAddrVal = await getSuiAddressIfConnected();

      if (publicKey != null) {
        final balance = await getSolanaBalance(publicKey);
        final collectibles = await getSolanaTokenCollectibles(publicKey) ?? [];

        double ethBalVal = 0.0;
        if (ethAddrVal != null) {
          ethBalVal = await getEthereumBalance(ethAddrVal) ?? 0.0;
        }

        double suiBalVal = 0.0;
        if (suiAddrVal != null) {
          suiBalVal = await getSuiBalance(suiAddrVal) ?? 0.0;
        }

        if (balance != null) {
          setState(() {
            walletBalance = balance;
            walletCollectibles = collectibles;
            ethAddress = ethAddrVal ?? '';
            suiAddress = suiAddrVal ?? '';
            ethBalance = ethBalVal;
            suiBalance = suiBalVal;
          });
        }
      }
    } catch (_) {}
    setState(() => isRefreshingBalance = false);
  }

  Future<void> autoConnectPhantomIfLinked(String? profileWalletKey) async {
    try {
      if (profileWalletKey != null) {
        final savedType = web.window.localStorage.getItem('selectedSolanaWallet');
        final typesToCheck = savedType != null ? [savedType] : ['phantom', 'solflare', 'backpack', 'trust'];

        for (final type in typesToCheck) {
          if (isSolanaWalletInstalled(type)) {
            final activeKey = await getSolanaPublicKeyIfConnected(type);
            if (activeKey != null && activeKey == profileWalletKey) {
              final balance = await getSolanaBalance(profileWalletKey) ?? 0.0;
              final collectibles = await getSolanaTokenCollectibles(profileWalletKey) ?? [];
              final short =
                  '${profileWalletKey.substring(0, 4)}...${profileWalletKey.substring(profileWalletKey.length - 4)}';

              final ethAddrVal = await getEthereumAddressIfConnected();
              final suiAddrVal = await getSuiAddressIfConnected();

              double ethBalVal = 0.0;
              if (ethAddrVal != null) {
                ethBalVal = await getEthereumBalance(ethAddrVal) ?? 0.0;
              }

              double suiBalVal = 0.0;
              if (suiAddrVal != null) {
                suiBalVal = await getSuiBalance(suiAddrVal) ?? 0.0;
              }

              setState(() {
                selectedWalletType = type;
                walletAddress = short;
                walletBalance = balance;
                walletCollectibles = collectibles;
                ethAddress = ethAddrVal ?? '';
                suiAddress = suiAddrVal ?? '';
                ethBalance = ethBalVal;
                suiBalance = suiBalVal;
                walletState = WalletState.connected;
              });
              return;
            }
          }
        }

        setState(() {
          showWalletReconnectPrompt = true;
          pendingReconnectWalletKey = profileWalletKey;
        });
        return;
      }

      final types = ['phantom', 'solflare', 'backpack', 'trust'];
      for (final type in types) {
        if (isSolanaWalletInstalled(type)) {
          final publicKey = await getSolanaPublicKeyIfConnected(type);
          if (publicKey != null) {
            final balance = await getSolanaBalance(publicKey) ?? 0.0;
            final collectibles = await getSolanaTokenCollectibles(publicKey) ?? [];
            final short = '${publicKey.substring(0, 4)}...${publicKey.substring(publicKey.length - 4)}';

            final ethAddrVal = await getEthereumAddressIfConnected();
            final suiAddrVal = await getSuiAddressIfConnected();

            double ethBalVal = 0.0;
            if (ethAddrVal != null) {
              ethBalVal = await getEthereumBalance(ethAddrVal) ?? 0.0;
            }

            double suiBalVal = 0.0;
            if (suiAddrVal != null) {
              suiBalVal = await getSuiBalance(suiAddrVal) ?? 0.0;
            }

            setState(() {
              selectedWalletType = type;
              walletAddress = short;
              walletBalance = balance;
              walletCollectibles = collectibles;
              ethAddress = ethAddrVal ?? '';
              suiAddress = suiAddrVal ?? '';
              ethBalance = ethBalVal;
              suiBalance = suiBalVal;
              walletState = WalletState.connected;
            });
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> handleSelectSolanaWallet(String type) async {
    setState(() {
      showWalletSelectionModal = false;
      selectedWalletType = type;
    });

    if (!isSolanaWalletInstalled(type)) {
      final friendlyName = type.substring(0, 1).toUpperCase() + type.substring(1);
      if (!isAuthenticated) {
        setState(() {
          authError = '$friendlyName Wallet is not installed. Please install it to continue.';
        });
      } else {
        setState(() => walletState = WalletState.disconnected);
      }
      return;
    }

    if (!isAuthenticated) {
      setState(() {
        isAuthLoading = true;
        authError = null;
      });

      try {
        final publicKey = await connectSolanaWallet(type);
        if (publicKey == null) {
          setState(() {
            authError = 'Wallet connection was rejected or failed.';
            isAuthLoading = false;
          });
          return;
        }

        final linkData = await FirestoreService().getWalletLink(publicKey);

        if (linkData != null) {
          final existingUid = linkData['uid'] as String?;
          final refreshToken = linkData['refreshToken'] as String?;

          if (refreshToken != null) {
            try {
              final authService = FirebaseAuthService();
              final newIdToken = await authService.refreshIdToken(refreshToken);
              final userData = await authService.getUserData(newIdToken);

              final authResult = AuthResult(
                uid: existingUid!,
                idToken: newIdToken,
                refreshToken: refreshToken,
                email: userData['email'] as String?,
                displayName: userData['displayName'] as String?,
              );

              SessionStorage.save(authResult);

              final profile = await FirestoreService(authResult.idToken, _handleTokenRefresh).getUser(authResult.uid);
              final profileType = profile?.accountType ?? AccountType.employer;

              SessionStorage.saveProfile(
                name: profile?.name ?? authResult.displayName ?? (authResult.email?.split('@').first ?? 'User'),
                email: authResult.email ?? '',
                accountType: profileType.name,
              );

              setState(() {
                userEmail = authResult.email ?? '';
                userProfile = profile;
                isAuthenticated = true;
                accountType = profileType;
                hybridToggle = profileType == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
                userName = profile?.name ?? authResult.displayName ?? (authResult.email?.split('@').first ?? 'User');
                isAuthLoading = false;
                walletAddress = '${publicKey.substring(0, 4)}...${publicKey.substring(publicKey.length - 4)}';
                walletState = WalletState.connected;
              });

              _initGemini();
              await loadJobs();
              await loadTransactions();
              _startListeningNotifications();
              _startListeningJobs();
              _startListeningRentals();
              _startListeningProperties();

              final balance = await getSolanaBalance(publicKey) ?? 0.0;
              final collectibles = await getSolanaTokenCollectibles(publicKey) ?? [];
              setState(() {
                walletBalance = balance;
                walletCollectibles = collectibles;
              });

              if (pendingQrJobId != null && pendingQrCode != null) {
                await executePendingQrVerification();
              }
              return;
            } catch (e) {
              setState(() {
                isAuthLoading = false;
                authError = 'Wallet recognized but session expired. Please sign in with email & password.';
                pendingWalletPublicKey = publicKey;
              });
              return;
            }
          } else {
            setState(() {
              isAuthLoading = false;
              authError = 'Wallet recognized! Please sign in with your email & password to continue.';
              pendingWalletPublicKey = publicKey;
            });
            return;
          }
        } else {
          setState(() {
            isAuthLoading = false;
            authError = null;
            pendingWalletPublicKey = publicKey;
            authView = AuthView.registerPath;
          });
        }
      } catch (e) {
        setState(() {
          authError = 'Wallet connection error: ${e.toString()}';
          isAuthLoading = false;
        });
      }
    } else {
      setState(() => walletState = WalletState.connecting);
      try {
        final publicKey = await connectSolanaWallet(type);
        if (publicKey == null) {
          setState(() => walletState = WalletState.disconnected);
          return;
        }

        final ethAddrVal = await connectEthereumWallet();
        final suiAddrVal = await connectSuiWallet();

        final balance = await getSolanaBalance(publicKey) ?? 0.0;
        final collectibles = await getSolanaTokenCollectibles(publicKey) ?? [];
        final short = '${publicKey.substring(0, 4)}...${publicKey.substring(publicKey.length - 4)}';

        double ethBalVal = 0.0;
        if (ethAddrVal != null) {
          ethBalVal = await getEthereumBalance(ethAddrVal) ?? 0.0;
        }

        double suiBalVal = 0.0;
        if (suiAddrVal != null) {
          suiBalVal = await getSuiBalance(suiAddrVal) ?? 0.0;
        }

        final token = SessionStorage.idToken;
        final currentUid = SessionStorage.uid;
        if (token != null && currentUid != null) {
          try {
            await FirestoreService(token, _handleTokenRefresh).linkWalletToUser(
              currentUid,
              publicKey,
              refreshToken: SessionStorage.refreshToken,
            );
          } catch (_) {}
        }

        setState(() {
          walletAddress = short;
          walletBalance = balance;
          walletCollectibles = collectibles;
          ethAddress = ethAddrVal ?? '';
          suiAddress = suiAddrVal ?? '';
          ethBalance = ethBalVal;
          suiBalance = suiBalVal;
          walletState = WalletState.connected;
        });
      } catch (_) {
        setState(() => walletState = WalletState.disconnected);
      }
    }
  }

  void handleDisconnectWallet() async {
    final type = selectedWalletType ?? 'phantom';
    try {
      await disconnectSolanaWallet(type);
    } catch (_) {}

    setState(() {
      walletState = WalletState.disconnected;
      walletAddress = '';
      walletBalance = 0.0;
      walletCollectibles = [];
      ethAddress = '';
      suiAddress = '';
      ethBalance = 0.0;
      suiBalance = 0.0;
      selectedWalletType = null;
      showWalletSelectionModal = false;

      // 1:1 Identity cleanup
      isAuthenticated = false;
      userProfile = null;
      myJobs = [];
      sessionPostedJobs = [];
      realtimeEmployerJobs = [];
      realtimeNyxianJobs = [];
      availableJobs = [];
      appliedJobs = [];
      renterPendingRequests = [];
      hostPendingRequests = [];
      notifications = [];
      chatMessages = [];
      currentChatId = '';
      showChat = false;
      showDepositModal = false;
      isDepositing = false;
      postJobError = null;
      selectedJobData = null;
      selectedJob = null;
      ongoingJob = null;
    });

    _stopSelectedJobRealtime();
    stopListeningToJobsJs();
    stopListeningToRentalsJs();
    stopListeningToPropertiesJs();

    SessionStorage.clear();
    showAppToast('Wallet Disconnected', 'Logged out because active wallet was disconnected.');
  }

  Future<void> _handleSolanaAccountChanged(String newPublicKey, String type) async {
    // 1. Wipe active dashboard states & cancel pending states
    setState(() {
      walletState = WalletState.connecting;
      walletAddress = '';
      walletBalance = 0.0;
      walletCollectibles = [];
      userProfile = null;
      myJobs = [];
      sessionPostedJobs = [];
      realtimeEmployerJobs = [];
      realtimeNyxianJobs = [];
      availableJobs = [];
      appliedJobs = [];
      renterPendingRequests = [];
      hostPendingRequests = [];
      notifications = [];
      chatMessages = [];
      currentChatId = '';
      showChat = false;
      showDepositModal = false;
      isDepositing = false;
      postJobError = null;
      selectedJobData = null;
      selectedJob = null;
      ongoingJob = null;
    });

    _stopSelectedJobRealtime();
    stopListeningToJobsJs();
    stopListeningToRentalsJs();
    stopListeningToPropertiesJs();

    // 2. Fetch the wallet link in Firestore
    try {
      final linkData = await FirestoreService().getWalletLink(newPublicKey);
      if (linkData != null) {
        final existingUid = linkData['uid'] as String?;
        final refreshToken = linkData['refreshToken'] as String?;
        if (refreshToken != null) {
          final authService = FirebaseAuthService();
          final newIdToken = await authService.refreshIdToken(refreshToken);
          final userData = await authService.getUserData(newIdToken);
          final authResult = AuthResult(
            uid: existingUid!,
            idToken: newIdToken,
            refreshToken: refreshToken,
            email: userData['email'] as String?,
            displayName: userData['displayName'] as String?,
          );

          SessionStorage.save(authResult);

          final profile = await FirestoreService(authResult.idToken, _handleTokenRefresh).getUser(authResult.uid);
          final profileType = profile?.accountType ?? AccountType.employer;

          SessionStorage.saveProfile(
            name: profile?.name ?? authResult.displayName ?? (authResult.email?.split('@').first ?? 'User'),
            email: authResult.email ?? '',
            accountType: profileType.name,
          );

          setState(() {
            isAuthenticated = true;
            userEmail = authResult.email ?? '';
            userProfile = profile;
            accountType = profileType;
            hybridToggle = profileType == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
            userName = profile?.name ?? authResult.displayName ?? (authResult.email?.split('@').first ?? 'User');
            walletAddress = '${newPublicKey.substring(0, 4)}...${newPublicKey.substring(newPublicKey.length - 4)}';
            walletState = WalletState.connected;
            selectedWalletType = type;
          });

          _initGemini();
          await loadJobs();
          await loadTransactions();
          _startListeningNotifications();
          _startListeningJobs();
          _startListeningRentals();
          _startListeningProperties();

          final balance = await getSolanaBalance(newPublicKey) ?? 0.0;
          final collectibles = await getSolanaTokenCollectibles(newPublicKey) ?? [];
          setState(() {
            walletBalance = balance;
            walletCollectibles = collectibles;
          });

          showAppToast('Account Switched', 'Successfully switched to wallet account: $walletAddress');
          return;
        }
      }

      // If no link found, sign out of current session and go to registration flow
      await signOutJs();
      SessionStorage.clear();
      setState(() {
        isAuthenticated = false;
        pendingWalletPublicKey = newPublicKey;
        selectedWalletType = type;
        walletState = WalletState.disconnected;
        authView = AuthView.registerPath;
        authError = 'No linked account found for this wallet. Please register or sign in to link it.';
      });
      showAppToast('Wallet Connected', 'Please sign in or register to link this wallet.');
    } catch (e) {
      setState(() {
        authError = 'Error switching wallet account: ${e.toString()}';
        walletState = WalletState.disconnected;
      });
      showAppToast('Error', 'Failed to switch wallet account.');
    }
  }

  void _handleSolanaWalletDisconnected() {
    setState(() {
      walletState = WalletState.disconnected;
      walletAddress = '';
      walletBalance = 0.0;
      walletCollectibles = [];
      ethAddress = '';
      suiAddress = '';
      ethBalance = 0.0;
      suiBalance = 0.0;
      selectedWalletType = null;
      showWalletSelectionModal = false;

      // 1:1 Identity cleanup
      isAuthenticated = false;
      userProfile = null;
      myJobs = [];
      sessionPostedJobs = [];
      realtimeEmployerJobs = [];
      realtimeNyxianJobs = [];
      availableJobs = [];
      appliedJobs = [];
      renterPendingRequests = [];
      hostPendingRequests = [];
      notifications = [];
      chatMessages = [];
      currentChatId = '';
      showChat = false;
      showDepositModal = false;
      isDepositing = false;
      postJobError = null;
      selectedJobData = null;
      selectedJob = null;
      ongoingJob = null;
    });

    _stopSelectedJobRealtime();
    stopListeningToJobsJs();
    stopListeningToRentalsJs();
    stopListeningToPropertiesJs();

    SessionStorage.clear();
    showAppToast('Wallet Disconnected', 'Logged out because active wallet was disconnected.');
  }

  Future<void> linkSolanaWallet(String type) async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;

    setState(() {
      isSavingProfile = true;
      profileSaveError = null;
    });

    try {
      final publicKey = await connectSolanaWallet(type);
      if (publicKey == null) {
        throw 'Failed to connect Solana Wallet. Please approve the connection request.';
      }

      // Check if wallet is already linked to another account
      final linkData = await FirestoreService().getWalletLink(publicKey);
      if (linkData != null) {
        final existingUid = linkData['uid'] as String?;
        if (existingUid != null && existingUid != uid) {
          throw 'This Solana wallet is already linked to another user account.';
        }
      }

      await FirestoreService(token, _handleTokenRefresh).linkWalletToUser(
        uid,
        publicKey,
        refreshToken: SessionStorage.refreshToken,
      );

      // Refresh local profile
      await loadUserProfile();

      setState(() {
        isSavingProfile = false;
        selectedWalletType = type;
      });
      showAppToast('Wallet Linked', 'Successfully linked your Solana wallet ($type).');
    } catch (e) {
      setState(() {
        isSavingProfile = false;
        profileSaveError = e.toString();
      });
      showAppToast('Failed to Link', e.toString());
    }
  }

  Future<void> unlinkSolanaWallet() async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;

    final walletKey = userProfile?.walletPublicKey;
    if (walletKey == null || walletKey.isEmpty) return;

    setState(() {
      isSavingProfile = true;
      profileSaveError = null;
    });

    try {
      final svc = FirestoreService(token, _handleTokenRefresh);

      // Delete the wallet link document
      await svc.deleteDocument('walletLinks/$walletKey');

      // Clear walletPublicKey on users document
      await svc.setDocument('users/$uid', {'walletPublicKey': ''});

      // Refresh local profile
      await loadUserProfile();

      setState(() {
        isSavingProfile = false;
        selectedWalletType = null;
        walletAddress = '';
        walletBalance = 0.0;
        walletCollectibles = [];
      });
      showAppToast('Wallet Unlinked', 'Solana wallet was successfully unlinked.');
    } catch (e) {
      setState(() {
        isSavingProfile = false;
        profileSaveError = e.toString();
      });
      showAppToast('Failed to Unlink', e.toString());
    }
  }

  Future<void> handleLinkGoogleAccount() async {
    setState(() {
      isSavingProfile = true;
      profileSaveError = null;
    });

    try {
      final configMap = {
        'apiKey': currentFirebaseConfig.apiKey,
        'authDomain': currentFirebaseConfig.authDomain,
        'projectId': currentFirebaseConfig.projectId,
        'storageBucket': currentFirebaseConfig.storageBucket,
        'messagingSenderId': currentFirebaseConfig.messagingSenderId,
        'appId': currentFirebaseConfig.appId,
      };

      final googleJsonStr = await linkGoogleAccountJs(configMap);
      if (googleJsonStr == null) {
        throw 'Google account linking was cancelled or failed.';
      }

      final Map<String, dynamic> googleData = jsonDecode(googleJsonStr);
      final email = googleData['email'] as String?;
      final uid = SessionStorage.uid;

      if (uid != null && email != null) {
        final svc = FirestoreService(SessionStorage.idToken!, _handleTokenRefresh);
        await svc.setDocument('users/$uid', {'googleEmail': email});
        await loadUserProfile();
      }

      setState(() {
        isSavingProfile = false;
      });
      showAppToast('Account Linked', 'Google account linked successfully!');
    } catch (e) {
      setState(() {
        isSavingProfile = false;
        profileSaveError = e.toString();
      });
      showAppToast('Failed to Link', e.toString());
    }
  }

  Future<void> handleUnlinkGoogleAccount() async {
    setState(() {
      isSavingProfile = true;
      profileSaveError = null;
    });

    try {
      final configMap = {
        'apiKey': currentFirebaseConfig.apiKey,
        'authDomain': currentFirebaseConfig.authDomain,
        'projectId': currentFirebaseConfig.projectId,
        'storageBucket': currentFirebaseConfig.storageBucket,
        'messagingSenderId': currentFirebaseConfig.messagingSenderId,
        'appId': currentFirebaseConfig.appId,
      };

      final googleJsonStr = await unlinkGoogleAccountJs(configMap);
      if (googleJsonStr == null) {
        throw 'Google account unlinking failed.';
      }

      final uid = SessionStorage.uid;
      if (uid != null) {
        final svc = FirestoreService(SessionStorage.idToken!, _handleTokenRefresh);
        await svc.setDocument('users/$uid', {'googleEmail': ''});
        await loadUserProfile();
      }

      setState(() {
        isSavingProfile = false;
      });
      showAppToast('Account Unlinked', 'Google account unlinked successfully.');
    } catch (e) {
      setState(() {
        isSavingProfile = false;
        profileSaveError = e.toString();
      });
      showAppToast('Failed to Unlink', e.toString());
    }
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _empTypeLabel(EmpType t) {
    switch (t) {
      case EmpType.fulltime:
        return 'Full-time';
      case EmpType.parttime:
        return 'Part-time';
      case EmpType.contractual:
        return 'One-time Gig';
    }
  }

  String _dateTypeLabel(JobDateType t) {
    switch (t) {
      case JobDateType.flexible:
        return 'Flexible';
      case JobDateType.onDate:
        return 'On Date';
      case JobDateType.beforeDate:
        return 'Before Date';
    }
  }

  String _timePrefLabel(TimePref t) {
    switch (t) {
      case TimePref.morning:
        return 'Morning';
      case TimePref.midday:
        return 'Midday';
      case TimePref.afternoon:
        return 'Afternoon';
      case TimePref.evening:
        return 'Evening';
    }
  }

  String _paymentTypeLabel(PaymentType t) {
    switch (t) {
      case PaymentType.daily:
        return 'Daily';
      case PaymentType.weekly:
        return 'Weekly';
      case PaymentType.fortnightly:
        return 'Fortnightly';
      case PaymentType.monthly:
        return 'Monthly';
      case PaymentType.packageFixed:
        return 'Package (Fixed)';
    }
  }

  Future<void> loadKycSubmission() async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;
    setState(() => isLoadingKyc = true);
    try {
      final doc = await FirestoreService(token, _handleTokenRefresh).getKycSubmission(uid);
      setState(() {
        activeKycSubmission = doc;
      });
    } catch (e) {
      print('loadKycSubmission error: $e');
    } finally {
      setState(() => isLoadingKyc = false);
    }
  }

  Future<void> loadHoldbacks() async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;
    try {
      final isNyxian = currentViewMode == AccountType.nyxian;
      final svc = FirestoreService(token, _handleTokenRefresh);
      final list = await svc.getEscrowHoldbacks(uid, isNyxian: isNyxian);

      // Check if any holdbacks are ready to release client-side
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final toRelease = list
          .where((item) => (item['releaseAt'] as int? ?? 0) <= nowMs && item['status'] == 'held')
          .toList();

      if (toRelease.isNotEmpty && isNyxian) {
        final userDoc = await svc.getDocument('users/$uid');
        if (userDoc != null) {
          double totalToRelease = 0.0;
          for (final holdback in toRelease) {
            final amt = (holdback['amount'] as num?)?.toDouble() ?? 0.0;
            totalToRelease += amt;

            await svc.createOrUpdate('escrow_holdbacks/${holdback['id']}', {
              ...holdback,
              'status': 'released',
              'releasedAt': nowMs,
            });
          }

          if (totalToRelease > 0) {
            final currentBal = (userDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            final currentEarned = (userDoc['totalEarned'] as num?)?.toDouble() ?? 0.0;

            await svc.createOrUpdate('users/$uid', {
              ...userDoc,
              'tyxBalance': currentBal + totalToRelease,
              'totalEarned': currentEarned + totalToRelease,
            });
          }
        }
      }

      final remaining = await svc.getEscrowHoldbacks(uid, isNyxian: isNyxian);
      setState(() {
        pendingHoldbacks = remaining;
      });
    } catch (e) {
      print('loadHoldbacks error: $e');
    }
  }

  Future<void> submitIdVerification({
    required String idType,
    required String idNumber,
    required String frontUrl,
    required String backUrl,
    required String selfieUrl,
  }) async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;

    setState(() => isLoadingKyc = true);
    try {
      final dbSvc = FirestoreService(token, _handleTokenRefresh);

      // Get existing doc if any to merge
      final existingDoc = await dbSvc.getKycSubmission(uid) ?? {};
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final updatedDoc = {
        ...existingDoc,
        'uid': uid,
        'fullName': userProfile?.name ?? userName,
        'submittedAt': nowMs,
        'updatedAt': nowMs,
        'idVerification': {
          'status': 'pending',
          'idType': idType,
          'idNumber': idNumber,
          'frontUrl': frontUrl,
          'backUrl': backUrl,
          'selfieUrl': selfieUrl,
          'submittedAt': nowMs,
        },
      };

      await dbSvc.saveKycSubmission(uid, updatedDoc);
      await loadKycSubmission();
      showAppToast('ID Verification Submitted! 🆔', 'Our team will review your government ID.');
      setState(() => showKycIdModal = false);
    } catch (e) {
      showAppToast('Submission Failed ❌', e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => isLoadingKyc = false);
    }
  }

  Future<void> submitBackgroundCheck({
    required String clearanceType,
    required String clearanceNumber,
    required String expiryDate,
    required String documentUrl,
  }) async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;

    setState(() => isLoadingKyc = true);
    try {
      final dbSvc = FirestoreService(token, _handleTokenRefresh);

      // Get existing doc if any to merge
      final existingDoc = await dbSvc.getKycSubmission(uid) ?? {};
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final updatedDoc = {
        ...existingDoc,
        'uid': uid,
        'fullName': userProfile?.name ?? userName,
        'submittedAt': nowMs,
        'updatedAt': nowMs,
        'backgroundCheck': {
          'status': 'pending',
          'clearanceType': clearanceType,
          'clearanceNumber': clearanceNumber,
          'expiryDate': expiryDate,
          'documentUrl': documentUrl,
          'submittedAt': nowMs,
        },
      };

      await dbSvc.saveKycSubmission(uid, updatedDoc);
      await loadKycSubmission();
      showAppToast('Background Check Submitted! 📄', 'Our team will review your clearance document.');
      setState(() => showKycBgModal = false);
    } catch (e) {
      showAppToast('Submission Failed ❌', e.toString().replaceAll('Exception: ', ''));
    } finally {
      setState(() => isLoadingKyc = false);
    }
  }

  Component _buildUserProfileModal(bool isDark) {
    return div(classes: 'fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm', [
      div(
        classes:
            'w-full max-w-md p-6 rounded-3xl ${isDark ? "bg-zinc-900 border border-zinc-800" : "bg-white"} shadow-2xl animate-fade-up flex flex-col relative',
        [
          button(
            classes: 'absolute top-4 right-4 p-2 rounded-full hover:bg-zinc-500/20 transition-colors',
            events: {'click': (_) => setState(() => showEmployerProfileModal = false)},
            [lIcon('x', cls: 'w-5 h-5 ${isDark ? "text-zinc-400" : "text-zinc-600"}')],
          ),

          if (isLoadingEmployerProfile)
            div(classes: 'py-12 flex justify-center', [
              lIcon('loader-2', cls: 'w-8 h-8 animate-spin text-indigo-500'),
            ])
          else if (employerProfileData != null)
            Builder(
              builder: (context) {
                final emp = employerProfileData!;
                final name = emp['name'] as String? ?? emp['displayName'] as String? ?? 'Unknown';
                final rating = (emp['rating'] as num?)?.toDouble() ?? 0.0;
                final about = emp['about'] as String? ?? emp['headline'] as String? ?? 'No description provided.';
                final phone = emp['phoneNumber'] as String? ?? emp['mobileNumber'] as String? ?? 'Not provided';
                final photo = emp['photoUrl'] as String? ?? emp['profile_photo'] as String? ?? '';

                final businessName = emp['businessName'] as String? ?? '';
                final industry = emp['industry'] as String? ?? '';
                final hasBusinessInfo = businessName.isNotEmpty && industry.isNotEmpty;

                final isEmail = emp['emailVerified'] == true;
                final isPhone = emp['phoneVerified'] == true;
                final isId = emp['idVerified'] == true;
                final isBg = emp['bgChecked'] == true;
                final vLevel = emp['verificationLevel'] as int? ?? 0;

                return div(classes: 'flex flex-col', [
                  div(classes: 'flex items-center gap-4 mb-6 mt-2', [
                    div(
                      classes:
                          'w-16 h-16 rounded-full flex items-center justify-center bg-indigo-600 flex-shrink-0 overflow-hidden relative',
                      [
                        if (photo.isNotEmpty)
                          img(src: photo, classes: 'w-full h-full object-cover')
                        else
                          span(classes: 'text-2xl font-bold text-white', [
                            Component.text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                          ]),
                      ],
                    ),
                    div(classes: 'flex-1 min-w-0', [
                      h3(
                        classes: 'text-xl font-bold truncate leading-tight ${isDark ? "text-white" : "text-zinc-800"}',
                        [
                          Component.text(
                            hasBusinessInfo ? businessName : name,
                          ),
                        ],
                      ),
                      if (hasBusinessInfo)
                        p(classes: 'text-xs text-indigo-400 font-semibold mb-1 truncate', [
                          Component.text('Industry: $industry'),
                        ]),
                      if (hasBusinessInfo)
                        p(classes: 'text-[11px] ${isDark ? "text-zinc-400" : "text-zinc-500"} mb-1.5', [
                          Component.text('Contact Person: $name'),
                        ]),
                      div(classes: 'flex items-center gap-2 mt-1', [
                        div(
                          classes:
                              'flex items-center gap-1 text-sm font-semibold ${isDark ? "text-zinc-400" : "text-zinc-650"} mr-2',
                          [
                            lIcon('star', cls: 'w-4 h-4 text-yellow-500 fill-current'),
                            Component.text(rating.toStringAsFixed(1)),
                          ],
                        ),
                        // Verification Badge
                        div(
                          classes:
                              'flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold '
                              '${vLevel == 2
                                  ? "bg-green-500/10 text-green-400 border border-green-500/20"
                                  : vLevel == 1
                                  ? "bg-blue-500/10 text-blue-400 border border-blue-500/20"
                                  : "bg-zinc-500/10 text-zinc-400 border border-zinc-500/20"}',
                          [
                            lIcon(vLevel > 0 ? 'shield-check' : 'shield-alert', cls: 'w-3 h-3'),
                            Component.text(
                              vLevel == 2
                                  ? 'Fully Verified'
                                  : vLevel == 1
                                  ? 'Basic Verified'
                                  : 'Unverified',
                            ),
                          ],
                        ),
                      ]),
                    ]),
                  ]),

                  div(classes: 'space-y-4 mb-2', [
                    div([
                      p(classes: 'text-xs font-semibold uppercase tracking-wider text-indigo-500 mb-1', [
                        Component.text('About'),
                      ]),
                      p(classes: 'text-sm ${isDark ? "text-zinc-300" : "text-zinc-700"}', [Component.text(about)]),
                    ]),
                    div([
                      p(classes: 'text-xs font-semibold uppercase tracking-wider text-indigo-500 mb-1', [
                        Component.text('Contact'),
                      ]),
                      p(classes: 'text-sm ${isDark ? "text-zinc-300" : "text-zinc-700"} flex items-center gap-2', [
                        lIcon('phone', cls: 'w-4 h-4 opacity-70'),
                        Component.text(phone),
                      ]),
                    ]),

                    // Trust & Verification Status Dashboard summary
                    div([
                      p(classes: 'text-xs font-semibold uppercase tracking-wider text-indigo-500 mb-2', [
                        Component.text('Verification Levels'),
                      ]),
                      div(
                        classes:
                            'p-3.5 rounded-2xl border ${isDark ? "bg-zinc-950 border-zinc-800" : "bg-zinc-50 border-zinc-200"} flex items-center justify-around gap-2 text-center',
                        [
                          div(classes: 'flex flex-col items-center gap-1', [
                            div(
                              classes:
                                  'p-1.5 rounded-lg ${isEmail ? "bg-green-500/10 text-green-400" : "bg-zinc-500/10 text-zinc-400"}',
                              [
                                lIcon('mail', cls: 'w-4 h-4'),
                              ],
                            ),
                            p(classes: 'text-[9px] font-bold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                              Component.text('Email'),
                            ]),
                          ]),
                          div(classes: 'flex flex-col items-center gap-1', [
                            div(
                              classes:
                                  'p-1.5 rounded-lg ${isPhone ? "bg-green-500/10 text-green-400" : "bg-zinc-500/10 text-zinc-400"}',
                              [
                                lIcon('phone', cls: 'w-4 h-4'),
                              ],
                            ),
                            p(classes: 'text-[9px] font-bold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                              Component.text('Phone'),
                            ]),
                          ]),
                          div(classes: 'flex flex-col items-center gap-1', [
                            div(
                              classes:
                                  'p-1.5 rounded-lg ${isId ? "bg-green-500/10 text-green-400" : "bg-zinc-500/10 text-zinc-400"}',
                              [
                                lIcon('file-text', cls: 'w-4 h-4'),
                              ],
                            ),
                            p(classes: 'text-[9px] font-bold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                              Component.text('ID'),
                            ]),
                          ]),
                          div(classes: 'flex flex-col items-center gap-1', [
                            div(
                              classes:
                                  'p-1.5 rounded-lg ${isBg ? "bg-green-500/10 text-green-400" : "bg-zinc-500/10 text-zinc-400"}',
                              [
                                lIcon('shield-check', cls: 'w-4 h-4'),
                              ],
                            ),
                            p(classes: 'text-[9px] font-bold ${isDark ? "text-zinc-500" : "text-zinc-400"}', [
                              Component.text('Background'),
                            ]),
                          ]),
                        ],
                      ),
                    ]),

                    if (emp['skills'] != null && (emp['skills'] as List).isNotEmpty)
                      div([
                        p(classes: 'text-xs font-semibold uppercase tracking-wider text-indigo-500 mb-2', [
                          Component.text('Preferred Skills'),
                        ]),
                        div(classes: 'flex flex-wrap gap-2', [
                          for (final skill in emp['skills'] as List)
                            span(
                              classes:
                                  'px-2 py-1 rounded-md text-xs font-medium border ${isDark ? "border-zinc-700 bg-zinc-800 text-zinc-300" : "border-zinc-200 bg-zinc-100 text-zinc-700"}',
                              [
                                Component.text(skill.toString()),
                              ],
                            ),
                        ]),
                      ]),
                  ]),
                ]);
              },
            )
          else
            div(classes: 'py-12 flex justify-center text-red-500 text-sm font-semibold', [
              Component.text('Failed to load profile.'),
            ]),
        ],
      ),
    ]);
  }

  @override
  Component build(BuildContext context) {
    final path = web.window.location.pathname;
    if (path == '/privacy-policy') {
      return const PrivacyPolicy();
    }
    if (path == '/terms-of-use') {
      return const TermsOfUse();
    }

    final darkBg = isDark ? 'bg-zinc-950 text-white' : 'bg-zinc-50 text-zinc-900';

    if (showWebSplash) {
      return div(
        classes:
            'fixed inset-0 z-[99999] flex flex-col items-center justify-center bg-[radial-gradient(circle_at_50%_50%,#1a0b2e_0%,#0d0618_50%,#05030a_100%)] overflow-hidden font-sans text-white [perspective:1200px]',
        [
          div(classes: 'splash-orb splash-orb-1', []),
          div(classes: 'splash-orb splash-orb-2', []),
          div(classes: 'splash-orb splash-orb-3', []),
          div(classes: 'splash-grid', []),
          div(classes: 'splash-shockwave', []),
          div(classes: 'splash-shockwave splash-shockwave-2', []),
          div(classes: 'splash-logo-container', [
            div(classes: 'splash-logo-glow', []),
            img(src: '/images/logo.svg', classes: 'splash-logo-img', attributes: {'alt': 'Tranyx Logo'}),
          ]),
          h1(classes: 'splash-title', [Component.text('TRANYX')]),
          p(classes: 'splash-subtitle', [Component.text('One Platform. Endless Opportunities.')]),
          div(classes: 'splash-loader-track', [
            div(classes: 'splash-loader-bar', []),
          ]),
        ],
      );
    }

    if (!isAuthenticated) {
      // Trigger random web metaballs initialization
      Timer.run(() => initRandomMetaballs('web-metaballs-container'));

      return div(
        classes:
            'min-h-screen w-full $darkBg font-sans flex items-center justify-center py-8 md:py-12 relative overflow-hidden',
        [
          // Floating 3D perspective grid background
          div(classes: 'splash-grid pointer-events-none', []),
          // Animated Metaballs background
          div(
            id: 'web-metaballs-container',
            classes: 'metaball-container',
            [],
          ),
          div(classes: 'w-full max-w-md p-6 z-10 relative', [
            AuthViewComponent(state: this),
          ]),
          if (showWalletSelectionModal) WalletSelectionModalComponent(state: this),
          if (showMobileAppPrompt) MobileAppPromptModalComponent(state: this),
        ],
      );
    }

    return div(classes: 'flex h-screen w-full overflow-hidden $darkBg font-sans', [
      // Desktop sidebar
      SidebarComponent(state: this),

      // Main area
      div(classes: 'flex-1 flex flex-col h-full relative overflow-hidden', [
        TopHeaderComponent(state: this),

        // Pending Payment Verification Banner
        if (pendingXenditInvoiceId != null)
          div(
            classes:
                'w-full py-3 px-6 ${isDark ? "bg-amber-500/10 border-zinc-800 text-amber-200" : "bg-amber-50 border-zinc-200 text-amber-800"} border-b text-xs flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 z-45 shrink-0 animate-fade-in',
            [
              span(classes: 'font-medium flex items-center gap-2', [
                lIcon('alert-triangle', cls: 'w-4 h-4 text-amber-450 shrink-0'),
                Component.text(
                  'Pending Tyxbit top-up of ₱${depositAmount.toStringAsFixed(2)} via Xendit. Please verify to credit and complete your request.',
                ),
              ]),
              div(classes: 'flex items-center gap-2', [
                button(
                  classes:
                      'px-3 py-1.5 rounded-lg text-xs font-bold text-white bg-green-500 hover:bg-green-600 transition-colors border-0 cursor-pointer flex items-center gap-1.5',
                  events: {
                    'click': (_) => setState(() {
                      showDepositModal = true;
                      selectedPaymentMethod = 'xendit';
                    }),
                  },
                  [lIcon('check-circle', cls: 'w-3.5 h-3.5'), Component.text('I Already Paid')],
                ),
                button(
                  classes:
                      'px-2 py-1.5 text-xs text-zinc-400 hover:text-zinc-300 cursor-pointer bg-transparent border-0 font-medium transition-colors',
                  events: {
                    'click': (_) {
                      if (confirmDialog(
                        'Dismiss this pending check? If you have paid, dismissing may delay your balance update.',
                      )) {
                        setState(() {
                          pendingXenditInvoiceId = null;
                          SessionStorage.pendingXenditInvoiceId = null;
                          SessionStorage.pendingXenditInvoiceAmount = 0.0;
                          SessionStorage.pendingPropertyBookingData = null;
                          SessionStorage.pendingVehicleBookingData = null;
                          SessionStorage.pendingJobId = null;
                          SessionStorage.pendingApplicantData = null;
                        });
                      }
                    },
                  },
                  [Component.text('Dismiss')],
                ),
              ]),
            ],
          ),

        // Scrollable content
        div(classes: 'flex-1 overflow-y-auto no-scrollbar pb-24 md:pb-8', [
          div(classes: 'mx-auto w-full max-w-6xl p-6 md:p-10', [
            if (activeTab == AppTab.home) HomeViewComponent(state: this),
            if (activeTab == AppTab.jobs) JobsViewComponent(state: this),
            if (activeTab == AppTab.transit) TransitViewComponent(state: this),
            if (activeTab == AppTab.profile) ProfileViewComponent(state: this),
          ]),
        ]),

        // Mobile bottom nav
        BottomNavComponent(state: this),

        // Powered by Terra logo badge in bottom right corner
        div(
          classes:
              'hidden md:flex items-center gap-1.5 absolute bottom-4 right-6 px-3 py-1.5 rounded-full border ${isDark ? "border-zinc-800 bg-zinc-900/60" : "border-zinc-200 bg-white/60"} backdrop-blur-md text-[10px] text-zinc-500 font-semibold z-40 transition-all hover:text-zinc-400',
          [
            Component.text('Powered by'),
            img(
              src: '/images/terra-logo.png',
              classes: 'h-3.5 object-contain opacity-60 hover:opacity-85 transition-opacity',
            ),
          ],
        ),
      ]),

      // Toast Notification
      if (latestToastNotification != null)
        div(
          classes:
              'fixed top-6 right-6 max-w-sm w-full bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 shadow-xl rounded-xl p-4 z-[9999] transform transition-all duration-500 flex items-start gap-3 translate-y-0 opacity-100',
          [
            div(
              classes:
                  'p-2 bg-indigo-100 dark:bg-indigo-500/20 text-indigo-600 dark:text-indigo-400 rounded-lg flex-shrink-0',
              [
                lIcon('bell', cls: 'w-5 h-5'),
              ],
            ),
            div(classes: 'flex-1 pt-1', [
              p(classes: 'text-sm font-bold text-zinc-900 dark:text-white', [
                Component.text(latestToastNotification!['title'] as String? ?? 'Notification'),
              ]),
              p(classes: 'text-xs text-zinc-500 mt-1', [
                Component.text(latestToastNotification!['message'] as String? ?? ''),
              ]),
            ]),
            button(
              classes: 'p-1 text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 transition-colors rounded-lg',
              events: {'click': (_) => setState(() => latestToastNotification = null)},
              [lIcon('x', cls: 'w-4 h-4')],
            ),
          ],
        ),

      // Category modal overlay
      if (showCategoryModal) CategoryModalComponent(state: this, key: const ValueKey('category-modal')),

      // List Vehicle modal overlay
      if (showListVehicleModal) ListVehicleModalComponent(appState: this, key: const ValueKey('list-vehicle-modal')),

      // Book Vehicle modal overlay
      if (showBookVehicleModal) BookVehicleModalComponent(appState: this, key: const ValueKey('book-vehicle-modal')),

      // Extend Rental modal overlay
      if (showExtendRentalModal) ExtendRentalModalComponent(appState: this, key: const ValueKey('extend-rental-modal')),

      // Rental Tracker Map overlay
      if (showRentalTrackerMap) RentalTrackerMapComponent(appState: this, key: const ValueKey('rental-tracker-map')),

      // Manage Vehicle modal overlay
      if (showManageVehicleModal)
        ManageVehicleModalComponent(appState: this, key: const ValueKey('manage-vehicle-modal')),

      // Public Vehicle Q&A modal overlay
      if (showVehicleQaModal && selectedRentalData != null)
        VehicleQaModalComponent(
          appState: this,
          rentalId: selectedRentalData!['id'],
          key: const ValueKey('vehicle-qa-modal'),
        ),

      // List Property modal overlay
      if (showListPropertyModal) ListPropertyModalComponent(appState: this, key: const ValueKey('list-property-modal')),

      // Book Property modal overlay
      if (showBookPropertyModal) BookPropertyModalComponent(appState: this, key: const ValueKey('book-property-modal')),

      // Manage Property modal overlay
      if (showManagePropertyModal)
        ManagePropertyModalComponent(appState: this, key: const ValueKey('manage-property-modal')),

      // Public Property Q&A modal overlay
      if (showPropertyQaModal) PropertyQaModalComponent(appState: this, key: const ValueKey('property-qa-modal')),

      // Unified Sign Contract modal overlay
      if (showSignContractModal && signingContractId != null)
        SignContractModalComponent(
          appState: this,
          title: signingContractTitle ?? '',
          contractTerms: signingContractTerms ?? '',
          rentalId: signingContractId!,
          isProperty: signingContractIsProperty,
          key: const ValueKey('sign-contract-modal'),
          onSigned: () {
            setState(() {
              showSignContractModal = false;
              signingContractId = null;
              signingContractTitle = null;
              signingContractTerms = null;
            });
            if (signingContractIsProperty) {
              _startListeningProperties();
            } else {
              _restoreSession();
            }
          },
        ),

      // Session Expired modal overlay
      if (showSessionExpiredModal) SessionExpiredModalComponent(state: this),

      // Wallet Selection modal overlay
      if (showWalletSelectionModal) WalletSelectionModalComponent(state: this),

      // Payment modal overlay
      if (showDepositModal) PaymentModalComponent(state: this),

      // SMS Verification modal overlay
      if (showSmsModal) SmsVerificationModalComponent(state: this),

      // Wallet Reconnect modal overlay
      if (showWalletReconnectPrompt) WalletReconnectModalComponent(state: this),

      // Rating modal overlay
      if (showRatingPopup) RatingModalComponent(state: this),

      // KYC modals
      if (showKycIdModal) KycIdModalComponent(state: this),
      if (showKycBgModal) KycBgModalComponent(state: this),

      // Delete confirmation modal overlay
      if (showDeleteConfirm) DeleteConfirmModalComponent(state: this),

      // Chat overlay
      if (showChat) ChatWidget(state: this),

      // Fullscreen Photo Modal Overlay
      if (fullScreenPhotoUrl != null)
        div(
          classes:
              'fixed inset-0 z-[1000] flex items-center justify-center p-4 bg-black/85 backdrop-blur-md animate-fade-in cursor-zoom-out',
          events: {'click': (_) => setState(() => fullScreenPhotoUrl = null)},
          [
            button(
              classes:
                  'absolute top-6 right-6 p-3 rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors cursor-pointer border-0',
              events: {'click': (_) => setState(() => fullScreenPhotoUrl = null)},
              [lIcon('x', cls: 'w-6 h-6')],
            ),
            img(
              src: fullScreenPhotoUrl!,
              classes:
                  'max-w-full max-h-[90vh] object-contain rounded-2xl shadow-2xl transition-all scale-100 cursor-default',
              events: {'click': (e) => e.stopPropagation()},
            ),
          ],
        ),

      // User Profile modal overlay
      if (showEmployerProfileModal) _buildUserProfileModal(isDark),
    ]);
  }
}

class SmsVerificationModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const SmsVerificationModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final codeSent = s.smsVerificationSessionInfo.isNotEmpty;

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md rounded-3xl border p-6 relative overflow-hidden transition-all duration-300 '
              '${isDark ? "bg-zinc-900 border-zinc-800 text-white" : "bg-white border-zinc-200 text-zinc-800 shadow-2xl"}',
          [
            // Premium background gradient flare
            div(
              [],
              classes: 'absolute top-0 right-0 w-32 h-32 bg-indigo-500/10 rounded-full blur-3xl pointer-events-none',
            ),

            // Header
            div(classes: 'flex items-start justify-between mb-5 relative z-10', [
              div([
                h3(classes: 'text-lg font-black tracking-tight flex items-center gap-2', [
                  lIcon('shield-check', cls: 'w-5 h-5 text-indigo-400'),
                  Component.text('Mobile Verification'),
                ]),
                p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"} mt-0.5', [
                  Component.text('Establish community trust and unlock badges.'),
                ]),
              ]),
              button(
                classes: 'p-1.5 rounded-full hover:bg-zinc-500/10 text-zinc-400 hover:text-zinc-200 transition-colors',
                events: {'click': (_) => s.setState(() => s.showSmsModal = false)},
                [lIcon('x', cls: 'w-4 h-4')],
              ),
            ]),

            // Error banner if any
            if (s.smsVerificationError != null)
              div(
                classes:
                    'p-3 mb-4 rounded-xl text-xs bg-red-500/10 border border-red-500/20 text-red-400 flex gap-2 items-start animate-shake',
                [
                  lIcon('alert-circle', cls: 'w-4 h-4 flex-shrink-0 mt-0.5'),
                  span(classes: 'font-medium', [Component.text(s.smsVerificationError!)]),
                ],
              ),

            // OTP Code Simulator Box (Only if simulated code is active!)
            if (codeSent && s.simulatedSmsCode != null)
              div(
                classes:
                    'p-4 mb-5 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs space-y-1 relative overflow-hidden',
                [
                  div(classes: 'flex items-center gap-1.5 font-bold mb-1', [
                    lIcon('terminal', cls: 'w-4 h-4'),
                    Component.text('Tranyx SMS Simulator Console'),
                  ]),
                  p(classes: 'font-medium opacity-85', [
                    Component.text('For seamless local testing, type the simulated verification code below:'),
                  ]),
                  div(
                    classes:
                        'mt-2 text-sm font-black tracking-widest text-center select-all bg-emerald-500/20 py-2 rounded-xl border border-emerald-500/30',
                    [
                      Component.text(s.simulatedSmsCode!),
                    ],
                  ),
                ],
              ),

            // Content
            if (!codeSent) ...[
              // Number Input State
              div(classes: 'space-y-4 mb-6', [
                div(classes: 'space-y-1', [
                  label(
                    classes:
                        'block text-xs font-bold ${isDark ? "text-zinc-400" : "text-zinc-500"} uppercase tracking-wider mb-1',
                    [
                      Component.text('Philippine Mobile Number'),
                    ],
                  ),
                  div(classes: 'flex gap-2 items-stretch', [
                    div(
                      classes:
                          'px-4 py-3 rounded-2xl flex items-center bg-zinc-500/10 font-bold border border-zinc-500/20 text-zinc-500 text-sm',
                      [Component.text('+63')],
                    ),
                    input(
                      type: InputType.tel,
                      classes:
                          'flex-1 px-4 py-3 rounded-2xl border text-sm font-semibold transition-all focus:outline-none focus:ring-2 focus:ring-indigo-500/20 '
                          '${isDark ? "bg-zinc-950 border-zinc-800 text-white placeholder-zinc-600 focus:border-indigo-500" : "bg-zinc-50 border-zinc-200 text-zinc-800 placeholder-zinc-400 focus:border-indigo-400"}',
                      attributes: {
                        'placeholder': '9000000000',
                        'maxlength': '10',
                        'id': 'verification-phone-input',
                        'name': 'phone',
                      },
                      value: s.smsVerificationPhoneNumber,
                      events: {
                        'input': (e) {
                          final val = getInputValue(e.target);
                          var digits = val.replaceAll(RegExp(r'\D'), '');
                          if (digits.length > 10) digits = digits.substring(0, 10);
                          s.setState(() => s.smsVerificationPhoneNumber = digits);
                        },
                      },
                    ),
                  ]),
                ]),
              ]),

              button(
                classes:
                    'w-full py-3.5 rounded-2xl font-bold text-white logo-gradient hover:opacity-95 transition-opacity flex items-center justify-center gap-2',
                events: s.isSendingSms ? {} : {'click': (_) => s.sendSmsCodeAction(s.smsVerificationPhoneNumber)},
                [
                  if (s.isSendingSms)
                    lIcon('loader-2', cls: 'w-4 h-4 animate-spin')
                  else
                    lIcon('message-square', cls: 'w-4 h-4'),
                  Component.text(s.isSendingSms ? 'Sending OTP Code...' : 'Send OTP via SMS'),
                ],
              ),
            ] else ...[
              // OTP Code Entry State
              div(classes: 'space-y-4 mb-6', [
                div(classes: 'space-y-1 text-center mb-2', [
                  p(classes: 'text-sm font-semibold', [
                    Component.text('We sent a 6-digit OTP code to:'),
                  ]),
                  p(classes: 'text-base font-bold text-indigo-400 mt-0.5', [
                    Component.text('+63 ${s.smsVerificationPhoneNumber}'),
                  ]),
                ]),

                div(classes: 'space-y-1', [
                  label(
                    classes:
                        'block text-xs font-bold ${isDark ? "text-zinc-400" : "text-zinc-500"} uppercase tracking-wider text-center mb-2',
                    [
                      Component.text('Enter 6-Digit OTP Code'),
                    ],
                  ),
                  input(
                    type: InputType.text,
                    classes:
                        'w-full px-4 py-3.5 rounded-2xl border text-center text-xl font-bold tracking-[0.7em] transition-all focus:outline-none focus:ring-2 focus:ring-indigo-500/20 '
                        '${isDark ? "bg-zinc-950 border-zinc-800 text-white focus:border-indigo-500" : "bg-zinc-50 border-zinc-200 text-zinc-800 focus:border-indigo-400"}',
                    attributes: {
                      'placeholder': '••••••',
                      'maxlength': '6',
                      'id': 'verification-otp-input',
                      'name': 'otp',
                    },
                    value: s.smsVerificationCode,
                    events: {
                      'input': (e) {
                        final val = getInputValue(e.target);
                        s.setState(() => s.smsVerificationCode = val.replaceAll(RegExp(r'\D'), ''));
                      },
                    },
                  ),
                ]),
              ]),

              div(classes: 'flex gap-3', [
                button(
                  classes:
                      'flex-1 py-3.5 rounded-2xl font-bold border transition-colors '
                      '${isDark ? "border-zinc-800 hover:bg-zinc-800 text-zinc-400" : "border-zinc-200 hover:bg-zinc-50 text-zinc-500"}',
                  events: {'click': (_) => s.setState(() => s.smsVerificationSessionInfo = '')},
                  [Component.text('Back')],
                ),
                button(
                  classes:
                      'flex-[2] py-3.5 rounded-2xl font-bold text-white logo-gradient hover:opacity-95 transition-opacity flex items-center justify-center gap-2',
                  events: s.isVerifyingSms ? {} : {'click': (_) => s.verifySmsCodeAction(s.smsVerificationCode)},
                  [
                    if (s.isVerifyingSms)
                      lIcon('loader-2', cls: 'w-4 h-4 animate-spin')
                    else
                      lIcon('check-circle', cls: 'w-4 h-4'),
                    Component.text(s.isVerifyingSms ? 'Verifying...' : 'Verify OTP'),
                  ],
                ),
              ]),
            ],
          ],
        ),
      ],
    );
  }
}

class WalletSelectionModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const WalletSelectionModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;

    final wallets = [
      {'id': 'phantom', 'name': 'Phantom', 'url': 'https://phantom.app/download'},
      {'id': 'solflare', 'name': 'Solflare', 'url': 'https://solflare.com/download'},
      {'id': 'trust', 'name': 'Trust Wallet', 'url': 'https://trustwallet.com/download'},
      {'id': 'backpack', 'name': 'Backpack', 'url': 'https://backpack.app/download'},
    ];

    Component getWalletIcon(String id, {String size = 'w-6 h-6'}) {
      if (id == 'phantom') return img(src: '/images/PhantomWallet.png', classes: '$size object-contain rounded-md');
      if (id == 'solflare') return img(src: '/images/Solflare.png', classes: '$size object-contain rounded-md');
      if (id == 'trust') return img(src: '/images/TrustWallet.jpeg', classes: '$size object-contain rounded-md');
      if (id == 'backpack') return img(src: '/images/BackPack.png', classes: '$size object-contain rounded-md');
      return lIcon('wallet', cls: '$size text-white');
    }

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md rounded-3xl border p-6 relative overflow-hidden transition-all duration-300 '
              '${isDark ? "bg-zinc-900 border-zinc-800 text-white" : "bg-white border-zinc-200 text-zinc-800 shadow-2xl"}',
          [
            // Top accent color flare
            div(
              [],
              classes:
                  'absolute top-0 left-0 right-0 h-1.5 bg-gradient-to-r from-purple-500 via-indigo-500 to-blue-500',
            ),

            // Close button
            button(
              classes:
                  'absolute top-4 right-4 p-2 rounded-full transition-colors cursor-pointer '
                  '${isDark ? "hover:bg-zinc-800 text-zinc-400 hover:text-white" : "hover:bg-zinc-100 text-zinc-500 hover:text-zinc-800"}',
              events: {
                'click': (_) => s.setState(() {
                  s.showWalletSelectionModal = false;
                }),
              },
              [lIcon('x', cls: 'w-4 h-4')],
            ),

            div(classes: 'flex flex-col space-y-4 pt-2', [
              div(classes: 'text-center', [
                h3(classes: 'text-xl font-black tracking-tight', [Component.text('Connect a Wallet')]),
                p(
                  classes: 'text-xs mt-2 leading-relaxed ${isDark ? "text-zinc-400" : "text-zinc-500"}',
                  [
                    Component.text(
                      'Select a Solana wallet from the list below to access your SOL and SPL tokens.',
                    ),
                  ],
                ),
              ]),

              div(classes: 'space-y-2.5 pt-2', [
                for (final w in wallets)
                  () {
                    final id = w['id']!;
                    final name = w['name']!;
                    final url = w['url']!;
                    final isInstalled = isSolanaWalletInstalled(id);
                    final isCurrentlyConnected = s.walletState == WalletState.connected && s.selectedWalletType == id;

                    final statusText = isCurrentlyConnected
                        ? 'Connected'
                        : (isInstalled ? 'Detected' : 'Not Installed');
                    final badgeClasses = isCurrentlyConnected
                        ? 'bg-emerald-500/10 text-emerald-400'
                        : (isInstalled ? 'bg-indigo-500/10 text-indigo-400' : 'bg-zinc-500/10 text-zinc-400');
                    final dotClasses = isCurrentlyConnected
                        ? 'bg-emerald-400'
                        : (isInstalled ? 'bg-indigo-400' : 'bg-zinc-400');

                    return div(
                      classes:
                          'w-full flex items-center justify-between p-3.5 rounded-2xl border transition-all '
                          '${isDark ? "bg-zinc-950/40 border-zinc-800/80 hover:border-zinc-700 hover:bg-zinc-900/60" : "bg-zinc-50/50 border-zinc-200/80 hover:border-zinc-300 hover:bg-zinc-50"}',
                      [
                        div(classes: 'flex items-center gap-3.5', [
                          div(
                            classes:
                                'p-2.5 rounded-xl ${isDark ? "bg-zinc-900" : "bg-white border border-zinc-150"} flex items-center justify-center',
                            [getWalletIcon(id, size: 'w-6 h-6')],
                          ),
                          div([
                            p(classes: 'font-bold text-sm tracking-tight', [Component.text(name)]),
                            span(
                              classes:
                                  'inline-flex items-center gap-1 text-[10px] font-bold mt-1 px-2 py-0.5 rounded-md '
                                  '$badgeClasses',
                              [
                                span(
                                  classes: 'w-1.5 h-1.5 rounded-full $dotClasses',
                                  [],
                                ),
                                Component.text(statusText),
                              ],
                            ),
                          ]),
                        ]),

                        if (isInstalled)
                          if (isCurrentlyConnected)
                            button(
                              classes:
                                  'px-4 py-2 rounded-xl text-xs font-bold text-white bg-red-500 hover:bg-red-600 transition-colors border-0 cursor-pointer shadow-md shadow-red-500/10',
                              events: {
                                'click': (_) => s.handleDisconnectWallet(),
                              },
                              [Component.text('Disconnect')],
                            )
                          else
                            button(
                              classes:
                                  'px-4 py-2 rounded-xl text-xs font-bold text-white bg-indigo-500 hover:bg-indigo-600 transition-colors border-0 cursor-pointer shadow-md shadow-indigo-500/10',
                              events: {
                                'click': (_) => s.handleSelectSolanaWallet(id),
                              },
                              [Component.text('Connect')],
                            )
                        else
                          a(
                            href: url,
                            classes:
                                'px-4 py-2 rounded-xl text-xs font-bold text-zinc-400 border border-zinc-700 hover:text-white hover:bg-zinc-800 transition-all text-center no-underline cursor-pointer',
                            target: Target.blank,
                            attributes: const {
                              'rel': 'noopener noreferrer',
                            },
                            [Component.text('Install')],
                          ),
                      ],
                    );
                  }(),
              ]),
            ]),
          ],
        ),
      ],
    );
  }
}

class WalletReconnectModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const WalletReconnectModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final walletKey = s.pendingReconnectWalletKey ?? '';
    final shortKey = walletKey.length > 8
        ? '${walletKey.substring(0, 4)}...${walletKey.substring(walletKey.length - 4)}'
        : walletKey;

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-md animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md rounded-3xl border p-6 relative overflow-hidden transition-all duration-300 '
              '${isDark ? "bg-zinc-900 border-zinc-800 text-white" : "bg-white border-zinc-200 text-zinc-800 shadow-2xl"}',
          [
            // Top accent color flare
            div(
              [],
              classes:
                  'absolute top-0 left-0 right-0 h-1.5 bg-gradient-to-r from-purple-500 via-indigo-500 to-blue-500',
            ),

            div(classes: 'flex flex-col items-center text-center space-y-4 pt-2', [
              div(
                classes:
                    'w-14 h-14 rounded-full bg-[#512da8]/15 flex items-center justify-center text-[#512da8] border border-[#512da8]/35 shadow-lg shadow-purple-500/10',
                [lIcon('wallet', cls: 'w-7 h-7')],
              ),

              div([
                h3(classes: 'text-xl font-black tracking-tight', [Component.text('Reconnect Phantom Wallet')]),
                p(
                  classes: 'text-xs mt-2 leading-relaxed ${isDark ? "text-zinc-400" : "text-zinc-500"}',
                  [
                    Component.text(
                      'We detected a linked Phantom Wallet on your profile. Would you like to reconnect to restore access to your Solana funds?',
                    ),
                  ],
                ),
              ]),

              div(
                classes:
                    'w-full py-3 px-4 rounded-2xl font-mono text-xs font-bold flex items-center justify-between border '
                    '${isDark ? "bg-zinc-950/60 border-zinc-800 text-purple-300" : "bg-purple-50/50 border-purple-100 text-purple-700"}',
                [
                  span(classes: 'text-[10px] uppercase font-black tracking-wider text-zinc-400', [
                    Component.text('Linked Wallet'),
                  ]),
                  span([Component.text(shortKey)]),
                ],
              ),

              div(classes: 'flex gap-3 w-full pt-2', [
                button(
                  classes:
                      'flex-1 py-3.5 rounded-2xl font-bold text-sm bg-zinc-500/10 hover:bg-zinc-500/15 transition-all text-center '
                      '${isDark ? "text-zinc-300 hover:text-white" : "text-zinc-600 hover:text-zinc-800"}',
                  events: {
                    'click': (_) => s.setState(() {
                      s.showWalletReconnectPrompt = false;
                      s.pendingReconnectWalletKey = null;
                    }),
                  },
                  [Component.text('Skip')],
                ),
                button(
                  classes:
                      'flex-1 py-3.5 rounded-2xl font-bold text-sm text-white bg-[#512da8] hover:bg-[#4527a0] transition-all text-center shadow-lg shadow-purple-500/20',
                  events: {
                    'click': (_) async {
                      s.setState(() {
                        s.showWalletReconnectPrompt = false;
                        s.pendingReconnectWalletKey = null;
                      });
                      await s.handleConnectWallet();
                    },
                  },
                  [Component.text('Reconnect')],
                ),
              ]),
            ]),
          ],
        ),
      ],
    );
  }
}

class MobileAppPromptModalComponent extends StatelessComponent {
  final TranyxAppState state;
  const MobileAppPromptModalComponent({required this.state, super.key});

  @override
  Component build(BuildContext context) {
    final s = state;
    final isDark = s.isDark;
    final userAgent = web.window.navigator.userAgent.toLowerCase();
    final isAndroid = userAgent.contains('android');

    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    String appId = 'com.terraph.tranyx';
    if (env == 'uat') appId = 'com.terraph.tranyx.uat';
    if (env == 'dev') appId = 'com.terraph.tranyx.dev';

    return div(
      classes:
          'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-md p-6 rounded-3xl border shadow-2xl ${isDark ? "bg-zinc-900 border-zinc-800 text-white" : "bg-white border-zinc-200 text-zinc-900"}',
          [
            div(classes: 'flex justify-between items-center mb-5', [
              div(classes: 'flex items-center gap-3', [
                svgLogo(size: 'w-7 h-7'),
                h3(classes: 'font-bold text-lg', [Component.text('Open Tranyx Mobile')]),
              ]),
              button(
                classes:
                    'p-1.5 rounded-full hover:bg-zinc-500/10 transition-colors ${isDark ? "text-zinc-400 hover:text-white" : "text-zinc-500 hover:text-zinc-800"}',
                events: {'click': (_) => s.setState(() => s.showMobileAppPrompt = false)},
                [lIcon('x', cls: 'w-5 h-5')],
              ),
            ]),
            p(classes: 'text-sm mb-6 ${isDark ? "text-zinc-400" : "text-zinc-600"} leading-relaxed', [
              Component.text(
                'How would you like to experience Tranyx on your device? You can continue in your web browser or open our mobile app.',
              ),
            ]),
            div(classes: 'space-y-3', [
              if (isAndroid)
                button(
                  classes:
                      'w-full py-3.5 px-4 rounded-2xl font-semibold border flex items-center justify-between transition-all ${isDark ? "border-purple-500/30 bg-purple-500/10 text-purple-300 hover:bg-purple-500/20" : "border-purple-200 bg-purple-50 text-purple-700 hover:bg-purple-100"}',
                  events: {
                    'click': (_) {
                      s.setState(() => s.showMobileAppPrompt = false);
                      web.window.location.assign('dappstore://details?id=$appId');
                    },
                  },
                  [
                    div(classes: 'flex items-center gap-3', [
                      lIcon('sparkles', cls: 'w-5 h-5 text-purple-400'),
                      span([Component.text('Solana dApp Store')]),
                    ]),
                    lIcon('external-link', cls: 'w-4 h-4 opacity-70'),
                  ],
                ),
              button(
                classes:
                    'w-full py-3.5 px-4 rounded-2xl font-semibold border flex items-center justify-center transition-all ${isDark ? "border-zinc-800 bg-zinc-800/80 text-zinc-300 hover:bg-zinc-800 hover:text-white" : "border-zinc-200 bg-zinc-100 text-zinc-700 hover:bg-zinc-200"}',
                events: {'click': (_) => s.setState(() => s.showMobileAppPrompt = false)},
                [Component.text('Continue in Web Browser')],
              ),
            ]),
          ],
        ),
      ],
    );
  }
}

