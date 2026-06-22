import 'dart:convert';
import 'dart:typed_data';
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

  static Future<void> savePhantomSessionKey(Uint8List keyBytes) async {
    await _storage.write(
      key: 'phantom_session_private_key',
      value: base64Url.encode(keyBytes),
    );
  }

  static Future<Uint8List?> getPhantomSessionKey() async {
    final val = await _storage.read(key: 'phantom_session_private_key');
    if (val == null) return null;
    return base64Url.decode(val);
  }

  static Future<void> deletePhantomSessionKey() async {
    await _storage.delete(key: 'phantom_session_private_key');
  }

  static Future<void> saveConnectingWalletType(String type) async {
    await _storage.write(key: 'connecting_wallet_type', value: type);
  }

  static Future<String?> getConnectingWalletType() async {
    return await _storage.read(key: 'connecting_wallet_type');
  }

  static Future<void> deleteConnectingWalletType() async {
    await _storage.delete(key: 'connecting_wallet_type');
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
