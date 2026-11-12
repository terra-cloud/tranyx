import 'package:test/test.dart';
import 'package:tranyx_web/components/pdf_source_guard.dart';

void main() {
  final b = {'tranyx-dev.firebasestorage.app'};
  test('accepts real PDF data URL only', () {
    expect(isSafePdfDataUrl('data:application/pdf;base64,JVBERi0xLjQK'), isTrue);
    expect(isSafePdfDataUrl('data:application/pdf;base64,AAAA'), isFalse);
    expect(isSafePdfDataUrl('data:text/html;base64,JVBERi'), isFalse);
    expect(isSafePdfDataUrl('javascript:alert(1)'), isFalse);
  });
  test('storage URLs must be https, exact host, this bucket', () {
    expect(isSafePdfStorageUrl('https://firebasestorage.googleapis.com/v0/b/tranyx-dev.firebasestorage.app/o/a%2Fb.pdf?alt=media', buckets: b), isTrue);
    expect(isSafePdfStorageUrl('https://storage.googleapis.com/tranyx-dev.firebasestorage.app/a.pdf', buckets: b), isTrue);
    expect(isSafePdfStorageUrl('https://storage.googleapis.com/other-bucket/a.pdf', buckets: b), isFalse);
    expect(isSafePdfStorageUrl('https://firebasestorage.googleapis.com/v0/b/other/o/a.pdf', buckets: b), isFalse);
    expect(isSafePdfStorageUrl('http://storage.googleapis.com/tranyx-dev.firebasestorage.app/a.pdf', buckets: b), isFalse);
    expect(isSafePdfStorageUrl('https://storage.googleapis.com.evil.com/tranyx-dev.firebasestorage.app/a.pdf', buckets: b), isFalse);
    expect(isSafePdfStorageUrl('https://evil.com/storage.googleapis.com/tranyx-dev.firebasestorage.app/a.pdf', buckets: b), isFalse);
    expect(isSafePdfStorageUrl('https://x@storage.googleapis.com/tranyx-dev.firebasestorage.app/a.pdf', buckets: b), isFalse);
  });
}
