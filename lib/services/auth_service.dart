import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Uygulama genelinde TC kimlik numaralarının Firestore'da düz metin olarak
/// saklanmasını önlemek için kullanılan sabit uygulama düzeyi tuz (pepper).
/// Bu değer hiçbir zaman değiştirilmemelidir; değiştirilirse mevcut kullanıcılar
/// giriş yapamaz hale gelir.
const String _kTcLookupPepper = 'h4st4-t4k1p-l00kup-p3pp3r-2025';

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

  /// TC kimlik numarasını Firestore'daki arama (lookup) alanı için PBKDF2 ile hash'ler.
  /// PBKDF2-HMAC-SHA256 kullanılarak sabit pepper ve yüksek iterasyon sayısıyla
  /// kaba kuvvet saldırılarına karşı direnç sağlanır. Düz metin TC numaraları
  /// veritabanında saklanmaz ve olası bir veri ihlalinde doğrudan okunamazlar.
  static String hashTcForLookup(String tc) {
    if (tc.isEmpty) return "";

    const int iterations = 10000;
    final passwordBytes = utf8.encode(tc);
    final saltBytes = utf8.encode(_kTcLookupPepper);

    // PBKDF2-HMAC-SHA256: tek blok (i=1), çıktı = 32 byte (256 bit)
    final saltWithBlock = Uint8List(saltBytes.length + 4);
    saltWithBlock.setRange(0, saltBytes.length, saltBytes);
    // Blok numarası 1, big-endian: [0x00, 0x00, 0x00, 0x01]
    saltWithBlock[saltBytes.length + 3] = 1;

    final hmac = Hmac(sha256, passwordBytes);
    var u = List<int>.from(hmac.convert(saltWithBlock).bytes);
    final t = List<int>.from(u);

    for (int i = 1; i < iterations; i++) {
      u = List<int>.from(hmac.convert(u).bytes);
      for (int j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }

    return t.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Firebase Auth için Email formatına çevirir (Sadece doktorlar için).
  static String createEmailFromHash(String hashedTc) {
    // Firebase auth email formatı zorunludur.
    return "$hashedTc@hastatakip.com";
  }
}
