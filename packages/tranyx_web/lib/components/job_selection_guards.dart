/// Pure guards used by the Jobs / Messages flows so async results never land on the wrong selection.

/// True when [jobId] (captured when an async load started) is no longer the selected job.
bool isStaleJobSelection(String? selectedJobId, String jobId) => (selectedJobId ?? '') != jobId;

/// True when a realtime applications snapshot belongs to the job the user is looking at.
bool applicationsBelongToJob(String? selectedJobId, String listenerJobId, List<Map<String, dynamic>> apps) {
  if (isStaleJobSelection(selectedJobId, listenerJobId)) return false;
  // Applications live in jobs/<id>/applications; any record that names another job is foreign.
  return apps.every((a) {
    final j = a['jobId'];
    return j == null || j.toString().isEmpty || j.toString() == listenerJobId;
  });
}

/// Finds the application of [applicantUid] among the applications loaded from `jobs/<jobId>/applications`.
Map<String, dynamic>? findApplicationFor(List<Map<String, dynamic>> apps, String applicantUid) {
  if (applicantUid.isEmpty) return null;
  for (final a in apps) {
    if ((a['applicantUid'] ?? '').toString() == applicantUid) return a;
  }
  return null;
}

/// Only the job's creator may review applicants, edit, or hire.
bool isJobCreator(Map<String, dynamic>? job, String? uid) {
  if (job == null || uid == null || uid.isEmpty) return false;
  final creator = (job['creatorId'] ?? '').toString();
  return creator.isNotEmpty && creator == uid;
}

/// A chat snapshot is only applied when it belongs to the chat currently open.
bool chatEventIsCurrent(String currentChatId, String eventChatId) =>
    currentChatId.isNotEmpty && currentChatId == eventChatId;
