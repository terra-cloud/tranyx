import 'package:shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('CustomContractHelper Tests', () {
    const legacyRawTerms =
        '[Uploaded File: May 10 2024 Notice of Contract Expiration (1).pdf]\n'
        'data:application/pdf;base64,JVBERi0xLjQKJcTl8uXrp/Og0MTGCjQgMCBvYmoKPDwKL0ZpbHRlciAvRmxhdGVEZWNvZGUKL0xlbmd0aCAxOTU...';

    const cleanNewTerms =
        '[Custom Contract: May 10 2024 Notice of Contract Expiration (1).pdf|id:doc_contract_1726301234567|hash:abc123def456]\n'
        'https://firebasestorage.googleapis.com/v0/b/tranyx-dev.firebasestorage.app/o/contract_documents%2Fdoc.pdf';

    const documentRefTerms =
        '[Custom Contract: Lease_Agreement_2026.pdf|id:doc_contract_998877]\n'
        'contract_document:doc_contract_998877';

    test('isCustomPdf correctly identifies PDF terms across all variants', () {
      expect(CustomContractHelper.isCustomPdf(legacyRawTerms), isTrue);
      expect(CustomContractHelper.isCustomPdf(cleanNewTerms), isTrue);
      expect(CustomContractHelper.isCustomPdf(documentRefTerms), isTrue);
      expect(CustomContractHelper.isCustomPdf('https://example.com/docs/contract.pdf'), isTrue);
      expect(CustomContractHelper.isCustomPdf('Standard P2P terms'), isFalse);
      expect(CustomContractHelper.isCustomPdf('Standard P2P Lease terms'), isFalse);
      expect(CustomContractHelper.isCustomPdf('No smoking, return with full tank.'), isFalse);
      expect(CustomContractHelper.isCustomPdf(null), isFalse);
      expect(CustomContractHelper.isCustomPdf(''), isFalse);
    });

    test('extractFileName extracts accurate filenames from legacy and structured terms', () {
      expect(
        CustomContractHelper.extractFileName(legacyRawTerms),
        equals('May 10 2024 Notice of Contract Expiration (1).pdf'),
      );
      expect(
        CustomContractHelper.extractFileName(cleanNewTerms),
        equals('May 10 2024 Notice of Contract Expiration (1).pdf'),
      );
      expect(
        CustomContractHelper.extractFileName(documentRefTerms),
        equals('Lease_Agreement_2026.pdf'),
      );
      expect(
        CustomContractHelper.extractFileName('https://example.com/agreements/host_special_lease.pdf'),
        equals('host_special_lease.pdf'),
      );
      expect(
        CustomContractHelper.extractFileName('Plain text terms'),
        equals('Custom Contract Document.pdf'),
      );
    });

    test('extractDocumentId extracts document ID when present', () {
      expect(CustomContractHelper.extractDocumentId(cleanNewTerms), equals('doc_contract_1726301234567'));
      expect(CustomContractHelper.extractDocumentId(documentRefTerms), equals('doc_contract_998877'));
      expect(CustomContractHelper.extractDocumentId(legacyRawTerms), isNull);
    });

    test('extractPdfSource retrieves storage URL, document ref, or data URI without bracket header', () {
      final legacySource = CustomContractHelper.extractPdfSource(legacyRawTerms);
      expect(legacySource.startsWith('data:application/pdf;base64,'), isTrue);
      expect(legacySource.contains('[Uploaded File:'), isFalse);

      final cleanSource = CustomContractHelper.extractPdfSource(cleanNewTerms);
      expect(cleanSource, equals('https://firebasestorage.googleapis.com/v0/b/tranyx-dev.firebasestorage.app/o/contract_documents%2Fdoc.pdf'));

      final docRefSource = CustomContractHelper.extractPdfSource(documentRefTerms);
      expect(docRefSource, equals('contract_document:doc_contract_998877'));
    });

    test('sanitizeForDisplay NEVER exposes Base64 strings and produces clean text', () {
      final sanitizedLegacy = CustomContractHelper.sanitizeForDisplay(legacyRawTerms);
      expect(sanitizedLegacy, equals('📄 Attached Contract Document: May 10 2024 Notice of Contract Expiration (1).pdf'));
      expect(sanitizedLegacy.contains('base64'), isFalse);
      expect(sanitizedLegacy.contains('data:'), isFalse);

      final sanitizedClean = CustomContractHelper.sanitizeForDisplay(cleanNewTerms);
      expect(sanitizedClean, equals('📄 Attached Contract Document: May 10 2024 Notice of Contract Expiration (1).pdf'));

      // Raw base64 string without header
      final rawDataOnly = 'data:application/pdf;base64,JVBERi0xLjQKJcTl8uXrp/Og0MTGC...';
      final sanitizedRaw = CustomContractHelper.sanitizeForDisplay(rawDataOnly);
      expect(sanitizedRaw, equals('📄 Attached Custom Contract Document (PDF)'));
      expect(sanitizedRaw.contains('base64'), isFalse);

      // Normal text terms are preserved
      expect(CustomContractHelper.sanitizeForDisplay('Please keep the car clean.'), equals('Please keep the car clean.'));
    });

    test('formatCleanTerms generates standardized reference', () {
      final formatted = CustomContractHelper.formatCleanTerms(
        fileName: 'Rental_Contract_2026.pdf',
        documentId: 'doc_123',
        storageUrl: 'https://storage.googleapis.com/test.pdf',
        sha256Hash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );

      expect(formatted.contains('[Custom Contract: Rental_Contract_2026.pdf|id:doc_123|hash:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855]'), isTrue);
      expect(formatted.endsWith('https://storage.googleapis.com/test.pdf'), isTrue);
    });

    test('formatFileSize converts bytes correctly', () {
      expect(CustomContractHelper.formatFileSize(0), equals('0 B'));
      expect(CustomContractHelper.formatFileSize(500), equals('500 B'));
      expect(CustomContractHelper.formatFileSize(1536), equals('1.5 KB'));
      expect(CustomContractHelper.formatFileSize(2 * 1024 * 1024), equals('2.00 MB'));
    });
  });
}
