import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:shared/shared.dart';
import '../tranyx_app.dart';
import '../../state/app_state.dart';
import '../../components/ui_helpers.dart';
import '../../services/web_interop.dart';

class EditJobModalComponent extends StatefulComponent {
  final TranyxAppState appState;
  const EditJobModalComponent({required this.appState, super.key});

  @override
  State<EditJobModalComponent> createState() => _EditJobModalState();
}

class _EditJobModalState extends State<EditJobModalComponent> {
  String _jobId = '';
  String _title = '';
  String _description = '';
  JobCategory _category = JobCategory.others;
  JobCategoryGroup _categoryGroup = JobCategoryGroup.miscellaneousEvents;
  String _dateRequirement = 'Flexible';
  DateTime? _jobDate;
  String _timePreference = 'Morning';
  String _locationType = 'On-site';
  String _address = '';
  String _landmark = '';
  String _pickupAddress = '';
  String _destinationAddress = '';
  List<String> _imageUrls = [];

  // Financial fields (read-only)
  String _pricingType = 'Package (Fixed)';
  double _pricingValue = 0.0;
  int _applicantCount = 0;

  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = component.appState.selectedJobData;
    if (data != null) {
      _jobId = data['id'] as String? ?? '';
      _title = data['title'] as String? ?? '';
      _description = data['description'] as String? ?? '';

      final catName = (data['category'] as String? ?? '').toLowerCase();
      _category = JobCategory.values.firstWhere(
        (c) => c.name.toLowerCase() == catName || c.label.toLowerCase() == catName,
        orElse: () => JobCategory.others,
      );

      final groupName = (data['categoryGroup'] as String? ?? '').toLowerCase();
      _categoryGroup = JobCategoryGroup.values.firstWhere(
        (g) => g.name.toLowerCase() == groupName || g.label.toLowerCase() == groupName,
        orElse: () => JobCategoryGroup.values.firstWhere(
          (g) => g.categories.contains(_category),
          orElse: () => JobCategoryGroup.miscellaneousEvents,
        ),
      );

      _dateRequirement = data['dateRequirement'] as String? ?? 'Flexible';
      _jobDate = parseDateTime(data['jobDate']);
      _timePreference = data['timePreference'] as String? ?? 'Morning';
      _locationType = data['locationType'] as String? ?? 'On-site';
      _address = data['address'] as String? ?? '';
      _landmark = data['landmark'] as String? ?? '';
      _pickupAddress = data['pickupAddress'] as String? ?? '';
      _destinationAddress = data['destinationAddress'] as String? ?? '';

      final rawImages = data['imageUrls'];
      if (rawImages is List) {
        _imageUrls = rawImages.map((e) => e.toString()).toList();
      }

      _pricingType = data['pricingType'] as String? ?? 'Package (Fixed)';
      _pricingValue = (data['pricingValue'] as num?)?.toDouble() ?? 0.0;
      _applicantCount = (data['applicantCount'] as num?)?.toInt() ?? 0;
    }
  }

  Future<void> _handleSubmit() async {
    setState(() => _error = null);

    if (_title.trim().isEmpty) {
      setState(() => _error = 'Please enter a job title.');
      return;
    }
    if (_description.trim().isEmpty) {
      setState(() => _error = 'Please enter a job description.');
      return;
    }
    if (_locationType == 'On-site' && _address.trim().isEmpty) {
      setState(() => _error = 'Please provide an address for on-site jobs.');
      return;
    }
    if (_dateRequirement != 'Flexible' && _jobDate == null) {
      setState(() => _error = 'Please specify a target date for the job.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final updates = <String, dynamic>{
        'title': _title.trim(),
        'description': _description.trim(),
        'category': _category.name,
        'categoryGroup': _categoryGroup.name,
        'dateRequirement': _dateRequirement,
        'timePreference': _timePreference,
        'locationType': _locationType,
        'address': _address.trim(),
        'landmark': _landmark.trim(),
        if (_jobDate != null) 'jobDate': _jobDate!.millisecondsSinceEpoch,
        if (_pickupAddress.trim().isNotEmpty) 'pickupAddress': _pickupAddress.trim(),
        if (_destinationAddress.trim().isNotEmpty) 'destinationAddress': _destinationAddress.trim(),
        'imageUrls': _imageUrls.where((url) => url.trim().isNotEmpty).toList(),
        'updatedAt': nowMs,
      };

      await component.appState.firestore.updateJobDetails(_jobId, updates);

      // Reflect updates instantly in local application state
      component.appState.setState(() {
        final existingMap = Map<String, dynamic>.from(component.appState.selectedJobData ?? {});
        existingMap.addAll(updates);
        component.appState.selectedJobData = existingMap;

        final currentSelected = component.appState.selectedJob;
        component.appState.selectedJob = SelectedJob(
          id: _jobId,
          title: updates['title'] as String,
          rate: currentSelected?.rate ?? '₱${_pricingValue.toStringAsFixed(2)}',
          distance: currentSelected?.distance ?? '—',
          urgency: updates['dateRequirement'] as String,
          status: existingMap['status'] as String? ?? 'Open',
          applicants: _applicantCount,
          createdAt: existingMap['createdAt'],
          acceptedApplicantId: existingMap['acceptedApplicantId'] as String?,
        );

        // Update in myJobs
        final myIdx = component.appState.myJobs.indexWhere((j) => j['id'] == _jobId);
        if (myIdx != -1) {
          component.appState.myJobs[myIdx] = existingMap;
        }

        // Update in availableJobs
        final availIdx = component.appState.availableJobs.indexWhere((j) => j['id'] == _jobId);
        if (availIdx != -1) {
          component.appState.availableJobs[availIdx] = existingMap;
        }

        component.appState.showEditJobModal = false;
        component.appState.showAppToast('Success', 'Job posting updated successfully.');
      });
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Component build(BuildContext context) {
    final isDark = component.appState.isDark;
    final dateStr = _jobDate != null
        ? '${_jobDate!.year}-${_jobDate!.month.toString().padLeft(2, '0')}-${_jobDate!.day.toString().padLeft(2, '0')}'
        : '';

    return div(
      classes: 'fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in',
      [
        div(
          classes:
              'w-full max-w-2xl max-h-[90vh] overflow-y-auto rounded-3xl p-6 md:p-8 ${isDark ? "bg-zinc-900 border border-zinc-800 text-zinc-100" : "bg-white text-zinc-900"} shadow-2xl space-y-6 animate-scale-up custom-scrollbar',
          [
            // Header
            div(classes: 'flex items-center justify-between pb-4 border-b ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
              div(classes: 'flex items-center gap-3', [
                div(classes: 'p-2.5 rounded-2xl bg-indigo-500/15 text-indigo-400', [
                  lIcon('edit-3', cls: 'w-5 h-5'),
                ]),
                div([
                  h2(classes: 'text-xl font-bold', [Component.text('Edit Job Posting')]),
                  p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                    Component.text('Update non-financial details before a Nyxian is accepted'),
                  ]),
                ]),
              ]),
              button(
                classes:
                    'p-2 rounded-xl border ${isDark ? "border-zinc-800 hover:bg-zinc-800 text-zinc-400" : "border-zinc-200 hover:bg-zinc-100 text-zinc-500"} transition-colors cursor-pointer',
                events: {'click': (_) => component.appState.closeEditJobModal()},
                [lIcon('x', cls: 'w-5 h-5')],
              ),
            ]),

            // Error banner
            if (_error != null)
              div(
                classes:
                    'p-4 rounded-2xl bg-red-500/10 border border-red-500/25 text-red-500 text-sm flex items-center gap-2 animate-fade-up',
                [
                  lIcon('alert-circle', cls: 'w-5 h-5 flex-shrink-0 text-red-500'),
                  span([Component.text(_error!)]),
                ],
              ),

            // Pre-hire Applicant Notice
            if (_applicantCount > 0)
              div(
                classes:
                    'p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/25 text-xs text-amber-500 font-medium flex items-center gap-2.5',
                [
                  lIcon('alert-triangle', cls: 'w-4 h-4 flex-shrink-0 text-amber-500'),
                  span([
                    Component.text(
                      'This gig has $_applicantCount applicant(s). Updating details will mark the job with an "Edited" badge so applicants see the latest requirements.',
                    ),
                  ]),
                ],
              ),

            // Section 1: Job Title & Description
            div(classes: 'space-y-4', [
              div([
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Job Title'),
                ]),
                input(
                  type: InputType.text,
                  classes:
                      'w-full p-3.5 rounded-xl border text-sm ${isDark ? "bg-zinc-800/80 border-zinc-700 text-white placeholder-zinc-500" : "bg-white border-zinc-300 text-zinc-900 placeholder-zinc-400"} outline-none focus:border-indigo-500 transition-colors',
                  value: _title,
                  attributes: {'placeholder': 'e.g., General House Cleaning / Plumbing Leak Fix'},
                  events: {'input': (e) => setState(() => _title = getInputValue(e.target))},
                ),
              ]),

              div([
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Job Description'),
                ]),
                textarea(
                  classes:
                      'w-full p-3.5 rounded-xl border text-sm ${isDark ? "bg-zinc-800/80 border-zinc-700 text-white placeholder-zinc-500" : "bg-white border-zinc-300 text-zinc-900 placeholder-zinc-400"} outline-none focus:border-indigo-500 transition-colors h-28 resize-none',
                  attributes: {'placeholder': 'Describe what needs to be done, specific requirements, or items to bring...'},
                  events: {'input': (e) => setState(() => _description = getInputValue(e.target))},
                  [Component.text(_description)],
                ),
              ]),
            ]),

            // Section 2: Category & Group
            div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
              div([
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Category Group'),
                ]),
                select(
                  classes:
                      'w-full p-3.5 rounded-xl border text-sm ${isDark ? "bg-zinc-800/80 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
                  events: {
                    'change': (e) {
                      final val = getInputValue(e.target);
                      setState(() {
                        _categoryGroup = JobCategoryGroup.values.firstWhere(
                          (g) => g.name == val,
                          orElse: () => JobCategoryGroup.miscellaneousEvents,
                        );
                        _category = _categoryGroup.categories.isNotEmpty
                            ? _categoryGroup.categories.first
                            : JobCategory.others;
                      });
                    },
                  },
                  [
                    for (final g in JobCategoryGroup.values)
                      option(value: g.name, selected: _categoryGroup == g, [Component.text(g.label)]),
                  ],
                ),
              ]),

              div([
                label(classes: 'block text-sm font-semibold mb-2 ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                  Component.text('Job Category'),
                ]),
                select(
                  classes:
                      'w-full p-3.5 rounded-xl border text-sm ${isDark ? "bg-zinc-800/80 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
                  events: {
                    'change': (e) {
                      final val = getInputValue(e.target);
                      setState(() {
                        _category = JobCategory.values.firstWhere(
                          (c) => c.name == val,
                          orElse: () => JobCategory.others,
                        );
                      });
                    },
                  },
                  [
                    for (final c in _categoryGroup.categories)
                      option(value: c.name, selected: _category == c, [Component.text(c.label)]),
                  ],
                ),
              ]),
            ]),

            // Section 3: Schedule & Urgency
            div(classes: 'p-4 rounded-2xl border ${isDark ? "bg-zinc-800/40 border-zinc-800" : "bg-zinc-50 border-zinc-200"} space-y-4', [
              h4(classes: 'text-sm font-bold flex items-center gap-2', [
                lIcon('calendar', cls: 'w-4 h-4 text-indigo-400'),
                Component.text('Schedule & Time Preference'),
              ]),

              div(classes: 'grid grid-cols-1 md:grid-cols-3 gap-4', [
                div([
                  label(classes: 'block text-xs font-semibold mb-1.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                    Component.text('Date Requirement'),
                  ]),
                  select(
                    classes:
                        'w-full p-3 rounded-xl border text-sm ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
                    events: {
                      'change': (e) => setState(() => _dateRequirement = getInputValue(e.target)),
                    },
                    [
                      option(value: 'Flexible', selected: _dateRequirement == 'Flexible', [Component.text('Flexible')]),
                      option(value: 'On Date', selected: _dateRequirement == 'On Date', [Component.text('On Date')]),
                      option(value: 'Before', selected: _dateRequirement == 'Before', [Component.text('Before Date')]),
                    ],
                  ),
                ]),

                div([
                  label(classes: 'block text-xs font-semibold mb-1.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                    Component.text('Target Date'),
                  ]),
                  input(
                    type: InputType.date,
                    classes:
                        'w-full p-3 rounded-xl border text-sm ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none',
                    value: dateStr,
                    events: {
                      'change': (e) {
                        final val = getInputValue(e.target);
                        if (val.isNotEmpty) {
                          setState(() => _jobDate = DateTime.tryParse(val));
                        }
                      },
                    },
                  ),
                ]),

                div([
                  label(classes: 'block text-xs font-semibold mb-1.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                    Component.text('Time Preference'),
                  ]),
                  select(
                    classes:
                        'w-full p-3 rounded-xl border text-sm ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
                    events: {
                      'change': (e) => setState(() => _timePreference = getInputValue(e.target)),
                    },
                    [
                      option(value: 'Morning', selected: _timePreference == 'Morning', [Component.text('Morning (8AM - 12PM)')]),
                      option(value: 'Midday', selected: _timePreference == 'Midday', [Component.text('Midday (12PM - 2PM)')]),
                      option(value: 'Afternoon', selected: _timePreference == 'Afternoon', [Component.text('Afternoon (2PM - 6PM)')]),
                      option(value: 'Evening', selected: _timePreference == 'Evening', [Component.text('Evening (6PM onwards)')]),
                    ],
                  ),
                ]),
              ]),
            ]),

            // Section 4: Location & Landmarks
            div(classes: 'p-4 rounded-2xl border ${isDark ? "bg-zinc-800/40 border-zinc-800" : "bg-zinc-50 border-zinc-200"} space-y-4', [
              h4(classes: 'text-sm font-bold flex items-center gap-2', [
                lIcon('map-pin', cls: 'w-4 h-4 text-indigo-400'),
                Component.text('Location & Landmarks'),
              ]),

              div(classes: 'grid grid-cols-1 md:grid-cols-2 gap-4', [
                div([
                  label(classes: 'block text-xs font-semibold mb-1.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                    Component.text('Location Type'),
                  ]),
                  select(
                    classes:
                        'w-full p-3 rounded-xl border text-sm ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none cursor-pointer',
                    events: {
                      'change': (e) => setState(() => _locationType = getInputValue(e.target)),
                    },
                    [
                      option(value: 'On-site', selected: _locationType == 'On-site', [Component.text('On-site')]),
                      option(value: 'Remote', selected: _locationType == 'Remote', [Component.text('Remote / Work from Anywhere')]),
                    ],
                  ),
                ]),

                if (_locationType == 'On-site')
                  div([
                    label(classes: 'block text-xs font-semibold mb-1.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                      Component.text('Landmark / Instructions'),
                    ]),
                    input(
                      type: InputType.text,
                      classes:
                          'w-full p-3 rounded-xl border text-sm ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none',
                      value: _landmark,
                      attributes: {'placeholder': 'e.g. Near Shell gas station, Gate 2'},
                      events: {'input': (e) => setState(() => _landmark = getInputValue(e.target))},
                    ),
                  ]),
              ]),

              if (_locationType == 'On-site')
                div([
                  label(classes: 'block text-xs font-semibold mb-1.5 ${isDark ? "text-zinc-400" : "text-zinc-600"}', [
                    Component.text('Street / Area Address'),
                  ]),
                  input(
                    type: InputType.text,
                    classes:
                        'w-full p-3 rounded-xl border text-sm ${isDark ? "bg-zinc-900 border-zinc-700 text-white" : "bg-white border-zinc-300"} outline-none',
                    value: _address,
                    attributes: {'placeholder': 'Street, Barangay, City'},
                    events: {'input': (e) => setState(() => _address = getInputValue(e.target))},
                  ),
                ]),
            ]),

            // Section 5: Budget & Escrow (Locked)
            div(
              classes:
                  'p-4 rounded-2xl border ${isDark ? "bg-zinc-800/20 border-zinc-800/80" : "bg-zinc-100/70 border-zinc-200"} flex items-start gap-3',
              [
                div(classes: 'p-2 rounded-xl bg-zinc-500/10 text-zinc-400 flex-shrink-0 mt-0.5', [
                  lIcon('lock', cls: 'w-4 h-4'),
                ]),
                div(classes: 'flex-1 space-y-1', [
                  div(classes: 'flex items-center justify-between', [
                    span(classes: 'text-sm font-bold ${isDark ? "text-zinc-300" : "text-zinc-700"}', [
                      Component.text('Escrow & Budget Terms (Protected)'),
                    ]),
                    span(classes: 'text-sm font-mono font-bold text-indigo-400', [
                      Component.text('₱${_pricingValue.toStringAsFixed(2)} ($_pricingType)'),
                    ]),
                  ]),
                  p(classes: 'text-xs ${isDark ? "text-zinc-400" : "text-zinc-500"}', [
                    Component.text(
                      'Escrow funds for this posting are currently reserved. Pricing is locked pre-hire to maintain fairness and platform integrity. To change the budget, please cancel and create a new gig.',
                    ),
                  ]),
                ]),
              ],
            ),

            // Footer actions
            div(classes: 'flex items-center justify-end gap-3 pt-4 border-t ${isDark ? "border-zinc-800" : "border-zinc-200"}', [
              button(
                classes:
                    'px-6 py-3 rounded-2xl font-semibold border ${isDark ? "border-zinc-700 hover:bg-zinc-800 text-zinc-300" : "border-zinc-300 hover:bg-zinc-100 text-zinc-700"} transition-colors cursor-pointer',
                events: {'click': (_) => component.appState.closeEditJobModal()},
                [Component.text('Cancel')],
              ),
              button(
                classes:
                    'px-8 py-3 rounded-2xl font-semibold text-white logo-gradient hover:opacity-90 transition-opacity flex items-center gap-2 cursor-pointer ${_isSubmitting ? "opacity-60 cursor-not-allowed" : ""}',
                events: _isSubmitting ? {} : {'click': (_) => _handleSubmit()},
                [
                  if (_isSubmitting) lIcon('loader-2', cls: 'w-4 h-4 animate-spin'),
                  Component.text(_isSubmitting ? 'Saving...' : 'Save Changes'),
                ],
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
