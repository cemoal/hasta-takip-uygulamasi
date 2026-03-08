import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class AuthService {
  /// Kriptografik olarak güvenli rastgele salt üretir (16 byte, hex string döner).
  /// dart:math Random.secure() arka planda /dev/urandom kullanır.
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Verilen TC ve salt ile SHA-256 hash üretir.
  static String hashTcWithSalt(String tc, String salt) {
    if (tc.isEmpty) return "";
    final saltedTc = "$tc$salt";
    final bytes = utf8.encode(saltedTc);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Firebase Auth için Email formatına çevirir (Sadece doktorlar için).
  static String createEmailFromHash(String hashedTc) {
    // Firebase auth email formatı zorunludur.
    return "$hashedTc@hastatakip.com";
  }
}
