// doktor_home.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'hasta_gecmis.dart';
import 'hasta_ekle.dart';
import 'main.dart';
import 'services/secure_storage_service.dart';

class DoktorHome extends StatefulWidget {
  const DoktorHome({super.key});

  @override
  State<DoktorHome> createState() => _DoktorHomeState();
}

class _DoktorHomeState extends State<DoktorHome> {
  final User? currentUser = FirebaseAuth.instance.currentUser;

  // Çıkış yap metodu (isteğe bağlı)
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

  // ALGORİTMA: Listeyi Acı Puanına göre (Büyükten küçüğe) sıralar

  // HELPER: Puana göre renk veren fonksiyon
  Color _getRiskRengi(int puan) {
    if (puan >= 8) return Colors.red.shade700; // Kritik
    if (puan >= 4) return Colors.orange.shade700; // Orta
    return Colors.green.shade700; // Stabil
  }

  // HELPER: Puana göre metin veren fonksiyon
  String _getRiskDurumu(int puan) {
    if (puan >= 8) return "Hasta Acı hissediyor";
    if (puan >= 4) return "Hastanın orta derecede acısı var";
    return "Stabil";
  }

  Widget _buildDurumChip(String label, Color renk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: renk.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: renk,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hasta Triyaj Listesi'),
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

      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('doktorlar')
            .doc(currentUser?.uid)
            .snapshots(),
        builder: (context, doktorSnapshot) {
          if (doktorSnapshot.hasError) {
            return const Center(child: Text('Bir hata oluştu'));
          }

          if (doktorSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!doktorSnapshot.hasData || !doktorSnapshot.data!.exists) {
            return const Center(child: Text('Doktor profili bulunamadı'));
          }

          final doktorVeri =
              doktorSnapshot.data!.data() as Map<String, dynamic>?;
          final List<dynamic> hastaListesi = doktorVeri?['hastalar'] ?? [];

          if (hastaListesi.isEmpty) {
            return const Center(
              child: Text(
                'Henüz ekli hastanız yok.\nSağ alt köşeden yeni hasta ekleyebilirsiniz.',
                textAlign: TextAlign.center,
              ),
            );
          }

          // Kendi hastalarının anlık verilerini sıralı getir
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('hastalar')
                .where(FieldPath.documentId, whereIn: hastaListesi)
                .snapshots(),
            builder: (context, hastalarSnapshot) {
              if (hastalarSnapshot.hasError) {
                return const Center(
                  child: Text('Hastalar yüklenirken hata oluştu'),
                );
              }
              if (hastalarSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              var docs = hastalarSnapshot.data!.docs;

              // Front-end'de son güncellemeye göre azalan sırala
              docs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;

                final aTime = aData['sonGuncelleme'] as Timestamp?;
                final bTime = bData['sonGuncelleme'] as Timestamp?;

                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
              });

              return ListView(
                children: docs.map((DocumentSnapshot document) {
                  Map<String, dynamic> data =
                      document.data()! as Map<String, dynamic>;

                  final String isim = data['isim'] ?? 'İsimsiz';
                  final int aci = data['aciPuani'] ?? 0;
                  final bool ilacIcildiMi = data['ilacIcildiMi'] ?? false;
                  final bool atesVar = data['atesVar'] ?? false;
                  final bool balgamVar = data['balgamVar'] ?? false;
                  final bool pansumanAkintiVar =
                      data['pansumanAkintiVar'] ?? false;
                  final bool solunumEgzersizi =
                      data['solunumEgzersiziYapildi'] ?? false;
                  final bool diskilama = data['diskilamaYapildi'] ?? false;
                  final bool suIcildi = data['suIcildi'] ?? false;

                  final Color riskRengi = _getRiskRengi(aci);

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => HastaGecmis(
                              hastaId: document.id,
                              hastaIsmi: isim,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: riskRengi,
                              radius: 28,
                              child: Text(
                                aci.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isim,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(_getRiskDurumu(aci)),
                                  const SizedBox(height: 6),
                                  Text(
                                    'İlaç alındı: ${ilacIcildiMi ? "Evet" : "Hayır"}',
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (atesVar)
                                        _buildDurumChip('🌡️ Ateş', Colors.red),
                                      if (balgamVar)
                                        _buildDurumChip(
                                          '💨 Balgam',
                                          Colors.orange,
                                        ),
                                      if (pansumanAkintiVar)
                                        _buildDurumChip(
                                          '🩹 Akıntı',
                                          Colors.red,
                                        ),
                                      if (!solunumEgzersizi)
                                        _buildDurumChip(
                                          '🫁 Egzersiz ❌',
                                          Colors.grey,
                                        ),
                                      if (!diskilama)
                                        _buildDurumChip('🚽 Yok', Colors.grey),
                                      if (!suIcildi)
                                        _buildDurumChip(
                                          '💧 Su ❌',
                                          Colors.orange,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (data['sonGuncelleme'] != null)
                                  Text(
                                    (data['sonGuncelleme'] is Timestamp)
                                        ? (data['sonGuncelleme'] as Timestamp)
                                              .toDate()
                                              .toLocal()
                                              .toString()
                                              .split('.')[0]
                                        : data['sonGuncelleme'].toString(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          );
        },
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const HastaEkle()),
          );
        },
        backgroundColor: Colors.teal,
        icon: const Icon(Icons.person_add),
        label: const Text('Yeni Hasta Ekle'),
      ),
    );
  }
}
