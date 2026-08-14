import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_profile.dart';
import '../../models/call_session.dart';
import '../../providers/app_state_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/liquid_glass_card.dart';
import '../chat_screen.dart';
import '../camera_station_screen.dart';
import '../live_camera_viewer_screen.dart';
import '../recordings_gallery_screen.dart';
import '../../widgets/profile_avatar.dart';

class ContactsTab extends StatelessWidget {
  final ScrollController scrollController;
  final double scrollProgress;
  final VoidCallback onShowAddDeviceModal;

  const ContactsTab({
    super.key,
    required this.scrollController,
    required this.scrollProgress,
    required this.onShowAddDeviceModal,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final myProfile = appState.myProfile;

    final Map<String, UserProfile> uniqueFamily = {};
    for (final d in appState.pairedDevicesList) {
      if (d.id != myProfile?.id &&
          d.id.isNotEmpty &&
          !d.deviceName.contains('Ev Tableti (Ömer)')) {
        final key = d.pairCode.isNotEmpty
            ? d.pairCode
            : (d.phoneNumber?.isNotEmpty == true
                ? d.phoneNumber!
                : (d.email?.isNotEmpty == true
                    ? d.email!
                    : d.id.split('_').last));
        if (!uniqueFamily.containsKey(key)) {
          uniqueFamily[key] = d;
        }
      }
    }
    final familyDevices = uniqueFamily.values.toList();

    return Stack(
      children: [
        SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 100),
          child: Column(
            children: [
              // --- Top Bar with Security Camera & Instagram-Style Heart Request Icon ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'OMEGA',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // SECURITY CAMERA MODE BUTTON (Next to Heart Icon)
                      IconButton(
                        icon: Icon(
                          Icons.videocam_rounded,
                          color: appState.activeFamilyCameras.isNotEmpty
                              ? const Color(0xFF00E676)
                              : Colors.white,
                          size: 26,
                        ),
                        onPressed: () => _showCameraCenterSheet(context, appState),
                      ),
                      const SizedBox(width: 4),

                      // HEART REQUEST ICON (White / Neon Green Theme)
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(
                              appState.pendingPairRequest != null
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: appState.pendingPairRequest != null
                                  ? const Color(0xFF00E676)
                                  : Colors.white,
                              size: 26,
                            ),
                            tooltip: 'Eşleşme İstekleri',
                            onPressed: () => _showRequestsModal(context, appState),
                          ),
                          if (appState.pendingPairRequest != null)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF00E676), width: 2),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0xFF00E676),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // --- Hero Top View (Animated Fade Out on Scroll) ---
              Opacity(
                opacity: (1.0 - scrollProgress).clamp(0.0, 1.0),
                child: Column(
                  children: [
                    Center(
                      child: ProfileAvatar(
                        profile: myProfile,
                        radius: 65,
                        borderWidth: 3,
                      ),
                    ),
                const SizedBox(height: 14),

                Text(
                  myProfile?.deviceName ?? 'Ev Tableti (Ömer)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bu Cihaz • Kod: ${myProfile?.pairCode ?? ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 20),

                // Pinned Quick Dial Bar (Shown ONLY when a device is selected by long-pressing)
                if (appState.favoriteDevice != null) ...[
                  Builder(
                    builder: (context) {
                      final fav = appState.favoriteDevice!;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            fav.deviceName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildLiquidActionButton(
                                icon: Icons.chat_bubble_rounded,
                                onTap: () {
                                  appState.selectActiveDevice(fav);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const ChatScreen()),
                                  );
                                },
                              ),
                              const SizedBox(width: 20),
                              _buildLiquidActionButton(
                                icon: Icons.call_rounded,
                                onTap: () async {
                                  appState.selectActiveDevice(fav);
                                  await appState.startCall(CallType.audio);
                                },
                              ),
                              const SizedBox(width: 20),
                              _buildLiquidActionButton(
                                icon: Icons.videocam_rounded,
                                onTap: () async {
                                  appState.selectActiveDevice(fav);
                                  await appState.startCall(CallType.video);
                                },
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Connected Family Section Header
          const Row(
            children: [
              Text(
                'Bağlı Aile Bireyleri & Cihazlar',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (familyDevices.isEmpty)
            LiquidGlassCard(
              child: const Column(
                children: [
                  Icon(Icons.devices_other_rounded, color: Colors.white70, size: 36),
                  SizedBox(height: 8),
                  Text(
                    'Henüz Bağlı Aile Cihazı Yok',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white, fontSize: 15),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Aşağıdaki "Yeni Cihaz / Aile Bireyi Ekle" butonuna basarak PIN, Telefon, E-Posta veya QR kod ile kolayca eşleştirin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            )
          else ...[
            for (final device in familyDevices) ...[
              _buildLiquidDeviceCard(context, appState, device),
              const SizedBox(height: 10),
            ],
          ],

          const SizedBox(height: 12),

          // Add New Device Liquid Card
          LiquidGlassCard(
            onTap: onShowAddDeviceModal,
            child: const Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person_add_rounded, color: AppTheme.primary),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Yeni Cihaz / Aile Bireyi Ekle',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 15)),
                      SizedBox(height: 2),
                      Text('PIN, Telefon, E-Posta veya QR kod ile yeni cihaz eşleştirin',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ],
      ),
    ),

    // Floating Overlay Banner (Arka planı ve profil resmini ASLA aşağı itmez)
    if (appState.pendingPairRequest != null && !appState.isPendingBannerDismissed)
      Positioned(
        top: 64,
        left: 16,
        right: 16,
        child: _buildPendingPairBanner(context, appState, appState.pendingPairRequest!),
      ),
  ],
);
  }

  // Pending Incoming Connection Request Banner
  Widget _buildPendingPairBanner(
      BuildContext context, AppStateProvider appState, UserProfile request) {
    final nameCtrl = TextEditingController(
        text: request.deviceName.isNotEmpty ? request.deviceName : 'Annem');
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 30,
            spreadRadius: 4,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF00E676).withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: LiquidGlassCard(
        isHighlight: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00E676),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: Colors.black, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'YENİ BAĞLANTI İSTEĞİ GELDİ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white70, size: 20),
                  tooltip: 'Kapat (Kalp Butonundan Ulaşılabilir)',
                  onPressed: () => appState.minimizePendingPairBanner(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Rich Requester Details Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.devices_rounded,
                          color: Color(0xFF00E676), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'İstek Gönderen Cihaz: ${request.deviceName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.contact_phone_rounded,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Eşleşme Kodu / Numara: ${request.pairCode}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            const Text(
              'Bu kişiyi rehberinizde hangi isimle kaydetmek istersiniz?',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Örn: Annem, Babam, Teyzem',
                labelText: 'Rehber Kayıt Adı',
                labelStyle: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.bold),
                prefixIcon:
                    const Icon(Icons.edit_rounded, color: AppTheme.primary),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => appState.dismissPendingPairRequest(),
                    child: const Text('Reddet'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      appState.acceptPendingPairRequest(
                          nameCtrl.text.trim().isNotEmpty
                              ? nameCtrl.text.trim()
                              : request.deviceName);
                    },
                    child: const Text('ONAYLA VE KAYDET',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiquidActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildLiquidDeviceCard(
      BuildContext context, AppStateProvider appState, UserProfile device) {
    final isFavorite = appState.favoriteDeviceId == device.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onLongPress: () {
          appState.toggleFavoriteDevice(device.id);
          final newFavState = appState.favoriteDeviceId == device.id;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newFavState
                    ? '📌 ${device.deviceName} üst hızlı arama alanına sabitlendi.'
                    : 'ℹ️ ${device.deviceName} üst hızlı arama alanından kaldırıldı.',
              ),
              backgroundColor: newFavState ? const Color(0xFF00E676) : AppTheme.primary,
              duration: const Duration(seconds: 2),
            ),
          );
        },
        child: LiquidGlassCard(
          isHighlight: isFavorite,
          onTap: () {
            appState.selectActiveDevice(device);
            _showContactDetailModal(context, appState, device);
          },
          child: Row(
            children: [
              ProfileAvatar(
                profile: device,
                radius: 25,
                borderWidth: 2,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: device.isOnline
                                ? const Color(0xFF00E676)
                                : Colors.white38,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          device.isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: Colors.white, size: 20),
                    tooltip: 'Mesaj Gönder',
                    onPressed: () {
                      appState.selectActiveDevice(device);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ChatScreen()),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.call_rounded,
                        color: Color(0xFF00E676), size: 20),
                    tooltip: 'Sesli Ara',
                    onPressed: () async {
                      appState.selectActiveDevice(device);
                      await appState.startCall(CallType.audio);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam_rounded,
                        color: Color(0xFF00E676), size: 22),
                    tooltip: 'Görüntülü Ara',
                    onPressed: () async {
                      appState.selectActiveDevice(device);
                      await appState.startCall(CallType.video);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContactDetailModal(
      BuildContext context, AppStateProvider appState, UserProfile device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF374151),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            ProfileAvatar(
              profile: device,
              radius: 40,
              borderWidth: 2,
            ),
            const SizedBox(height: 12),
            Text(
              device.deviceName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: device.isOnline
                        ? const Color(0xFF00E676)
                        : Colors.white38,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${device.isOnline ? 'Çevrimiçi' : 'Çevrimdışı'} • Kod: ${device.pairCode}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildDetailModalActionButton(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Mesaj',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatScreen()),
                    );
                  },
                ),
                _buildDetailModalActionButton(
                  icon: Icons.call_rounded,
                  label: 'Sesli',
                  onTap: () async {
                    Navigator.pop(modalCtx);
                    await appState.startCall(CallType.audio);
                  },
                ),
                _buildDetailModalActionButton(
                  icon: Icons.videocam_rounded,
                  label: 'Görüntülü',
                  onTap: () async {
                    Navigator.pop(modalCtx);
                    await appState.startCall(CallType.video);
                  },
                ),
                _buildDetailModalActionButton(
                  icon: Icons.notifications_active_rounded,
                  label: 'İkaz',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    appState.sendMessage('🔔 YÜKSEK İKAZ: Lütfen cihaza bakın!');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🔔 Cihaza yüksek sesli bildirim gönderildi!'),
                        backgroundColor: AppTheme.primary,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit_rounded, color: Colors.white),
                    title: const Text('Kişi Adını Düzenle',
                        style: TextStyle(color: Colors.white)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.white54),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      _showRenameDialog(context, appState, device);
                    },
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  ListTile(
                    leading:
                        const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    title: const Text('Eşleşmeyi Sonlandır',
                        style: TextStyle(color: Colors.redAccent)),
                    trailing: const Icon(Icons.chevron_right_rounded,
                        color: Colors.redAccent),
                    onTap: () {
                      Navigator.pop(modalCtx);
                      _showDeleteConfirmDialog(context, appState, device);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailModalActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  void _showDeleteConfirmDialog(
      BuildContext context, AppStateProvider appState, UserProfile device) {
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
                color: Colors.amber.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Eşleşmeyi Sonlandır',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          '${device.deviceName} cihazını rehberinizden çıkarmak istediğinize emin misiniz?\n\nBu işlem gerçekleştiğinde eşleşme HER İKİ CİHAZDA DA canlı olarak sonlandırılacaktır.',
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
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
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.amber,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await appState.blockDevice(device.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${device.deviceName} engellendi.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
            child: const Text('Engelle', style: TextStyle(fontWeight: FontWeight.w600)),
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
              await appState.removePairedDevice(device.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${device.deviceName} eşleşmesi sonlandırıldı.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text('Evet, Çıkar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(
      BuildContext context, AppStateProvider appState, UserProfile device) {
    final renameCtrl = TextEditingController(text: device.deviceName);
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
                color: const Color(0xFF00E676).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_rounded, color: Color(0xFF00E676), size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Kişi Adını Düzenle',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: TextField(
          controller: renameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Örn: Annem, Babam, Teyzem',
            hintStyle: const TextStyle(color: Colors.white38),
            labelText: 'Kişi / Cihaz Adı',
            labelStyle: const TextStyle(color: Color(0xFF00E676)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.08),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF00E676), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
          ),
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
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              elevation: 4,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () async {
              if (renameCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                await appState.renamePairedDevice(
                    device.id, renameCtrl.text.trim());
              }
            },
            child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRequestsModal(BuildContext context, AppStateProvider appState) {
    final request = appState.pendingPairRequest;
    final nameCtrl = TextEditingController(
        text: request?.deviceName.isNotEmpty == true ? request!.deviceName : 'Annem');
    final historyList = appState.approvedPairHistory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 1. GELEN İSTEKLER SEKSİYONU
                const Text(
                  '📩 GELEN BAĞLANTI İSTEKLERİ',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),

                if (request == null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Henüz yanıt bekleyen yeni bir eşleşme isteği yok.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF00E676).withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_add_rounded,
                                color: Color(0xFF00E676)),
                            const SizedBox(width: 8),
                            const Text(
                              'YENİ BAĞLANTI İSTEĞİ GELDİ',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close,
                                  color: Colors.white70, size: 20),
                              onPressed: () {
                                appState.minimizePendingPairBanner();
                                Navigator.pop(ctx);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.important_devices_rounded,
                                      color: Color(0xFF00E676), size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    'İstek Gönderen Cihaz: ${request.deviceName}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.badge_rounded,
                                      color: Colors.white70, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Eşleşme Kodu / Numara: ${request.pairCode}',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Bu kişiyi rehberinizde hangi isimle kaydetmek istersiniz?',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: nameCtrl,
                          style: const TextStyle(
                              color: Colors.black, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: 'Örn: Annem, Babam, Teyzem',
                            labelText: 'Rehber Kayıt Adı',
                            labelStyle:
                                const TextStyle(color: Color(0xFF00E676)),
                            prefixIcon: const Icon(Icons.edit_rounded,
                                color: Color(0xFF00E676)),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white38),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () {
                                  appState.dismissPendingPairRequest();
                                  Navigator.pop(ctx);
                                },
                                child: const Text('Reddet'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00E676),
                                  foregroundColor: Colors.black,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () {
                                  appState.acceptPendingPairRequest(
                                      nameCtrl.text.trim().isNotEmpty
                                          ? nameCtrl.text.trim()
                                          : request.deviceName);
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          '✅ Cihaz eşleşmesi onaylandı ve bağlandı!'),
                                      backgroundColor: Color(0xFF00E676),
                                    ),
                                  );
                                },
                                child: const Text('KABUL ET VE BAĞLAN',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // 2. GÖNDERİLEN BEKLEYEN İSTEKLER SEKSİYONU
                const SizedBox(height: 20),
                const Text(
                  '⏳ GÖNDERİLEN BEKLEYEN İSTEKLER',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                if (appState.sentPairRequests.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Şu anda gönderilmiş bekleyen eşleşme isteğiniz bulunmuyor.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  )
                else
                  Column(
                    children: appState.sentPairRequests.map((code) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hourglass_top_rounded,
                                color: Colors.amber, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hedef Kod/Tel: $code',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Text(
                                    'Karşı cihazın onayı bekleniyor...',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.close_rounded, size: 14),
                              label: const Text('İPTAL ET',
                                  style: TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                await appState.cancelSentPairRequest(code);
                                setModalState(() {});
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Eşleşme isteği iptal edildi.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 24),

                // 3. ONAYLANAN EŞLEŞME GEÇMİŞİ SEKSİYONU
                const Text(
                  '✅ ONAYLANAN BAĞLANTI GEÇMİŞİ',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                if (historyList.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Text(
                      'Henüz onaylanmış bağlantı geçmişiniz bulunmuyor.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  )
                else
                  Column(
                    children: historyList.map((dev) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Color(0xFF00E676), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dev.deviceName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Kod/Tel: ${dev.pairCode}',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF00E676).withValues(alpha: 0.2),
                                foregroundColor: const Color(0xFF00E676),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side:
                                      const BorderSide(color: Color(0xFF00E676)),
                                ),
                              ),
                              icon: const Icon(Icons.send_rounded, size: 14),
                              label: const Text('KARŞILIK İSTEK',
                                  style: TextStyle(
                                      fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final myId = appState.myProfile?.id ?? 'omega';
                                final myName =
                                    appState.myProfile?.deviceName ?? 'Omega Cihazı';
                                final res = await appState.sendPairRequest(
                                    dev.pairCode, myId, myName);
                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  if (res == PairRequestResult.success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '${dev.deviceName} cihazına karşılık eşleşme isteği gönderildi!'),
                                        backgroundColor: const Color(0xFF00E676),
                                      ),
                                    );
                                  } else if (res == PairRequestResult.alreadyPaired) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('⚠️ Bu cihaz zaten bağlı cihaz listenizde ekli!'),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  } else if (res == PairRequestResult.alreadyPending) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('⏳ Bu cihaza halihazırda bekleyen bir eşleşme isteğiniz var!'),
                                        backgroundColor: Colors.blueAccent,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCameraCenterSheet(BuildContext context, AppStateProvider appState) {
    appState.startListeningFamilyCameras();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        bool useFrontCamera = false;
        bool motionDetection = true;
        bool enableRecording = true;
        int cooldownMinutes = 5;
        bool dimScreen = true;

        return Consumer<AppStateProvider>(
          builder: (context, currentAppState, _) {
            final myId = currentAppState.myProfile?.id ?? '';
            final activeCameras = currentAppState.activeFamilyCameras.where((c) => c['deviceId'] != myId).toList();

            return StatefulBuilder(
              builder: (context, setModalState) {
                return SingleChildScrollView(
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white30,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Row(
                            children: [
                              Icon(Icons.videocam_rounded, color: Color(0xFF00E676), size: 24),
                              SizedBox(width: 10),
                              Text(
                                'Güvenlik & Bebek Kamerası',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Active Live Cameras List (If any device is broadcasting)
                          if (activeCameras.isNotEmpty) ...[
                            const Text(
                              '🟢 CANLI YAYINDAKİ CİHAZLAR',
                              style: TextStyle(color: Color(0xFF00E676), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 8),
                            ...activeCameras.map((cam) {
                              final name = cam['deviceName'] ?? 'Ev Kamerası';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.videocam_rounded, color: Color(0xFF00E676), size: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00E676),
                                        foregroundColor: Colors.black,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      ),
                                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                                      label: const Text('Canlı İzle', style: TextStyle(fontWeight: FontWeight.bold)),
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => LiveCameraViewerScreen(cameraData: cam),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const Divider(color: Colors.white24, height: 24),
                          ],

                          // Host Camera Setup (Ev Tableti / Kamera İstasyonu Yap)
                          const Text(
                            '📹 BU CİHAZI KAMERA YAP (EV TABLETİ)',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 10),

                          SwitchListTile(
                            activeThumbColor: const Color(0xFF00E676),
                            title: const Text('Kamera Seçimi', style: TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text(useFrontCamera ? 'Ön Kamera' : 'Arka Kamera', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                            value: useFrontCamera,
                            onChanged: (val) => setModalState(() => useFrontCamera = val),
                          ),
                          SwitchListTile(
                            activeThumbColor: const Color(0xFF00E676),
                            title: const Text('Kesintisiz Video Kaydı', style: TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: const Text('Yayın açıkken videoları 5\'er dk parçalarla kaydeder ve 7 gün saklar', style: TextStyle(color: Colors.white60, fontSize: 12)),
                            value: enableRecording,
                            onChanged: (val) => setModalState(() => enableRecording = val),
                          ),
                          SwitchListTile(
                            activeThumbColor: const Color(0xFF00E676),
                            title: const Text('Hareket Algılama Bildirimi', style: TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: const Text('Hareket olduğunda anne/babaya anında bildirim atar', style: TextStyle(color: Colors.white60, fontSize: 12)),
                            value: motionDetection,
                            onChanged: (val) => setModalState(() => motionDetection = val),
                          ),
                          if (motionDetection) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bildirim Sıklığı (Bekleme Süresi)',
                                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [1, 3, 5, 10, 15, 30].map((mins) {
                                        final isSelected = cooldownMinutes == mins;
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 8.0),
                                          child: GestureDetector(
                                            onTap: () => setModalState(() => cooldownMinutes = mins),
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 150),
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isSelected ? const Color(0xFF00E676) : const Color(0xFF334155),
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isSelected ? const Color(0xFF00E676) : Colors.white30,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isSelected) ...[
                                                    const Icon(Icons.check_rounded, color: Colors.black, size: 16),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Text(
                                                    '$mins dk',
                                                    style: TextStyle(
                                                      color: isSelected ? Colors.black : Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],

                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              icon: const Icon(Icons.videocam_rounded),
                              label: const Text(
                                'Kamera Yayınını Başlat',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              onPressed: () async {
                                final nav = Navigator.of(context);
                                Navigator.pop(ctx);
                                final settings = {
                                  'useFrontCamera': useFrontCamera,
                                  'motionDetection': motionDetection,
                                  'cooldownMinutes': cooldownMinutes,
                                  'enableRecording': enableRecording,
                                  'dimScreen': dimScreen,
                                };
                                await appState.startCameraHostMode(settings);
                                nav.push(
                                  MaterialPageRoute(
                                    builder: (_) => CameraStationScreen(settings: settings),
                                  ),
                                );
                              },
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
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              icon: const Icon(Icons.video_library_rounded, color: Colors.amberAccent),
                              label: const Text(
                                '📹 Kayıtlı Videoları İzle (Geçmiş)',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RecordingsGalleryScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
