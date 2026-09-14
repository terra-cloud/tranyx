import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Helper utility for detecting, parsing, sanitizing, and versioning custom contract PDF documents.
///
/// Ensures raw Base64 data is NEVER rendered to the UI, supports legacy formats
/// (`[Uploaded File: name]\ndata:...`), and manages structured contract document references.
class CustomContractHelper {
  static const int maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

  /// Checks if the given contract terms represent a custom PDF document.
  static bool isCustomPdf(String? terms) {
    if (terms == null || terms.trim().isEmpty) return false;
    final trimmed = terms.trim();
    final lower = trimmed.toLowerCase();

    // Check bracketed headers
    if (trimmed.startsWith('[Uploaded File:') ||
        trimmed.startsWith('[Custom Contract:') ||
        trimmed.startsWith('[Custom PDF Contract:')) {
      return true;
    }

    // Check MIME type or extension
    if (lower.contains('data:application/pdf') ||
        lower.contains('.pdf') ||
        lower.contains('/pdf')) {
      return true;
    }

    // Check document ID reference prefix
    if (trimmed.startsWith('contract_document:') || trimmed.startsWith('doc_contract_')) {
      return true;
    }

    return false;
  }

  /// Extracts the original PDF filename from contract terms.
  static String extractFileName(String? terms, {String defaultName = 'Custom Contract Document.pdf'}) {
    if (terms == null || terms.trim().isEmpty) return defaultName;
    final trimmed = terms.trim();

    // Pattern 1: [Uploaded File: <filename>]
    final uploadMatch = RegExp(r'\[Uploaded File:\s*([^\]]+)\]', caseSensitive: false).firstMatch(trimmed);
    if (uploadMatch != null) {
      final name = uploadMatch.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }

    // Pattern 2: [Custom Contract: <filename>] or [Custom PDF Contract: <filename>]
    final customMatch = RegExp(r'\[(?:Custom Contract|Custom PDF Contract):\s*([^\|\]]+)', caseSensitive: false).firstMatch(trimmed);
    if (customMatch != null) {
      final name = customMatch.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    }

    // Pattern 3: JSON encoded metadata
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        if (map['fileName'] != null && map['fileName'].toString().isNotEmpty) {
          return map['fileName'].toString();
        }
      } catch (_) {}
    }

    // Fallback: if terms is a direct URL ending in .pdf
    if (trimmed.toLowerCase().endsWith('.pdf') && (trimmed.startsWith('http://') || trimmed.startsWith('https://'))) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        return Uri.decodeComponent(uri.pathSegments.last);
      }
    }

    return defaultName;
  }

  /// Extracts the document ID if present in the terms.
  static String? extractDocumentId(String? terms) {
    if (terms == null || terms.trim().isEmpty) return null;
    final trimmed = terms.trim();

    // Pattern 1: id:<docId>
    final idMatch = RegExp(r'id:([a-zA-Z0-9_\-]+)', caseSensitive: false).firstMatch(trimmed);
    if (idMatch != null) {
      return idMatch.group(1);
    }

    // Pattern 2: contract_document:<docId>
    final prefixMatch = RegExp(r'contract_document:([a-zA-Z0-9_\-]+)', caseSensitive: false).firstMatch(trimmed);
    if (prefixMatch != null) {
      return prefixMatch.group(1);
    }

    // Pattern 3: doc_contract_...
    final directMatch = RegExp(r'\b(doc_contract_[a-zA-Z0-9_]+)\b').firstMatch(trimmed);
    if (directMatch != null) {
      return directMatch.group(1);
    }

    // Pattern 4: JSON encoded
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        if (map['documentId'] != null) return map['documentId'].toString();
        if (map['id'] != null) return map['id'].toString();
      } catch (_) {}
    }

    return null;
  }

  /// Extracts the underlying PDF source (HTTP URL, document ID reference, or Base64 data URI).
  static String extractPdfSource(String? terms) {
    if (terms == null || terms.trim().isEmpty) return '';
    final trimmed = terms.trim();

    // Check for newline separator: [Header]\n<payload>
    final newlineIdx = trimmed.indexOf('\n');
    if (newlineIdx != -1) {
      final payload = trimmed.substring(newlineIdx + 1).trim();
      if (payload.isNotEmpty) {
        return payload;
      }
    }

    // Check for inline data URL: data:application/pdf;base64,...
    final dataIdx = trimmed.indexOf('data:application/pdf');
    if (dataIdx != -1) {
      return trimmed.substring(dataIdx).trim();
    }

    // Check for HTTP/HTTPS URL
    final httpIdx = trimmed.indexOf('http://');
    final httpsIdx = trimmed.indexOf('https://');
    final startIdx = (httpsIdx != -1) ? httpsIdx : httpIdx;
    if (startIdx != -1) {
      final sub = trimmed.substring(startIdx);
      final spaceIdx = sub.indexOf(' ');
      final closingBracketIdx = sub.indexOf(']');
      int end = sub.length;
      if (spaceIdx != -1 && spaceIdx < end) end = spaceIdx;
      if (closingBracketIdx != -1 && closingBracketIdx < end) end = closingBracketIdx;
      return sub.substring(0, end).trim();
    }

    // Check for document ID prefix
    final docId = extractDocumentId(trimmed);
    if (docId != null) {
      return 'contract_document:$docId';
    }

    return trimmed;
  }

  /// Produces a sanitized, human-readable summary of the contract terms.
  /// Guarantees that raw Base64 strings are NEVER returned.
  static String sanitizeForDisplay(String? terms) {
    if (terms == null || terms.trim().isEmpty) return 'No contract terms specified.';
    final trimmed = terms.trim();

    if (isCustomPdf(trimmed)) {
      final name = extractFileName(trimmed, defaultName: '');
      if (name.isNotEmpty) {
        return '📄 Attached Contract Document: $name';
      }
      return '📄 Attached Custom Contract Document (PDF)';
    }

    // For regular text terms, ensure any accidental Base64 is not rendered
    if (trimmed.contains('data:application/pdf;base64,') ||
        (trimmed.length > 500 && !trimmed.contains(' ') && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(trimmed))) {
      return '📄 Attached Custom Contract Document (PDF)';
    }

    return trimmed;
  }

  /// Formats clean contract terms reference with filename and document ID.
  static String formatCleanTerms({
    required String fileName,
    required String documentId,
    String? storageUrl,
    String? sha256Hash,
  }) {
    final cleanName = fileName.replaceAll('\n', '').replaceAll(']', '').trim();
    final source = (storageUrl != null && storageUrl.isNotEmpty) ? storageUrl : 'contract_document:$documentId';
    final hashPart = (sha256Hash != null && sha256Hash.isNotEmpty) ? '|hash:$sha256Hash' : '';
    return '[Custom Contract: $cleanName|id:$documentId$hashPart]\n$source';
  }

  /// Calculates the SHA-256 hash of byte data.
  static String calculateSha256(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Formats bytes into human-readable size (e.g., 240 KB, 1.2 MB).
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
