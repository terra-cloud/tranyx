// ignore: avoid_web_libraries_in_flutter
import 'package:http/http.dart' as http;
import 'package:jaspr/dom.dart';
import 'dart:async';
import 'dart:convert';
import 'package:tranyx_web/services/web_interop.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';

import 'package:tranyx_web/services/firebase_service.dart';

import '../state/app_state.dart';
import '../client/views/auth_view.dart';
import '../client/views/home_view.dart';
import '../client/views/jobs_view.dart';
import '../client/views/transit_view.dart';
import '../client/views/profile_view.dart';
import '../client/widgets/sidebar.dart';
import '../client/widgets/bottom_nav.dart';
import '../client/widgets/top_header.dart';
import '../client/widgets/category_modal.dart';
import '../client/widgets/payment_modal.dart';

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
  JobsView jobsView = JobsView.list;

  // ── Category modal ──────────────────────────────────────────
  bool showCategoryModal = false;
  bool categoryModalForSelect = false;

  // ── Jobs state ──────────────────────────────────────────────
  List<Map<String, dynamic>> myJobs = [];
  List<Map<String, dynamic>> sessionPostedJobs = [];
  List<Map<String, dynamic>> availableJobs = [];
  bool isLoadingJobs = false;
  String? jobsError;
  String activeJobFilter = 'Recommended';
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

  // ── Employer Profile state ────────────────────────────────────
  bool showEmployerProfileModal = false;
  bool isLoadingEmployerProfile = false;
  Map<String, dynamic>? employerProfileData;

  // ── Wallet ──────────────────────────────────────────────────
  WalletState walletState = WalletState.disconnected;
  String walletAddress = '';
  double walletBalance = 0.0;
  bool isRefreshingBalance = false;

  // ── Services ────────────────────────────────────────────────
  final _auth = FirebaseAuthService();
  GeminiService? _gemini;

  FirestoreService get _firestore => FirestoreService(SessionStorage.idToken, _handleTokenRefresh);

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
    await _loadUserProfile();
    // Load jobs for current tab
    await loadJobs();
  }

  Future<void> _loadUserProfile() async {
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

      // Find the first job with status 'In Progress' for the ongoing widget
      final ongoing = merged.cast<Map<String, dynamic>?>().firstWhere(
        (j) => (j?['status'] as String?)?.toLowerCase() == 'in progress',
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

    if (walletBalance < 100) {
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
        'amount': walletBalance,
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
    final hasTracker = jobMap['hasTracker'] as bool? ?? false;

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
        showCompletionScanner = true;
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

        // 1. Release from Escrow
        final escrowDoc = await svc.getDocument('escrow/${job['id']}');
        if (escrowDoc == null) throw 'Escrow record not found. Contact support.';

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
      }

      setState(() {
        isCompletingJob = false;
        showCompletionScanner = false;
        completionScanInput = '';
      });
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

        // 1. Check for escrow
        final escrowDoc = await svc.getEscrow(job['id'] as String);
        if (escrowDoc != null && employerId != null) {
          final refundAmount = (escrowDoc['amount'] as num?)?.toDouble() ?? 0.0;

          // 2. Refund to Employer
          final empDoc = await svc.getDocument('users/$employerId');
          if (empDoc != null) {
            final currentBal = (empDoc['tyxBalance'] as num?)?.toDouble() ?? 0.0;
            final newBal = currentBal + refundAmount;

            // Depending on if the method 'updateTyxBalance' exists, using createOrUpdate to be safe
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

          // 3. Delete escrow
          await svc.deleteDocument('escrow/${job['id']}');
        }

        // 4. Update Job Status
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

  /// Nyxian calls this to update their delivery sub-status.
  /// [subStatus] should be one of:
  ///   'heading_to_pickup' | 'arrived_pickup' | 'purchase_complete' | 'heading_to_destination' | 'arrived_destination'
  Future<void> handleUpdateNyxianSubStatus(String subStatus) async {
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
          'nyxianSubStatus': subStatus,
        };

        // If arrived at destination, mark overall status as "Done" so employer can generate payment QR
        if (subStatus == 'arrived_destination') {
          updates['status'] = 'Done';
        }

        await svc.createOrUpdate('jobs/${job['id']}', updates);
      }
      setState(() {
        isUpdatingSubStatus = false;
        selectedJobData = {
          ...selectedJobData!,
          'nyxianSubStatus': subStatus,
          if (subStatus == 'arrived_destination') 'status': 'Done',
        };
      });
      // Refresh so the home ongoing widget reflects the change
      await loadJobs();
    } catch (_) {
      setState(() => isUpdatingSubStatus = false);
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
    
    final formattedEditPhone = editPhone.trim().isNotEmpty ? '+63 ${editPhone.trim()}' : '';
    final currentPhone = profile.phoneNumber ?? '';
    final currentTaxId = profile.taxId ?? '';

    return editName.trim() != profile.name ||
           editEmail.trim() != profile.email ||
           formattedEditPhone != currentPhone ||
           editTaxId.trim() != currentTaxId;
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
    return editHeadline.trim() != (profile.headline ?? '') ||
           editHourlyRate.trim() != (profile.hourlyRate?.toString() ?? '') ||
           skillsChanged ||
           editBusinessName.trim() != (profile.businessName ?? '') ||
           editIndustry.trim() != (profile.industry ?? '') ||
           editTaxId.trim() != (profile.taxId ?? '');
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

  Future<void> updateVerificationField({
    bool? email,
    bool? phone,
    bool? id,
    bool? bg,
  }) async {
    final existing = userProfile;
    if (existing == null) return;

    setState(() => isUpdatingVerification = true);
    try {
      final nextEmail = email ?? existing.emailVerified;
      final nextPhone = phone ?? existing.phoneVerified;
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
      if (tab != AppTab.jobs) {
        jobsView = JobsView.list;
        createStep = 1;
      }
    });
    if (tab == AppTab.jobs) loadJobs();
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
      String? publicKey = profileWalletKey;

      // If no linked wallet, try to see if Phantom is already trusted
      if (publicKey == null && isPhantomInstalled()) {
        publicKey = await getPhantomPublicKeyIfConnected();
      }

      if (publicKey == null) return;

      final balance = await getSolanaBalance(publicKey) ?? 0.0;
      final short = '${publicKey.substring(0, 4)}...${publicKey.substring(publicKey.length - 4)}';
      setState(() {
        walletAddress = short;
        walletBalance = balance;
        walletState = WalletState.connected;
      });
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

      // Category modal overlay
      if (showCategoryModal) CategoryModalComponent(state: this),

      // Payment modal overlay
      if (showDepositModal) PaymentModalComponent(state: this),
    ]);
  }
}
