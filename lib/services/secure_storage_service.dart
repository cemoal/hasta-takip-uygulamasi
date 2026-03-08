import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const String _keyTc = 'user_tc';
  static const String _keyPassword = 'user_password';
  static const String _keyUserType = 'user_type'; // 'hasta' veya 'doktor'

  // Bilgileri güvenli depolama alanına kaydet
  Future<void> saveCredentials({
    required String tc,
    required String password,
    required String userType,
  }) async {
    await _storage.write(key: _keyTc, value: tc);
    await _storage.write(key: _keyPassword, value: password);
    await _storage.write(key: _keyUserType, value: userType);
  }

  // Kayıtlı bilgileri sil (Log out için)
  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyTc);
    await _storage.delete(key: _keyPassword);
    await _storage.delete(key: _keyUserType);
  }

  // Kayıtlı bilgileri getir
  Future<Map<String, String?>> getCredentials() async {
    final tc = await _storage.read(key: _keyTc);
    final password = await _storage.read(key: _keyPassword);
    final userType = await _storage.read(key: _keyUserType);

    return {'tc': tc, 'password': password, 'userType': userType};
  }

  // Cihazda kayıtlı kimlik bilgisi var mı?
  Future<bool> hasCredentials() async {
    final tc = await _storage.read(key: _keyTc);
    return tc != null && tc.isNotEmpty;
  }

  // Biyometrik doğrulama destekleniyor mu ve kullanılabilir mi?
  Future<bool> canUseBiometrics() async {
    final isAvailable = await _localAuth.canCheckBiometrics;
    final isDeviceSupported = await _localAuth.isDeviceSupported();
    return isAvailable || isDeviceSupported;
  }

  // Biyometrik doğrulama işlemini başlat
  Future<bool> authenticateBiometrics() async {
    try {
      final canUse = await canUseBiometrics();
      if (!canUse) return false;

      return await _localAuth.authenticate(
        localizedReason: 'Cihaza tanımlı yönteminizle giriş yapın.',
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint("Biyometrik doğrulama hatası: $e");
      return false;
    }
  }
}
