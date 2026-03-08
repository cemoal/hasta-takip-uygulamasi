// hasta_gecmis.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

class HastaGecmis extends StatefulWidget {
  final String hastaId;
  final String hastaIsmi;

  const HastaGecmis({
    super.key,
    required this.hastaId,
    required this.hastaIsmi,
  });

  @override
  State<HastaGecmis> createState() => _HastaGecmisState();
}

class _HastaGecmisState extends State<HastaGecmis> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _oynatiliyor = false;
  bool _audioYukleniyor = false;

  @override
  void initState() {
    super.initState();
    _playerBaslat();
  }

  Future<void> _playerBaslat() async {
    await _player.openPlayer();
  }

  @override
  void dispose() {
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _sesOynat(String base64Str) async {
    if (_oynatiliyor) {
      await _player.stopPlayer();
      setState(() => _oynatiliyor = false);
      return;
    }
    setState(() => _audioYukleniyor = true);
    try {
      final bytes = base64Decode(base64Str);
      print('[SES] Decode edildi: ${bytes.length} byte');

      if (bytes.isEmpty) {
        throw Exception('Ses verisi boş!');
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/oksuruk_temp.m4a');
      await tempFile.writeAsBytes(bytes);
      print('[SES] Dosyaya yazıldı: ${tempFile.path}');

      await _player.startPlayer(
        fromURI: tempFile.path,
        codec: Codec.aacMP4,
        whenFinished: () {
          print('[SES] Oynatma bitti');
          if (mounted) setState(() => _oynatiliyor = false);
        },
      );
      print('[SES] startPlayer çağrıldı');
      setState(() => _oynatiliyor = true);
    } catch (e) {
      print('[SES HATA] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ses oynatılamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _audioYukleniyor = false);
    }
  }

  // HELPER: Puana göre renk
  Color _getRiskRengi(int puan) {
    if (puan >= 8) return Colors.red.shade700;
    if (puan >= 4) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  // HELPER: Puana göre emoji
  String _getAciEmoji(int puan) {
    if (puan >= 8) return '😣';
    if (puan >= 4) return '😐';
    return '😊';
  }

  // Tarih formatlayıcı
  String _formatTarih(Timestamp? ts) {
    if (ts == null) return "Bilinmiyor";
    final t = ts.toDate().toLocal();
    return "${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}";
  }

  // Sağlık durumu ikonu oluşturucu
  Widget _buildDurumIcon(
    IconData icon,
    String label,
    bool aktif,
    Color renk, {
    bool invertMeaning = false,
  }) {
    // invertMeaning: true → aktif=true iyi demek (yeşil), aktif=false kötü demek
    // invertMeaning: false → aktif=true kötü demek (renk), aktif=false iyi demek (yeşil)
    final bool kotu = invertMeaning ? !aktif : aktif;
    final Color gostergeRenk = kotu ? renk : Colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: gostergeRenk.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: gostergeRenk.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: gostergeRenk),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: gostergeRenk,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            kotu ? Icons.warning_rounded : Icons.check_circle,
            size: 12,
            color: gostergeRenk,
          ),
        ],
      ),
    );
  }

  // Yeni ameliyat ekleme diyalogu
  Future<void> _yeniAmeliyatEkle(BuildContext context) async {
    final turuController = TextEditingController();
    DateTime? secilenAmeliyatTarihi;
    DateTime? secilenTaburcuTarihi;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Yeni Ameliyat Ekle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: turuController,
                      decoration: const InputDecoration(
                        labelText: 'Ameliyat Türü',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      title: const Text("Ameliyat Tarihi"),
                      subtitle: Text(
                        secilenAmeliyatTarihi != null
                            ? "${secilenAmeliyatTarihi!.day}/${secilenAmeliyatTarihi!.month}/${secilenAmeliyatTarihi!.year}"
                            : "Seçiniz",
                      ),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          setState(() => secilenAmeliyatTarihi = date);
                        }
                      },
                    ),
                    ListTile(
                      title: const Text("Taburcu Tarihi (Opsiyonel)"),
                      subtitle: Text(
                        secilenTaburcuTarihi != null
                            ? "${secilenTaburcuTarihi!.day}/${secilenTaburcuTarihi!.month}/${secilenTaburcuTarihi!.year}"
                            : "Seçiniz",
                      ),
                      trailing: const Icon(Icons.exit_to_app),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          setState(() => secilenTaburcuTarihi = date);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (turuController.text.trim().isEmpty ||
                        secilenAmeliyatTarihi == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Tür ve Ameliyat Tarihi zorunludur."),
                        ),
                      );
                      return;
                    }

                    final yeniAmeliyat = {
                      'turu': turuController.text.trim(),
                      'ameliyatTarihi': Timestamp.fromDate(
                        secilenAmeliyatTarihi!,
                      ),
                      'taburcuTarihi': secilenTaburcuTarihi != null
                          ? Timestamp.fromDate(secilenTaburcuTarihi!)
                          : null,
                      'eklenmeTarihi': FieldValue.serverTimestamp(),
                    };

                    await FirebaseFirestore.instance
                        .collection('hastalar')
                        .doc(widget.hastaId)
                        .update({
                          'ameliyatlar': FieldValue.arrayUnion([yeniAmeliyat]),
                        });

                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Taburcu tarihi ekleme diyalogu
  Future<void> _taburcuTarihiEkle(
    BuildContext context,
    Map<String, dynamic> ameliyat,
    List<dynamic> tumAmeliyatlar,
  ) async {
    DateTime? secilenTaburcuTarihi;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('${ameliyat['turu']} - Taburcu Et'),
              content: ListTile(
                title: const Text("Taburcu Tarihi Seç"),
                subtitle: Text(
                  secilenTaburcuTarihi != null
                      ? "${secilenTaburcuTarihi!.day}/${secilenTaburcuTarihi!.month}/${secilenTaburcuTarihi!.year}"
                      : "Tarih Seçiniz",
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setState(() => secilenTaburcuTarihi = date);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (secilenTaburcuTarihi == null) return;

                    // Eski ameliyatı listeden çıkarıp yenisini (güncellenmişini) ekleyeceğiz
                    final guncelAmeliyat = Map<String, dynamic>.from(ameliyat);
                    guncelAmeliyat['taburcuTarihi'] = Timestamp.fromDate(
                      secilenTaburcuTarihi!,
                    );

                    final yenilist = List<dynamic>.from(tumAmeliyatlar);
                    final index = yenilist.indexWhere(
                      (a) =>
                          a['turu'] == ameliyat['turu'] &&
                          a['ameliyatTarihi'] == ameliyat['ameliyatTarihi'],
                    );

                    if (index != -1) {
                      yenilist[index] = guncelAmeliyat;
                      await FirebaseFirestore.instance
                          .collection('hastalar')
                          .doc(widget.hastaId)
                          .update({'ameliyatlar': yenilist});
                    }

                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.hastaIsmi} - Detaylar'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ÜST KISIM: AMELİYATLAR
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.teal.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Tedavi / Ameliyat Bilgileri",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade900,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _yeniAmeliyatEkle(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text("Ekle"),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.teal.shade800,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(50, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('hastalar')
                      .doc(widget.hastaId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    final List<dynamic> ameliyatlar =
                        data != null && data.containsKey('ameliyatlar')
                        ? data['ameliyatlar'] as List<dynamic>
                        : [];

                    if (ameliyatlar.isEmpty) {
                      return const Text(
                        "Hastaya ait ameliyat kaydı bulunmamaktadır.",
                        style: TextStyle(fontStyle: FontStyle.italic),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ameliyatlar.length,
                      itemBuilder: (context, index) {
                        final a = ameliyatlar[index] as Map<String, dynamic>;
                        final isTaburcu = a['taburcuTarihi'] != null;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: 1,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: Icon(
                              Icons.local_hospital,
                              color: isTaburcu ? Colors.green : Colors.orange,
                            ),
                            title: Text(
                              a['turu'] ?? 'Bilinmiyor',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "Ameliyat: ${_formatTarih(a['ameliyatTarihi'] as Timestamp?)}\n"
                              "Taburcu: ${isTaburcu ? _formatTarih(a['taburcuTarihi'] as Timestamp?) : 'Devam Ediyor'}",
                              style: const TextStyle(height: 1.3),
                            ),
                            trailing: !isTaburcu
                                ? OutlinedButton(
                                    onPressed: () => _taburcuTarihiEkle(
                                      context,
                                      a,
                                      ameliyatlar,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.teal,
                                      side: const BorderSide(
                                        color: Colors.teal,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      minimumSize: const Size(60, 30),
                                    ),
                                    child: const Text(
                                      "Taburcu Et",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 2),

          // --- ÖKSÜRÜK KAYDI ---
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('hastalar')
                .doc(widget.hastaId)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              final oksurukBase64 = data?['oksurukBase64'] as String?;
              final oksurukTarihi = data?['oksurukTarihi'] as Timestamp?;

              return Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🎤 Öksürük Kaydı',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (oksurukBase64 != null) ...[
                      if (oksurukTarihi != null)
                        Text(
                          'Tarih: ${_formatTarih(oksurukTarihi)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _audioYukleniyor
                              ? null
                              : () => _sesOynat(oksurukBase64),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _oynatiliyor
                                ? Colors.red.shade600
                                : Colors.blue.shade700,
                            foregroundColor: Colors.white,
                          ),
                          icon: _audioYukleniyor
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _oynatiliyor ? Icons.stop : Icons.play_arrow,
                                ),
                          label: Text(
                            _audioYukleniyor
                                ? 'Yükleniyor...'
                                : (_oynatiliyor ? 'Durdur' : 'Kaydı Dinle'),
                          ),
                        ),
                      ),
                    ] else
                      const Text(
                        'Henüz öksürük kaydı gönderilmedi.',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          const Divider(height: 1, thickness: 2),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Acı Puanı ve İlaç Geçmişi",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('hastalar')
                  .doc(widget.hastaId)
                  .collection('gecmis')
                  .orderBy('tarih', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Bir hata oluştu'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.data == null || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'Henüz geçmiş kayıt yok',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final data =
                        snapshot.data!.docs[index].data()!
                            as Map<String, dynamic>;

                    final int aci = data['aciPuani'] ?? 0;
                    final bool ilacIcildiMi = data['ilacIcildiMi'] ?? false;
                    final bool atesVar = data['atesVar'] ?? false;
                    final bool balgamVar = data['balgamVar'] ?? false;
                    final String balgamTuru = data['balgamTuru'] ?? '';
                    final bool pansumanAkintiVar =
                        data['pansumanAkintiVar'] ?? false;
                    final bool solunumEgzersizi =
                        data['solunumEgzersiziYapildi'] ?? false;
                    final bool diskilama = data['diskilamaYapildi'] ?? false;
                    final bool suIcildi = data['suIcildi'] ?? false;
                    final String donem = data['donem'] ?? '';
                    final Color riskRengi = _getRiskRengi(aci);

                    String tarihStr = '—';
                    if (data['tarih'] != null && data['tarih'] is Timestamp) {
                      final tarih = (data['tarih'] as Timestamp)
                          .toDate()
                          .toLocal();
                      tarihStr =
                          '${tarih.day.toString().padLeft(2, '0')}/'
                          '${tarih.month.toString().padLeft(2, '0')}/'
                          '${tarih.year}  '
                          '${tarih.hour.toString().padLeft(2, '0')}:'
                          '${tarih.minute.toString().padLeft(2, '0')}';
                    }

                    // Balgam türü Türkçe label
                    String balgamLabel = '';
                    if (balgamVar) {
                      switch (balgamTuru) {
                        case 'kanli':
                          balgamLabel = 'Kanlı 🩸';
                          break;
                        case 'sari':
                          balgamLabel = 'Sarı';
                          break;
                        case 'seffaf':
                          balgamLabel = 'Şeffaf';
                          break;
                        default:
                          balgamLabel = balgamTuru;
                      }
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: riskRengi.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Üst satır: Acı puanı + tarih
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: riskRengi,
                                  radius: 24,
                                  child: Text(
                                    aci.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_getAciEmoji(aci)}  Acı Puanı: $aci / 10',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: riskRengi,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            ilacIcildiMi
                                                ? Icons.check_circle
                                                : Icons.cancel,
                                            size: 18,
                                            color: ilacIcildiMi
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            ilacIcildiMi
                                                ? 'İlaç alındı'
                                                : 'İlaç alınmadı',
                                            style: TextStyle(
                                              color: ilacIcildiMi
                                                  ? Colors.green.shade700
                                                  : Colors.red.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (donem.isNotEmpty)
                                      Text(
                                        donem == 'sabah'
                                            ? '🌅 Sabah'
                                            : '🌙 Akşam',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: donem == 'sabah'
                                              ? Colors.amber.shade800
                                              : Colors.indigo.shade800,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    const Icon(
                                      Icons.access_time,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      tarihStr,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const Divider(height: 20),

                            // Alt satır: 6 yeni sağlık göstergesi
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _buildDurumIcon(
                                  Icons.thermostat,
                                  'Ateş',
                                  atesVar,
                                  Colors.red,
                                ),
                                _buildDurumIcon(
                                  Icons.air,
                                  balgamVar
                                      ? 'Balgam ($balgamLabel)'
                                      : 'Balgam',
                                  balgamVar,
                                  Colors.orange,
                                ),
                                _buildDurumIcon(
                                  Icons.healing,
                                  'Akıntı',
                                  pansumanAkintiVar,
                                  Colors.red,
                                ),
                                _buildDurumIcon(
                                  Icons.self_improvement,
                                  'Solunum Egz.',
                                  solunumEgzersizi,
                                  Colors.teal,
                                  invertMeaning: true,
                                ),
                                _buildDurumIcon(
                                  Icons.check_circle_outline,
                                  'Dışkılama',
                                  diskilama,
                                  Colors.teal,
                                  invertMeaning: true,
                                ),
                                _buildDurumIcon(
                                  Icons.water_drop,
                                  'Su',
                                  suIcildi,
                                  Colors.blue,
                                  invertMeaning: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
