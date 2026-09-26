import 'package:test/test.dart';
import 'package:shared/src/job_sla_helper.dart';

void main() {
  group('JobSlaHelper Classification & Rules', () {
    test('Classifies Category A: Immediate / Delivery / Errand', () {
      final deliveryJob = {
        'categoryGroup': 'delivery',
        'category': 'foodDelivery',
        'locationType': 'On-site',
        'employmentType': 'One-time Gig',
      };
      expect(JobSlaHelper.classifyJob(deliveryJob), equals(JobSlaCategory.immediateDelivery));

      final errandJob = {
        'categoryGroup': 'miscellaneousEvents',
        'category': 'queueingService',
        'locationType': 'On-site',
        'employmentType': 'One-time Gig',
      };
      expect(JobSlaHelper.classifyJob(errandJob), equals(JobSlaCategory.immediateDelivery));

      final urgentJob = {
        'categoryGroup': 'cleaning',
        'category': 'houseCleaning',
        'locationType': 'On-site',
        'dateRequirement': 'Urgent / Immediate',
        'employmentType': 'One-time Gig',
      };
      expect(JobSlaHelper.classifyJob(urgentJob), equals(JobSlaCategory.immediateDelivery));
    });

    test('Classifies Category B: On-Demand Local Service', () {
      final cleaningJob = {
        'categoryGroup': 'cleaning',
        'category': 'houseCleaning',
        'locationType': 'On-site',
        'dateRequirement': 'Flexible',
        'employmentType': 'One-time Gig',
      };
      expect(JobSlaHelper.classifyJob(cleaningJob), equals(JobSlaCategory.onDemandLocal));

      final repairJob = {
        'categoryGroup': 'homeRepair',
        'category': 'plumber',
        'locationType': 'On-site',
        'dateRequirement': 'Flexible',
        'employmentType': 'One-time Gig',
      };
      expect(JobSlaHelper.classifyJob(repairJob), equals(JobSlaCategory.onDemandLocal));
    });

    test('Classifies Category C: Scheduled Local Job', () {
      final scheduledJob = {
        'categoryGroup': 'cleaning',
        'category': 'deepCleaning',
        'locationType': 'On-site',
        'dateRequirement': 'On Date',
        'jobDate': DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
        'employmentType': 'One-time Gig',
      };
      expect(JobSlaHelper.classifyJob(scheduledJob), equals(JobSlaCategory.scheduledLocal));
    });

    test('Classifies Category D: Remote / Online Work', () {
      final remoteJob = {
        'categoryGroup': 'tech',
        'category': 'webDeveloper',
        'locationType': 'Remote',
        'employmentType': 'One-time Gig',
      };
      expect(JobSlaHelper.classifyJob(remoteJob), equals(JobSlaCategory.remoteOnline));

      final virtualAssistJob = {
        'categoryGroup': 'business',
        'category': 'virtualAssistant',
        'locationType': 'Remote',
        'employmentType': 'One-time Gig',
      };
      expect(JobSlaHelper.classifyJob(virtualAssistJob), equals(JobSlaCategory.remoteOnline));
    });

    test('Classifies Category E: Long-Term / Project-Based Work', () {
      final longTermJob = {
        'categoryGroup': 'tech',
        'category': 'softwareDev',
        'locationType': 'Remote',
        'employmentType': 'Full-time Contract',
      };
      expect(JobSlaHelper.classifyJob(longTermJob), equals(JobSlaCategory.longTermProject));

      final multiDayJob = {
        'categoryGroup': 'homeRepair',
        'category': 'carpenter',
        'locationType': 'On-site',
        'employmentType': 'Multi-day Project',
      };
      expect(JobSlaHelper.classifyJob(multiDayJob), equals(JobSlaCategory.longTermProject));
    });

    test('Default SLA Durations and Reminders match specifications', () {
      const config = JobSlaConfig();

      // Category A: 15 mins SLA, 5 mins reminder
      expect(config.getSlaMinutes(JobSlaCategory.immediateDelivery), equals(15));
      expect(config.getReminderMinutes(JobSlaCategory.immediateDelivery), equals(5));

      // Category B: 60 mins SLA, 30 mins reminder
      expect(config.getSlaMinutes(JobSlaCategory.onDemandLocal), equals(60));
      expect(config.getReminderMinutes(JobSlaCategory.onDemandLocal), equals(30));

      // Category C: 240 mins (4 hours) SLA, 120 mins reminder
      expect(config.getSlaMinutes(JobSlaCategory.scheduledLocal), equals(240));
      expect(config.getReminderMinutes(JobSlaCategory.scheduledLocal), equals(120));

      // Category D: 240 mins (4 hours) SLA, 120 mins reminder
      expect(config.getSlaMinutes(JobSlaCategory.remoteOnline), equals(240));
      expect(config.getReminderMinutes(JobSlaCategory.remoteOnline), equals(120));

      // Category E: 720 mins (12 hours) SLA, 360 mins reminder
      expect(config.getSlaMinutes(JobSlaCategory.longTermProject), equals(720));
      expect(config.getReminderMinutes(JobSlaCategory.longTermProject), equals(360));
    });

    test('Category C rule: Acknowledgment deadline does NOT extend beyond configured job start time', () {
      final now = DateTime.now();
      // Job is scheduled to start in 2 hours (120 minutes)
      final jobStartTime = now.add(const Duration(hours: 2));

      final scheduledJob = {
        'categoryGroup': 'homeRepair',
        'category': 'electrician',
        'locationType': 'On-site',
        'dateRequirement': 'On Date',
        'jobDate': jobStartTime.millisecondsSinceEpoch,
        'employmentType': 'One-time Gig',
      };

      final deadline = JobSlaHelper.calculateDeadline(
        job: scheduledJob,
        hiredAt: now,
      );

      // Default SLA is 4 hours (240 min), but job starts in 2 hours (120 min), so deadline must be clamped to jobStartTime
      expect(deadline.millisecondsSinceEpoch, equals(jobStartTime.millisecondsSinceEpoch));
    });

    test('Category C: Normal deadline used when job start time is further out than 4 hours', () {
      final now = DateTime.now();
      // Job is scheduled to start in 24 hours
      final jobStartTime = now.add(const Duration(hours: 24));

      final scheduledJob = {
        'categoryGroup': 'homeRepair',
        'category': 'electrician',
        'locationType': 'On-site',
        'dateRequirement': 'On Date',
        'jobDate': jobStartTime.millisecondsSinceEpoch,
        'employmentType': 'One-time Gig',
      };

      final deadline = JobSlaHelper.calculateDeadline(
        job: scheduledJob,
        hiredAt: now,
      );

      // Default 4 hours SLA should be applied
      final expectedDeadline = now.add(const Duration(hours: 4));
      expect(deadline.difference(expectedDeadline).inSeconds.abs(), lessThanOrEqualTo(1));
    });

    test('JobSlaConfig serialization and custom overrides', () {
      final customConfig = JobSlaConfig(
        immediateDeliveryMinutes: 20,
        immediateDeliveryReminderMinutes: 7,
        onDemandLocalMinutes: 90,
      );

      final map = customConfig.toMap();
      final fromMap = JobSlaConfig.fromMap(map);

      expect(fromMap.immediateDeliveryMinutes, equals(20));
      expect(fromMap.immediateDeliveryReminderMinutes, equals(7));
      expect(fromMap.onDemandLocalMinutes, equals(90));
      expect(fromMap.scheduledLocalMinutes, equals(240));
    });

    test('formatRemainingTime formats countdown accurately', () {
      expect(JobSlaHelper.formatRemainingTime(const Duration(minutes: 8, seconds: 42)), equals('08:42'));
      expect(JobSlaHelper.formatRemainingTime(const Duration(seconds: 45)), equals('00:45'));
      expect(JobSlaHelper.formatRemainingTime(const Duration(hours: 3, minutes: 25)), equals('3h 25m'));
      expect(JobSlaHelper.formatRemainingTime(const Duration(hours: 2)), equals('2h'));
      expect(JobSlaHelper.formatRemainingTime(const Duration(seconds: -10)), equals('00:00'));
    });

    test('formatSlaDurationLabel formats labels accurately', () {
      expect(JobSlaHelper.formatSlaDurationLabel(15), equals('15 minutes'));
      expect(JobSlaHelper.formatSlaDurationLabel(60), equals('1 hour'));
      expect(JobSlaHelper.formatSlaDurationLabel(240), equals('4 hours'));
      expect(JobSlaHelper.formatSlaDurationLabel(720), equals('12 hours'));
    });
  });
}
