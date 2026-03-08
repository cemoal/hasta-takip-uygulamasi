import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/auth_service.dart';

class DoktorKayit extends StatefulWidget {
  const DoktorKayit({super.key});

  @override
  State<DoktorKayit> createState() => _DoktorKayitState();
}

class _DoktorKayitState extends State<DoktorKayit> {
  final _tcController = TextEditingController();
  final _isimController = TextEditingController();
  final _sifreController = TextEditingController();
  bool _yukleniyor = false;

  void _kayitOl() async {
    final tc = _tcController.text.trim();
    final isim = _isimController.text.trim();
    final sifre = _sifreController.text.trim();

    if (tc.length != 11 || isim.isEmpty || sifre.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Lütfen tüm alanları geçerli doldurun. Şifre en az 6 karakter olmalı.",
          ),
        ),
      );
      return;
    }

    setState(() => _yukleniyor = true);

    try {
      final salt = AuthService.generateSalt();
      final hashedTc = AuthService.hashTcWithSalt(tc, salt);
      final email = AuthService.createEmailFromHash(hashedTc);

      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: sifre);

      await FirebaseFirestore.instance
          .collection('doktorlar')
          .doc(userCredential.user!.uid)
          .set({
            'isim': isim,
            'tcHash': hashedTc,
            'tcSalt': salt,
            'tcLookup': tc,
            'hastalar': [],
            'kayitTarihi': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Kayıt başarılı! Giriş yapabilirsiniz."),
          ),
        );
        Navigator.pop(context); // Login ekranına geri dön
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Kayıt hatası: ${e.message}")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Bir hata oluştu: $e")));
      }
    } finally {
      setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doktor Kayıt'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.medical_information, size: 80, color: Colors.teal),
            const SizedBox(height: 30),
            TextField(
              controller: _tcController,
              decoration: const InputDecoration(
                labelText: "TC Kimlik Numarası",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
              keyboardType: TextInputType.number,
              maxLength: 11,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _isimController,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Ad Soyad (Örn: Dr. Ahmet Yılmaz)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sifreController,
              decoration: const InputDecoration(
                labelText: "Şifre (En az 6 karakter)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _yukleniyor ? null : _kayitOl,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
                child: _yukleniyor
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Kayıt Ol", style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
