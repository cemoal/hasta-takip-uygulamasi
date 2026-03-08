import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

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
}
