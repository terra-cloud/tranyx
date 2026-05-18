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
  final DateTime? createdAt;
  final String? walletPublicKey;
  final double tyxBalance;
  final int jobsDone;
  final double totalEarned;

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
    this.createdAt,
    this.walletPublicKey,
    this.tyxBalance = 0.0,
    this.jobsDone = 0,
    this.totalEarned = 0.0,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> map) {
    final type = AccountType.values.firstWhere(
      (e) => e.name == map['accountType'],
      orElse: () => AccountType.employer,
    );
    return UserProfile(
      uid: uid,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      accountType: type,
      employerType: map['employerType'] != null
          ? EmployerType.values.firstWhere(
              (e) => e.name == map['employerType'],
              orElse: () => EmployerType.personal,
            )
          : null,
      businessName: map['businessName'] as String?,
      businessPermit: map['businessPermit'] as String?,
      industry: map['industry'] as String?,
      taxId: map['taxId'] as String?,
      headline: map['headline'] as String?,
      hourlyRate: (map['hourlyRate'] as num?)?.toDouble(),
      skills: (map['skills'] as List?)?.map((e) => e as String).toList(),
      rating: (map['rating'] as num?)?.toDouble(),
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int)
          : null,
      walletPublicKey: map['walletPublicKey'] as String?,
      tyxBalance: (map['tyxBalance'] as num?)?.toDouble() ?? 0.0,
      jobsDone: map['jobsDone'] as int? ?? 0,
      totalEarned: (map['totalEarned'] as num?)?.toDouble() ?? 0.0,
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
    'createdAt': createdAt?.millisecondsSinceEpoch,
    'walletPublicKey': walletPublicKey,
    'tyxBalance': tyxBalance,
    'jobsDone': jobsDone,
    'totalEarned': totalEarned,
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
    DateTime? createdAt,
    String? walletPublicKey,
    double? tyxBalance,
    int? jobsDone,
    double? totalEarned,
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
      createdAt: createdAt ?? this.createdAt,
      walletPublicKey: walletPublicKey ?? this.walletPublicKey,
      tyxBalance: tyxBalance ?? this.tyxBalance,
      jobsDone: jobsDone ?? this.jobsDone,
      totalEarned: totalEarned ?? this.totalEarned,
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
    );
  }
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
