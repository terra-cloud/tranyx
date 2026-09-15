import 'package:local_auth/local_auth.dart';
import 'package:tranyx_mobile/core/utils/secure_storage_helper.dart';

class BiometricService {
  static final _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  static bool isAuthenticating = false;

  static Future<bool> authenticate() async {
    isAuthenticating = true;
    try {
      final success = await _auth.authenticate(
        localizedReason: 'Unlock Tranyx to access your DeFi wallet',
        biometricOnly: false,
      );
      return success;
    } catch (_) {
      return false;
    } finally {
      Future.delayed(const Duration(milliseconds: 300), () {
        isAuthenticating = false;
      });
    }
  }

  static Future<bool> isBiometricEnabled() =>
      SecureStorageHelper.getBiometricEnabled();

  static Future<void> setBiometricEnabled(bool value) =>
      SecureStorageHelper.saveBiometricEnabled(value);
}
