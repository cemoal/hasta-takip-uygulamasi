import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class HastaEkle extends StatefulWidget {
  const HastaEkle({super.key});

  @override
  State<HastaEkle> createState() => _HastaEkleState();
}

class _HastaEkleState extends State<HastaEkle> {
  final _tcController = TextEditingController();
  bool _yukleniyor = false;

  @override
  void dispose() {
    _tcController.dispose();
    super.dispose();
  }

  void _hastayaIstekGonder(String tc) async {
    if (tc.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen 11 haneli geçerli bir TC girin.")),
      );
      return;
    }

    setState(() => _yukleniyor = true);

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) throw Exception("Doktor girişi bulunamadı.");

      final veritabani = FirebaseFirestore.instance;

      // 1. tcLookup alanı ile hastayı bul
      final query = await veritabani
          .collection('hastalar')
          .where('tcLookup', isEqualTo: tc)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Hasta sisteme kayıtlı değil. Önce hastasın kayıt olması gerekir.",
              ),
            ),
          );
        }
        return;
      }

      final hastaDoc = query.docs.first;
      final hashedTc = hastaDoc.id; // doc ID zaten hash'li TC

      // 2. Doktorun adını al
      final doktorDoc = await veritabani
          .collection('doktorlar')
          .doc(currentUserId)
          .get();
      final doktorIsmi = doktorDoc.data()?['isim'] ?? 'Bilinmeyen Doktor';

      // 3. Hastaya istek gönder
      await veritabani
          .collection('hastalar')
          .doc(hashedTc)
          .collection('bekleyen_doktorlar')
          .doc(currentUserId)
          .set({
            'doktorId': currentUserId,
            'doktorIsmi': doktorIsmi,
            'istekTarihi': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Hastaya takip isteği başarıyla gönderildi!"),
          ),
        );
        Navigator.pop(context); // Geri dön
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Hata: $e")));
      }
    } finally {
      setState(() => _yukleniyor = false);
    }
  }

  void _scanQrCode() async {
    // QR Tarayıcı sayfası aç
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerPage()),
    );

    if (!mounted) return;

    if (result != null && result.length == 11) {
      _tcController.text = result;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("QR Okundu: $result")));
    } else if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Geçersiz QR Kod. Sadece 11 haneli TC içermeli."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Hasta Ekle'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.person_add_alt_1, size: 80, color: Colors.teal),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tcController,
                    decoration: const InputDecoration(
                      labelText: "Hastanın TC Kimlik Numarası",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 11,
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: 24.0,
                  ), // maxLength text altındaki hizalama için
                  child: IconButton(
                    onPressed: _scanQrCode,
                    icon: const Icon(
                      Icons.qr_code_scanner,
                      size: 36,
                      color: Colors.teal,
                    ),
                    tooltip: "QR Kod ile Oku",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _yukleniyor
                    ? null
                    : () => _hastayaIstekGonder(_tcController.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                ),
                child: _yukleniyor
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "İstek Gönder",
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Basit QR Okuyucu Ekranı
class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final MobileScannerController controller = MobileScannerController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Kod Okut'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: MobileScanner(
        controller: controller,
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final barcode = barcodes.first;
            if (barcode.rawValue != null) {
              final String code = barcode.rawValue!;
              // Kamerayı kapatıp sonucu geri döndür
              controller.stop();
              Navigator.pop(context, code);
            }
          }
        },
      ),
    );
  }
}
