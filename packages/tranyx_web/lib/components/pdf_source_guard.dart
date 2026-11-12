import '../services/firebase_service.dart';

/// Max lease/contract PDF size accepted by the web uploader. The PDF is stored base64-encoded in a
/// single Firestore document (1 MiB limit), and base64 adds ~33%, so 700 KB is the safe ceiling.
const int kLeasePdfMaxBytes = 700 * 1024;

const String kPdfDataPrefix = 'data:application/pdf;base64,JVBERi';

String formatPdfLimit() => '700 KB';

/// `data:application/pdf;base64,JVBERi…` (a real `%PDF` header) and nothing else.
bool isSafePdfDataUrl(String source) => source.startsWith(kPdfDataPrefix);

/// https URL on the exact Google Storage hosts, under THIS project's bucket only.
bool isSafePdfStorageUrl(String source, {Set<String>? buckets}) {
  final Uri uri;
  try {
    uri = Uri.parse(source.trim());
  } catch (_) {
    return false;
  }
  if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) return false;
  if (uri.hasPort && uri.port != 443) return false;
  final allowed = buckets ?? _projectBuckets();
  final seg = uri.pathSegments;
  if (uri.host == 'firebasestorage.googleapis.com') {
    // /v0/b/<bucket>/o/<object>
    return seg.length >= 5 && seg[0] == 'v0' && seg[1] == 'b' && allowed.contains(seg[2]) && seg[3] == 'o';
  }
  if (uri.host == 'storage.googleapis.com') {
    // /<bucket>/<object>
    return seg.length >= 2 && allowed.contains(seg[0]);
  }
  return false;
}

bool isAllowedPdfSource(String source) => isSafePdfDataUrl(source) || isSafePdfStorageUrl(source);

Set<String> _projectBuckets() {
  final c = currentFirebaseConfig;
  return {c.storageBucket, '${c.projectId}.appspot.com', '${c.projectId}.firebasestorage.app'};
}
