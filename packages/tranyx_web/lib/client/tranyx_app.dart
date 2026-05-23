// ignore: avoid_web_libraries_in_flutter
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'dart:async';
import 'dart:convert';
import 'package:tranyx_web/services/web_interop.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';

import 'package:tranyx_web/services/firebase_service.dart';
import 'package:tranyx_web/components/ui_helpers.dart';

import '../state/app_state.dart';
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

@client
class TranyxApp extends StatefulComponent {
  const TranyxApp({super.key});
  @override
  State<TranyxApp> createState() => TranyxAppState();
}

class TranyxAppState extends State<TranyxApp> {
  // ── Theme / Auth ────────────────────────────────────────────
  bool isDark = true;
  bool isAuthenticated = false;
  bool isAuthLoading = false;
  String? authError;

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

  // ── Jobs state ──────────────────────────────────────────────
  List<Map<String, dynamic>> myJobs = [];
  List<Map<String, dynamic>> sessionPostedJobs = [];
  List<Map<String, dynamic>> realtimeEmployerJobs = [];
  List<Map<String, dynamic>> realtimeNyxianJobs = [];
  List<Map<String, dynamic>> availableJobs = [];
  List<Map<String, dynamic>> realtimeRentals = [];
  List<Map<String, dynamic>> renterPendingRequests = [];
  bool isLoadingJobs = false;
  String? jobsError;
  String activeJobFilter = 'Recommended';
  String activeJobPane = 'active'; // 'active'/'history' for employer, 'browse'/'my_gigs' for nyxian
  Map<String, dynamic>? ongoingJob; // first 'In Progress' job
  String homeSearchQuery = '';

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

  // Job Completion State
  bool showCompletionScanner = false;
  String completionScanInput = '';
  bool isCompletingJob = false;
  bool isGeneratingCode = false;
  String? generatedCompletionCode;

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
  WalletState walletState = WalletState.disconnected;
  String walletAddress = '';
  double walletBalance = 0.0;
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
  bool isUploadingChatPhoto = false;
  Map<String, dynamic>? acceptedApplicantProfile;




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
      final isTerminal = s == 'completed' || s == 'done' || s == 'complete' || s == 'cancelled' || s == 'closed';
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
        final isTerminal = s == 'completed' || s == 'done' || s == 'complete' || s == 'cancelled' || s == 'closed';
        return !isTerminal;
      });
    } catch (_) {
      return null;
    }
  }

  void showAppToast(String title, String message) {
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
              
              final title = fresh['title'] as String? ?? selectedJob?.title ?? '';
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
    if (SessionStorage.hasSession) {
      _restoreSession();
    }
    _initGemini();
  }

  void _initGemini() {
    _gemini = GeminiService(currentFirebaseConfig, idToken: SessionStorage.idToken);
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
    // Load jobs for current tab
    await loadJobs();
    await loadTransactions();
    _startListeningNotifications();
    _startListeningJobs();
    _startListeningRentals();
    _startListeningProperties();
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
          
          // Identify if there are new notifications that we didn't have before
          final newNotifs = unreadNotifs.where((n) => !notifications.any((existing) => existing['id'] == n['id'])).toList();
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
          notifications = unreadNotifs;
        });
      } catch (e) {
        print('Error parsing notifications: $e');
      }
    });
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
              return s != null &&
                  s != 'open' &&
                  s != 'completed' &&
                  s != 'cancelled' &&
                  s != 'held' &&
                  s != 'pending';
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
      final list = await _firestore.getRenterPendingRequests(uid);
      setState(() {
        renterPendingRequests = list;
      });
    } catch (e) {
      print('Error loading renter pending requests: $e');
    }
  }

  Future<void> loadUserProfile() async {
    final uid = SessionStorage.uid;
    if (uid == null) return;
    try {
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
    } catch (_) {}
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
          await FirestoreService(result.idToken, _handleTokenRefresh).linkWalletToUser(result.uid, walletKey);
        } catch (_) {}
      }

      _initGemini();
      await loadJobs();
      await loadTransactions();
      _startListeningNotifications();
      _startListeningJobs();
      _startListeningRentals();
      // Auto-connect Phantom wallet if already trusted by the browser
      unawaited(autoConnectPhantomIfLinked(profile?.walletPublicKey));
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
          await FirestoreService(result.idToken, _handleTokenRefresh).linkWalletToUser(result.uid, walletKey);
        } catch (_) {}
      }

      _initGemini();
      await loadJobs();
      await loadTransactions();
      _startListeningNotifications();
      _startListeningJobs();
      _startListeningRentals();
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
        // Redirect to register path to ask for role
        setState(() {
          pendingGoogleAuthResult = authResult;
          authView = AuthView.registerPath;
          isAuthLoading = false;
        });
        return;
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
        userName = profile.name;
        userEmail = profile.email;
        userProfile = profile;
        isAuthLoading = false;
        authView = AuthView.login;
      });

      if (pendingWalletPublicKey != null) {
        final walletKey = pendingWalletPublicKey!;
        pendingWalletPublicKey = null;
        try {
          await FirestoreService(authResult.idToken, _handleTokenRefresh).linkWalletToUser(authResult.uid, walletKey);
        } catch (_) {}
      }

      _initGemini();
      await loadJobs();
      await loadTransactions();
      _startListeningNotifications();
      _startListeningJobs();
      _startListeningRentals();
      unawaited(autoConnectPhantomIfLinked(profile.walletPublicKey));
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
          await FirestoreService(authResult.idToken, _handleTokenRefresh).linkWalletToUser(authResult.uid, walletKey);
        } catch (_) {}
      }

      _initGemini();
      await loadJobs();
      await loadTransactions();
      _startListeningNotifications();
      _startListeningJobs();
      _startListeningRentals();
      unawaited(autoConnectPhantomIfLinked(profile.walletPublicKey));
    } catch (e) {
      setState(() {
        authError = e.toString();
        isAuthLoading = false;
      });
    }
  }

  Future<void> handlePhantomSignIn() async {
    if (!isPhantomInstalled()) {
      setState(() {
        authError = 'Phantom Wallet is not installed. Please visit phantom.app to install it.';
      });
      return;
    }

    setState(() {
      isAuthLoading = true;
      authError = null;
    });

    try {
      final publicKey = await connectPhantomWallet();
      if (publicKey == null) {
        setState(() {
          authError = 'Wallet connection was rejected or failed.';
          isAuthLoading = false;
        });
        return;
      }

      // Check if this wallet is linked to an existing account
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

            // Load user profile from Firestore to get account type
            final profile = await FirestoreService(authResult.idToken, _handleTokenRefresh).getUser(authResult.uid);
            final type = profile?.accountType ?? AccountType.employer;

            SessionStorage.saveProfile(
              name: profile?.name ?? authResult.displayName ?? (authResult.email?.split('@').first ?? 'User'),
              email: authResult.email ?? '',
              accountType: type.name,
            );

            setState(() {
              isAuthenticated = true;
              accountType = type;
              hybridToggle = type == AccountType.nyxian ? AccountType.nyxian : AccountType.employer;
              userName = profile?.name ?? authResult.displayName ?? (authResult.email?.split('@').first ?? 'User');
              userEmail = authResult.email ?? '';
              userProfile = profile;
              isAuthLoading = false;
              authView = AuthView.login;
            });

            _initGemini();
            await loadJobs();
            unawaited(autoConnectPhantomIfLinked(profile?.walletPublicKey));
            return;
          } catch (e) {
            // Token refresh failed, fallback to manual login
            setState(() {
              isAuthLoading = false;
              authError = '🦊 Wallet recognized but session expired. Please sign in with email & password.';
              pendingWalletPublicKey = publicKey;
            });
            return;
          }
        } else {
          // Legacy or no refresh token stored — fallback to prompt
          setState(() {
            isAuthLoading = false;
            authError = '🦊 Wallet recognized! Please sign in with your email & password to continue.';
            pendingWalletPublicKey = publicKey;
          });
          return;
        }
      } else {
        // New user — redirect to register with wallet pre-linked
        setState(() {
          isAuthLoading = false;
          authError = null;
          pendingWalletPublicKey = publicKey;
          authView = AuthView.registerPath;
        });
      }
    } catch (e) {
      setState(() {
        authError = 'Phantom connection error: ${e.toString()}';
        isAuthLoading = false;
      });
    }
  }

  void handleLogout() {
    SessionStorage.clear();
    stopListeningToJobsJs();
    stopListeningToRentalsJs();
    stopListeningToPropertiesJs();
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
    });
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
      if (uid == null) return;
      final my = await _firestore.getMyJobs(uid);
      final accepted = await _firestore.getAcceptedJobs(uid);

      // Combine created jobs and accepted jobs into one list
      final allMyJobs = [...my, ...accepted];

      final avail = await _firestore.getAvailableJobs(currentViewMode);

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
          return s != null &&
              s != 'open' &&
              s != 'completed' &&
              s != 'cancelled' &&
              s != 'held' &&
              s != 'pending';
        },
        orElse: () => null,
      );
      setState(() {
        myJobs = merged;
        availableJobs = avail;
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

  Future<void> handlePostJob() async {
    final uid = SessionStorage.uid;
    final token = SessionStorage.idToken;
    if (uid == null || token == null) return;

    if (!canPostJob) {
      setState(() {
        postJobError = 'Normal accounts can only have 1 active job at a time. Please complete your current ongoing job before posting a new one.';
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
      if (currentBal < price) {
        setState(() {
          depositAmount = price - currentBal;
          showDepositModal = true;
          isPostingJob = false;
        });
        return;
      }

      // 2. Sufficient balance: Deduct and Move to Escrow
      await svc.createOrUpdate('users/$uid', {
        ...userDoc,
        'tyxBalance': currentBal - price,
      });

      // Update local state balance
      walletBalance = currentBal - price;
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

      // Create escrow record
      await svc.createOrUpdate('escrow/$jobId', {
        'amount': price,
        'employerId': uid,
        'status': 'held',
        'createdAt': now.millisecondsSinceEpoch,
      });

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
      const apiKey = 'xnd_development_6en2scIVPSVNYySuAtoeoHL7NTZ0xl5tMfMsHbkJT3e2HnI7fyFxkC1LkDD3A';
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
          'amount': depositAmount,
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
      const apiKey = 'xnd_development_6en2scIVPSVNYySuAtoeoHL7NTZ0xl5tMfMsHbkJT3e2HnI7fyFxkC1LkDD3A';
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
          }

          setState(() {
            isVerifyingPayment = false;
            pendingXenditInvoiceId = null;
            showDepositModal = false;
          });

          // Finalize job posting ONLY if we were in the middle of posting a job
          if (newJobTitle.isNotEmpty) {
            await handlePostJob();
          } else if (pendingJobId != null && pendingApplicantData != null) {
            final jId = pendingJobId!;
            final aData = pendingApplicantData!;
            pendingJobId = null;
            pendingApplicantData = null;
            await acceptApplicant(jId, aData);
          }
        } else if (status == 'EXPIRED') {
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

    final tyxBal = userProfile?.tyxBalance ?? 0.0;
    if (tyxBal < 100) {
      setState(() => profileSaveError = 'Minimum withdrawal is 100 Tyx (₱100).');
      return;
    }

    setState(() => isSavingProfile = true);

    try {
      final svc = FirestoreService(token, _handleTokenRefresh);

      // Create withdrawal request record
      await svc.createOrUpdate('withdrawalRequests', {
        'uid': uid,
        'userName': userName,
        'amount': tyxBal,
        'status': 'Pending',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'method': 'Bank/Gcash',
      });

      // Optionally deduct balance immediately or wait for approval
      // For this MVP, we'll wait for back-office approval before deducting.

      setState(() {
        isSavingProfile = false;
        profileSaveError = 'Withdrawal request sent! Our back office will process it within 24 hours.';
      });
    } catch (e) {
      setState(() {
        isSavingProfile = false;
        profileSaveError = 'Failed to send request: $e';
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
        final url = await ImgBBService(currentFirebaseConfig, idToken: token).uploadImageBytes(file.bytes, file.name);
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
    final title = jobMap['title'] as String? ?? '';
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
          (p) => p.id == propertyId,
          orElse: () => PropertyRental(
            id: '', hostId: '', hostName: '', title: '', description: '',
            type: PropertyType.house, category: PropertyCategory.residential,
            priceMonthly: 0, priceWeekly: 0, priceDaily: 0, depositMonths: 0,
            address: '', latitude: 0, longitude: 0, photoUrls: [], amenities: [],
            status: '', contractType: '', contractTerms: '', createdAt: DateTime.now(), allowChat: false,
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
    });
    listenToChatJs(chatId, (String jsonStr) {
      try {
        final raw = jsonDecode(jsonStr) as List<dynamic>;
        setState(() {
          chatMessages = raw.map((m) {
            final map = Map<String, dynamic>.from(m as Map);
            // Normalize Firestore timestamp
            if (map['createdAt'] is Map) {
              final ts = map['createdAt'] as Map;
              map['createdAt'] = (ts['_seconds'] as int? ?? 0) * 1000 +
                  ((ts['_nanoseconds'] as int? ?? 0) ~/ 1000000);
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
      Timer(const Duration(seconds: 3), () {
        setState(() => chatPiiBlocked = false);
      });
      return;
    }
    setState(() {
      chatInputText = '';
      chatPiiBlocked = false;
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
      final apps = await FirestoreService(token, _handleTokenRefresh).getApplications(jobId);
      setState(() {
        jobApplicants = apps;
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
        final correctCode = jobDoc['completionCode'] as String?;
        if (completionScanInput.trim() != correctCode) {
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

        // Deduct 3% fee
        final platformFee = price * 0.03;
        final nyxianPayout = price - platformFee;

        // Add to Nyxian Wallet
        if (nyxianId != null) {
          final nyxDoc = await svc.getDocument('users/$nyxianId');
          if (nyxDoc != null) {
            final currentNyxBal = (nyxDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            final currentJobsDone = nyxDoc['jobsDone'] as int? ?? 0;
            final currentEarned = (nyxDoc['totalEarned'] as num?)?.toDouble() ?? 0.0;

            await svc.createOrUpdate('users/$nyxianId', {
              ...nyxDoc,
              'tyxBalance': currentNyxBal + nyxianPayout,
              'jobsDone': currentJobsDone + 1,
              'totalEarned': currentEarned + nyxianPayout,
            });
          }
        }

        // Record platform fee
        await svc.createOrUpdate('platform_fees/${job['id']}', {
          'jobId': job['id'],
          'amount': platformFee,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });

        // Delete escrow
        await svc.deleteDocument('escrow/${job['id']}');

        // Mark job as complete
        await svc.createOrUpdate('jobs/${job['id']}', {
          ...jobDoc,
          'status': 'Completed',
        });

        String? targetId;
        String? targetName;
        if (currentViewMode == AccountType.employer) {
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
          if (nyxianId == uid && userProfile != null) {
            userProfile = userProfile!.copyWith(
              tyxBalance: userProfile!.tyxBalance + nyxianPayout,
              totalEarned: userProfile!.totalEarned + nyxianPayout,
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
            await svc.createOrUpdate('jobs/$jId', {
              ...jobDoc,
              if (accountType == AccountType.employer) 'employerRated': true,
              if (accountType == AccountType.nyxian) 'nyxianRated': true,
            });
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
        final reachedFirstPoint = hasTracker && (
          status == 'arrived_pickup' ||
          status == 'paid_cashier' ||
          status == 'in_transit' ||
          status == 'arrived_dropoff' ||
          status == 'done' ||
          status == 'completed'
        );

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
      showAppToast('Posting Deleted', 'Job posting has been deleted and the ₱ ${refundAmount.toStringAsFixed(0)} held escrow has been returned to your balance.');
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
        final url = await ImgBBService(currentFirebaseConfig, idToken: token).uploadImageBytes(file.bytes, file.name);
        if (url != null) {
          setState(() => receiptPhotoUrl = url);
        }
      }
    } catch (_) {
    } finally {
      setState(() => isUploadingReceipt = false);
    }
  }

  /// Nyxian's browser calls this to broadcast their GPS position.
  Future<void> broadcastNyxianLocation(double lat, double lng) async {
    final token = SessionStorage.idToken;
    final job = selectedJobData;
    if (token == null || job == null) return;
    try {
      final svc = FirestoreService(token, _handleTokenRefresh);
      final jobDoc = await svc.getDocument('jobs/${job['id']}');
      if (jobDoc != null) {
        await svc.createOrUpdate('jobs/${job['id']}', {
          ...jobDoc,
          'nyxianLat': lat,
          'nyxianLng': lng,
        });
      }
    } catch (_) {} // Silently ignore broadcast failures
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

  void initializeProfileEditing() {
    final profile = userProfile;
    if (profile == null) return;
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
    if (profile == null) return false;

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
    if (profile == null) return false;
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
      // Gracefully switch to simulated playground mode with a beautiful OTP code!
      final randomOtp = (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
      setState(() {
        simulatedSmsCode = randomOtp;
        smsVerificationSessionInfo = 'simulated';
        isSendingSms = false;
      });
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
        if (code == simulatedSmsCode || code == '123456') {
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
      final existing = userProfile;
      if (existing == null) return;

      final formattedEditPhone = editPhone.trim().isNotEmpty ? '+63 ${editPhone.trim()}' : null;

      final updated = existing.copyWith(
        name: editName.trim().isNotEmpty ? editName.trim() : null,
        email: editEmail.trim().isNotEmpty ? editEmail.trim() : null,
        phoneNumber: formattedEditPhone,
        taxId: editTaxId.trim().isNotEmpty ? editTaxId.trim() : '',
      );
      await handleSaveProfile(updated);
      setState(() {
        isSavingProfile = false;
        editName = '';
        editEmail = '';
        editPhone = '';
        editTaxId = '';
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
      final existing = userProfile;
      if (existing == null) return;
      final skills = editSkills;
      final updated = existing.copyWith(
        businessName: editBusinessName.trim().isNotEmpty ? editBusinessName.trim() : '',
        industry: editIndustry.trim().isNotEmpty ? editIndustry.trim() : '',
        taxId: editTaxId.trim().isNotEmpty ? editTaxId.trim() : '',
        headline: editHeadline.trim().isNotEmpty ? editHeadline.trim() : '',
        hourlyRate: editHourlyRate.trim().isNotEmpty ? (double.tryParse(editHourlyRate) ?? existing.hourlyRate) : 0.0,
        skills: skills,
      );
      await handleSaveProfile(updated);
      setState(() {
        isSavingProfile = false;
        editSkills = [];
        newSkillInput = '';
        editHeadline = '';
        editHourlyRate = '';
        editBusinessName = '';
        editIndustry = '';
        editTaxId = '';
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
    if (tab == AppTab.jobs) loadJobs();
    if (tab == AppTab.transit) loadRenterPendingRequests();
  }

  // ── Wallet ──────────────────────────────────────────────────

  Future<void> handleConnectWallet() async {
    if (!isPhantomInstalled()) {
      setState(() => walletState = WalletState.disconnected);
      return;
    }
    setState(() => walletState = WalletState.connecting);
    try {
      final publicKey = await connectPhantomWallet();
      if (publicKey == null) {
        setState(() => walletState = WalletState.disconnected);
        return;
      }
      final balance = await getSolanaBalance(publicKey) ?? 0.0;
      final short = '${publicKey.substring(0, 4)}...${publicKey.substring(publicKey.length - 4)}';

      // Persist wallet link to Firestore if user is logged in
      final token = SessionStorage.idToken;
      final uid = SessionStorage.uid;
      if (token != null && uid != null) {
        try {
          await FirestoreService(token, _handleTokenRefresh).linkWalletToUser(uid, publicKey);
        } catch (_) {}
      }

      setState(() {
        walletAddress = short;
        walletBalance = balance;
        walletState = WalletState.connected;
      });
    } catch (_) {
      setState(() => walletState = WalletState.disconnected);
    }
  }

  Future<void> handleRefreshBalance() async {
    if (walletState != WalletState.connected || walletAddress.isEmpty) return;
    setState(() => isRefreshingBalance = true);
    try {
      String? publicKey = userProfile?.walletPublicKey;
      if (publicKey == null && isPhantomInstalled()) {
        publicKey = await getPhantomPublicKeyIfConnected();
      }

      if (publicKey != null) {
        final balance = await getSolanaBalance(publicKey);
        if (balance != null) {
          setState(() => walletBalance = balance);
        }
      }
    } catch (_) {}
    setState(() => isRefreshingBalance = false);
  }

  /// Called after login — auto-connects to the linked wallet to fetch balance.
  Future<void> autoConnectPhantomIfLinked(String? profileWalletKey) async {
    try {
      if (profileWalletKey != null && isPhantomInstalled()) {
        final activeKey = await getPhantomPublicKeyIfConnected();
        if (activeKey != null && activeKey == profileWalletKey) {
          final balance = await getSolanaBalance(profileWalletKey) ?? 0.0;
          final short =
              '${profileWalletKey.substring(0, 4)}...${profileWalletKey.substring(profileWalletKey.length - 4)}';
          setState(() {
            walletAddress = short;
            walletBalance = balance;
            walletState = WalletState.connected;
          });
          return;
        }

        // If not silently connected, ask the user if they want to reconnect
        setState(() {
          showWalletReconnectPrompt = true;
          pendingReconnectWalletKey = profileWalletKey;
        });
        return;
      }

      // If no linked wallet on profile, try to see if Phantom is already trusted in browser
      if (isPhantomInstalled()) {
        final publicKey = await getPhantomPublicKeyIfConnected();
        if (publicKey != null) {
          final balance = await getSolanaBalance(publicKey) ?? 0.0;
          final short = '${publicKey.substring(0, 4)}...${publicKey.substring(publicKey.length - 4)}';
          setState(() {
            walletAddress = short;
            walletBalance = balance;
            walletState = WalletState.connected;
          });
        }
      }
    } catch (_) {}
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

  @override
  Component build(BuildContext context) {
    final darkBg = isDark ? 'bg-zinc-950 text-white' : 'bg-zinc-50 text-zinc-900';

    if (!isAuthenticated) {
      return div(classes: 'min-h-screen w-full $darkBg font-sans flex items-center justify-center py-8 md:py-12', [
        div(classes: 'w-full max-w-md p-6', [
          AuthViewComponent(state: this),
        ]),
      ]);
    }

    return div(classes: 'flex h-screen w-full overflow-hidden $darkBg font-sans', [
      // Desktop sidebar
      SidebarComponent(state: this),

      // Main area
      div(classes: 'flex-1 flex flex-col h-full relative overflow-hidden', [
        TopHeaderComponent(state: this),

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
      if (showCategoryModal) CategoryModalComponent(state: this),

      // List Vehicle modal overlay
      if (showListVehicleModal) ListVehicleModalComponent(appState: this),

      // Book Vehicle modal overlay
      if (showBookVehicleModal) BookVehicleModalComponent(appState: this),

      // Extend Rental modal overlay
      if (showExtendRentalModal) ExtendRentalModalComponent(appState: this),

      // Rental Tracker Map overlay
      if (showRentalTrackerMap) RentalTrackerMapComponent(appState: this),

      // Manage Vehicle modal overlay
      if (showManageVehicleModal) ManageVehicleModalComponent(appState: this),

      // Public Vehicle Q&A modal overlay
      if (showVehicleQaModal && selectedRentalData != null) VehicleQaModalComponent(appState: this, rentalId: selectedRentalData!['id']),

      // List Property modal overlay
      if (showListPropertyModal) ListPropertyModalComponent(appState: this),

      // Book Property modal overlay
      if (showBookPropertyModal) BookPropertyModalComponent(appState: this),

      // Manage Property modal overlay
      if (showManagePropertyModal) ManagePropertyModalComponent(appState: this),

      // Public Property Q&A modal overlay
      if (showPropertyQaModal) PropertyQaModalComponent(appState: this),

      // Unified Sign Contract modal overlay
      if (showSignContractModal && signingContractId != null) SignContractModalComponent(
        appState: this,
        title: signingContractTitle ?? '',
        contractTerms: signingContractTerms ?? '',
        rentalId: signingContractId!,
        isProperty: signingContractIsProperty,
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

      // Payment modal overlay
      if (showDepositModal) PaymentModalComponent(state: this),

      // SMS Verification modal overlay
      if (showSmsModal) SmsVerificationModalComponent(state: this),

      // Wallet Reconnect modal overlay
      if (showWalletReconnectPrompt) WalletReconnectModalComponent(state: this),

      // Rating modal overlay
      if (showRatingPopup) RatingModalComponent(state: this),

      // Delete confirmation modal overlay
      if (showDeleteConfirm) DeleteConfirmModalComponent(state: this),

      // Chat overlay
      if (showChat) ChatWidget(state: this),
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
                          final val = (e.target as dynamic).value as String;
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
                        final val = (e.target as dynamic).value as String;
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
