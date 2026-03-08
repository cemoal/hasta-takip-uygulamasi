import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class AuthService {
  /// Uygulama genelinde tcLookup alanı için kullanılan global salt.
  /// /dev/urandom ile üretilmiştir (32 byte). Bu salt sayesinde
  /// Firestore sızsa bile TC numaraları düz metin olarak görünmez.
  static const String _lookupSalt =
      'c5ccbd87521fc55c57e0816a78303d108eb5722fbcc9a26275155d3af7298b6b';

  /// TC'yi global salt ile hash'leyerek Firestore lookup alanı için kullanır.
  /// Aynı TC her zaman aynı hash'i üretir (sorgulanabilir).
  static String hashTcForLookup(String tc) {
    if (tc.isEmpty) return "";
    final saltedTc = "$tc$_lookupSalt";
    final bytes = utf8.encode(saltedTc);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

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
