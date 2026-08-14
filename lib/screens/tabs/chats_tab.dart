import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/user_profile.dart';
import '../../providers/app_state_provider.dart';
import '../../services/firebase_config_service.dart';
import '../../widgets/liquid_glass_card.dart';
import '../chat_screen.dart';
import '../group_chat_screen.dart';
import '../../widgets/profile_avatar.dart';

class ChatsTab extends StatelessWidget {
  final VoidCallback onShowAddDeviceModal;

  const ChatsTab({super.key, required this.onShowAddDeviceModal});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final Map<String, UserProfile> uniqueFamily = {};
    for (final d in appState.pairedDevicesList) {
      if (d.id != appState.myProfile?.id) {
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

    final lastGroupMsg = appState.groupChatHistory.isNotEmpty
        ? appState.groupChatHistory.last
        : null;
    final lastGroupMsgText = lastGroupMsg != null
        ? '${lastGroupMsg.senderName ?? "Üye"}: ${lastGroupMsg.text}'
        : 'Tüm aile bireyleriyle ortak oda';
    final lastGroupTime = lastGroupMsg != null
        ? DateFormat('HH:mm').format(lastGroupMsg.timestamp)
        : '';

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sohbetler',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Aile bireyleriyle anlık uçtan uca şifreli mesajlaşın',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showNewChatSelectModal(context, appState),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.add_comment_rounded, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- PERSISTENT FAMILY GROUP CHAT CARD ---
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupChatScreen()),
              );
            },
            onLongPress: () => _confirmResetGroupChatDialog(context, appState),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1E293B).withValues(alpha: 0.95),
                    const Color(0xFF0F172A).withValues(alpha: 0.9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.2),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFF10B981)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        '👨‍👩‍👧‍👦',
                        style: TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Aile Odası',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                              ),
                              child: const Text(
                                'Grup',
                                style: TextStyle(
                                  color: Color(0xFFFBBF24),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lastGroupMsgText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (lastGroupTime.isNotEmpty)
                        Text(
                          lastGroupTime,
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 4),
                      if (appState.groupUnreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${appState.groupUnreadCount}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white54,
                          size: 20,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (familyDevices.isEmpty)
            LiquidGlassCard(
              child: const Column(
                children: [
                  Icon(Icons.chat_bubble_outline_rounded,
                      color: Colors.white70, size: 40),
                  SizedBox(height: 10),
                  Text(
                    'Henüz Sohbet Bulunmuyor',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Kişiler sekmesinden yeni cihaz ekleyerek anında mesajlaşmaya başlayabilirsiniz.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            )
          else ...[
            for (final device in familyDevices) ...[
              Builder(builder: (context) {
                // Calculate unread count and last message for this device
                final unreadCount = appState.unreadCountFrom(device.id);
                final deviceMessages = appState.getMessagesForContact(device.id, device.pairCode);
                final lastMsg = deviceMessages.isNotEmpty ? deviceMessages.last : null;
                final lastMsgText = lastMsg?.text ?? '';
                final lastMsgTime = lastMsg != null
                    ? DateFormat('HH:mm').format(lastMsg.timestamp)
                    : '';

                return LiquidGlassCard(
                  onTap: () {
                    appState.selectActiveDevice(device);
                    appState.markMessagesAsRead(device.id);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ChatScreen()),
                    );
                  },
                  onLongPress: () => _confirmDeleteChatDialog(context, appState, device),
                  child: Row(
                    children: [
                      ProfileAvatar(
                        profile: device,
                        radius: 24,
                        borderWidth: 2,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  device.deviceName,
                                  style: TextStyle(
                                    fontWeight: unreadCount > 0 ? FontWeight.w800 : FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  lastMsgTime,
                                  style: TextStyle(
                                    color: unreadCount > 0 ? const Color(0xFF00E676) : Colors.white60,
                                    fontSize: 11,
                                    fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              lastMsgText.isNotEmpty ? lastMsgText : 'Henüz mesaj yok',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unreadCount > 0 ? Colors.white : Colors.white70,
                                fontSize: 13,
                                fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          child: Center(
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  void _showNewChatSelectModal(BuildContext context, AppStateProvider appState) {
    final familyDevices = appState.pairedDevicesList
        .where((d) => d.id != appState.myProfile?.id)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalCtx) {
        return SingleChildScrollView(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.chat_rounded, color: Color(0xFF00E676), size: 24),
                          SizedBox(width: 10),
                          Text(
                            'Yeni Sohbet Başlat',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white60),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Rehberinizdeki kişilerden birini seçerek sohbet başlatın:',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  if (familyDevices.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.people_outline_rounded, color: Colors.white38, size: 48),
                          SizedBox(height: 10),
                          Text(
                            'Henüz rehberinizde bağlı aile bireyi bulunmuyor.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      icon: const Icon(Icons.person_add_rounded),
                      label: const Text(
                        'YENİ KİŞİ / CİHAZ EKLE',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        Navigator.pop(modalCtx);
                        onShowAddDeviceModal();
                      },
                    ),
                  ] else ...[
                    for (final device in familyDevices) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: ProfileAvatar(
                            profile: device,
                            radius: 20,
                            borderWidth: 1.5,
                          ),
                          title: Text(
                            device.deviceName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          subtitle: Text(
                            'Kod: ${device.pairCode}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: Color(0xFF00E676),
                              size: 18,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(modalCtx);
                            appState.selectActiveDevice(device);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ChatScreen()),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmDeleteChatDialog(BuildContext context, AppStateProvider appState, UserProfile device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sohbeti Sil',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          '${device.deviceName} ile olan tüm mesajlar ve sohbet geçmişi hem bu cihazdan hem de veritabanından kalıcı olarak silinecek. Emin misiniz?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('Sohbeti Sil', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(ctx);
              await appState.deleteEntireChatWithDevice(device.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${device.deviceName} ile sohbet geçmişi silindi.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmResetGroupChatDialog(BuildContext context, AppStateProvider appState) async {
    final isAdmin = await FirebaseConfigService.isNetworkAdmin();
    if (!context.mounted) return;

    if (!isAdmin) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 24),
              SizedBox(width: 10),
              Text('Yönetici Yetkisi Gerekli', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            'Aile Odası mesajlarını yalnızca ağı ilk kuran Yönetici Cihaz tüm cihazlar için sıfırlayabilir.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tamam', style: TextStyle(color: Color(0xFF00E676))),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aile Sohbetini Sıfırla',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          '👑 Yönetici İşlemi:\nTüm bağlı cihazlardaki ve sunucudaki Aile Odası mesajları kalıcı olarak temizlenecektir. Devam etmek istiyor musunuz?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Tüm Cihazlarda Sıfırla', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(ctx);
              await appState.resetFamilyGroupChatForAllDevices();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('👑 Aile Odası tüm cihazlar için başarıyla sıfırlandı.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
