import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_profile.dart';
import '../../providers/app_state_provider.dart';
import '../../widgets/liquid_glass_card.dart';
import '../onboarding_screen.dart';
import '../../widgets/profile_avatar.dart';
import '../../services/legal_terms_service.dart';
import '../../services/firebase_config_service.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final myProfile = appState.myProfile;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title & Top-Right QR Button for all devices
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ayarlar & Profil',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Cihaz modunuzu ve profilinizi yönetin',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
              if (myProfile != null)
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E676)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.qr_code_2_rounded,
                        color: Color(0xFF00E676), size: 26),
                    tooltip: 'Sabit QR Kodumu Göster',
                    onPressed: () => _showMyQRModal(context, myProfile),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // User Profile Card with Edit Photo / Icon Button
          LiquidGlassCard(
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _showPhotoOrIconPicker(context, appState),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      ProfileAvatar(
                        profile: myProfile,
                        radius: 30,
                        borderWidth: 2,
                      ),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF00E676),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.black,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              myProfile?.deviceName ?? 'Ev Tableti',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded,
                                color: Colors.white70, size: 18),
                            onPressed: () =>
                                _showPairingInfoUpdateDialog(context, appState),
                          ),
                        ],
                      ),
                      Text(
                        'Cihaz Kodu: ${myProfile?.pairCode ?? ""}',
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Pairing Method Updates Card
          LiquidGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cihaz & İletişim Yapılandırması',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.phonelink_setup_rounded,
                        color: Colors.white, size: 20),
                  ),
                  title: const Text(
                    '🔑 Telefon / E-Posta / Kodu Güncelle',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Tel: ${myProfile?.phoneNumber ?? "Tanımsız"} • E-Posta: ${myProfile?.email ?? "Tanımsız"}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white70),
                  onTap: () => _showPairingInfoUpdateDialog(context, appState),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Privacy & Photo Sharing Section
          LiquidGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gizlilik & Fotoğraf Paylaşımı',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (myProfile?.sharePhoto ?? true)
                          ? const Color(0xFF00E676)
                          : Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      (myProfile?.sharePhoto ?? true)
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      color: (myProfile?.sharePhoto ?? true)
                          ? Colors.black
                          : Colors.white70,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Profil Fotoğrafımı Paylaş',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    (myProfile?.sharePhoto ?? true)
                        ? 'Eşleşen cihazlar fotoğrafınızı görebilir'
                        : 'Fotoğrafınız karşı taraftan gizli',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  trailing: Switch(
                    value: myProfile?.sharePhoto ?? true,
                    activeTrackColor: const Color(0xFF00E676).withValues(alpha: 0.5),
                    activeThumbColor: const Color(0xFF00E676),
                    onChanged: (val) async {
                      await appState.toggleSharePhoto(val);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Data Retention & Auto-Cleanup Section
          LiquidGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Veri Saklama & Otomatik Temizlik',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Arama Kayıtları',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('2 Ay (60 Gün)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Color(0xFF00E676), fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '60 günden eski arama kayıtları otomatik silinir',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const Divider(color: Colors.white24, height: 20),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Sohbet & Mesaj Geçmişi',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('3 Ay (90 Gün)',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Color(0xFF00E676), fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  '90 günden eski sohbet mesajları otomatik temizlenir',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // App Information & Real Diagnostics Section
          LiquidGlassCard(
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Güvenlik Protokolü',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text('Uçtan Uca P2P WebRTC',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                  ],
                ),
                const Divider(color: Colors.white24, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Eşleşme Kodu / PIN',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      myProfile?.pairCode ?? '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Bağlı Cihaz Sayısı',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${appState.pairedDevicesList.length} Aktif Cihaz',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Color(0xFF00E676), fontSize: 13),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Canlı Sunucu Bağlantısı',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Firebase Realtime DB',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.gavel_rounded,
                        color: Color(0xFF00E676), size: 20),
                  ),
                  title: const Text(
                    'Yasal Sözleşmeler & KVKK',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'EULA, TCK 132-134 sorumluluk reddi ve gizlilik politikası',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white70),
                  onTap: () => _showLegalTermsDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Aile Ağı & BYODB Veritabanı Yönetim Kartı
          LiquidGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hub_rounded, color: Color(0xFF00E676), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Aile Ağı & Firebase Veritabanı (BYODB)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Bu cihaz bağımsız ailenizin özel Firebase veritabanına bağlıdır. Yeni cihazlarınızı tek saniyede bu ağa dahil edebilirsiniz:',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 14),

                // Network Role Badge & Active RTDB URL box
                FutureBuilder<Map<String, dynamic>>(
                  future: () async {
                    final activeUrl = await FirebaseConfigService.getActiveRtdbUrl();
                    final isAdmin = await FirebaseConfigService.isNetworkAdmin();
                    final adminOnly = await FirebaseConfigService.isAdminOnlySharing();
                    return {
                      'activeUrl': activeUrl,
                      'isAdmin': isAdmin,
                      'adminOnly': adminOnly,
                    };
                  }(),
                  builder: (ctx, snapshot) {
                    final data = snapshot.data;
                    final activeUrl = data?['activeUrl'] ?? 'Yükleniyor...';
                    final isAdmin = data?['isAdmin'] ?? false;
                    final adminOnly = data?['adminOnly'] ?? true;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Role Badge
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isAdmin
                                    ? Colors.amber.withValues(alpha: 0.2)
                                    : const Color(0xFF00E676).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isAdmin ? Colors.amber : const Color(0xFF00E676),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                                    color: isAdmin ? Colors.amber : const Color(0xFF00E676),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isAdmin ? '👑 Ağ Yöneticisi (Kurucu Cihaz)' : '👤 Aile Ağı Üyesi',
                                    style: TextStyle(
                                      color: isAdmin ? Colors.amber : const Color(0xFF00E676),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Active RTDB URL Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cloud_done_rounded, color: Color(0xFF00E676), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Aktif Veritabanı URL:',
                                      style: TextStyle(color: Colors.white54, fontSize: 10),
                                    ),
                                    Text(
                                      activeUrl,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Admin Toggle for Network Policy
                        if (isAdmin) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_person_rounded, color: Colors.amber, size: 18),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Yalnızca Yönetici Cihaz Davet Edebilir',
                                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Kapalıyken diğer aile üyeleri de QR gösterebilir.',
                                        style: TextStyle(color: Colors.white54, fontSize: 9.5),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: adminOnly,
                                  activeThumbColor: const Color(0xFF00E676),
                                  onChanged: (val) async {
                                    await FirebaseConfigService.setAdminOnlySharing(val);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // Actions: Show Network QR (or Locked indicator) & Sync Rules
                        if (!isAdmin && adminOnly) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.lock_rounded, color: Colors.amber, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Aile Ağı Paylaşımı Kilitli: Yalnızca kurucu yönetici cihaz yeni üye ekleyebilir.',
                                    style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.shield_rounded, size: 18, color: Color(0xFF00E676)),
                              label: const Text(
                                'GÜVENLİK KURALLARI & RULES',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              onPressed: () => _syncFirebaseRulesDialog(context),
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00E676),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                                  label: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'AĞ QR KODU',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  onPressed: () => _showFamilyNetworkQrModal(context),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white38),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  icon: const Icon(Icons.shield_rounded, size: 18, color: Color(0xFF00E676)),
                                  label: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'RULES YÜKLE',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                  onPressed: () => _syncFirebaseRulesDialog(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // High-Contrast Centered Reset Button
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showResetConfirmation(context, appState),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restart_alt_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Kurulumu Sıfırla ve Yeniden Başlat',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }



  void _showPairingInfoUpdateDialog(
      BuildContext context, AppStateProvider appState) {
    final currentProfile = appState.myProfile;
    final nameCtrl = TextEditingController(text: currentProfile?.deviceName ?? '');
    final phoneCtrl = TextEditingController(text: currentProfile?.phoneNumber ?? '');
    final emailCtrl = TextEditingController(text: currentProfile?.email ?? '');
    final pinCtrl = TextEditingController(text: currentProfile?.pairCode ?? '');

    // Determine current selected method
    PairingMethod selectedMethod = PairingMethod.pinCode;
    if (currentProfile != null) {
      if (currentProfile.phoneNumber != null &&
          currentProfile.phoneNumber!.isNotEmpty &&
          currentProfile.pairCode == currentProfile.phoneNumber) {
        selectedMethod = PairingMethod.phoneNumber;
      } else if (currentProfile.email != null &&
          currentProfile.email!.isNotEmpty &&
          currentProfile.pairCode == currentProfile.email) {
        selectedMethod = PairingMethod.email;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF384353),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            '🔑 İletişim Bilgilerini Güncelle',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    labelText: 'Cihaz Adı',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.edit_rounded, color: Color(0xFF00E676)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF00E676), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Eşleştirme Yöntemini Seçin:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Method Selector Segmented Buttons
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => selectedMethod = PairingMethod.pinCode),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedMethod == PairingMethod.pinCode
                                ? const Color(0xFF00E676)
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.pin_rounded,
                                color: selectedMethod == PairingMethod.pinCode ? Colors.black : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sabit PIN',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedMethod == PairingMethod.pinCode ? Colors.black : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => selectedMethod = PairingMethod.phoneNumber),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedMethod == PairingMethod.phoneNumber
                                ? const Color(0xFF00E676)
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.phone_rounded,
                                color: selectedMethod == PairingMethod.phoneNumber ? Colors.black : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Telefon',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedMethod == PairingMethod.phoneNumber ? Colors.black : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(() => selectedMethod = PairingMethod.email),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedMethod == PairingMethod.email
                                ? const Color(0xFF00E676)
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.email_rounded,
                                color: selectedMethod == PairingMethod.email ? Colors.black : Colors.white,
                                size: 20,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'E-Posta',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: selectedMethod == PairingMethod.email ? Colors.black : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Method Specific Field
                if (selectedMethod == PairingMethod.pinCode)
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      labelText: 'Sabit Eşleştirme PIN Kodu',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.pin_rounded, color: Color(0xFF00E676)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF00E676), width: 2),
                      ),
                    ),
                  ),

                if (selectedMethod == PairingMethod.phoneNumber)
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      labelText: 'Telefon Numarası (Eşleşme Kodu)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: 'Örn: 05317011121',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.phone_rounded, color: Color(0xFF00E676)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF00E676), width: 2),
                      ),
                    ),
                  ),

                if (selectedMethod == PairingMethod.email)
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.08),
                      labelText: 'E-Posta Adresi (Eşleşme Kodu)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: 'Örn: ahmet@gmail.com',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.email_rounded, color: Color(0xFF00E676)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF00E676), width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final newName = nameCtrl.text.trim();
                final phoneVal = phoneCtrl.text.trim();
                final emailVal = emailCtrl.text.trim();
                final pinVal = pinCtrl.text.trim();

                String finalPairCode = pinVal;
                if (selectedMethod == PairingMethod.phoneNumber) {
                  if (phoneVal.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ Lütfen geçerli bir telefon numarası giriniz.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  finalPairCode = phoneVal;
                } else if (selectedMethod == PairingMethod.email) {
                  if (emailVal.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('⚠️ Lütfen geçerli bir e-posta adresi giriniz.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  finalPairCode = emailVal;
                }

                Navigator.pop(ctx);
                await appState.updateMyProfileAndRole(
                  newName: newName,
                  newPhone: phoneVal,
                  newEmail: emailVal,
                  newPin: finalPairCode,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '✅ Eşleştirme bilgileri güncellendi! Mevcut tüm cihaz bağlantıları korundu.',
                      ),
                      backgroundColor: Color(0xFF00E676),
                    ),
                  );
                }
              },
              child: const Text(
                'GÜNCELLE VE KAYDET',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetConfirmation(BuildContext context, AppStateProvider appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B).withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1.2,
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.restart_alt_rounded, color: Colors.redAccent, size: 22),
            ),
            const SizedBox(width: 12),
            const Text(
              'Kurulumu Sıfırla',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Cihaz profilini sıfırlayıp yeniden kurulum sihirbazına dönmek istediğinize emin misiniz?',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 4,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await appState.unpairAndReset();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
              }
            },
            child: const Text('Evet, Sıfırla', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showMyQRModal(BuildContext context, UserProfile myProfile) {
    final payload = {
      'deviceName': myProfile.deviceName,
      'pairCode': myProfile.pairCode,
      'role': myProfile.role.name,
      'avatar': myProfile.avatarIcon,
      'phoneNumber': myProfile.phoneNumber,
      'email': myProfile.email,
    };
    final String qrData = jsonEncode(payload);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF384353),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_2_rounded, color: Color(0xFF00E676), size: 28),
                SizedBox(width: 8),
                Text(
                  'Sabit Cihaz QR Kodunuz',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Diğer cihaz bu QR kodu kamerasından okutarak eşleşme isteği gönderebilir:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${myProfile.deviceName} • Kod: ${myProfile.pairCode}${myProfile.phoneNumber != null && myProfile.phoneNumber!.isNotEmpty ? " • Tel: ${myProfile.phoneNumber}" : ""}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('KAPAT',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoOrIconPicker(BuildContext context, AppStateProvider appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF384353),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📷 Profil Fotoğrafı İşlemleri',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: Color(0xFF00E676)),
              title: const Text('Galeriden Yeni Fotoğraf Seç',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onTap: () async {
                Navigator.pop(ctx);
                final ImagePicker picker = ImagePicker();
                final XFile? image =
                    await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
                if (image != null) {
                  try {
                    final bytes = await image.readAsBytes();
                    await appState.uploadMyProfilePhoto(image.path, bytes: bytes);
                  } catch (e) {
                    debugPrint('⚠️ [PHOTO READ ERROR]: $e');
                    await appState.uploadMyProfilePhoto(image.path);
                  }
                }
              },
            ),
            if ((appState.myProfile?.avatarIcon != null &&
                    appState.myProfile!.avatarIcon.isNotEmpty) ||
                (appState.myProfile?.photoBase64 != null &&
                    appState.myProfile!.photoBase64!.isNotEmpty)) ...[
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent),
                title: const Text('Mevcut Fotoğrafı Kaldır',
                    style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await appState.removeMyProfilePhoto();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLegalTermsDialog(BuildContext context) {
    LegalTermsService.showLegalTermsModal(context);
  }

  Future<void> _showFamilyNetworkQrModal(BuildContext context) async {
    final activeUrl = await FirebaseConfigService.getActiveRtdbUrl();
    final qrPayload = FirebaseConfigService.generateNetworkQrPayload(activeUrl);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF384353),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '📲 Aile Ağı Kurulum QR Kodu',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Evdeki diğer cihazlar (ör: bebek tableti veya eşinizin telefonu) kurulumun ilk adımında "QR ile Katıl" diyerek bu kodu okuttuğunda 1 saniyede bu veritabanına bağlanır.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 190.0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              activeUrl,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('KAPAT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncFirebaseRulesDialog(BuildContext context) async {
    final activeUrl = await FirebaseConfigService.getActiveRtdbUrl();
    bool isSyncing = false;
    String? statusMsg;
    bool? isSuccess;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          ),
          title: const Row(
            children: [
              Icon(Icons.shield_rounded, color: Color(0xFF00E676), size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Firebase Güvenlik Kuralları',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Omega uygulamasının hızlı ve güvenli çalışması için gereken 9 düğüm indeksi ve güvenlik kuralları veritabanınıza otomatik yüklenecektir.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (statusMsg != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSuccess == true
                        ? const Color(0xFF00E676).withValues(alpha: 0.18)
                        : Colors.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSuccess == true
                          ? const Color(0xFF00E676)
                          : Colors.orange,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSuccess == true
                            ? Icons.check_circle_rounded
                            : Icons.info_outline_rounded,
                        color: isSuccess == true
                            ? const Color(0xFF00E676)
                            : Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusMsg!,
                          style: TextStyle(
                            color: isSuccess == true
                                ? const Color(0xFF00E676)
                                : Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
              label: const Text('Kuralları Kopyala', style: TextStyle(color: Colors.white70)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: FirebaseConfigService.formattedRulesJson));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('📋 Kurallar panoya kopyalandı!'),
                    backgroundColor: Color(0xFF00E676),
                  ),
                );
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSyncing
                  ? null
                  : () async {
                      setDialogState(() {
                        isSyncing = true;
                        statusMsg = 'Kurallar yükleniyor...';
                      });
                      final res = await FirebaseConfigService.deployRules(activeUrl);
                      setDialogState(() {
                        isSyncing = false;
                        isSuccess = res['success'] == true;
                        statusMsg = res['message'];
                      });
                    },
              child: isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.black)),
                    )
                  : const Text('OTOMATİK YÜKLE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
