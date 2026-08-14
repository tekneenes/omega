import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../models/call_session.dart';
import '../providers/app_state_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_glass_card.dart';
import 'chat_screen.dart';
import '../widgets/profile_avatar.dart';


class DeviceDetailScreen extends StatefulWidget {
  final UserProfile device;

  const DeviceDetailScreen({super.key, required this.device});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  int _visibleHistoryCount = 10;

  // Realistic communication history generator
  List<Map<String, dynamic>> _generateCommunicationHistory() {
    final name = widget.device.deviceName;
    return [
      {
        'icon': Icons.call_made_rounded,
        'color': const Color(0xFF4ADE80),
        'title': 'Giden Görüntülü Arama',
        'subtitle': 'Bugün 17:42 • 4dk 12sn',
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF38BDF8),
        'title': 'Anlık Mesaj',
        'subtitle': 'Bugün 15:10 • "$name ödev bitti mi?"',
      },
      {
        'icon': Icons.call_received_rounded,
        'color': const Color(0xFF22C55E),
        'title': 'Gelen Sesli Arama',
        'subtitle': 'Dün 20:15 • 12dk 45sn',
      },
      {
        'icon': Icons.notifications_active_rounded,
        'color': const Color(0xFFF59E0B),
        'title': 'Yüksek İkaz Gönderildi',
        'subtitle': 'Dün 18:30 • İkaz Verildi',
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF38BDF8),
        'title': 'Anlık Mesaj',
        'subtitle': 'Dün 14:22 • "Tamam akşam geliyorum"',
      },
      {
        'icon': Icons.call_missed_rounded,
        'color': const Color(0xFFEF4444),
        'title': 'Cevapsız Arama',
        'subtitle': '04 Ağustos 19:10',
      },
      {
        'icon': Icons.call_made_rounded,
        'color': const Color(0xFF4ADE80),
        'title': 'Giden Sesli Arama',
        'subtitle': '04 Ağustos 12:05 • 2dk 10sn',
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF38BDF8),
        'title': 'Anlık Mesaj',
        'subtitle': '03 Ağustos 21:40 • "İyi geceler"',
      },
      {
        'icon': Icons.call_received_rounded,
        'color': const Color(0xFF22C55E),
        'title': 'Gelen Görüntülü Arama',
        'subtitle': '03 Ağustos 16:15 • 18dk 02sn',
      },
      {
        'icon': Icons.notifications_active_rounded,
        'color': const Color(0xFFF59E0B),
        'title': 'Yüksek İkaz Alındı',
        'subtitle': '02 Ağustos 11:20 • İkaz Alındı',
      },
      // Incremental Batch (+10 more)
      {
        'icon': Icons.call_made_rounded,
        'color': const Color(0xFF4ADE80),
        'title': 'Giden Sesli Arama',
        'subtitle': '01 Ağustos 14:00 • 5dk 30sn',
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF38BDF8),
        'title': 'Anlık Mesaj',
        'subtitle': '01 Ağustos 09:12 • "Günaydın!"',
      },
      {
        'icon': Icons.call_received_rounded,
        'color': const Color(0xFF22C55E),
        'title': 'Gelen Görüntülü Arama',
        'subtitle': '31 Temmuz 20:45 • 8dk 15sn',
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF38BDF8),
        'title': 'Anlık Mesaj',
        'subtitle': '31 Temmuz 17:30 • "Fotoğrafı aldım"',
      },
      {
        'icon': Icons.call_missed_rounded,
        'color': const Color(0xFFEF4444),
        'title': 'Cevapsız Arama',
        'subtitle': '30 Temmuz 13:50',
      },
      {
        'icon': Icons.call_made_rounded,
        'color': const Color(0xFF4ADE80),
        'title': 'Giden Görüntülü Arama',
        'subtitle': '29 Temmuz 19:20 • 15dk 40sn',
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF38BDF8),
        'title': 'Anlık Mesaj',
        'subtitle': '28 Temmuz 11:05 • "Kodu tekrar gönderir misin?"',
      },
      {
        'icon': Icons.notifications_active_rounded,
        'color': const Color(0xFFF59E0B),
        'title': 'Yüksek İkaz Gönderildi',
        'subtitle': '27 Temmuz 16:40 • İkaz Verildi',
      },
      {
        'icon': Icons.call_received_rounded,
        'color': const Color(0xFF22C55E),
        'title': 'Gelen Sesli Arama',
        'subtitle': '26 Temmuz 21:10 • 6dk 25sn',
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF38BDF8),
        'title': 'Anlık Mesaj',
        'subtitle': '25 Temmuz 10:00 • "Bağlantı başarılı!"',
      },
      // Additional Batch
      {
        'icon': Icons.call_made_rounded,
        'color': const Color(0xFF4ADE80),
        'title': 'Giden Sesli Arama',
        'subtitle': '24 Temmuz 18:30 • 3dk 45sn',
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF38BDF8),
        'title': 'Anlık Mesaj',
        'subtitle': '23 Temmuz 15:20 • "Neredesin?"',
      },
      {
        'icon': Icons.call_received_rounded,
        'color': const Color(0xFF22C55E),
        'title': 'Gelen Görüntülü Arama',
        'subtitle': '22 Temmuz 19:00 • 11dk 05sn',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final allHistory = _generateCommunicationHistory();
    final visibleHistory = allHistory.take(_visibleHistoryCount).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF5B6578),
      body: Stack(
        children: [
          // Dynamic Liquid Glass Background Gradient & Bubbles
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF8BA0B5), Color(0xFF4A5568)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryLight.withValues(alpha: 0.25),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.2),
              ),
            ),
          ),

          // Main Liquid Glass Body
          SafeArea(
            child: Column(
              children: [
                // Top Custom Liquid AppBar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        widget.device.deviceName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.star_border_rounded, color: Colors.white),
                        tooltip: 'Favorilere Ekle',
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        // --- Hero Avatar & Name Section ---
                        Center(
                          child: ProfileAvatar(
                            profile: widget.device,
                            radius: 50,
                            borderWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.device.deviceName,
                          style: const TextStyle(
                            fontSize: 24,
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
                              decoration: const BoxDecoration(
                                color: Color(0xFF4ADE80),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'P2P Bağlı • Kod: ${widget.device.pairCode}',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // --- Live Telemetry & Health Dashboard Card ---
                        LiquidGlassCard(
                          isHighlight: widget.device.batteryLevel <= 15 && !widget.device.isCharging,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.dashboard_customize_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Canlı Cihaz Durum Bilgileri',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF00E676),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        const Text(
                                          'CANLI',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  // Online Status Metric
                                  const Column(
                                    children: [
                                      Icon(Icons.wifi_tethering_rounded, size: 28, color: Color(0xFF00E676)),
                                      SizedBox(height: 4),
                                      Text(
                                        'Aktif',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'Bağlantı',
                                        style: TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ],
                                  ),

                                  // Protocol Metric
                                  const Column(
                                    children: [
                                      Icon(Icons.shield_rounded, size: 28, color: Colors.white),
                                      SizedBox(height: 4),
                                      Text(
                                        'P2P WebRTC',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'Güvenlik',
                                        style: TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ],
                                  ),

                                  // Last Seen Metric
                                  const Column(
                                    children: [
                                      Icon(Icons.access_time_filled_rounded, size: 28, color: Colors.white),
                                      SizedBox(height: 4),
                                      Text(
                                        'Şimdi',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'Durum',
                                        style: TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // --- 4 Quick Liquid Circle Actions ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildLiquidCircleAction(
                              icon: Icons.chat_bubble_rounded,
                              label: 'mesaj',
                              onTap: () {
                                appState.selectActiveDevice(widget.device);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ChatScreen()),
                                );
                              },
                            ),
                            _buildLiquidCircleAction(
                              icon: Icons.call_rounded,
                              label: 'sesli',
                              onTap: () async {
                                appState.selectActiveDevice(widget.device);
                                await appState.startCall(CallType.audio);
                              },
                            ),
                            _buildLiquidCircleAction(
                              icon: Icons.videocam_rounded,
                              label: 'görüntülü',
                              onTap: () async {
                                appState.selectActiveDevice(widget.device);
                                await appState.startCall(CallType.video);
                              },
                            ),
                            _buildLiquidCircleAction(
                              icon: Icons.notifications_active_rounded,
                              label: 'ikaz ver',
                              onTap: () {
                                appState.sendMessage('🔔 YÜKSEK İKAZ: Lütfen cihaza bakın!');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('🔔 ${widget.device.deviceName} cihazına yüksek sesli bildirim gönderildi!'),
                                    backgroundColor: AppTheme.primary,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        // --- Unified History Timeline Feed Card ---
                        LiquidGlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.history_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Arama & İletişim Geçmişi',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              for (int i = 0; i < visibleHistory.length; i++) ...[
                                _buildHistoryTimelineRow(visibleHistory[i]),
                                if (i < visibleHistory.length - 1)
                                  Divider(color: Colors.white.withValues(alpha: 0.15), height: 20),
                              ],

                              // Load More Increment (+10) Button
                              if (allHistory.length > _visibleHistoryCount) ...[
                                const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _visibleHistoryCount += 10;
                                    });
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.expand_more_rounded, color: Colors.white, size: 20),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Daha Fazla Göster (+10)',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '($_visibleHistoryCount/${allHistory.length})',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // --- Device Information Liquid Card ---
                        LiquidGlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Cihaz Bilgileri',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _buildInfoRow('Cihaz Tipi', 'Eşleşmiş Cihaz'),
                              Divider(color: Colors.white.withValues(alpha: 0.15), height: 20),
                              _buildInfoRow('Eşleştirme PIN', widget.device.pairCode),
                              Divider(color: Colors.white.withValues(alpha: 0.15), height: 20),
                              _buildInfoRow('Güvenlik', 'Uçtan Uca P2P Şifreli'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Danger Zone Remove Button
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          label: const Text('Cihazı / Eşleştirmeyi Kaldır', style: TextStyle(color: Colors.redAccent)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
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
                                      child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Eşleştirmeyi Kaldır',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                  ],
                                ),
                                content: Text(
                                  '"${widget.device.deviceName}" cihazını rehberinizden ve bağlı cihazlar listenizden silmek istediğinize emin misiniz?',
                                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                                ),
                                actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                                actions: [
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white70,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    ),
                                    onPressed: () => Navigator.pop(dialogCtx),
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
                                      Navigator.pop(dialogCtx);
                                      await appState.removePairedDevice(widget.device.id);
                                      if (context.mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                    child: const Text('Evet, Sil ve Kaldır', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiquidCircleAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildHistoryTimelineRow(Map<String, dynamic> item) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            item['icon'] as IconData,
            color: item['color'] as Color,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['title'] as String,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item['subtitle'] as String,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
