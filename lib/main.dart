import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'hasta_home.dart';
import 'doktor_home.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'doktor_kayit.dart';
import 'hasta_kayit.dart';
import 'services/secure_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const HastaTakipApp());
}

class HastaTakipApp extends StatelessWidget {
  const HastaTakipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Sağ üstteki 'Debug' bandını kaldırır
      title: 'Hasta Takip Sistemi',
      theme: ThemeData(
        // Medikal uygulamalar için temiz, güven veren renkler (Teal/Mavi)
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SecureStorageService _storageService = SecureStorageService();

  // Tab Controller veya basit state ile Hasta/Doktor geçişi
  bool _isDoktorGiris = false;

  // Hasta Giriş Controller
  final TextEditingController _hastaTcController = TextEditingController();
  final TextEditingController _hastaSifreController = TextEditingController();

  // Doktor Giriş Controller
  final TextEditingController _doktorTcController = TextEditingController();
  final TextEditingController _doktorSifreController = TextEditingController();

  bool _yukleniyor = false;

  @override
  void initState() {
    super.initState();
    _checkSavedCredentials();
  }

  Future<void> _checkSavedCredentials() async {
    setState(() => _yukleniyor = true);
    try {
      if (await _storageService.hasCredentials()) {
        final credentials = await _storageService.getCredentials();
        final tc = credentials['tc'];
        final password = credentials['password'];
        final userType = credentials['userType'];

        if (tc != null && password != null && userType != null) {
          // Biyometrik doğrulama iste
          bool authSuccess = await _storageService.authenticateBiometrics();

          if (authSuccess) {
            if (userType == 'hasta') {
              _hastaTcController.text = tc;
              _hastaSifreController.text = password;
              await _hastaGirisYap(isAutoLogin: true);
            } else if (userType == 'doktor') {
              _doktorTcController.text = tc;
              _doktorSifreController.text = password;
              await _doktorGirisYap(isAutoLogin: true);
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Kayıtlı oturum kontrol hatası: $e");
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _askToSaveCredentials(
    String tc,
    String password,
    String userType,
  ) async {
    if (!mounted) return;

    // Zaten kayıtlıysa sorma
    if (await _storageService.hasCredentials()) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Biyometrik Giriş'),
        content: const Text(
          'Sonraki girişlerinizde cihazınızın biyometrik doğrulamasını (Yüz Tanıma/Parmak İzi) kullanarak hızlıca giriş yapmak ister misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hayır'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet, Kullan'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _storageService.saveCredentials(
        tc: tc,
        password: password,
        userType: userType,
      );
    }
  }

  Future<void> _hastaGirisYap({bool isAutoLogin = false}) async {
    final tc = _hastaTcController.text.trim();
    final sifre = _hastaSifreController.text.trim();

    if (tc.length != 11 || sifre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen geçerli bir TC ve Şifre girin.")),
      );
      return;
    }

    setState(() => _yukleniyor = true);

    try {
      // 1. tcLookup alanına göre Firestore'da hastayı bul
      final query = await FirebaseFirestore.instance
          .collection('hastalar')
          .where('tcLookup', isEqualTo: AuthService.hashTcForLookup(tc))
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Bu TC ile kayıtlı hasta bulunamadı."),
            ),
          );
        }
        return;
      }

      final hastaData = query.docs.first.data();
      final String salt = hastaData['tcSalt'] ?? '';

      // 2. Salt ile hash üret ve Firebase Auth ile giriş yap
      final hashedTc = AuthService.hashTcWithSalt(tc, salt);
      final email = AuthService.createEmailFromHash(hashedTc);

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: sifre,
      );

      if (!isAutoLogin) {
        await _askToSaveCredentials(tc, sifre, 'hasta');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HastaHome(hastaId: query.docs.first.id),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Giriş hatası: ${e.message ?? 'Geçersiz kimlik bilgileri.'}",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Giriş başarısız: $e")));
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _doktorGirisYap({bool isAutoLogin = false}) async {
    final tc = _doktorTcController.text.trim();
    final sifre = _doktorSifreController.text.trim();

    if (tc.length != 11 || sifre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen geçerli bir TC ve Şifre girin.")),
      );
      return;
    }

    setState(() => _yukleniyor = true);

    try {
      // 1. tcLookup alanına göre Firestore'da doktoru bul
      final query = await FirebaseFirestore.instance
          .collection('doktorlar')
          .where('tcLookup', isEqualTo: AuthService.hashTcForLookup(tc))
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Bu TC ile kayıtlı doktor bulunamadı."),
            ),
          );
        }
        return;
      }

      final doktorData = query.docs.first.data();
      final String salt = doktorData['tcSalt'] ?? '';

      // 2. Salt ile hash üret ve Firebase Auth ile giriş yap
      final hashedTc = AuthService.hashTcWithSalt(tc, salt);
      final email = AuthService.createEmailFromHash(hashedTc);

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: sifre,
      );

      if (!isAutoLogin) {
        await _askToSaveCredentials(tc, sifre, 'doktor');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DoktorHome()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Giriş hatası: ${e.message ?? 'Geçersiz kimlik bilgileri.'}",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Bir hata oluştu: $e")));
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hasta Takip Sistemi'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.medical_services_outlined,
                size: 80,
                color: Colors.teal,
              ),
              const SizedBox(height: 20),

              // Segmented Control (Hasta / Doktor)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text("Hasta Girişi"),
                    selected: !_isDoktorGiris,
                    onSelected: (val) {
                      setState(() => _isDoktorGiris = false);
                    },
                    selectedColor: Colors.orange.shade200,
                  ),
                  const SizedBox(width: 16),
                  ChoiceChip(
                    label: const Text("Doktor Girişi"),
                    selected: _isDoktorGiris,
                    onSelected: (val) {
                      setState(() => _isDoktorGiris = true);
                    },
                    selectedColor: Colors.teal.shade200,
                  ),
                ],
              ),
              const SizedBox(height: 30),

              if (!_isDoktorGiris) ...[
                // Hasta Formu
                TextField(
                  controller: _hastaTcController,
                  decoration: const InputDecoration(
                    labelText: "TC Kimlik Numarası",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  autofillHints: const [AutofillHints.username],
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _hastaSifreController,
                  decoration: const InputDecoration(
                    labelText: "Şifre",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  autofillHints: const [AutofillHints.password],
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _yukleniyor ? null : _hastaGirisYap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade100,
                      foregroundColor: Colors.orange.shade900,
                    ),
                    child: _yukleniyor
                        ? const CircularProgressIndicator()
                        : const Text(
                            "Giriş Yap",
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HastaKayit(),
                      ),
                    );
                  },
                  child: const Text("Hesabınız yok mu? Hasta olarak kaydolun"),
                ),
              ] else ...[
                // Doktor Formu
                TextField(
                  controller: _doktorTcController,
                  decoration: const InputDecoration(
                    labelText: "TC Kimlik Numarası",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.medical_information),
                  ),
                  autofillHints: const [AutofillHints.username],
                  keyboardType: TextInputType.number,
                  maxLength: 11,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _doktorSifreController,
                  decoration: const InputDecoration(
                    labelText: "Şifre",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  autofillHints: const [AutofillHints.password],
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _yukleniyor ? null : _doktorGirisYap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade100,
                      foregroundColor: Colors.teal.shade900,
                    ),
                    child: _yukleniyor
                        ? const CircularProgressIndicator()
                        : const Text(
                            "Giriş Yap",
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DoktorKayit(),
                      ),
                    );
                  },
                  child: const Text("Hesabınız yok mu? Doktor olarak kaydolun"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
