import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tranyx_mobile/core/theme/app_colors.dart';
import 'package:tranyx_mobile/core/providers/theme_provider.dart';
import 'package:tranyx_mobile/features/jobs/providers/jobs_provider.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_list_view.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_details_view.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/create_job_wizard.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/apply_job_view.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/review_applicants_view.dart';
import 'package:tranyx_mobile/features/jobs/presentation/widgets/job_success_view.dart';

class JobsView extends ConsumerStatefulWidget {
  final bool isTablet;

  const JobsView({super.key, this.isTablet = false});

  @override
  ConsumerState<JobsView> createState() => _JobsViewState();
}

class _JobsViewState extends ConsumerState<JobsView> {
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateHeaderHeight();
    });
  }

  void _updateHeaderHeight() {
    if (!mounted) return;
    final context = _headerKey.currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox;
      if (_headerHeight != box.size.height) {
        setState(() {
          _headerHeight = box.size.height;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider);
    final jobsView = ref.watch(jobsViewProvider);
    final selectedJob = ref.watch(selectedJobProvider);

    Widget listPane = JobListView(
      isTablet: widget.isTablet,
      headerKey: _headerKey,
    );

    Widget rightPane;
    if (jobsView == 'list' && selectedJob == null) {
      rightPane = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.work_outline,
              size: 64,
              color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
            ),
            const SizedBox(height: 16),
            Text(
              "Select a job to view details",
              style: TextStyle(
                color: isDarkMode
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
      );
    } else if (jobsView == 'create') {
      rightPane = const CreateJobWizard();
    } else if (jobsView == 'details' && selectedJob != null) {
      rightPane = const JobDetailsView();
    } else if (jobsView == 'review' && selectedJob != null) {
      rightPane = const ReviewApplicantsView();
    } else if (jobsView == 'apply' && selectedJob != null) {
      rightPane = const ApplyJobView();
    } else if (jobsView == 'success') {
      rightPane = const JobSuccessView();
    } else {
      rightPane = const SizedBox.shrink();
    }

    if (widget.isTablet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 1, child: listPane),
          const SizedBox(width: 32),
          Container(
            width: 1,
            color: isDarkMode ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          const SizedBox(width: 32),
          Expanded(flex: 2, child: rightPane),
        ],
      );
    } else {
      return SizedBox(
        height:
            MediaQuery.sizeOf(context).height -
            (kToolbarHeight + kBottomNavigationBarHeight + 150),
        child: jobsView == 'list' ? listPane : rightPane,
      );
    }
  }
}
