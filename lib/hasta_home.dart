// hasta_home.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hasta_takip_uygulamasi/main.dart';
import 'services/secure_storage_service.dart';

class HastaHome extends StatefulWidget {
  final String hastaId;

  const HastaHome({super.key, required this.hastaId});

  @override
  State<HastaHome> createState() => _HastaHomeState();
}

class _HastaHomeState extends State<HastaHome> {
  // State Değişkenleri
  double _aciPuani = 5.0;
  bool _ilacIcildiMi = false;

  // Yeni sağlık takip alanları
  bool _atesVar = false;
  bool _balgamVar = false;
  String _balgamTuru = 'seffaf'; // 'kanli', 'sari', 'seffaf'
  bool _pansumanAkintiVar = false;
  bool _solunumEgzersiziYapildi = false;
  bool _diskilamaYapildi = false;
  bool _suIcildi = false;

  // Yükleniyor animasyonu için kontrol değişkeni
  bool _yukleniyor = false;

  // --- Ses Kaydı Değişkenleri ---
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderAcik = false;
  bool _kayitYapiliyor = false;
  bool _kayitHazir = false;
  bool _sesYukleniyor = false;
  String? _kaydedilmisYol;
  int _geriSayim = 8; // maks 8 saniye
  Timer? _geriSayimTimer;

  @override
  void initState() {
    super.initState();
    _recorderBaslat();
  }

  Future<void> _recorderBaslat() async {
    await _recorder.openRecorder();
    setState(() => _recorderAcik = true);
  }

  @override
  void dispose() {
    _geriSayimTimer?.cancel();
    _recorder.closeRecorder();
    super.dispose();
  }

  // Çıkış yap metodu
  void _cikisYap() async {
    final SecureStorageService storageService = SecureStorageService();
    await storageService.clearCredentials();
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  // --- SES KAYIT FONKSİYONLARI ---

  Future<void> _kayitBaslat() async {
    final izin = await Permission.microphone.request();
    if (!izin.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mikrofon izni verilmedi.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final yol =
        '${tempDir.path}/oksuruk_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.startRecorder(
      toFile: yol,
      codec: Codec.aacMP4, // .m4a formatı
    );

    setState(() {
      _kayitYapiliyor = true;
      _kayitHazir = false;
      _kaydedilmisYol = yol;
      _geriSayim = 8;
    });

    // Geri sayım başlat, 8 saniyede otomatik durdur
    _geriSayimTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _geriSayim--);
      if (_geriSayim <= 0) {
        timer.cancel();
        await _kayitDurdur();
      }
    });
  }

  Future<void> _kayitDurdur() async {
    _geriSayimTimer?.cancel();
    await _recorder.stopRecorder();
    if (mounted) {
      setState(() {
        _kayitYapiliyor = false;
        _kayitHazir = true;
      });
    }
  }

  Future<void> _sesGonder() async {
    if (_kaydedilmisYol == null) return;
    setState(() => _sesYukleniyor = true);

    try {
      final dosya = File(_kaydedilmisYol!);

      // Dosyanın gerçekten oluşturulduğunu doğrula
      if (!await dosya.exists()) {
        throw Exception('Kayıt dosyası bulunamadı. Lütfen tekrar kayıt yapın.');
      }

      final bytes = await dosya.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Kayıt dosyası boş. Lütfen tekrar kayıt yapın.');
      }

      // Firebase Storage yerine base64 olarak Firestore'a kaydet
      final base64Str = base64Encode(bytes);

      await FirebaseFirestore.instance
          .collection('hastalar')
          .doc(widget.hastaId)
          .set({
            'oksurukBase64': base64Str,
            'oksurukTarihi': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _kayitHazir = false;
          _kaydedilmisYol = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎤 Öksürük kaydı doktora iletildi!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sesYukleniyor = false);
    }
  }

  String _getCurrentDonem() {
    final saat = DateTime.now().hour;
    return saat < 12 ? 'sabah' : 'aksam';
  }

  String _getDonemAdi() {
    return _getCurrentDonem() == 'sabah' ? '🌅 Sabah' : '🌙 Akşam';
  }

  Future<bool> _buDonemdeKayitVarMi() async {
    final now = DateTime.now();
    final donem = _getCurrentDonem();

    DateTime donemBaslangic;
    if (donem == 'sabah') {
      donemBaslangic = DateTime(now.year, now.month, now.day, 0, 0);
    } else {
      donemBaslangic = DateTime(now.year, now.month, now.day, 12, 0);
    }

    final kayitlar = await FirebaseFirestore.instance
        .collection('hastalar')
        .doc(widget.hastaId)
        .collection('gecmis')
        .where('donem', isEqualTo: donem)
        .get();

    final simdi = Timestamp.fromDate(donemBaslangic);
    return kayitlar.docs.any((doc) {
      final data = doc.data();
      if (data['tarih'] != null) {
        final tarih = data['tarih'] as Timestamp;
        return tarih.compareTo(simdi) >= 0;
      }
      return false;
    });
  }

  // Onay diyaloğu göster
  Future<bool> _onayDiyaloguGoster() async {
    final donemAdi = _getDonemAdi();
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ Zaten Veri Gönderildi'),
            content: Text(
              '$donemAdi dönemi için zaten veri gönderdiniz.\n\nYine de güncellemek ister misiniz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Güncelle'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // VERİ KAYDETME FONKSİYONU 🚀
  Future<void> _durumuKaydet() async {
    // Önce bu dönemde kayıt var mı kontrol et
    final kayitVar = await _buDonemdeKayitVarMi();
    if (kayitVar) {
      final devamEt = await _onayDiyaloguGoster();
      if (!devamEt) return; // Kullanıcı vazgeçti
    }

    setState(() {
      _yukleniyor = true; // Yükleniyor simgesini başlat
    });

    try {
      // 1. Veritabanı referansını al
      var veritabani = FirebaseFirestore.instance;

      // 2. 'hastalar' koleksiyonuna ekle (veya güncelle)
      final veriMap = {
        'aciPuani': _aciPuani.round(),
        'ilacIcildiMi': _ilacIcildiMi,
        'atesVar': _atesVar,
        'balgamVar': _balgamVar,
        'balgamTuru': _balgamVar ? _balgamTuru : null,
        'pansumanAkintiVar': _pansumanAkintiVar,
        'solunumEgzersiziYapildi': _solunumEgzersiziYapildi,
        'diskilamaYapildi': _diskilamaYapildi,
        'suIcildi': _suIcildi,
        'sonGuncelleme': FieldValue.serverTimestamp(),
      };

      await veritabani
          .collection('hastalar')
          .doc(widget.hastaId)
          .set(veriMap, SetOptions(merge: true));

      // Geçmiş kayıtlarına da ekle (silinmez, birikir)
      await veritabani
          .collection('hastalar')
          .doc(widget.hastaId)
          .collection('gecmis')
          .add({
            ...veriMap,
            'tarih': FieldValue.serverTimestamp(),
            'donem': _getCurrentDonem(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Durumun Doktora İletildi!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Hata oluştu: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _yukleniyor = false; // Yükleniyor simgesini durdur
      });
    }
  }

  // Tarihleri formatlayan yardımcı fonksiyon
  String _formatTarih(Timestamp? ts) {
    if (ts == null) return "Bilinmiyor";
    final t = ts.toDate().toLocal();
    return "${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}";
  }

  // Doktor isteğini kabul et
  Future<void> _doktorKabulEt(String doktorId) async {
    setState(() => _yukleniyor = true);
    try {
      final veritabani = FirebaseFirestore.instance;
      // Doktora hastayı ekle
      await veritabani.collection('doktorlar').doc(doktorId).update({
        'hastalar': FieldValue.arrayUnion([widget.hastaId]),
      });
      // İsteği sil
      await veritabani
          .collection('hastalar')
          .doc(widget.hastaId)
          .collection('bekleyen_doktorlar')
          .doc(doktorId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Doktor isteği kabul edildi.")),
        );
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

  // Doktor isteğini reddet
  Future<void> _doktorReddet(String doktorId) async {
    setState(() => _yukleniyor = true);
    try {
      final veritabani = FirebaseFirestore.instance;
      // İsteği sil
      await veritabani
          .collection('hastalar')
          .doc(widget.hastaId)
          .collection('bekleyen_doktorlar')
          .doc(doktorId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Doktor isteği reddedildi.")),
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bugünkü Durumun'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _cikisYap,
            tooltip: 'Çıkış Yap',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- BEKLEYEN DOKTOR İSTEKLERİ ---
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('hastalar')
                  .doc(widget.hastaId)
                  .collection('bekleyen_doktorlar')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Bekleyen Doktor İstekleri",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: snapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final doc = snapshot.data!.docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final doktorIsmi =
                            data['doktorIsmi'] ?? 'Bilinmeyen Doktor';
                        final doktorId = doc.id;

                        return Card(
                          color: Colors.orange.shade50,
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.orange.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.medical_services,
                                      color: Colors.orange.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "$doktorIsmi sizi hastası olarak eklemek istiyor.",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => _doktorReddet(doktorId),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text("Reddet"),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () => _doktorKabulEt(doktorId),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text("Kabul Et"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 30),
                  ],
                );
              },
            ),

            // --- HASTANIN AMELİYAT GEÇMİŞİ ---
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('hastalar')
                  .doc(widget.hastaId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();

                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data == null || !data.containsKey('ameliyatlar')) {
                  return const SizedBox.shrink();
                }

                final List<dynamic> ameliyatlar = data['ameliyatlar'] ?? [];
                if (ameliyatlar.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Tedavi Geçmişiniz",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ameliyatlar.length,
                      itemBuilder: (context, index) {
                        final a = ameliyatlar[index] as Map<String, dynamic>;
                        final isTaburcu = a['taburcuTarihi'] != null;

                        return Card(
                          elevation: 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.teal.shade100),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isTaburcu
                                  ? Colors.green.shade100
                                  : Colors.orange.shade100,
                              child: Icon(
                                isTaburcu ? Icons.home : Icons.local_hospital,
                                color: isTaburcu
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                            title: Text(
                              a['turu'] ?? 'Bilinmiyor',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "Ameliyat: ${_formatTarih(a['ameliyatTarihi'] as Timestamp?)}\n"
                              "Durum: ${isTaburcu ? 'Taburcu Edildi (${_formatTarih(a['taburcuTarihi'] as Timestamp?)})' : 'Tedavi Devam Ediyor'}",
                              style: const TextStyle(height: 1.3),
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 30),
                  ],
                );
              },
            ),
            // --- SON AMELİYAT GEÇMİŞİ ---

            // Dönem bilgisi
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: _getCurrentDonem() == 'sabah'
                    ? Colors.amber.shade50
                    : Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _getCurrentDonem() == 'sabah'
                      ? Colors.amber.shade300
                      : Colors.indigo.shade300,
                ),
              ),
              child: Text(
                '${_getDonemAdi()} kaydı giriliyor',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _getCurrentDonem() == 'sabah'
                      ? Colors.amber.shade900
                      : Colors.indigo.shade900,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Şu an ne kadar acı hissediyorsun?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // Slider Alanı
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _aciPuani,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: _aciPuani.round().toString(),
                    activeColor: Colors.teal,
                    onChanged: (double yeniDeger) {
                      setState(() {
                        _aciPuani = yeniDeger;
                      });
                    },
                  ),
                ),
                CircleAvatar(
                  backgroundColor: _aciPuani > 7
                      ? Colors.red
                      : Colors.teal.shade100,
                  child: Text(
                    _aciPuani.round().toString(),
                    style: TextStyle(
                      color: _aciPuani > 7
                          ? Colors.white
                          : Colors.teal.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 40),

            const Text(
              "İlaçlarını Aldın mı?",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            SwitchListTile(
              title: const Text("Evet, ilaçlarımı içtim"),
              subtitle: _ilacIcildiMi
                  ? const Text(
                      "Harika! Geçmiş olsun.",
                      style: TextStyle(color: Colors.green),
                    )
                  : const Text(
                      "Lütfen ilaçlarını aksatma.",
                      style: TextStyle(color: Colors.red),
                    ),
              value: _ilacIcildiMi,
              activeThumbColor: Colors.teal,
              onChanged: (bool deger) {
                setState(() {
                  _ilacIcildiMi = deger;
                });
              },
              secondary: Icon(
                Icons.medication,
                color: _ilacIcildiMi ? Colors.teal : Colors.grey,
                size: 30,
              ),
            ),

            const Divider(height: 40),

            // --- ATEŞ TAKİBİ ---
            const Text(
              "🌡️ Ateş Durumu",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text("Ateşim var"),
              subtitle: _atesVar
                  ? const Text(
                      "Doktorunuzu bilgilendirin.",
                      style: TextStyle(color: Colors.red),
                    )
                  : const Text(
                      "Ateşiniz yok, harika!",
                      style: TextStyle(color: Colors.green),
                    ),
              value: _atesVar,
              activeThumbColor: Colors.red,

              onChanged: (bool deger) {
                setState(() => _atesVar = deger);
              },
              secondary: Icon(
                Icons.thermostat,
                color: _atesVar ? Colors.red : Colors.grey,
                size: 30,
              ),
            ),

            const Divider(height: 40),

            // --- BALGAM TAKİBİ ---
            const Text(
              "💨 Balgam Durumu",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text("Balgamım var"),
              subtitle: _balgamVar
                  ? const Text(
                      "Balgam türünü seçin.",
                      style: TextStyle(color: Colors.orange),
                    )
                  : const Text(
                      "Balgam yok.",
                      style: TextStyle(color: Colors.green),
                    ),
              value: _balgamVar,
              activeThumbColor: Colors.orange,

              onChanged: (bool deger) {
                setState(() => _balgamVar = deger);
              },
              secondary: Icon(
                Icons.air,
                color: _balgamVar ? Colors.orange : Colors.grey,
                size: 30,
              ),
            ),
            if (_balgamVar) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: DropdownButtonFormField<String>(
                  initialValue: _balgamTuru,
                  decoration: const InputDecoration(
                    labelText: "Balgam Türü",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.color_lens),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'seffaf', child: Text('Şeffaf')),
                    DropdownMenuItem(value: 'sari', child: Text('Sarı')),
                    DropdownMenuItem(value: 'kanli', child: Text('Kanlı 🩸')),
                  ],
                  onChanged: (String? yeniDeger) {
                    if (yeniDeger != null) {
                      setState(() => _balgamTuru = yeniDeger);
                    }
                  },
                ),
              ),
            ],

            const Divider(height: 40),

            // --- PANSUMAN DURUMU ---
            const Text(
              "🩹 Pansuman Durumu",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text("Pansumanda akıntı var"),
              subtitle: _pansumanAkintiVar
                  ? const Text(
                      "Akıntı mevcut, doktorunuza bildirin.",
                      style: TextStyle(color: Colors.red),
                    )
                  : const Text(
                      "Akıntı yok, temiz.",
                      style: TextStyle(color: Colors.green),
                    ),
              value: _pansumanAkintiVar,
              activeThumbColor: Colors.red,

              onChanged: (bool deger) {
                setState(() => _pansumanAkintiVar = deger);
              },
              secondary: Icon(
                Icons.healing,
                color: _pansumanAkintiVar ? Colors.red : Colors.grey,
                size: 30,
              ),
            ),

            const Divider(height: 40),

            // --- SOLUNUM EGZERSİZİ ---
            const Text(
              "🫁 Solunum Egzersizi",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text("Solunum egzersizimi yaptım"),
              subtitle: _solunumEgzersiziYapildi
                  ? const Text(
                      "Harikasın! Düzenli devam et.",
                      style: TextStyle(color: Colors.green),
                    )
                  : const Text(
                      "Solunum egzersizini yapmayı unutma!",
                      style: TextStyle(color: Colors.orange),
                    ),
              value: _solunumEgzersiziYapildi,
              activeThumbColor: Colors.teal,
              onChanged: (bool deger) {
                setState(() => _solunumEgzersiziYapildi = deger);
              },
              secondary: Icon(
                Icons.self_improvement,
                color: _solunumEgzersiziYapildi ? Colors.teal : Colors.grey,
                size: 30,
              ),
            ),

            const Divider(height: 40),

            // --- DIŞKILAMA KONTROLÜ ---
            const Text(
              "🚽 Dışkılama Kontrolü",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text("Bugün dışkılama yaptım"),
              subtitle: _diskilamaYapildi
                  ? const Text(
                      "Kaydedildi.",
                      style: TextStyle(color: Colors.green),
                    )
                  : const Text(
                      "Henüz yapılmadı.",
                      style: TextStyle(color: Colors.grey),
                    ),
              value: _diskilamaYapildi,
              activeThumbColor: Colors.teal,
              onChanged: (bool deger) {
                setState(() => _diskilamaYapildi = deger);
              },
              secondary: Icon(
                Icons.check_circle_outline,
                color: _diskilamaYapildi ? Colors.teal : Colors.grey,
                size: 30,
              ),
            ),

            const Divider(height: 40),

            // --- SU HATIRLATICI ---
            const Text(
              "💧 Su İçme Hatırlatıcı",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text("Yeterli su içtim"),
              subtitle: _suIcildi
                  ? const Text(
                      "Aferin! Su içmeye devam et.",
                      style: TextStyle(color: Colors.blue),
                    )
                  : const Text(
                      "Günlük su ihtiyacını karşıla!",
                      style: TextStyle(color: Colors.orange),
                    ),
              value: _suIcildi,
              activeThumbColor: Colors.blue,

              onChanged: (bool deger) {
                setState(() => _suIcildi = deger);
              },
              secondary: Icon(
                Icons.water_drop,
                color: _suIcildi ? Colors.blue : Colors.grey,
                size: 30,
              ),
            ),

            const SizedBox(height: 20),

            // Kaydet Butonu
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _yukleniyor ? null : _durumuKaydet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: _yukleniyor
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'DURUMU GÖNDER',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),

            const Divider(height: 40),

            // --- ÖKSÜRÜK KAYDI BÖLÜMÜ ---
            const Text(
              '🎤 Öksürük Kaydı Gönder',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Doktorunuza öksürük sesinizi gönderin. Maksimum 8 saniye.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Geri sayım göstergesi (sadece kayıt sırasında)
            if (_kayitYapiliyor)
              Center(
                child: Column(
                  children: [
                    Text(
                      '$_geriSayim',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                    const Text(
                      'saniye kaldı',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _kayitDurdur,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.stop),
                      label: const Text('Durdur'),
                    ),
                  ],
                ),
              )
            else if (_kayitHazir)
              // Kayıt hazır → Gönder veya Yeniden kaydet
              Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'Kayıt hazır!',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _sesYukleniyor ? null : _kayitBaslat,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Yeniden Kaydet'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.teal,
                            side: const BorderSide(color: Colors.teal),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _sesYukleniyor ? null : _sesGonder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                          icon: _sesYukleniyor
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                          label: Text(
                            _sesYukleniyor ? 'Gönderiliyor...' : 'Gönder',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              // Başlat butonu
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _recorderAcik ? _kayitBaslat : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.mic),
                  label: const Text(
                    'Kayıt Başlat',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
