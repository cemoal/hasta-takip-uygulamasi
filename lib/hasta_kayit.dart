import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/auth_service.dart';

class HastaKayit extends StatefulWidget {
  const HastaKayit({super.key});

  @override
  State<HastaKayit> createState() => _HastaKayitState();
}

class _HastaKayitState extends State<HastaKayit> {
  final _tcController = TextEditingController();
  final _isimController = TextEditingController();
  final _yasController = TextEditingController();
  final _sifreController = TextEditingController();
  bool _yukleniyor = false;

  void _kayitOl() async {
    final tc = _tcController.text.trim();
    final isim = _isimController.text.trim();
    final yas = int.tryParse(_yasController.text.trim()) ?? 0;
    final sifre = _sifreController.text.trim();

    if (tc.length != 11 || isim.isEmpty || yas <= 0 || sifre.length < 6) {
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
          .collection('hastalar')
          .doc(hashedTc)
          .set({
            'isim': isim,
            'yas': yas,
            'uid': userCredential.user!.uid,
            'tcSalt': salt,
            'tcLookup': tc,
            'kayitTarihi': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Kayıt başarılı! Giriş yapabilirsiniz."),
          ),
        );
        Navigator.pop(context);
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
  void dispose() {
    _tcController.dispose();
    _isimController.dispose();
    _yasController.dispose();
    _sifreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hasta Kayıt'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.person_add, size: 80, color: Colors.orange),
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
                labelText: "Ad Soyad",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _yasController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Yaş",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
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
                  backgroundColor: Colors.orange.shade700,
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
