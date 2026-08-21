// Core data models for Tranyx (Shared between Mobile and Web)
import 'enums.dart';

export 'enums.dart';

enum AccountType {
  nyxian,
  employer,
  hybrid;

  String get label {
    switch (this) {
      case AccountType.nyxian:
        return 'Nyxian';
      case AccountType.employer:
        return 'Employer';
      case AccountType.hybrid:
        return 'Hybrid PRO';
    }
  }

  String get badgeClasses {
    switch (this) {
      case AccountType.nyxian:
        return 'bg-green-500/20 text-green-400';
      case AccountType.employer:
        return 'bg-blue-500/20 text-blue-400';
      case AccountType.hybrid:
        return 'bg-amber-500/20 text-amber-500';
    }
  }
}

enum EmployerType { personal, business }

class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final String? phoneNumber;
  final AccountType accountType;
  final EmployerType? employerType;
  final String? businessName;
  final String? businessPermit;
  final String? industry;
  final String? taxId;
  final String? headline;
  final double? hourlyRate;
  final List<String>? skills;
  final double? rating;
  final double? renterRating;
  final double? hostRating;
  final DateTime? createdAt;
  final String? walletPublicKey;
  final String? googleEmail;
  final double tyxBalance;
  final int jobsDone;
  final double totalEarned;
  final int verificationLevel;
  final bool emailVerified;
  final bool phoneVerified;
  final bool idVerified;
  final bool bgChecked;
  final bool isPremium;
  final DateTime? premiumUntil;
  final bool isBonded;
  final List<String>? certificationUrls;
  final String? activePromoCode;
  final String? activePromoDiscountType;
  final double? activePromoDiscountValue;
  final List<String> disabledPromos;
  final int terraPoints;
  final List<String> earnedRewards;

  const UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.phoneNumber,
    required this.accountType,
    this.employerType,
    this.businessName,
    this.businessPermit,
    this.industry,
    this.taxId,
    this.headline,
    this.hourlyRate,
    this.skills,
    this.rating,
    this.renterRating,
    this.hostRating,
    this.createdAt,
    this.walletPublicKey,
    this.googleEmail,
    this.tyxBalance = 0.0,
    this.jobsDone = 0,
    this.totalEarned = 0.0,
    this.verificationLevel = 0,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.idVerified = false,
    this.bgChecked = false,
    this.isPremium = false,
    this.premiumUntil,
    this.isBonded = false,
    this.certificationUrls,
    this.activePromoCode,
    this.activePromoDiscountType,
    this.activePromoDiscountValue,
    this.disabledPromos = const [],
    this.terraPoints = 0,
    this.earnedRewards = const [],
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    final type = AccountType.values.firstWhere(
      (e) => e.name == map['accountType'],
      orElse: () => AccountType.employer,
    );

    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is num) return DateTime.fromMillisecondsSinceEpoch(val.toInt());
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
        final asNum = num.tryParse(val);
        if (asNum != null) return DateTime.fromMillisecondsSinceEpoch(asNum.toInt());
      }
      try {
        final dynamic dyn = val;
        if (dyn.millisecondsSinceEpoch is int) {
          return DateTime.fromMillisecondsSinceEpoch(dyn.millisecondsSinceEpoch as int);
        }
        if (dyn.toDate is Function) {
          final res = dyn.toDate();
          if (res is DateTime) return res;
        }
      } catch (_) {}
      return null;
    }

    int parseInt(dynamic val, [int fallback = 0]) {
      if (val == null) return fallback;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? fallback;
      return fallback;
    }

    List<String>? parseStringList(dynamic val) {
      if (val == null) return null;
      if (val is List) {
        return val.map((e) => e.toString()).toList();
      }
      return null;
    }

    return UserProfile(
      uid: uid,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? (map['name'] as String).trim()
          : ((map['displayName'] as String?)?.trim().isNotEmpty == true
              ? (map['displayName'] as String).trim()
              : ((map['email'] as String?)?.split('@').first.isNotEmpty == true
                  ? (map['email'] as String).split('@').first
                  : 'User')),
      email: map['email'] as String? ?? '',
      photoUrl: (map['photoUrl'] ?? map['avatarUrl'] ?? map['picture']) as String?,
      phoneNumber: (map['phoneNumber'] ?? map['phone'] ?? map['contactNumber']) as String?,
      accountType: type,
      employerType: map['employerType'] != null
          ? EmployerType.values.firstWhere(
              (e) => e.name == map['employerType'],
              orElse: () => EmployerType.personal,
            )
          : null,
      businessName: (map['businessName'] ?? map['companyName']) as String?,
      businessPermit: map['businessPermit'] as String?,
      industry: map['industry'] as String?,
      taxId: (map['taxId'] ?? map['tin']) as String?,
      headline: (map['headline'] ?? map['bio'] ?? map['title']) as String?,
      hourlyRate: (map['hourlyRate'] as num?)?.toDouble(),
      skills: parseStringList(map['skills']),
      rating: (map['rating'] as num?)?.toDouble(),
      renterRating: (map['renterRating'] as num?)?.toDouble(),
      hostRating: (map['hostRating'] as num?)?.toDouble(),
      createdAt: parseDate(map['createdAt']),
      walletPublicKey: (map['walletPublicKey'] ??
              map['solanaWalletAddress'] ??
              map['walletAddress']) as String?,
      googleEmail: map['googleEmail'] as String?,
      tyxBalance: (map['tyxBalance'] as num?)?.toDouble() ?? 0.0,
      jobsDone: parseInt(map['jobsDone']),
      totalEarned: (map['totalEarned'] as num?)?.toDouble() ?? 0.0,
      verificationLevel: parseInt(map['verificationLevel']),
      emailVerified: map['emailVerified'] as bool? ?? false,
      phoneVerified: map['phoneVerified'] as bool? ?? false,
      idVerified: map['idVerified'] as bool? ?? false,
      bgChecked: map['bgChecked'] as bool? ?? false,
      isPremium: map['isPremium'] as bool? ?? false,
      premiumUntil: parseDate(map['premiumUntil']),
      isBonded: map['isBonded'] as bool? ?? false,
      certificationUrls: parseStringList(map['certificationUrls']),
      activePromoCode: map['activePromoCode'] as String?,
      activePromoDiscountType: map['activePromoDiscountType'] as String?,
      activePromoDiscountValue: (map['activePromoDiscountValue'] as num?)?.toDouble(),
      disabledPromos: parseStringList(map['disabledPromos']) ?? const [],
      terraPoints: parseInt(map['terraPoints']),
      earnedRewards: parseStringList(map['earnedRewards']) ?? const [],
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'email': email,
    'photoUrl': photoUrl,
    'phoneNumber': phoneNumber,
    'accountType': accountType.name,
    'employerType': employerType?.name,
    'businessName': businessName,
    'businessPermit': businessPermit,
    'industry': industry,
    'taxId': taxId,
    'headline': headline,
    'hourlyRate': hourlyRate,
    'skills': skills,
    'rating': rating,
    'renterRating': renterRating,
    'hostRating': hostRating,
    'createdAt': createdAt?.millisecondsSinceEpoch,
    'walletPublicKey': walletPublicKey,
    'googleEmail': googleEmail,
    'tyxBalance': tyxBalance,
    'jobsDone': jobsDone,
    'totalEarned': totalEarned,
    'verificationLevel': verificationLevel,
    'emailVerified': emailVerified,
    'phoneVerified': phoneVerified,
    'idVerified': idVerified,
    'bgChecked': bgChecked,
    'isPremium': isPremium,
    'premiumUntil': premiumUntil?.millisecondsSinceEpoch,
    'isBonded': isBonded,
    'certificationUrls': certificationUrls,
    'activePromoCode': activePromoCode,
    'activePromoDiscountType': activePromoDiscountType,
    'activePromoDiscountValue': activePromoDiscountValue,
    'disabledPromos': disabledPromos,
    'terraPoints': terraPoints,
    'earnedRewards': earnedRewards,
  };

  UserProfile copyWith({
    String? name,
    String? email,
    String? photoUrl,
    String? phoneNumber,
    AccountType? accountType,
    EmployerType? employerType,
    String? businessName,
    String? businessPermit,
    String? industry,
    String? taxId,
    String? headline,
    double? hourlyRate,
    List<String>? skills,
    double? rating,
    double? renterRating,
    double? hostRating,
    DateTime? createdAt,
    String? walletPublicKey,
    String? googleEmail,
    double? tyxBalance,
    int? jobsDone,
    double? totalEarned,
    int? verificationLevel,
    bool? emailVerified,
    bool? phoneVerified,
    bool? idVerified,
    bool? bgChecked,
    bool? isPremium,
    DateTime? premiumUntil,
    bool? isBonded,
    List<String>? certificationUrls,
    String? activePromoCode,
    String? activePromoDiscountType,
    double? activePromoDiscountValue,
    List<String>? disabledPromos,
    int? terraPoints,
    List<String>? earnedRewards,
  }) {
    return UserProfile(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      accountType: accountType ?? this.accountType,
      employerType: employerType ?? this.employerType,
      businessName: businessName ?? this.businessName,
      businessPermit: businessPermit ?? this.businessPermit,
      industry: industry ?? this.industry,
      taxId: taxId ?? this.taxId,
      headline: headline ?? this.headline,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      skills: skills ?? this.skills,
      rating: rating ?? this.rating,
      renterRating: renterRating ?? this.renterRating,
      hostRating: hostRating ?? this.hostRating,
      createdAt: createdAt ?? this.createdAt,
      walletPublicKey: walletPublicKey ?? this.walletPublicKey,
      googleEmail: googleEmail ?? this.googleEmail,
      tyxBalance: tyxBalance ?? this.tyxBalance,
      jobsDone: jobsDone ?? this.jobsDone,
      totalEarned: totalEarned ?? this.totalEarned,
      verificationLevel: verificationLevel ?? this.verificationLevel,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      idVerified: idVerified ?? this.idVerified,
      bgChecked: bgChecked ?? this.bgChecked,
      isPremium: isPremium ?? this.isPremium,
      premiumUntil: premiumUntil ?? this.premiumUntil,
      isBonded: isBonded ?? this.isBonded,
      certificationUrls: certificationUrls ?? this.certificationUrls,
      activePromoCode: activePromoCode ?? this.activePromoCode,
      activePromoDiscountType: activePromoDiscountType ?? this.activePromoDiscountType,
      activePromoDiscountValue: activePromoDiscountValue ?? this.activePromoDiscountValue,
      disabledPromos: disabledPromos ?? this.disabledPromos,
      terraPoints: terraPoints ?? this.terraPoints,
      earnedRewards: earnedRewards ?? this.earnedRewards,
    );
  }
}

class Job {
  final String id;
  final String creatorId;
  final String creatorName;
  final String? creatorPhotoUrl;
  final AccountType creatorType;
  final String title;
  final String description;
  final JobCategory category;
  final JobCategoryGroup categoryGroup;
  final String employmentType;
  final String dateRequirement;
  final DateTime? jobDate;
  final String timePreference;
  final String pricingType;
  final double pricingValue;
  final String locationType;
  final String? address;
  final String? landmark;
  final DateTime createdAt;
  final String status;
  final int applicantCount;
  final List<String> recentApplicantPhotos;
  final List<String> applicantUids;

  final String? pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String? destinationAddress;
  final double? destinationLat;
  final double? destinationLng;
  final bool hasTracker;
  final String? acceptedApplicantId;
  final String? completionCode;
  final String? receiptUrl;
  final bool employerRated;
  final bool nyxianRated;
  final String? promoCode;
  final double? discountAmount;

  const Job({
    required this.id,
    required this.creatorId,
    required this.creatorName,
    this.creatorPhotoUrl,
    required this.creatorType,
    required this.title,
    required this.description,
    required this.category,
    required this.categoryGroup,
    required this.employmentType,
    required this.dateRequirement,
    this.jobDate,
    required this.timePreference,
    required this.pricingType,
    required this.pricingValue,
    required this.locationType,
    this.address,
    this.landmark,
    required this.createdAt,
    this.status = 'Open',
    this.applicantCount = 0,
    this.recentApplicantPhotos = const [],
    this.applicantUids = const [],
    this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    this.destinationAddress,
    this.destinationLat,
    this.destinationLng,
    this.hasTracker = false,
    this.acceptedApplicantId,
    this.completionCode,
    this.receiptUrl,
    this.employerRated = false,
    this.nyxianRated = false,
    this.promoCode,
    this.discountAmount,
  });

  Map<String, dynamic> toMap() {
    return {
      'creatorId': creatorId,
      'creatorName': creatorName,
      'creatorPhotoUrl': creatorPhotoUrl,
      'creatorType': creatorType.name,
      'title': title,
      'description': description,
      'category': category.name,
      'categoryGroup': categoryGroup.name,
      'employmentType': employmentType,
      'dateRequirement': dateRequirement,
      'jobDate': jobDate?.millisecondsSinceEpoch,
      'timePreference': timePreference,
      'pricingType': pricingType,
      'pricingValue': pricingValue,
      'locationType': locationType,
      'address': address,
      'landmark': landmark,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'status': status,
      'applicantCount': applicantCount,
      'recentApplicantPhotos': recentApplicantPhotos,
      'applicantUids': applicantUids,
      'pickupAddress': pickupAddress,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'destinationAddress': destinationAddress,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'hasTracker': hasTracker,
      'acceptedApplicantId': acceptedApplicantId,
      'completionCode': completionCode,
      'receiptUrl': receiptUrl,
      'employerRated': employerRated,
      'nyxianRated': nyxianRated,
      'promoCode': promoCode,
      'discountAmount': discountAmount,
    };
  }

  factory Job.fromMap(Map<String, dynamic> map, String id) {
    return Job(
      id: id,
      creatorId: map['creatorId'] ?? '',
      creatorName: map['creatorName'] ?? '',
      creatorPhotoUrl: map['creatorPhotoUrl'],
      creatorType: AccountType.values.firstWhere(
        (e) => e.name == map['creatorType'],
        orElse: () => AccountType.employer,
      ),
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: JobCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => JobCategory.others,
      ),
      categoryGroup: JobCategoryGroup.values.firstWhere(
        (e) => e.name == map['categoryGroup'],
        orElse: () => JobCategoryGroup.miscellaneousEvents,
      ),
      employmentType: map['employmentType'] ?? '',
      dateRequirement: map['dateRequirement'] ?? '',
      jobDate: map['jobDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['jobDate'])
          : null,
      timePreference: map['timePreference'] ?? '',
      pricingType: map['pricingType'] ?? '',
      pricingValue: (map['pricingValue'] as num?)?.toDouble() ?? 0.0,
      locationType: map['locationType'] ?? '',
      address: map['address'],
      landmark: map['landmark'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      status: map['status'] ?? 'Open',
      applicantCount: map['applicantCount'] ?? 0,
      recentApplicantPhotos: List<String>.from(
        map['recentApplicantPhotos'] ?? [],
      ),
      applicantUids: List<String>.from(map['applicantUids'] ?? []),
      pickupAddress: map['pickupAddress'],
      pickupLat: (map['pickupLat'] as num?)?.toDouble(),
      pickupLng: (map['pickupLng'] as num?)?.toDouble(),
      destinationAddress: map['destinationAddress'],
      destinationLat: (map['destinationLat'] as num?)?.toDouble(),
      destinationLng: (map['destinationLng'] as num?)?.toDouble(),
      hasTracker: map['hasTracker'] ?? false,
      acceptedApplicantId: map['acceptedApplicantId'] as String?,
      completionCode: map['completionCode']?.toString(),
      receiptUrl: map['receiptUrl'] as String?,
      employerRated: map['employerRated'] ?? false,
      nyxianRated: map['nyxianRated'] ?? false,
      promoCode: map['promoCode'] as String?,
      discountAmount: (map['discountAmount'] as num?)?.toDouble(),
    );
  }

  Job copyWith({
    String? id,
    String? creatorId,
    String? creatorName,
    String? creatorPhotoUrl,
    AccountType? creatorType,
    String? title,
    String? description,
    JobCategory? category,
    JobCategoryGroup? categoryGroup,
    String? employmentType,
    String? dateRequirement,
    DateTime? jobDate,
    String? timePreference,
    String? pricingType,
    double? pricingValue,
    String? locationType,
    String? address,
    String? landmark,
    DateTime? createdAt,
    String? status,
    int? applicantCount,
    List<String>? recentApplicantPhotos,
    List<String>? applicantUids,
    String? pickupAddress,
    double? pickupLat,
    double? pickupLng,
    String? destinationAddress,
    double? destinationLat,
    double? destinationLng,
    bool? hasTracker,
    String? acceptedApplicantId,
    String? completionCode,
    String? receiptUrl,
    bool? employerRated,
    bool? nyxianRated,
    String? promoCode,
    double? discountAmount,
  }) {
    return Job(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      creatorName: creatorName ?? this.creatorName,
      creatorPhotoUrl: creatorPhotoUrl ?? this.creatorPhotoUrl,
      creatorType: creatorType ?? this.creatorType,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      categoryGroup: categoryGroup ?? this.categoryGroup,
      employmentType: employmentType ?? this.employmentType,
      dateRequirement: dateRequirement ?? this.dateRequirement,
      jobDate: jobDate ?? this.jobDate,
      timePreference: timePreference ?? this.timePreference,
      pricingType: pricingType ?? this.pricingType,
      pricingValue: pricingValue ?? this.pricingValue,
      locationType: locationType ?? this.locationType,
      address: address ?? this.address,
      landmark: landmark ?? this.landmark,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      applicantCount: applicantCount ?? this.applicantCount,
      recentApplicantPhotos:
          recentApplicantPhotos ?? this.recentApplicantPhotos,
      applicantUids: applicantUids ?? this.applicantUids,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLat: pickupLat ?? this.pickupLat,
      pickupLng: pickupLng ?? this.pickupLng,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      hasTracker: hasTracker ?? this.hasTracker,
      acceptedApplicantId: acceptedApplicantId ?? this.acceptedApplicantId,
      completionCode: completionCode ?? this.completionCode,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      employerRated: employerRated ?? this.employerRated,
      nyxianRated: nyxianRated ?? this.nyxianRated,
      promoCode: promoCode ?? this.promoCode,
      discountAmount: discountAmount ?? this.discountAmount,
    );
  }
  String get employerId => creatorId;
  String? get acceptedNyxianId => acceptedApplicantId;
  double get budget => pricingValue;
  bool get isHired => acceptedApplicantId != null && acceptedApplicantId!.trim().isNotEmpty;
  bool get isCancellationLocked =>
      isHired ||
      status.toLowerCase() == 'in progress' ||
      status.toLowerCase() == 'in_progress' ||
      status.toUpperCase() == 'ACCEPTED' ||
      status == 'MUTUAL_CANCEL_PENDING' ||
      isTerminal;
  bool get isTerminal =>
      status.toLowerCase() == 'completed' ||
      status.toLowerCase() == 'cancelled' ||
      status.toUpperCase() == 'ADMIN_CANCELLED';
  bool get isCancelled =>
      status.toLowerCase() == 'cancelled' ||
      status.toUpperCase() == 'ADMIN_CANCELLED';
  bool get isCompleted => status.toLowerCase() == 'completed';
}

class JobApplication {
  final String id;
  final String jobId;
  final String applicantUid;
  final String applicantName;
  final String? applicantPhotoUrl;
  final String coverNote;
  final double proposalRate;
  final bool isCounterOffer;
  final DateTime createdAt;
  final String status;

  const JobApplication({
    required this.id,
    required this.jobId,
    required this.applicantUid,
    required this.applicantName,
    this.applicantPhotoUrl,
    required this.coverNote,
    required this.proposalRate,
    required this.isCounterOffer,
    required this.createdAt,
    this.status = 'PENDING',
  });

  Map<String, dynamic> toMap() {
    return {
      'jobId': jobId,
      'applicantUid': applicantUid,
      'applicantName': applicantName,
      'applicantPhotoUrl': applicantPhotoUrl,
      'coverNote': coverNote,
      'proposalRate': proposalRate,
      'isCounterOffer': isCounterOffer,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'status': status,
    };
  }

  factory JobApplication.fromMap(Map<String, dynamic> map, String id) {
    return JobApplication(
      id: id,
      jobId: map['jobId'] ?? '',
      applicantUid: map['applicantUid'] ?? '',
      applicantName: map['applicantName'] ?? '',
      applicantPhotoUrl: map['applicantPhotoUrl'],
      coverNote: map['coverNote'] ?? '',
      proposalRate: (map['proposalRate'] as num?)?.toDouble() ?? 0.0,
      isCounterOffer: map['isCounterOffer'] ?? false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      status: map['status'] ?? 'PENDING',
    );
  }

  JobApplication copyWith({
    String? id,
    String? jobId,
    String? applicantUid,
    String? applicantName,
    String? applicantPhotoUrl,
    String? coverNote,
    double? proposalRate,
    bool? isCounterOffer,
    DateTime? createdAt,
    String? status,
  }) {
    return JobApplication(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      applicantUid: applicantUid ?? this.applicantUid,
      applicantName: applicantName ?? this.applicantName,
      applicantPhotoUrl: applicantPhotoUrl ?? this.applicantPhotoUrl,
      coverNote: coverNote ?? this.coverNote,
      proposalRate: proposalRate ?? this.proposalRate,
      isCounterOffer: isCounterOffer ?? this.isCounterOffer,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}

class JobCancellationLog {
  final String id;
  final String jobId;
  final String cancelledBy;
  final String role; // 'employer' | 'admin'
  final String action; // 'UNILATERAL_CANCEL' | 'ADMIN_OVERRIDE_CANCEL'
  final String status; // 'CANCELLED' | 'ADMIN_CANCELLED'
  final String reason;
  final String? previousStatus;
  final String? acceptedApplicantId;
  final DateTime timestamp;

  const JobCancellationLog({
    required this.id,
    required this.jobId,
    required this.cancelledBy,
    required this.role,
    required this.action,
    required this.status,
    required this.reason,
    this.previousStatus,
    this.acceptedApplicantId,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'jobId': jobId,
      'cancelledBy': cancelledBy,
      'role': role,
      'action': action,
      'status': status,
      'reason': reason,
      'previousStatus': previousStatus,
      'acceptedApplicantId': acceptedApplicantId,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory JobCancellationLog.fromMap(Map<String, dynamic> map, String id) {
    return JobCancellationLog(
      id: id,
      jobId: map['jobId'] ?? '',
      cancelledBy: map['cancelledBy'] ?? map['adminUid'] ?? '',
      role: map['role'] ?? 'employer',
      action: map['action'] ?? 'UNILATERAL_CANCEL',
      status: map['status'] ?? 'CANCELLED',
      reason: map['reason'] ?? '',
      previousStatus: map['previousStatus'],
      acceptedApplicantId: map['acceptedApplicantId'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }
}

class JobQuestion {
  final String id;
  final String jobId;
  final String authorId;
  final String authorName;
  final String? authorPhotoUrl;
  final String questionText;
  final String? answerText;
  final DateTime createdAt;

  const JobQuestion({
    required this.id,
    required this.jobId,
    required this.authorId,
    required this.authorName,
    this.authorPhotoUrl,
    required this.questionText,
    this.answerText,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'jobId': jobId,
      'authorId': authorId,
      'authorName': authorName,
      'authorPhotoUrl': authorPhotoUrl,
      'questionText': questionText,
      'answerText': answerText,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory JobQuestion.fromMap(Map<String, dynamic> map, String id) {
    return JobQuestion(
      id: id,
      jobId: map['jobId'] ?? '',
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? '',
      authorPhotoUrl: map['authorPhotoUrl'],
      questionText: map['questionText'] ?? '',
      answerText: map['answerText'],
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
    );
  }
}

class CategoryItem {
  final int id;
  final String label;
  final String icon;
  final bool hasTracker;

  const CategoryItem({
    required this.id,
    required this.label,
    required this.icon,
    this.hasTracker = false,
  });
}

class JobGroup {
  final int id;
  final String label;
  final String icon;
  final String color;
  final List<CategoryItem> categories;

  const JobGroup({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.categories,
  });
}

class VehicleRental {
  final String id;
  final String hostId;
  final String hostName;
  final String? hostPhotoUrl;
  final String brand;
  final String model;
  final int year;
  final VehicleType type;
  final String plateNumber;
  final double vehicleValue;
  final String ltoCrNumber;
  final String ltoOrNumber;
  final String insuranceProvider;
  final String insurancePolicyNumber;
  final String? franchisePermit;
  final String interiorPhotoUrl;
  final String frontPhotoUrl;
  final String backPhotoUrl;
  final String contractType; // 'tranyx' | 'custom'
  final String contractTerms;
  final double price12h;
  final double priceDaily;
  final double priceWeekly;
  final double priceMonthly;
  final double extensionRatePerHour;
  final double latePenaltyRatePerHour;
  final String
  status; // 'Available', 'Booked', 'On the Way', 'Active', 'Returning', 'Completed', 'Cancelled'
  final String? fuelType; // 'Gasoline', 'Diesel', 'Electric', 'Hybrid'
  final String? transmission; // 'Automatic', 'Manual'

  // Driver services info
  final bool offersDriver;
  final double driverDailyPrice;
  final String driverNote;
  final String driverLicenseNumber;

  // Renter and active booking info
  final String? renteeId;
  final String? renteeName;
  final String? renteePhotoUrl;
  final String? rentalDurationType; // '12h', 'daily', 'weekly', 'monthly'
  final int? rentalMultiplier;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? totalCost;
  final String? renteeSignatureName;
  final String? renteeLicenseNumber;
  final DateTime? signedAt;
  final bool? hireWithDriver;

  // Party Verification Snapshots
  final bool? hostIsVerified;
  final String? hostVerificationStatus; // 'VERIFIED' | 'UNVERIFIED'
  final String? hostVerificationTier;
  final bool? renteeIsVerified;
  final String? renteeVerificationStatus; // 'VERIFIED' | 'UNVERIFIED'
  final String? renteeVerificationTier;

  // Live coordinates
  final double? trackingLat;
  final double? trackingLng;

  // Hosting location
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final DateTime createdAt;

  const VehicleRental({
    required this.id,
    required this.hostId,
    required this.hostName,
    this.hostPhotoUrl,
    required this.brand,
    required this.model,
    required this.year,
    required this.type,
    required this.plateNumber,
    required this.vehicleValue,
    required this.ltoCrNumber,
    required this.ltoOrNumber,
    required this.insuranceProvider,
    required this.insurancePolicyNumber,
    this.franchisePermit,
    required this.interiorPhotoUrl,
    required this.frontPhotoUrl,
    required this.backPhotoUrl,
    required this.contractType,
    required this.contractTerms,
    required this.price12h,
    required this.priceDaily,
    required this.priceWeekly,
    required this.priceMonthly,
    required this.extensionRatePerHour,
    required this.latePenaltyRatePerHour,
    required this.status,
    this.offersDriver = false,
    this.driverDailyPrice = 0.0,
    this.driverNote = '',
    this.driverLicenseNumber = '',
    this.renteeId,
    this.renteeName,
    this.renteePhotoUrl,
    this.rentalDurationType,
    this.rentalMultiplier,
    this.startDate,
    this.endDate,
    this.totalCost,
    this.renteeSignatureName,
    this.renteeLicenseNumber,
    this.signedAt,
    this.hireWithDriver,
    this.hostIsVerified,
    this.hostVerificationStatus,
    this.hostVerificationTier,
    this.renteeIsVerified,
    this.renteeVerificationStatus,
    this.renteeVerificationTier,
    this.trackingLat,
    this.trackingLng,
    this.fuelType,
    this.transmission,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'hostId': hostId,
      'hostName': hostName,
      'hostPhotoUrl': hostPhotoUrl,
      'brand': brand,
      'model': model,
      'year': year,
      'type': type.name,
      'plateNumber': plateNumber,
      'vehicleValue': vehicleValue,
      'ltoCrNumber': ltoCrNumber,
      'ltoOrNumber': ltoOrNumber,
      'insuranceProvider': insuranceProvider,
      'insurancePolicyNumber': insurancePolicyNumber,
      'franchisePermit': franchisePermit,
      'interiorPhotoUrl': interiorPhotoUrl,
      'frontPhotoUrl': frontPhotoUrl,
      'backPhotoUrl': backPhotoUrl,
      'contractType': contractType,
      'contractTerms': contractTerms,
      'price12h': price12h,
      'priceDaily': priceDaily,
      'priceWeekly': priceWeekly,
      'priceMonthly': priceMonthly,
      'extensionRatePerHour': extensionRatePerHour,
      'latePenaltyRatePerHour': latePenaltyRatePerHour,
      'status': status,
      'fuelType': fuelType,
      'transmission': transmission,
      'offersDriver': offersDriver,
      'driverDailyPrice': driverDailyPrice,
      'driverNote': driverNote,
      'driverLicenseNumber': driverLicenseNumber,
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': renteePhotoUrl,
      'rentalDurationType': rentalDurationType,
      'rentalMultiplier': rentalMultiplier,
      'startDate': startDate?.millisecondsSinceEpoch,
      'endDate': endDate?.millisecondsSinceEpoch,
      'totalCost': totalCost,
      'renteeSignatureName': renteeSignatureName,
      'renteeLicenseNumber': renteeLicenseNumber,
      'signedAt': signedAt?.millisecondsSinceEpoch,
      'hireWithDriver': hireWithDriver,
      'hostIsVerified': hostIsVerified,
      'hostVerificationStatus': hostVerificationStatus,
      'hostVerificationTier': hostVerificationTier,
      'renteeIsVerified': renteeIsVerified,
      'renteeVerificationStatus': renteeVerificationStatus,
      'renteeVerificationTier': renteeVerificationTier,
      'trackingLat': trackingLat,
      'trackingLng': trackingLng,
      'pickupAddress': pickupAddress,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  factory VehicleRental.fromMap(Map<String, dynamic> map, String id) {
    final vType = VehicleType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => VehicleType.car,
    );
    return VehicleRental(
      id: id,
      hostId: map['hostId'] ?? '',
      hostName: map['hostName'] ?? '',
      hostPhotoUrl: map['hostPhotoUrl'],
      brand: map['brand'] ?? '',
      model: map['model'] ?? '',
      year: map['year'] is int
          ? map['year']
          : int.tryParse(map['year']?.toString() ?? '') ?? 0,
      type: vType,
      plateNumber: map['plateNumber'] ?? '',
      vehicleValue: (map['vehicleValue'] as num?)?.toDouble() ?? 0.0,
      ltoCrNumber: map['ltoCrNumber'] ?? '',
      ltoOrNumber: map['ltoOrNumber'] ?? '',
      insuranceProvider: map['insuranceProvider'] ?? '',
      insurancePolicyNumber: map['insurancePolicyNumber'] ?? '',
      franchisePermit: map['franchisePermit'],
      interiorPhotoUrl: map['interiorPhotoUrl'] ?? '',
      frontPhotoUrl: map['frontPhotoUrl'] ?? '',
      backPhotoUrl: map['backPhotoUrl'] ?? '',
      contractType: map['contractType'] ?? 'tranyx',
      contractTerms: map['contractTerms'] ?? '',
      price12h: (map['price12h'] as num?)?.toDouble() ?? 0.0,
      priceDaily: (map['priceDaily'] as num?)?.toDouble() ?? 0.0,
      priceWeekly: (map['priceWeekly'] as num?)?.toDouble() ?? 0.0,
      priceMonthly: (map['priceMonthly'] as num?)?.toDouble() ?? 0.0,
      extensionRatePerHour:
          (map['extensionRatePerHour'] as num?)?.toDouble() ?? 0.0,
      latePenaltyRatePerHour:
          (map['latePenaltyRatePerHour'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'Available',
      fuelType: map['fuelType'] as String?,
      transmission: map['transmission'] as String?,
      offersDriver: map['offersDriver'] as bool? ?? false,
      driverDailyPrice: (map['driverDailyPrice'] as num?)?.toDouble() ?? 0.0,
      driverNote: map['driverNote'] ?? '',
      driverLicenseNumber: map['driverLicenseNumber'] ?? '',
      renteeId: map['renteeId'],
      renteeName: map['renteeName'],
      renteePhotoUrl: map['renteePhotoUrl'],
      rentalDurationType: map['rentalDurationType'],
      rentalMultiplier: map['rentalMultiplier'],
      startDate: map['startDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['startDate'])
          : null,
      endDate: map['endDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['endDate'])
          : null,
      totalCost: (map['totalCost'] as num?)?.toDouble(),
      renteeSignatureName: map['renteeSignatureName'],
      renteeLicenseNumber: map['renteeLicenseNumber'],
      signedAt: map['signedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['signedAt'])
          : null,
      hireWithDriver: map['hireWithDriver'] as bool?,
      hostIsVerified: map['hostIsVerified'] as bool?,
      hostVerificationStatus: map['hostVerificationStatus'] as String?,
      hostVerificationTier: map['hostVerificationTier'] as String?,
      renteeIsVerified: map['renteeIsVerified'] as bool?,
      renteeVerificationStatus: map['renteeVerificationStatus'] as String?,
      renteeVerificationTier: map['renteeVerificationTier'] as String?,
      trackingLat: (map['trackingLat'] as num?)?.toDouble(),
      trackingLng: (map['trackingLng'] as num?)?.toDouble(),
      pickupAddress: map['pickupAddress'] ?? '',
      pickupLat: (map['pickupLat'] as num?)?.toDouble() ?? 0.0,
      pickupLng: (map['pickupLng'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
    );
  }
}

class PropertyRental {
  final String id;
  final String hostId;
  final String hostName;
  final String? hostPhotoUrl;
  final String title;
  final String description;
  final PropertyType type;
  final PropertyCategory category;
  final double priceMonthly;
  final double priceWeekly;
  final double priceDaily;
  final int depositMonths;
  final String address;
  final double latitude;
  final double longitude;
  final List<String> photoUrls;
  final List<String> amenities;
  final String
  status; // 'Available', 'Awaiting Signature', 'Booked', 'Active', 'Completed', 'Cancelled'
  final String contractType; // 'tranyx' | 'custom'
  final String contractTerms;
  final DateTime createdAt;
  final bool allowChat;
  final double? securityDepositAmount;
  final double? advanceAmount;

  // Party Verification Snapshots
  final bool? hostIsVerified;
  final String? hostVerificationStatus; // 'VERIFIED' | 'UNVERIFIED'
  final String? hostVerificationTier;
  final bool? renteeIsVerified;
  final String? renteeVerificationStatus; // 'VERIFIED' | 'UNVERIFIED'
  final String? renteeVerificationTier;

  // Renter details
  final String? renteeId;
  final String? renteeName;
  final String? renteePhotoUrl;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? totalCost;
  final String? renteeSignatureName;
  final DateTime? signedAt;
  final String? currentRequestId;
  final int? rentalMultiplier;
  final String? rentalDurationType;
  final String? signatureHash;
  final String? renteeLicenseNumber;

  const PropertyRental({
    required this.id,
    required this.hostId,
    required this.hostName,
    this.hostPhotoUrl,
    required this.title,
    required this.description,
    required this.type,
    required this.category,
    required this.priceMonthly,
    required this.priceWeekly,
    required this.priceDaily,
    required this.depositMonths,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.photoUrls,
    required this.amenities,
    required this.status,
    required this.contractType,
    required this.contractTerms,
    required this.createdAt,
    this.allowChat = false,
    this.securityDepositAmount,
    this.advanceAmount,
    this.hostIsVerified,
    this.hostVerificationStatus,
    this.hostVerificationTier,
    this.renteeIsVerified,
    this.renteeVerificationStatus,
    this.renteeVerificationTier,
    this.renteeId,
    this.renteeName,
    this.renteePhotoUrl,
    this.startDate,
    this.endDate,
    this.totalCost,
    this.renteeSignatureName,
    this.signedAt,
    this.currentRequestId,
    this.rentalMultiplier,
    this.rentalDurationType,
    this.signatureHash,
    this.renteeLicenseNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'hostId': hostId,
      'hostName': hostName,
      'hostPhotoUrl': hostPhotoUrl,
      'title': title,
      'description': description,
      'type': type.name,
      'category': category.name,
      'priceMonthly': priceMonthly,
      'priceWeekly': priceWeekly,
      'priceDaily': priceDaily,
      'depositMonths': depositMonths,
      'securityDepositAmount': securityDepositAmount,
      'advanceAmount': advanceAmount,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'photoUrls': photoUrls,
      'amenities': amenities,
      'status': status,
      'contractType': contractType,
      'contractTerms': contractTerms,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'allowChat': allowChat,
      'hostIsVerified': hostIsVerified,
      'hostVerificationStatus': hostVerificationStatus,
      'hostVerificationTier': hostVerificationTier,
      'renteeIsVerified': renteeIsVerified,
      'renteeVerificationStatus': renteeVerificationStatus,
      'renteeVerificationTier': renteeVerificationTier,
      'renteeId': renteeId,
      'renteeName': renteeName,
      'renteePhotoUrl': renteePhotoUrl,
      'startDate': startDate?.millisecondsSinceEpoch,
      'endDate': endDate?.millisecondsSinceEpoch,
      'totalCost': totalCost,
      'renteeSignatureName': renteeSignatureName,
      'signedAt': signedAt?.millisecondsSinceEpoch,
      'currentRequestId': currentRequestId,
      'rentalMultiplier': rentalMultiplier,
      'rentalDurationType': rentalDurationType,
      'signatureHash': signatureHash,
      'renteeLicenseNumber': renteeLicenseNumber,
    };
  }

  factory PropertyRental.fromMap(Map<String, dynamic> map, String id) {
    final pType = PropertyType.values.firstWhere(
      (e) => e.name == map['type'],
      orElse: () => PropertyType.house,
    );
    final pCat = PropertyCategory.values.firstWhere(
      (e) => e.name == map['category'],
      orElse: () => PropertyCategory.residential,
    );

    return PropertyRental(
      id: id,
      hostId: map['hostId'] ?? '',
      hostName: map['hostName'] ?? '',
      hostPhotoUrl: map['hostPhotoUrl'],
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      type: pType,
      category: pCat,
      priceMonthly: (map['priceMonthly'] as num?)?.toDouble() ?? 0.0,
      priceWeekly: (map['priceWeekly'] as num?)?.toDouble() ?? 0.0,
      priceDaily: (map['priceDaily'] as num?)?.toDouble() ?? 0.0,
      depositMonths: (map['depositMonths'] as num?)?.toInt() ?? 0,
      securityDepositAmount: (map['securityDepositAmount'] as num?)?.toDouble(),
      advanceAmount: (map['advanceAmount'] as num?)?.toDouble(),
      address: map['address'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      photoUrls: List<String>.from(map['photoUrls'] ?? []),
      amenities: List<String>.from(map['amenities'] ?? []),
      status: map['status'] ?? 'Available',
      contractType: map['contractType'] ?? 'tranyx',
      contractTerms: map['contractTerms'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      allowChat: map['allowChat'] as bool? ?? false,
      hostIsVerified: map['hostIsVerified'] as bool?,
      hostVerificationStatus: map['hostVerificationStatus'] as String?,
      hostVerificationTier: map['hostVerificationTier'] as String?,
      renteeIsVerified: map['renteeIsVerified'] as bool?,
      renteeVerificationStatus: map['renteeVerificationStatus'] as String?,
      renteeVerificationTier: map['renteeVerificationTier'] as String?,
      renteeId: map['renteeId'],
      renteeName: map['renteeName'],
      renteePhotoUrl: map['renteePhotoUrl'],
      startDate: map['startDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['startDate'])
          : null,
      endDate: map['endDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['endDate'])
          : null,
      totalCost: (map['totalCost'] as num?)?.toDouble(),
      renteeSignatureName: map['renteeSignatureName'],
      signedAt: map['signedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['signedAt'])
          : null,
      currentRequestId: map['currentRequestId'],
      rentalMultiplier: (map['rentalMultiplier'] as num?)?.toInt(),
      rentalDurationType: map['rentalDurationType'],
      signatureHash: map['signatureHash'],
      renteeLicenseNumber: map['renteeLicenseNumber'],
    );
  }
}

class PartyVerificationHelper {
  static bool isPartyVerified({
    bool? isVerified,
    String? status,
    int? level,
    bool? idVerified,
  }) {
    if (isVerified == true) return true;
    if (status != null && (status.toUpperCase() == 'VERIFIED' || status.toUpperCase() == 'ID_VERIFIED')) {
      return true;
    }
    if (idVerified == true) return true;
    if (level != null && level >= 2) return true;
    return false;
  }

  static String formatVerificationTier({
    bool? isVerified,
    String? status,
    int? level,
    bool? idVerified,
    String? explicitTier,
  }) {
    if (explicitTier != null && explicitTier.isNotEmpty && explicitTier != 'None' && explicitTier != 'Unverified') {
      return explicitTier;
    }
    final verified = isPartyVerified(
      isVerified: isVerified,
      status: status,
      level: level,
      idVerified: idVerified,
    );
    if (!verified) return 'Unverified Account';
    if (level == 3) return 'Level 3 Pro Verified';
    if (level == 2 || idVerified == true) return 'Government ID Verified';
    if (level == 1) return 'Basic Verified';
    return 'Government ID Verified';
  }

  static String formatIdentityStatusLabel({
    bool? isVerified,
    String? status,
    int? level,
    bool? idVerified,
    String? explicitTier,
  }) {
    final verified = isPartyVerified(
      isVerified: isVerified,
      status: status,
      level: level,
      idVerified: idVerified,
    );
    if (!verified) return 'Identity Status: Unverified Account';
    final tier = formatVerificationTier(
      isVerified: isVerified,
      status: status,
      level: level,
      idVerified: idVerified,
      explicitTier: explicitTier,
    );
    return 'Identity Status: Verified ($tier)';
  }
}

class Promo {
  final String code;
  final String discountType; // 'percentage' | 'flat'
  final double discountValue;
  final String applicableTo; // 'services' | 'rentals' | 'both'
  final int? maxUsers;
  final int usedCount;
  final bool isSingleUsePerUser;
  final bool isSingleUseGlobal;
  final List<String> usedBy;
  final DateTime? expirationDate;
  final bool isActive;
  final DateTime createdAt;
  final bool isAutoApply;
  final List<String>? eligibleUserUids;
  final bool onlyForSubscribed;
  final bool onlyForHybrid;
  final List<String> applicableRoles;

  const Promo({
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.applicableTo,
    this.maxUsers,
    this.usedCount = 0,
    this.isSingleUsePerUser = true,
    this.isSingleUseGlobal = false,
    this.usedBy = const [],
    this.expirationDate,
    this.isActive = true,
    required this.createdAt,
    this.isAutoApply = false,
    this.eligibleUserUids,
    this.onlyForSubscribed = false,
    this.onlyForHybrid = false,
    this.applicableRoles = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'discountType': discountType,
      'discountValue': discountValue,
      'applicableTo': applicableTo,
      'maxUsers': maxUsers,
      'usedCount': usedCount,
      'isSingleUsePerUser': isSingleUsePerUser,
      'isSingleUseGlobal': isSingleUseGlobal,
      'usedBy': usedBy,
      'expirationDate': expirationDate?.millisecondsSinceEpoch,
      'isActive': isActive,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isAutoApply': isAutoApply,
      'eligibleUserUids': eligibleUserUids,
      'onlyForSubscribed': onlyForSubscribed,
      'onlyForHybrid': onlyForHybrid,
      'applicableRoles': applicableRoles,
    };
  }

  factory Promo.fromMap(Map<String, dynamic> map, String code) {
    return Promo(
      code: code,
      discountType: map['discountType'] as String? ?? 'flat',
      discountValue: (map['discountValue'] as num?)?.toDouble() ?? 0.0,
      applicableTo: map['applicableTo'] as String? ?? 'both',
      maxUsers: map['maxUsers'] as int?,
      usedCount: map['usedCount'] as int? ?? 0,
      isSingleUsePerUser: map['isSingleUsePerUser'] as bool? ?? true,
      isSingleUseGlobal: map['isSingleUseGlobal'] as bool? ?? false,
      usedBy: List<String>.from(map['usedBy'] ?? []),
      expirationDate: map['expirationDate'] != null
          ? (map['expirationDate'] is int
              ? DateTime.fromMillisecondsSinceEpoch(map['expirationDate'] as int)
              : DateTime.tryParse(map['expirationDate'].toString()))
          : null,
      isActive: map['isActive'] as bool? ?? true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int? ?? 0),
      isAutoApply: map['isAutoApply'] as bool? ?? false,
      eligibleUserUids: map['eligibleUserUids'] != null
          ? List<String>.from(map['eligibleUserUids'])
          : null,
      onlyForSubscribed: map['onlyForSubscribed'] as bool? ?? false,
      onlyForHybrid: map['onlyForHybrid'] as bool? ?? false,
      applicableRoles: List<String>.from(map['applicableRoles'] ?? []),
    );
  }
}

class NewsPost {
  final String id;
  final String title;
  final String content;
  final String imageUrl;
  final String category; // 'promo' | 'news' | 'advertisement' | 'announcement'
  final String? promoCode; // linked promo code if any
  final String actionType; // 'link' | 'promo' | 'none'
  final String? actionUrl; // deeplink or universal link or web link
  final bool isActive;
  final DateTime createdAt;
  final DateTime? publishAt;

  // Embedded button configuration
  final String? buttonText;
  final double? buttonX; // X percentage (0.0 to 100.0)
  final double? buttonY; // Y percentage (0.0 to 100.0)
  final double? buttonWidth; // width percentage (0.0 to 100.0)
  final double? buttonHeight; // height percentage (0.0 to 100.0)
  final String? buttonLink; // specific link for this button
  final String? buttonBgColor; // custom fill color (hex format, e.g. #4f46e5)
  final String? buttonTextColor; // custom text color (hex format, e.g. #ffffff)
  final String? buttonBorderColor; // custom border color (hex format, e.g. #ffffff)
  final double? buttonBorderWidth; // border width in pixels
  final double? buttonBorderRadius; // border radius in pixels
  final double? buttonPaddingV; // vertical padding in pixels
  final double? buttonPaddingH; // horizontal padding in pixels

  const NewsPost({
    required this.id,
    required this.title,
    required this.content,
    required this.imageUrl,
    required this.category,
    this.promoCode,
    required this.actionType,
    this.actionUrl,
    this.isActive = true,
    required this.createdAt,
    this.publishAt,
    this.buttonText,
    this.buttonX,
    this.buttonY,
    this.buttonWidth,
    this.buttonHeight,
    this.buttonLink,
    this.buttonBgColor,
    this.buttonTextColor,
    this.buttonBorderColor,
    this.buttonBorderWidth,
    this.buttonBorderRadius,
    this.buttonPaddingV,
    this.buttonPaddingH,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'content': content,
    'imageUrl': imageUrl,
    'category': category,
    'promoCode': promoCode,
    'actionType': actionType,
    'actionUrl': actionUrl,
    'isActive': isActive,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'publishAt': publishAt?.millisecondsSinceEpoch,
    'buttonText': buttonText,
    'buttonX': buttonX,
    'buttonY': buttonY,
    'buttonWidth': buttonWidth,
    'buttonHeight': buttonHeight,
    'buttonLink': buttonLink,
    'buttonBgColor': buttonBgColor,
    'buttonTextColor': buttonTextColor,
    'buttonBorderColor': buttonBorderColor,
    'buttonBorderWidth': buttonBorderWidth,
    'buttonBorderRadius': buttonBorderRadius,
    'buttonPaddingV': buttonPaddingV,
    'buttonPaddingH': buttonPaddingH,
  };

  factory NewsPost.fromMap(Map<String, dynamic> map, String id) {
    DateTime parseDate(dynamic val) {
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val != null) {
        try {
          return (val as dynamic).toDate() as DateTime;
        } catch (_) {}
        try {
          return DateTime.fromMillisecondsSinceEpoch((val as num).toInt());
        } catch (_) {}
      }
      return DateTime.now();
    }

    return NewsPost(
      id: id,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      imageUrl: map['imageUrl'] as String? ?? '',
      category: map['category'] as String? ?? 'news',
      promoCode: map['promoCode'] as String?,
      actionType: map['actionType'] as String? ?? 'none',
      actionUrl: map['actionUrl'] as String?,
      isActive: map['isActive'] as bool? ?? true,
      createdAt: parseDate(map['createdAt']),
      publishAt: map['publishAt'] != null ? parseDate(map['publishAt']) : null,
      buttonText: map['buttonText'] as String?,
      buttonX: (map['buttonX'] as num?)?.toDouble(),
      buttonY: (map['buttonY'] as num?)?.toDouble(),
      buttonWidth: (map['buttonWidth'] as num?)?.toDouble(),
      buttonHeight: (map['buttonHeight'] as num?)?.toDouble(),
      buttonLink: map['buttonLink'] as String?,
      buttonBgColor: map['buttonBgColor'] as String?,
      buttonTextColor: map['buttonTextColor'] as String?,
      buttonBorderColor: map['buttonBorderColor'] as String?,
      buttonBorderWidth: (map['buttonBorderWidth'] as num?)?.toDouble(),
      buttonBorderRadius: (map['buttonBorderRadius'] as num?)?.toDouble(),
      buttonPaddingV: (map['buttonPaddingV'] as num?)?.toDouble(),
      buttonPaddingH: (map['buttonPaddingH'] as num?)?.toDouble(),
    );
  }
}

