import 'enums.dart';

/// Categories for Job Acknowledgment SLAs as defined in Tranyx specifications.
enum JobSlaCategory {
  /// Category A — Immediate / Delivery / Errand (Default SLA: 15 mins, Reminder: 5 mins)
  immediateDelivery('immediate_delivery', 'Immediate / Delivery / Errand', 15, 5),

  /// Category B — On-Demand Local Service (Default SLA: 60 mins / 1 hour, Reminder: 30 mins)
  onDemandLocal('ondemand_local', 'On-Demand Local Service', 60, 30),

  /// Category C — Scheduled Local Job (Default SLA: 240 mins / 4 hours, Reminder: 120 mins)
  scheduledLocal('scheduled_local', 'Scheduled Local Job', 240, 120),

  /// Category D — Remote / Online Work (Default SLA: 240 mins / 4 hours, Reminder: 120 mins)
  remoteOnline('remote_online', 'Remote / Online Work', 240, 120),

  /// Category E — Long-Term / Project-Based (Default SLA: 720 mins / 12 hours, Reminder: 360 mins)
  longTermProject('longterm_project', 'Long-Term / Project-Based', 720, 360);

  final String id;
  final String label;
  final int defaultSlaMinutes;
  final int defaultReminderMinutes;

  const JobSlaCategory(this.id, this.label, this.defaultSlaMinutes, this.defaultReminderMinutes);

  static JobSlaCategory fromId(String? id) {
    if (id == null) return JobSlaCategory.onDemandLocal;
    final cleanId = id.trim().toLowerCase();
    for (final cat in JobSlaCategory.values) {
      if (cat.id == cleanId || cat.name.toLowerCase() == cleanId) {
        return cat;
      }
    }
    return JobSlaCategory.onDemandLocal;
  }
}

/// Admin-configurable SLA durations and reminder thresholds.
class JobSlaConfig {
  final int immediateDeliveryMinutes;
  final int immediateDeliveryReminderMinutes;

  final int onDemandLocalMinutes;
  final int onDemandLocalReminderMinutes;

  final int scheduledLocalMinutes;
  final int scheduledLocalReminderMinutes;

  final int remoteOnlineMinutes;
  final int remoteOnlineReminderMinutes;

  final int longTermProjectMinutes;
  final int longTermProjectReminderMinutes;

  const JobSlaConfig({
    this.immediateDeliveryMinutes = 15,
    this.immediateDeliveryReminderMinutes = 5,
    this.onDemandLocalMinutes = 60,
    this.onDemandLocalReminderMinutes = 30,
    this.scheduledLocalMinutes = 240,
    this.scheduledLocalReminderMinutes = 120,
    this.remoteOnlineMinutes = 240,
    this.remoteOnlineReminderMinutes = 120,
    this.longTermProjectMinutes = 720,
    this.longTermProjectReminderMinutes = 360,
  });

  int getSlaMinutes(JobSlaCategory category) {
    switch (category) {
      case JobSlaCategory.immediateDelivery:
        return immediateDeliveryMinutes;
      case JobSlaCategory.onDemandLocal:
        return onDemandLocalMinutes;
      case JobSlaCategory.scheduledLocal:
        return scheduledLocalMinutes;
      case JobSlaCategory.remoteOnline:
        return remoteOnlineMinutes;
      case JobSlaCategory.longTermProject:
        return longTermProjectMinutes;
    }
  }

  int getReminderMinutes(JobSlaCategory category) {
    switch (category) {
      case JobSlaCategory.immediateDelivery:
        return immediateDeliveryReminderMinutes;
      case JobSlaCategory.onDemandLocal:
        return onDemandLocalReminderMinutes;
      case JobSlaCategory.scheduledLocal:
        return scheduledLocalReminderMinutes;
      case JobSlaCategory.remoteOnline:
        return remoteOnlineReminderMinutes;
      case JobSlaCategory.longTermProject:
        return longTermProjectReminderMinutes;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'immediateDeliveryMinutes': immediateDeliveryMinutes,
      'immediateDeliveryReminderMinutes': immediateDeliveryReminderMinutes,
      'onDemandLocalMinutes': onDemandLocalMinutes,
      'onDemandLocalReminderMinutes': onDemandLocalReminderMinutes,
      'scheduledLocalMinutes': scheduledLocalMinutes,
      'scheduledLocalReminderMinutes': scheduledLocalReminderMinutes,
      'remoteOnlineMinutes': remoteOnlineMinutes,
      'remoteOnlineReminderMinutes': remoteOnlineReminderMinutes,
      'longTermProjectMinutes': longTermProjectMinutes,
      'longTermProjectReminderMinutes': longTermProjectReminderMinutes,
    };
  }

  factory JobSlaConfig.fromMap(Map? map) {
    if (map == null) return const JobSlaConfig();
    return JobSlaConfig(
      immediateDeliveryMinutes: (map['immediateDeliveryMinutes'] as num?)?.toInt() ?? 15,
      immediateDeliveryReminderMinutes: (map['immediateDeliveryReminderMinutes'] as num?)?.toInt() ?? 5,
      onDemandLocalMinutes: (map['onDemandLocalMinutes'] as num?)?.toInt() ?? 60,
      onDemandLocalReminderMinutes: (map['onDemandLocalReminderMinutes'] as num?)?.toInt() ?? 30,
      scheduledLocalMinutes: (map['scheduledLocalMinutes'] as num?)?.toInt() ?? 240,
      scheduledLocalReminderMinutes: (map['scheduledLocalReminderMinutes'] as num?)?.toInt() ?? 120,
      remoteOnlineMinutes: (map['remoteOnlineMinutes'] as num?)?.toInt() ?? 240,
      remoteOnlineReminderMinutes: (map['remoteOnlineReminderMinutes'] as num?)?.toInt() ?? 120,
      longTermProjectMinutes: (map['longTermProjectMinutes'] as num?)?.toInt() ?? 720,
      longTermProjectReminderMinutes: (map['longTermProjectReminderMinutes'] as num?)?.toInt() ?? 360,
    );
  }
}

/// Helper methods for classifying jobs, calculating deadlines, and countdown formatting.
class JobSlaHelper {
  /// Classifies a job (from either a [Job] model or a Firestore `Map<String, dynamic>`)
  /// into one of the 5 SLA categories:
  /// - Category A: Immediate / Delivery / Errand
  /// - Category B: On-Demand Local Service
  /// - Category C: Scheduled Local Job
  /// - Category D: Remote / Online Work
  /// - Category E: Long-Term / Project-Based
  static JobSlaCategory classifyJob(dynamic job) {
    if (job == null) return JobSlaCategory.onDemandLocal;

    final String catGroup = _extractString(job, 'categoryGroup').toLowerCase();
    final String cat = _extractString(job, 'category').toLowerCase();
    final String locationType = _extractString(job, 'locationType').toLowerCase();
    final String empType = _extractString(job, 'employmentType').toLowerCase();
    final String dateReq = _extractString(job, 'dateRequirement').toLowerCase();
    final dynamic jobDateRaw = _extractField(job, 'jobDate');

    // 1. Category E: Long-Term / Project-Based Work
    // Multi-day, contract, recurring, or long-term projects
    if (empType.contains('full-time') ||
        empType.contains('fulltime') ||
        empType.contains('part-time') ||
        empType.contains('parttime') ||
        empType.contains('long-term') ||
        empType.contains('contract') ||
        empType.contains('recurring') ||
        empType.contains('multi-day')) {
      return JobSlaCategory.longTermProject;
    }

    // 2. Category A: Immediate / Delivery / Errand
    // Food/document delivery, courier, parcel, grocery, errands
    final isDeliveryGroup = catGroup.contains('delivery') || catGroup.contains('moving');
    final isDeliveryCat = cat.contains('delivery') ||
        cat.contains('runner') ||
        cat.contains('courier') ||
        cat.contains('shopper') ||
        cat.contains('errand') ||
        cat.contains('pickup') ||
        cat.contains('queueing');
    final isUrgentOrImmediate = dateReq.contains('urgent') ||
        dateReq.contains('immediate') ||
        dateReq.contains('asap') ||
        dateReq.contains('today');

    if (isDeliveryGroup || isDeliveryCat || (isUrgentOrImmediate && !locationType.contains('remote'))) {
      return JobSlaCategory.immediateDelivery;
    }

    // 3. Category D: Remote / Online Work
    // Remote location or online work categories (design, programming, writing, data entry, virtual assistance)
    final isRemoteLoc = locationType.contains('remote') || locationType.contains('online');
    final isTechOrRemoteCategory = catGroup.contains('tech') ||
        catGroup.contains('creative') ||
        catGroup.contains('marketing') ||
        catGroup.contains('business') ||
        cat.contains('writer') ||
        cat.contains('designer') ||
        cat.contains('developer') ||
        cat.contains('virtual') ||
        cat.contains('dataentry') ||
        cat.contains('data entry') ||
        cat.contains('online');

    if (isRemoteLoc || isTechOrRemoteCategory) {
      return JobSlaCategory.remoteOnline;
    }

    // 4. Category C: Scheduled Local Job
    // Job scheduled for a specific future date/time
    final hasScheduledDate = (dateReq.contains('date') || dateReq.contains('schedule') || jobDateRaw != null) &&
        !dateReq.contains('flexible');

    if (hasScheduledDate) {
      return JobSlaCategory.scheduledLocal;
    }

    // 5. Category B: On-Demand Local Service (Default for local services)
    return JobSlaCategory.onDemandLocal;
  }

  /// Calculates the acknowledgment deadline for a job given its hire time.
  /// Enforces that for Category C (Scheduled Local Job), the acknowledgment deadline
  /// does not extend beyond the configured job start time.
  static DateTime calculateDeadline({
    required dynamic job,
    required DateTime hiredAt,
    JobSlaConfig config = const JobSlaConfig(),
  }) {
    final category = classifyJob(job);
    final slaMinutes = config.getSlaMinutes(category);
    DateTime deadline = hiredAt.add(Duration(minutes: slaMinutes));

    // Category C rule: Acknowledgment deadline should not extend beyond the configured job start time
    if (category == JobSlaCategory.scheduledLocal) {
      final scheduledStart = _extractDateTime(job, 'jobDate');
      if (scheduledStart != null && scheduledStart.isAfter(hiredAt)) {
        if (deadline.isAfter(scheduledStart)) {
          deadline = scheduledStart;
        }
      }
    }

    return deadline;
  }

  /// Returns the reminder timestamp for a job given its hire time and deadline.
  static DateTime calculateReminderTime({
    required dynamic job,
    required DateTime hiredAt,
    required DateTime deadline,
    JobSlaConfig config = const JobSlaConfig(),
  }) {
    final category = classifyJob(job);
    final reminderMinutes = config.getReminderMinutes(category);
    final reminderTime = hiredAt.add(Duration(minutes: reminderMinutes));

    // If reminderTime is past the deadline, set reminder halfway
    if (reminderTime.isAfter(deadline)) {
      final halfDuration = deadline.difference(hiredAt) ~/ 2;
      return hiredAt.add(halfDuration);
    }

    return reminderTime;
  }

  /// Formats the remaining time until deadline for display in the chat UI.
  /// Examples: "08:42", "58s", "3h 45m"
  static String formatRemainingTime(Duration remaining) {
    if (remaining.isNegative) return '00:00';

    final totalSeconds = remaining.inSeconds;
    if (totalSeconds < 3600) {
      final minutes = remaining.inMinutes;
      final seconds = totalSeconds % 60;
      final mStr = minutes.toString().padLeft(2, '0');
      final sStr = seconds.toString().padLeft(2, '0');
      return '$mStr:$sStr';
    } else {
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes % 60;
      if (minutes == 0) return '${hours}h';
      return '${hours}h ${minutes}m';
    }
  }

  /// Friendly label for SLA duration (e.g. "15 minutes", "1 hour", "4 hours", "12 hours")
  static String formatSlaDurationLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes minute${minutes == 1 ? '' : 's'}';
    }
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    if (rem == 0) {
      return '$hours hour${hours == 1 ? '' : 's'}';
    }
    return '$hours hr $rem min';
  }

  // --- Internal extraction helpers ---

  static String _extractString(dynamic job, String key) {
    if (job == null) return '';
    if (job is Map) {
      final val = job[key];
      return val?.toString() ?? '';
    }
    try {
      final val = (job as dynamic).toMap()[key];
      return val?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static dynamic _extractField(dynamic job, String key) {
    if (job == null) return null;
    if (job is Map) return job[key];
    try {
      return (job as dynamic).toMap()[key];
    } catch (_) {
      return null;
    }
  }

  static DateTime? _extractDateTime(dynamic job, String key) {
    final raw = _extractField(job, key);
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {
        final parsed = int.tryParse(raw);
        if (parsed != null) return DateTime.fromMillisecondsSinceEpoch(parsed);
      }
    }
    return null;
  }
}
