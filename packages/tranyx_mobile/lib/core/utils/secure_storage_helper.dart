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

  static Future<void> savePhantomSessionToken(String token) async {
    await _storage.write(key: 'phantom_session_token', value: token);
  }

  static Future<String?> getPhantomSessionToken() async {
    return await _storage.read(key: 'phantom_session_token');
  }

  static Future<void> deletePhantomSessionToken() async {
    await _storage.delete(key: 'phantom_session_token');
  }

  static Future<void> savePhantomEncryptionPublicKey(String key) async {
    await _storage.write(key: 'phantom_encryption_public_key', value: key);
  }

  static Future<String?> getPhantomEncryptionPublicKey() async {
    return await _storage.read(key: 'phantom_encryption_public_key');
  }

  static Future<void> deletePhantomEncryptionPublicKey() async {
    await _storage.delete(key: 'phantom_encryption_public_key');
  }

  static Future<void> savePendingDepositPhpAmount(double amount) async {
    await _storage.write(key: 'pending_deposit_php_amount', value: amount.toString());
  }

  static Future<double?> getPendingDepositPhpAmount() async {
    final val = await _storage.read(key: 'pending_deposit_php_amount');
    if (val == null) return null;
    return double.tryParse(val);
  }

  static Future<void> deletePendingDepositPhpAmount() async {
    await _storage.delete(key: 'pending_deposit_php_amount');
  }

  static Future<void> savePendingDepositCryptoAmount(double amount) async {
    await _storage.write(key: 'pending_deposit_crypto_amount', value: amount.toString());
  }

  static Future<double?> getPendingDepositCryptoAmount() async {
    final val = await _storage.read(key: 'pending_deposit_crypto_amount');
    if (val == null) return null;
    return double.tryParse(val);
  }

  static Future<void> deletePendingDepositCryptoAmount() async {
    await _storage.delete(key: 'pending_deposit_crypto_amount');
  }

  static Future<void> savePendingDepositCurrency(String currency) async {
    await _storage.write(key: 'pending_deposit_currency', value: currency);
  }

  static Future<String?> getPendingDepositCurrency() async {
    return await _storage.read(key: 'pending_deposit_currency');
  }

  static Future<void> deletePendingDepositCurrency() async {
    await _storage.delete(key: 'pending_deposit_currency');
  }

  static Future<void> saveTrustWalletAddress(String address) async {
    await _storage.write(key: 'trust_wallet_address', value: address);
  }

  static Future<String?> getTrustWalletAddress() async {
    return await _storage.read(key: 'trust_wallet_address');
  }

  static Future<void> deleteTrustWalletAddress() async {
    await _storage.delete(key: 'trust_wallet_address');
  }

  static Future<void> saveTrustWalletTopic(String topic) async {
    await _storage.write(key: 'trust_wallet_topic', value: topic);
  }

  static Future<String?> getTrustWalletTopic() async {
    return await _storage.read(key: 'trust_wallet_topic');
  }

  static Future<void> deleteTrustWalletTopic() async {
    await _storage.delete(key: 'trust_wallet_topic');
  }

  static Future<void> saveTrustWalletKey(String keyHex) async {
    await _storage.write(key: 'trust_wallet_key', value: keyHex);
  }

  static Future<String?> getTrustWalletKey() async {
    return await _storage.read(key: 'trust_wallet_key');
  }

  static Future<void> deleteTrustWalletKey() async {
    await _storage.delete(key: 'trust_wallet_key');
  }

  static Future<void> saveMwaAuthToken(String token) async {
    await _storage.write(key: 'mwa_auth_token', value: token);
  }

  static Future<String?> getMwaAuthToken() async {
    return await _storage.read(key: 'mwa_auth_token');
  }

  static Future<void> deleteMwaAuthToken() async {
    await _storage.delete(key: 'mwa_auth_token');
  }

  static const _biometricKey = 'biometric_lock_enabled';

  static Future<void> saveBiometricEnabled(bool value) async {
    await _storage.write(key: _biometricKey, value: value.toString());
  }

  static Future<bool> getBiometricEnabled() async {
    final val = await _storage.read(key: _biometricKey);
    return val == 'true';
  }
}
