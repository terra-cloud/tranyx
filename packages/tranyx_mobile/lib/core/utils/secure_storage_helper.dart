import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageHelper {
  static const _storage = FlutterSecureStorage();

  static Future<void> savePassword(String password) async {
    await _storage.write(key: 'user_password', value: password);
  }

  static Future<String?> getPassword() async {
    return await _storage.read(key: 'user_password');
  }

  static Future<void> deletePassword() async {
    await _storage.delete(key: 'user_password');
  }

  static String obfuscate(String text) {
    const key = "tranyx_secure_key_2026";
    final bytes = utf8.encode(text);
    final keyBytes = utf8.encode(key);
    final result = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ keyBytes[i % keyBytes.length],
    );
    return base64Url.encode(result);
  }

  static String deobfuscate(String base64text) {
    const key = "tranyx_secure_key_2026";
    final bytes = base64Url.decode(base64text);
    final keyBytes = utf8.encode(key);
    final result = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ keyBytes[i % keyBytes.length],
    );
    return utf8.decode(result);
  }
}
